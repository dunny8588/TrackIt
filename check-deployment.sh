#!/bin/bash

# TrackIt Deployment Status Checker
# This script checks the status of the TrackIt deployment on the remote server
# and compares it with the local version

set -e  # Exit immediately if a command exits with a non-zero status

# Colors for prettier output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=====================================${NC}"
echo -e "${YELLOW}   TrackIt Deployment Status Check   ${NC}"
echo -e "${YELLOW}=====================================${NC}"

CONFIG_FILE="deploy-config.json"
ENVIRONMENT="production"  # Default environment

# Parse command line arguments
COMPARE=false
DIFF_CHECK=false

function show_help {
  echo -e "${CYAN}Usage:${NC} ./check-deployment.sh [options]"
  echo -e ""
  echo -e "${CYAN}Options:${NC}"
  echo -e "  -e, --environment ENV   Set environment to check (default: production)"
  echo -e "  -c, --config FILE       Set config file (default: deploy-config.json)"
  echo -e "  -d, --diff              Compare local and remote versions"
  echo -e "  -f, --full-diff         Download and perform a full diff of files"
  echo -e "  -h, --help              Show this help message"
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
    -d|--diff)
      COMPARE=true
      shift
      ;;
    -f|--full-diff)
      DIFF_CHECK=true
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

# Check if required configuration is available
if [ "$HOST" == "null" ] || [ "$USERNAME" == "null" ] || [ "$REMOTE_PATH" == "null" ]; then
  echo -e "${RED}Error: Missing required configuration for $ENVIRONMENT environment${NC}"
  exit 1
fi

# Define deployment directory - look for it in the current directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_DIR="${SCRIPT_DIR}/deployment"
SERVER_FILES_DIR="${SCRIPT_DIR}/current-server-files"

# Create SSH command with port
SSH_CMD="ssh -p $PORT $USERNAME@$HOST"

echo -e "${CYAN}Checking deployment status for ${YELLOW}$ENVIRONMENT${CYAN} environment...${NC}"

# Check server status
echo -e "\n${CYAN}Server Status:${NC}"
SERVER_STATUS=$($SSH_CMD "uptime" 2>/dev/null)
if [ $? -eq 0 ]; then
  echo -e "${GREEN}Server is running${NC}"
  echo -e "${BLUE}$SERVER_STATUS${NC}"
else
  echo -e "${RED}Server is not reachable${NC}"
  exit 1
fi

# Check if deployment directory exists on server
REMOTE_DIR_CHECK=$($SSH_CMD "[ -d \"$REMOTE_PATH\" ] && echo \"exists\" || echo \"not found\"")
if [ "$REMOTE_DIR_CHECK" == "exists" ]; then
  echo -e "${GREEN}Deployment directory exists on server${NC}"
else
  echo -e "${RED}Deployment directory does not exist on server${NC}"
  exit 1
fi

# Check Nginx status
NGINX_STATUS=$($SSH_CMD "systemctl is-active nginx" 2>/dev/null)
if [ "$NGINX_STATUS" == "active" ]; then
  echo -e "${GREEN}Nginx is running${NC}"
else
  echo -e "${RED}Nginx is not running${NC}"
fi

# Get remote deployment info
echo -e "\n${CYAN}Remote Deployment Information:${NC}"
REMOTE_INFO=$($SSH_CMD "if [ -f \"$REMOTE_PATH/deployment-info.json\" ]; then cat \"$REMOTE_PATH/deployment-info.json\"; else echo '{\"error\": \"No deployment information found\"}'; fi")
echo "$REMOTE_INFO" | jq '.'

# Get recent changes
echo -e "\n${CYAN}Recent Deployment History:${NC}"
$SSH_CMD "if [ -f \"$REMOTE_PATH/version.json\" ]; then cat \"$REMOTE_PATH/version.json\"; else echo '{\"versions\": []}'; fi" | jq '.versions[-3:]'

