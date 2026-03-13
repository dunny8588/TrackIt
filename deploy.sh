#!/bin/bash

# TrackIt Unified Deployment Script
# Builds, deploys, and verifies in a single command.
# Run from the TrackIt repo root directory.

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

CONFIG_FILE="deploy-config.json"
ENVIRONMENT="production"

# Flags
DRY_RUN=false
FORCE=false
SHOW_VERSION=false
ROLLBACK=false
SKIP_BUILD=false
VERSION_MESSAGE=""
CREATE_VERSION=false

function show_help {
  echo -e "${CYAN}Usage:${NC} ./deploy.sh [options]"
  echo ""
  echo -e "${CYAN}Options:${NC}"
  echo -e "  --dry-run              Simulate deployment without making changes"
  echo -e "  --force                Skip confirmation prompts"
  echo -e "  --skip-build           Skip the build step (use existing dist/)"
  echo -e "  --version              Show remote deployment version"
  echo -e "  --create-version MSG   Tag this deploy with a version message"
  echo -e "  --rollback             Rollback to previous server backup"
  echo -e "  --environment ENV      Target environment (default: production)"
  echo -e "  --help                 Show this help message"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)      DRY_RUN=true; shift ;;
    --force)        FORCE=true; shift ;;
    --skip-build)   SKIP_BUILD=true; shift ;;
    --version)      SHOW_VERSION=true; shift ;;
    --create-version) CREATE_VERSION=true; VERSION_MESSAGE="$2"; shift; shift ;;
    --rollback)     ROLLBACK=true; shift ;;
    --environment)  ENVIRONMENT="$2"; shift; shift ;;
    --help)         show_help; exit 0 ;;
    *)              echo -e "${RED}Unknown option: $1${NC}"; show_help; exit 1 ;;
  esac
done

# --- Prerequisites ---

