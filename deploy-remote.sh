#!/bin/bash

# TrackIt Remote Deployment Script (Improved Version)
# This script deploys the TrackIt application to a remote server
# with enhanced version tracking and rollback capabilities

set -e  # Exit immediately if a command exits with a non-zero status

# Colors for prettier output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=====================================${NC}"
echo -e "${YELLOW}   TrackIt Remote Deployment Process  ${NC}"
echo -e "${YELLOW}=====================================${NC}"

CONFIG_FILE="deploy-config.json"
ENVIRONMENT="production"  # Default environment

# Parse command line arguments
PRESERVE=false
SHOW_REMOTE_VERSION=false
ROLLBACK=false
FORCE=false
DRY_RUN=false

function show_help {
  echo -e "${CYAN}Usage:${NC} ./deploy-remote.sh [options]"
  echo -e ""
  echo -e "${CYAN}Options:${NC}"
  echo -e "  -e, --environment ENV   Set deployment environment (default: production)"
  echo -e "  -c, --config FILE       Set config file (default: deploy-config.json)"
  echo -e "  -p, --preserve          Preserve files on remote server"
  echo -e "  -v, --version           Show remote deployment version"
  echo -e "  -r, --rollback          Rollback to previous deployment"
  echo -e "  -f, --force             Force deployment without confirmation"
  echo -e "  -d, --dry-run           Simulate deployment without making changes"
  echo -e "  -h, --help              Show this help message"
  echo -e ""
  echo -e "${CYAN}Examples:${NC}"
  echo -e "  ./deploy-remote.sh"
  echo -e "  ./deploy-remote.sh --environment staging"
  echo -e "  ./deploy-remote.sh --rollback"
  echo -e "  ./deploy-remote.sh --dry-run"
}

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -e|--environment)
      ENVIRONMENT="$2"
      shift
      shift
      ;;
    -c|--config)
      CONFIG_FILE="$2"
      shift
      shift
      ;;
    -p|--preserve)
      PRESERVE=true
      shift
      ;;
    -v|--version)
      SHOW_REMOTE_VERSION=true
      shift
      ;;
    -r|--rollback)
      ROLLBACK=true
      shift
      ;;
    -f|--force)
      FORCE=true
      shift
      ;;
    -d|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $key${NC}"
      show_help
      exit 1
      ;;
  esac
done

echo -e "${YELLOW}Configuring deployment for ${BLUE}$ENVIRONMENT${NC} environment"

# Check if configuration file exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo -e "${RED}Error: Configuration file $CONFIG_FILE not found${NC}"
  exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo -e "${RED}Error: jq is not installed. Please install it and try again.${NC}"
  echo -e "${YELLOW}You can install it with: sudo apt-get install jq${NC}"
  exit 1
fi

# Load configuration for the selected environment
HOST=$(jq -r ".environments.$ENVIRONMENT.host" "$CONFIG_FILE")
PORT=$(jq -r ".environments.$ENVIRONMENT.port" "$CONFIG_FILE")
USERNAME=$(jq -r ".environments.$ENVIRONMENT.username" "$CONFIG_FILE")
REMOTE_PATH=$(jq -r ".environments.$ENVIRONMENT.remotePath" "$CONFIG_FILE")
DELETE_REMOTE=$(jq -r ".deploymentSettings.deleteRemote" "$CONFIG_FILE")
BACKUP_BEFORE_DEPLOY=$(jq -r ".deploymentSettings.backupBeforeDeploy" "$CONFIG_FILE")
BACKUP_LOCATION=$(jq -r ".deploymentSettings.backupLocation" "$CONFIG_FILE")

# Check if required configuration is available
if [ "$HOST" == "null" ] || [ "$USERNAME" == "null" ] || [ "$REMOTE_PATH" == "null" ]; then
  echo -e "${RED}Error: Missing required configuration for $ENVIRONMENT environment${NC}"
  exit 1
fi

# Define deployment directory - look for it in the current directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_DIR="${SCRIPT_DIR}/deployment"
echo -e "${BLUE}Script directory: ${SCRIPT_DIR}${NC}"
echo -e "${BLUE}Looking for deployment directory at: ${DEPLOYMENT_DIR}${NC}"

# Create SSH command with port
SSH_CMD="ssh -p $PORT $USERNAME@$HOST"

# Handle showing remote version
if [ "$SHOW_REMOTE_VERSION" = true ]; then
  echo -e "${YELLOW}Checking remote deployment version...${NC}"
  $SSH_CMD "if [ -f \"$REMOTE_PATH/deployment-info.json\" ]; then cat \"$REMOTE_PATH/deployment-info.json\"; else echo '{\"error\": \"No deployment information found\"}'; fi" | jq '.'
  
  echo -e "\n${YELLOW}Checking deployment history...${NC}"
  $SSH_CMD "if [ -f \"$REMOTE_PATH/version.json\" ]; then cat \"$REMOTE_PATH/version.json\"; else echo '{\"versions\": []}'; fi" | jq '.versions[-5:]'
  exit 0