# Check for the index.html file
INDEX_CHECK=$($SSH_CMD "[ -f \"$REMOTE_PATH/index.html\" ] && echo \"exists\" || echo \"not found\"")
if [ "$INDEX_CHECK" == "exists" ]; then
  echo -e "\n${GREEN}Application index.html file exists${NC}"
else
  echo -e "\n${RED}Application index.html file not found${NC}"
fi

# Get file count
FILE_COUNT=$($SSH_CMD "find \"$REMOTE_PATH\" -type f | wc -l")
echo -e "${BLUE}Total files in deployment: $FILE_COUNT${NC}"

# Check last modified time of key files
echo -e "\n${CYAN}Last Modified Times:${NC}"
$SSH_CMD "find \"$REMOTE_PATH\" -name \"*.js\" -o -name \"*.css\" -o -name \"index.html\" | sort | head -5 | xargs ls -lth" | awk '{print $6, $7, $8, $9}'

# Compare local and remote versions if requested
if [ "$COMPARE" = true ]; then
  if [ -f "${DEPLOYMENT_DIR}/deployment-info.json" ]; then
    echo -e "\n${CYAN}Comparing Local vs Remote Deployment:${NC}"
    LOCAL_INFO=$(cat "${DEPLOYMENT_DIR}/deployment-info.json")
    
    LOCAL_TIMESTAMP=$(echo "$LOCAL_INFO" | jq -r '.timestamp')
    REMOTE_TIMESTAMP=$(echo "$REMOTE_INFO" | jq -r '.timestamp')
    
    LOCAL_COMMIT=$(echo "$LOCAL_INFO" | jq -r '.git_commit_short')
    REMOTE_COMMIT=$(echo "$REMOTE_INFO" | jq -r '.git_commit_short')
    
    echo -e "${YELLOW}Timestamp:${NC}"
    echo -e "  Local:  ${BLUE}$LOCAL_TIMESTAMP${NC}"
    echo -e "  Remote: ${BLUE}$REMOTE_TIMESTAMP${NC}"
    
    echo -e "${YELLOW}Git Commit:${NC}"
    echo -e "  Local:  ${BLUE}$LOCAL_COMMIT${NC}"
    echo -e "  Remote: ${BLUE}$REMOTE_COMMIT${NC}"
    
    if [ "$LOCAL_COMMIT" == "$REMOTE_COMMIT" ]; then
      echo -e "\n${GREEN}✓ Local and remote deployments match!${NC}"
    else
      echo -e "\n${RED}✗ Local and remote deployments differ!${NC}"
      
      if [ -x "$(command -v git)" ]; then
        echo -e "\n${CYAN}Commit Differences:${NC}"
        if [ "$REMOTE_COMMIT" != "unknown" ] && [ "$LOCAL_COMMIT" != "unknown" ]; then
          git log --oneline "$REMOTE_COMMIT..$LOCAL_COMMIT" 2>/dev/null || echo -e "${RED}Cannot compare commits${NC}"
        else
          echo -e "${RED}Cannot compare commits - unknown commit hashes${NC}"
        fi
      fi
    fi
  else
    echo -e "\n${RED}Local deployment info not found${NC}"
  fi
fi

