#!/bin/bash

# TrackIt Local Deployment Script (Improved Version)
# This script builds the TrackIt application and prepares it for deployment
# It now includes versioning and change tracking capabilities

set -e  # Exit immediately if a command exits with a non-zero status

# Colors for prettier output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=====================================${NC}"
echo -e "${YELLOW}   TrackIt Deployment Process        ${NC}"
echo -e "${YELLOW}=====================================${NC}"

# Get command line options
SHOW_VERSION=false
CREATE_VERSION=false
VERSION_MESSAGE=""
SKIP_BUILD=false

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --version)
      SHOW_VERSION=true
      shift
      ;;
    --create-version)
      CREATE_VERSION=true
      VERSION_MESSAGE="$2"
      shift
      shift
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    *)
      echo -e "${RED}Unknown option: $key${NC}"
      echo -e "Usage: ./deploy.sh [--version] [--create-version \"Version message\"] [--skip-build]"
      exit 1
      ;;
  esac
done

# Check if we're in the right directory
if [ ! -f "./TrackIt/package.json" ]; then
  echo -e "${RED}Error: Must be run from the parent directory of TrackIt${NC}"
  exit 1
fi

# Get Git commit information
echo -e "${BLUE}Checking Git status...${NC}"
CURRENT_BRANCH=$(git branch --show-current)
LATEST_COMMIT=$(git log -1 --pretty=format:"%h - %s (%cr) <%an>")
GIT_STATUS=$(git status --porcelain)

echo -e "${CYAN}Current branch: ${CURRENT_BRANCH}${NC}"
echo -e "${CYAN}Latest commit: ${LATEST_COMMIT}${NC}"

if [ ! -z "$GIT_STATUS" ]; then
  echo -e "${YELLOW}Warning: You have uncommitted changes:${NC}"
  echo -e "$GIT_STATUS"
  
  if [ "$CREATE_VERSION" = true ]; then
    echo -e "${RED}Error: Cannot create a version with uncommitted changes.${NC}"
    echo -e "${YELLOW}Please commit your changes first.${NC}"
    exit 1
  fi
fi

# Handle versioning
VERSION_FILE="deployment/version.json"
DEPLOYMENT_DIR="$(pwd)/deployment"

# Create the deployment directory if it doesn't exist
if [ ! -d "${DEPLOYMENT_DIR}" ]; then
  mkdir -p "${DEPLOYMENT_DIR}"
  echo -e "${GREEN}Created deployment directory at ${DEPLOYMENT_DIR}${NC}"
fi

# Check if version.json exists
if [ ! -f "$VERSION_FILE" ]; then
  echo -e "${YELLOW}Creating new version file...${NC}"
  echo '{"versions": []}' > "$VERSION_FILE"
fi

if [ "$SHOW_VERSION" = true ]; then
  echo -e "${CYAN}Deployment version history:${NC}"
  jq '.versions[-5:]' "$VERSION_FILE"
  exit 0
fi

if [ "$CREATE_VERSION" = true ]; then
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  GIT_COMMIT=$(git rev-parse HEAD)
  TMP_FILE=$(mktemp)
  
  jq --arg timestamp "$TIMESTAMP" \
     --arg message "$VERSION_MESSAGE" \
     --arg branch "$CURRENT_BRANCH" \
     --arg commit "$GIT_COMMIT" \
     '.versions += [{
        "timestamp": $timestamp,
        "message": $message,
        "branch": $branch,
        "commit": $commit
      }]' "$VERSION_FILE" > "$TMP_FILE"
  
  mv "$TMP_FILE" "$VERSION_FILE"
  echo -e "${GREEN}Created new version: $VERSION_MESSAGE${NC}"
fi

if [ "$SKIP_BUILD" = true ]; then
  echo -e "${YELLOW}Skipping build process...${NC}"
else
  # Enter the TrackIt directory
  cd TrackIt

  # Install dependencies if node_modules doesn't exist
  if [ ! -d "node_modules" ]; then
    echo -e "${YELLOW}Installing dependencies...${NC}"
    npm install
  else
    echo -e "${GREEN}Dependencies already installed${NC}"
  fi

  # Explicitly apply custom patches to ensure they're included in the build
  echo -e "${YELLOW}Applying custom patches...${NC}"
  if [ -f "custom_patches/install_custom_columns.sh" ]; then
    bash custom_patches/install_custom_columns.sh || echo -e "${RED}Failed to apply custom patches${NC}"
  else
    echo -e "${RED}Custom patches script not found${NC}"
  fi

  # Run linting (but continue if it fails)
  echo -e "${YELLOW}Running linting...${NC}"
  npm run lint || echo -e "${RED}Linting failed but continuing with deployment${NC}"

  # Build for production
  echo -e "${YELLOW}Building for production...${NC}"
  npm run build

  # Copy built files to deployment directory
  echo -e "${YELLOW}Copying built files to deployment directory...${NC}"
  rm -rf "${DEPLOYMENT_DIR}"/* 2>/dev/null || true
  cp -R dist/spa/* "${DEPLOYMENT_DIR}"/ || echo -e "${RED}Failed to copy dist/spa/* - check if build was successful${NC}"
  cp LICENSE "${DEPLOYMENT_DIR}"/ || echo -e "${RED}Failed to copy LICENSE${NC}"
  cp README.md "${DEPLOYMENT_DIR}/README.md" || echo -e "${RED}Failed to copy README.md${NC}"

  cd ..
fi

# Add version.json to the deployment directory if it's not there
if [ ! -f "${DEPLOYMENT_DIR}/version.json" ]; then
  cp "$VERSION_FILE" "${DEPLOYMENT_DIR}/version.json"
fi

# Create a deployment-info.json file with metadata
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=$(git rev-parse HEAD)
GIT_COMMIT_SHORT=$(git rev-parse --short HEAD)

cat > "${DEPLOYMENT_DIR}/deployment-info.json" << EOF
{
  "timestamp": "$TIMESTAMP",
  "git_branch": "$CURRENT_BRANCH",
  "git_commit": "$GIT_COMMIT",
  "git_commit_short": "$GIT_COMMIT_SHORT",
  "git_commit_message": "$(git log -1 --pretty=format:"%s")",
  "deployed_by": "$(whoami)@$(hostname)"
}
EOF

echo -e "${GREEN}Deployment preparation complete!${NC}"
echo -e "${YELLOW}Your built application is now in the deployment directory.${NC}"
echo -e "${YELLOW}To deploy to your server, you can now run a command like:${NC}"
echo -e "${GREEN}./deploy-remote.sh${NC}"
echo ""
echo -e "${YELLOW}To create a versioned deployment:${NC}"
echo -e "${GREEN}./deploy.sh --create-version \"Your version message here\"${NC}"
echo ""
echo -e "${YELLOW}To view deployment history:${NC}"
echo -e "${GREEN}./deploy.sh --version${NC}"