fi

# Handle rollback
if [ "$ROLLBACK" = true ]; then
  echo -e "${YELLOW}Starting rollback process...${NC}"
  
  # Check for available backups
  BACKUPS=$($SSH_CMD "find $BACKUP_LOCATION -name 'trackit_*.tar.gz' -type f -printf '%T@ %p\n' | sort -nr | head -10 | cut -d' ' -f2-")
  
  if [ -z "$BACKUPS" ]; then
    echo -e "${RED}Error: No backups found in $BACKUP_LOCATION${NC}"
    exit 1
  fi
  
  echo -e "${CYAN}Available backups:${NC}"
  IFS=$'\n'
  BACKUP_ARRAY=()
  i=1
  for backup in $BACKUPS; do
    filename=$(basename "$backup")
    date_part=${filename#trackit_}
    date_part=${date_part%.tar.gz}
    formatted_date=$(date -d "${date_part:0:8} ${date_part:9:2}:${date_part:11:2}:${date_part:13:2}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
      formatted_date="Unknown date format"
    fi
    
    echo -e "$i) $filename ($formatted_date)"
    BACKUP_ARRAY+=("$backup")
    ((i++))
  done
  
  # If there's only one backup, select it automatically
  if [ ${#BACKUP_ARRAY[@]} -eq 1 ]; then
    SELECTED_INDEX=1
  else
    # Prompt for selection if not forced
    if [ "$FORCE" = false ]; then
      read -p "Enter the number of the backup to restore (1-${#BACKUP_ARRAY[@]}): " SELECTED_INDEX
    else
      # Default to the most recent backup if forced
      SELECTED_INDEX=1
    fi
  fi
  
  if ! [[ "$SELECTED_INDEX" =~ ^[0-9]+$ ]] || [ "$SELECTED_INDEX" -lt 1 ] || [ "$SELECTED_INDEX" -gt ${#BACKUP_ARRAY[@]} ]; then
    echo -e "${RED}Error: Invalid selection${NC}"
    exit 1
  fi
  
  SELECTED_BACKUP="${BACKUP_ARRAY[$SELECTED_INDEX-1]}"
  echo -e "${YELLOW}Selected backup: $SELECTED_BACKUP${NC}"
  
  # Confirm rollback
  if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
    read -p "Are you sure you want to rollback to this version? (y/N): " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
      echo -e "${YELLOW}Rollback cancelled${NC}"
      exit 0
    fi
  fi
  
  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}Dry run: Would extract $SELECTED_BACKUP to $REMOTE_PATH${NC}"
  else
    echo -e "${YELLOW}Extracting backup...${NC}"
    $SSH_CMD "tar -xzf $SELECTED_BACKUP -C $REMOTE_PATH"
    echo -e "${GREEN}Rollback completed successfully!${NC}"
  fi
  
  exit 0
fi

# Check if deployment directory exists
if [ ! -d "${DEPLOYMENT_DIR}" ]; then
  echo -e "${RED}Error: Deployment directory not found. Run deploy.sh first.${NC}"
  exit 1
fi

# Run the local deployment script if needed
if [ -z "$(ls -A "${DEPLOYMENT_DIR}" 2>/dev/null)" ]; then
  echo -e "${RED}Error: Deployment directory is empty. Run deploy.sh first.${NC}"
  exit 1
fi

# Check deployment info file
if [ ! -f "${DEPLOYMENT_DIR}/deployment-info.json" ]; then
  echo -e "${YELLOW}Warning: No deployment info file found. Creating a basic one...${NC}"
  
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  GIT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
  GIT_COMMIT_SHORT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
  GIT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
  
  cat > "${DEPLOYMENT_DIR}/deployment-info.json" << EOF
{
  "timestamp": "$TIMESTAMP",
  "git_branch": "$GIT_BRANCH",
  "git_commit": "$GIT_COMMIT",
  "git_commit_short": "$GIT_COMMIT_SHORT",
  "deployed_by": "$(whoami)@$(hostname)"
}
EOF
fi

# Show deployment information
echo -e "${CYAN}Local deployment info:${NC}"
cat "${DEPLOYMENT_DIR}/deployment-info.json" | jq '.'

# Check for version file
if [ ! -f "${DEPLOYMENT_DIR}/version.json" ]; then
  echo -e "${YELLOW}Warning: No version tracking file found. Creating a basic one...${NC}"
  echo '{"versions": []}' > "${DEPLOYMENT_DIR}/version.json"
fi

# Confirm deployment if not forced
if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
  read -p "Are you sure you want to deploy to $ENVIRONMENT? (y/N): " CONFIRM
  if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo -e "${YELLOW}Deployment cancelled${NC}"
    exit 0
  fi
fi

# Run pre-deployment commands on the remote server
echo -e "${YELLOW}Running pre-deployment commands...${NC}"
PRE_DEPLOY_COMMANDS=$(jq -r ".environments.$ENVIRONMENT.preDeployCommands[]" "$CONFIG_FILE" 2>/dev/null)
if [ ! -z "$PRE_DEPLOY_COMMANDS" ]; then
  echo "$PRE_DEPLOY_COMMANDS" | while read -r cmd; do
    echo -e "${BLUE}Running: $cmd${NC}"
    if [ "$DRY_RUN" = false ]; then
      $SSH_CMD "$cmd" || echo -e "${RED}Warning: Command failed: $cmd${NC}"
    else
      echo -e "${YELLOW}Dry run: Would execute '$cmd' on remote host${NC}"
    fi
  done
fi

# Backup existing deployment if configured
if [ "$BACKUP_BEFORE_DEPLOY" == "true" ]; then
  echo -e "${YELLOW}Backing up existing deployment...${NC}"
  TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
  BACKUP_CMD="mkdir -p $BACKUP_LOCATION && if [ -d \"$REMOTE_PATH\" ]; then tar -czf $BACKUP_LOCATION/trackit_$TIMESTAMP.tar.gz -C $REMOTE_PATH .; fi"
  
  if [ "$DRY_RUN" = false ]; then
    $SSH_CMD "$BACKUP_CMD" || echo -e "${RED}Warning: Backup failed${NC}"
  else
    echo -e "${YELLOW}Dry run: Would back up remote deployment to $BACKUP_LOCATION/trackit_$TIMESTAMP.tar.gz${NC}"
  fi
fi

# Deploy the application
echo -e "${YELLOW}Deploying application to remote server...${NC}"
RSYNC_DELETE=""
if [ "$DELETE_REMOTE" == "true" ] && [ "$PRESERVE" == "false" ]; then
  echo -e "${YELLOW}Using --delete option: Files on server that don't exist locally will be removed${NC}"
  RSYNC_DELETE="--delete"
elif [ "$PRESERVE" == "true" ]; then
  echo -e "${GREEN}Preserve mode: Files on server that don't exist locally will be kept${NC}"
fi

# Add dry-run flag if needed
RSYNC_DRY_RUN=""
if [ "$DRY_RUN" = true ]; then
  RSYNC_DRY_RUN="--dry-run"
  echo -e "${YELLOW}DRY RUN MODE: No changes will be made to the server${NC}"
fi

echo -e "${YELLOW}Running rsync command:${NC}"
echo -e "${BLUE}rsync -avz --progress $RSYNC_DELETE $RSYNC_DRY_RUN -e \"ssh -p $PORT\" \"${DEPLOYMENT_DIR}\"/ $USERNAME@$HOST:$REMOTE_PATH/${NC}"

rsync -avz --progress $RSYNC_DELETE $RSYNC_DRY_RUN -e "ssh -p $PORT" "${DEPLOYMENT_DIR}"/ $USERNAME@$HOST:$REMOTE_PATH/

# Run post-deployment commands on the remote server
echo -e "${YELLOW}Running post-deployment commands...${NC}"
POST_DEPLOY_COMMANDS=$(jq -r ".environments.$ENVIRONMENT.postDeployCommands[]" "$CONFIG_FILE" 2>/dev/null)
if [ ! -z "$POST_DEPLOY_COMMANDS" ]; then
  echo "$POST_DEPLOY_COMMANDS" | while read -r cmd; do
    echo -e "${BLUE}Running: $cmd${NC}"
    if [ "$DRY_RUN" = false ]; then
      $SSH_CMD "$cmd" || echo -e "${RED}Warning: Command failed: $cmd${NC}"
    else
      echo -e "${YELLOW}Dry run: Would execute '$cmd' on remote host${NC}"
    fi
  done
fi

if [ "$DRY_RUN" = true ]; then
  echo -e "${YELLOW}Dry run completed. No changes were made.${NC}"
else
  echo -e "${GREEN}Deployment to $ENVIRONMENT completed successfully!${NC}"
  echo -e "${YELLOW}Your application is now available at: ${GREEN}https://$HOST${NC}"
fi

# Output information about preserve mode if it was used
if [ "$PRESERVE" == "true" ]; then
  echo -e "\n${YELLOW}Note: This deployment was done in preserve mode.${NC}"
  echo -e "${YELLOW}Files on the server that don't exist locally were preserved.${NC}"
  echo -e "${YELLOW}If you encounter issues, consider running deployment without the --preserve flag.${NC}"
fi

# Help information for further actions
echo -e "\n${CYAN}Next steps:${NC}"
echo -e "  - To check the deployed version: ${GREEN}./deploy-remote.sh --version${NC}"
echo -e "  - To rollback to a previous version: ${GREEN}./deploy-remote.sh --rollback${NC}"