function check_prereqs {
  local missing=()
  command -v node >/dev/null 2>&1  || missing+=("node")
  command -v npx >/dev/null 2>&1   || missing+=("npx")
  command -v rsync >/dev/null 2>&1 || missing+=("rsync")
  command -v jq >/dev/null 2>&1    || missing+=("jq (apt install jq)")
  command -v curl >/dev/null 2>&1  || missing+=("curl")

  if [ ${#missing[@]} -gt 0 ]; then
    echo -e "${RED}Missing required tools:${NC}"
    for tool in "${missing[@]}"; do
      echo -e "  - $tool"
    done
    exit 1
  fi
}

function load_config {
  if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: $CONFIG_FILE not found. Are you in the TrackIt repo root?${NC}"
    exit 1
  fi

  HOST=$(jq -r ".environments.$ENVIRONMENT.host" "$CONFIG_FILE")
  PORT=$(jq -r ".environments.$ENVIRONMENT.port" "$CONFIG_FILE")
  USERNAME=$(jq -r ".environments.$ENVIRONMENT.username" "$CONFIG_FILE")
  REMOTE_PATH=$(jq -r ".environments.$ENVIRONMENT.remotePath" "$CONFIG_FILE")
  BACKUP_BEFORE_DEPLOY=$(jq -r ".deploymentSettings.backupBeforeDeploy" "$CONFIG_FILE")
  BACKUP_LOCATION=$(jq -r ".deploymentSettings.backupLocation" "$CONFIG_FILE")
  DELETE_REMOTE=$(jq -r ".deploymentSettings.deleteRemote" "$CONFIG_FILE")

  if [ "$HOST" = "null" ] || [ "$USERNAME" = "null" ] || [ "$REMOTE_PATH" = "null" ]; then
    echo -e "${RED}Error: Missing config for '$ENVIRONMENT' environment${NC}"
    exit 1
  fi

  SSH_CMD="ssh -p $PORT $USERNAME@$HOST"
}

# --- Load config and check prereqs ---

check_prereqs
load_config

if [ ! -f "package.json" ]; then
  echo -e "${RED}Error: package.json not found. Run this script from the TrackIt repo root.${NC}"
  exit 1
fi

# --- Show remote version ---

if [ "$SHOW_VERSION" = true ]; then
  echo -e "${CYAN}Remote deployment info:${NC}"
  $SSH_CMD "cat $REMOTE_PATH/deployment-info.json 2>/dev/null || echo '{\"error\": \"No deployment info found\"}'" | jq '.'
  exit 0
fi

# --- Rollback ---

if [ "$ROLLBACK" = true ]; then
  echo -e "${YELLOW}Checking available backups...${NC}"
  BACKUPS=$($SSH_CMD "find $BACKUP_LOCATION -name 'trackit_*.tar.gz' -type f -printf '%T@ %p\n' | sort -nr | head -10 | cut -d' ' -f2-")

  if [ -z "$BACKUPS" ]; then
    echo -e "${RED}No backups found in $BACKUP_LOCATION${NC}"
    exit 1
  fi

  echo -e "${CYAN}Available backups:${NC}"
  IFS=$'\n'
  BACKUP_ARRAY=()
  i=1
  for backup in $BACKUPS; do
    echo -e "  $i) $(basename "$backup")"
    BACKUP_ARRAY+=("$backup")
    ((i++))
  done

  if [ "$FORCE" = true ]; then
    SELECTED_INDEX=1
  else
    read -p "Select backup to restore (1-${#BACKUP_ARRAY[@]}): " SELECTED_INDEX
  fi

  if ! [[ "$SELECTED_INDEX" =~ ^[0-9]+$ ]] || [ "$SELECTED_INDEX" -lt 1 ] || [ "$SELECTED_INDEX" -gt ${#BACKUP_ARRAY[@]} ]; then
    echo -e "${RED}Invalid selection${NC}"
    exit 1
  fi

  SELECTED_BACKUP="${BACKUP_ARRAY[$SELECTED_INDEX-1]}"

  if [ "$FORCE" = false ]; then
    read -p "Rollback to $(basename "$SELECTED_BACKUP")? (y/N): " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
      echo -e "${YELLOW}Cancelled${NC}"
      exit 0
    fi
  fi

  echo -e "${YELLOW}Restoring backup...${NC}"
  $SSH_CMD "tar -xzf $SELECTED_BACKUP -C $REMOTE_PATH"
  $SSH_CMD "systemctl reload nginx"
  echo -e "${GREEN}Rollback complete.${NC}"
  exit 0
fi

# --- Git info ---

echo -e "${YELLOW}=====================================${NC}"
echo -e "${YELLOW}   TrackIt Deploy                    ${NC}"
echo -e "${YELLOW}=====================================${NC}"

CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
GIT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
GIT_COMMIT_SHORT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_MESSAGE=$(git log -1 --pretty=format:"%s" 2>/dev/null || echo "unknown")

echo -e "${CYAN}Branch:${NC} $CURRENT_BRANCH"
echo -e "${CYAN}Commit:${NC} $GIT_COMMIT_SHORT - $GIT_MESSAGE"

GIT_STATUS=$(git status --porcelain 2>/dev/null)
if [ -n "$GIT_STATUS" ]; then
  echo -e "${YELLOW}Warning: uncommitted changes present${NC}"
fi

# --- Version tagging ---

if [ "$CREATE_VERSION" = true ]; then
  if [ -n "$GIT_STATUS" ]; then
    echo -e "${RED}Cannot create version with uncommitted changes. Commit first.${NC}"
    exit 1
  fi

  VERSION_FILE="version.json"
  if [ ! -f "$VERSION_FILE" ]; then
    echo '{"versions": []}' > "$VERSION_FILE"
  fi

  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  TMP_FILE=$(mktemp)
  jq --arg ts "$TIMESTAMP" \
     --arg msg "$VERSION_MESSAGE" \
     --arg branch "$CURRENT_BRANCH" \
     --arg commit "$GIT_COMMIT" \
     '.versions += [{"timestamp": $ts, "message": $msg, "branch": $branch, "commit": $commit}]' \
     "$VERSION_FILE" > "$TMP_FILE"
  mv "$TMP_FILE" "$VERSION_FILE"
  echo -e "${GREEN}Version tagged: $VERSION_MESSAGE${NC}"
fi

# --- Build ---

if [ "$SKIP_BUILD" = true ]; then
  echo -e "${YELLOW}Skipping build (using existing dist/spa/)${NC}"
  if [ ! -d "dist/spa" ]; then
    echo -e "${RED}Error: dist/spa/ does not exist. Run without --skip-build.${NC}"
    exit 1
  fi
else
  # Apply custom patches before build
  if [ -f "custom_patches/install_custom_columns.sh" ]; then
    echo -e "${YELLOW}Applying custom patches...${NC}"
    bash custom_patches/install_custom_columns.sh || echo -e "${RED}Warning: patch script failed${NC}"
  fi

  echo -e "${YELLOW}Building for production...${NC}"
  npx quasar build -m spa

  if [ ! -d "dist/spa" ]; then
    echo -e "${RED}Build failed: dist/spa/ not created${NC}"
    exit 1
  fi
fi

# --- Generate deployment metadata ---

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
cat > "dist/spa/deployment-info.json" << DEOF
{
  "timestamp": "$TIMESTAMP",
  "git_branch": "$CURRENT_BRANCH",
  "git_commit": "$GIT_COMMIT",
  "git_commit_short": "$GIT_COMMIT_SHORT",
  "git_commit_message": "$GIT_MESSAGE",
  "deployed_by": "$(whoami)@$(hostname)"
}
DEOF

# Copy version.json into dist if it exists
if [ -f "version.json" ]; then
  cp version.json dist/spa/version.json
fi

echo -e "${GREEN}Build complete. Commit: $GIT_COMMIT_SHORT${NC}"

# --- Confirm ---

if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
  read -p "Deploy to $ENVIRONMENT ($HOST)? (y/N): " CONFIRM
  if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo -e "${YELLOW}Cancelled${NC}"
    exit 0
  fi
fi

# --- Backup on server ---

if [ "$BACKUP_BEFORE_DEPLOY" = "true" ] && [ "$DRY_RUN" = false ]; then
  echo -e "${YELLOW}Backing up current deployment...${NC}"
  BACKUP_TS=$(date +"%Y%m%d_%H%M%S")
  $SSH_CMD "mkdir -p $BACKUP_LOCATION" || true
  $SSH_CMD "if [ -d '$REMOTE_PATH' ] && [ -f '$REMOTE_PATH/index.html' ]; then tar -czf $BACKUP_LOCATION/trackit_$BACKUP_TS.tar.gz -C $REMOTE_PATH .; fi" || echo -e "${RED}Warning: backup failed${NC}"
fi

# --- Deploy ---

RSYNC_FLAGS="-avz --progress"
if [ "$DELETE_REMOTE" = "true" ]; then
  RSYNC_FLAGS="$RSYNC_FLAGS --delete"
fi
if [ "$DRY_RUN" = true ]; then
  RSYNC_FLAGS="$RSYNC_FLAGS --dry-run"
fi

echo -e "${YELLOW}Deploying to $HOST:$REMOTE_PATH ...${NC}"
$SSH_CMD "mkdir -p $REMOTE_PATH" || true
rsync $RSYNC_FLAGS -e "ssh -p $PORT" dist/spa/ "$USERNAME@$HOST:$REMOTE_PATH/"

if [ "$DRY_RUN" = true ]; then
  echo -e "${YELLOW}Dry run complete. No changes made.${NC}"
  exit 0
fi

# --- Reload nginx ---

echo -e "${YELLOW}Reloading nginx...${NC}"
$SSH_CMD "systemctl reload nginx"

# --- Verify ---

echo -e "${YELLOW}Verifying deployment...${NC}"
sleep 2

REMOTE_INFO=$(curl -sf "https://$HOST/deployment-info.json" 2>/dev/null || echo "")

if [ -z "$REMOTE_INFO" ]; then
  echo -e "${RED}Warning: Could not fetch deployment-info.json from https://$HOST${NC}"
  echo -e "${YELLOW}Deployment may have succeeded but verification failed.${NC}"
  echo -e "${YELLOW}Check manually: https://$HOST${NC}"
  exit 0
fi

REMOTE_COMMIT=$(echo "$REMOTE_INFO" | jq -r '.git_commit' 2>/dev/null || echo "")

if [ "$REMOTE_COMMIT" = "$GIT_COMMIT" ]; then
  echo -e "${GREEN}=====================================${NC}"
  echo -e "${GREEN}  Deployment verified!               ${NC}"
  echo -e "${GREEN}  Commit $GIT_COMMIT_SHORT is live   ${NC}"
  echo -e "${GREEN}  https://$HOST                      ${NC}"
  echo -e "${GREEN}=====================================${NC}"
else
  echo -e "${RED}Verification failed!${NC}"
  echo -e "${RED}Expected commit: $GIT_COMMIT${NC}"
  echo -e "${RED}Remote commit:   $REMOTE_COMMIT${NC}"
  echo -e "${YELLOW}This may be a caching issue. Try: curl -H 'Cache-Control: no-cache' https://$HOST/deployment-info.json${NC}"
  exit 1
fi