# Perform full diff check if requested
if [ "$DIFF_CHECK" = true ]; then
  # Check if deployment directory exists
  if [ ! -d "${DEPLOYMENT_DIR}" ]; then
    echo -e "${RED}Error: Deployment directory not found. Run deploy.sh first.${NC}"
    exit 1
  fi
  
  # Create/clear the server files directory
  echo -e "\n${YELLOW}Creating/clearing directory for server files...${NC}"
  mkdir -p "${SERVER_FILES_DIR}"
  rm -rf "${SERVER_FILES_DIR:?}"/* # :? prevents rm -rf / if the variable is empty
  
  # Download current server files
  echo -e "${YELLOW}Downloading current server files from ${USERNAME}@${HOST}:${REMOTE_PATH}/...${NC}"
  rsync -avz -e "ssh -p $PORT" $USERNAME@$HOST:$REMOTE_PATH/ "${SERVER_FILES_DIR}/"
  
  # Compare key files to see differences
  echo -e "${YELLOW}Comparing key files and assets...${NC}"
  
  # Check for differences in JavaScript files
  echo -e "${BLUE}Checking JavaScript files:${NC}"
  for file in $(find "${DEPLOYMENT_DIR}" -name "*.js" | sort); do
    rel_path="${file#${DEPLOYMENT_DIR}/}"
    server_file="${SERVER_FILES_DIR}/${rel_path}"
    
    if [ -f "$server_file" ]; then
      if diff -q "$file" "$server_file" >/dev/null; then
        echo -e "✅ ${GREEN}${rel_path} is identical${NC}"
      else
        echo -e "❌ ${RED}${rel_path} has differences${NC}"
        diff -u "$server_file" "$file" | head -20 # Show first 20 lines of differences
      fi
    else
      echo -e "⚠️ ${YELLOW}${rel_path} only exists locally, will be added to server${NC}"
    fi
  done
  
  # Check for differences in CSS files
  echo -e "\n${BLUE}Checking CSS files:${NC}"
  for file in $(find "${DEPLOYMENT_DIR}" -name "*.css" | sort); do
    rel_path="${file#${DEPLOYMENT_DIR}/}"
    server_file="${SERVER_FILES_DIR}/${rel_path}"
    
    if [ -f "$server_file" ]; then
      if diff -q "$file" "$server_file" >/dev/null; then
        echo -e "✅ ${GREEN}${rel_path} is identical${NC}"
      else
        echo -e "❌ ${RED}${rel_path} has differences${NC}"
        diff -u "$server_file" "$file" | head -20 # Show first 20 lines of differences
      fi
    else
      echo -e "⚠️ ${YELLOW}${rel_path} only exists locally, will be added to server${NC}"
    fi
  done
  
  # Check for differences in HTML files
  echo -e "\n${BLUE}Checking HTML files:${NC}"
  for file in $(find "${DEPLOYMENT_DIR}" -name "*.html" | sort); do
    rel_path="${file#${DEPLOYMENT_DIR}/}"
    server_file="${SERVER_FILES_DIR}/${rel_path}"
    
    if [ -f "$server_file" ]; then
      if diff -q "$file" "$server_file" >/dev/null; then
        echo -e "✅ ${GREEN}${rel_path} is identical${NC}"
      else
        echo -e "❌ ${RED}${rel_path} has differences${NC}"
        diff -u "$server_file" "$file" | head -20 # Show first 20 lines of differences
      fi
    else
      echo -e "⚠️ ${YELLOW}${rel_path} only exists locally, will be added to server${NC}"
    fi
  done
  
  # Check for files that only exist on the server but not in deployment
  echo -e "\n${BLUE}Checking for files only on server:${NC}"
  for file in $(find "${SERVER_FILES_DIR}" -type f -name "*.js" -o -name "*.css" -o -name "*.html" | sort); do
    rel_path="${file#${SERVER_FILES_DIR}/}"
    local_file="${DEPLOYMENT_DIR}/${rel_path}"
    
    if [ ! -f "$local_file" ]; then
      echo -e "⚠️ ${YELLOW}${rel_path} only exists on server and will be ${RED}DELETED${NC} if you deploy with --delete option"
    fi
  done
  
  echo -e "\n${GREEN}Diff check completed. Review the above output to understand what changes will be made during deployment.${NC}"
  echo -e "${YELLOW}To deploy without deleting remote files, use: ./deploy-remote.sh --preserve${NC}"
fi

echo -e "\n${CYAN}Deployment Check Complete${NC}"
echo -e "${YELLOW}=====================================${NC}"