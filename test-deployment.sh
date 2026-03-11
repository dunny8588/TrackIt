#!/bin/bash

# Test Deployment Script
# This script simulates a deployment without actually connecting to a remote server

set -e  # Exit immediately if a command exits with a non-zero status

# Colors for prettier output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting TrackIt Test Deployment Process${NC}"

# Run the local deployment script
echo -e "${YELLOW}Running local deployment script...${NC}"
./deploy.sh

# Define deployment directory
PARENT_DIR=$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")
DEPLOYMENT_DIR="${PARENT_DIR}/deployment"

# Check if deployment directory exists and contains files
if [ ! -d "${DEPLOYMENT_DIR}" ] || [ -z "$(ls -A "${DEPLOYMENT_DIR}" 2>/dev/null)" ]; then
  echo -e "${RED}Error: Deployment directory is empty or not found.${NC}"
  exit 1
fi

# Create a test deployment directory
TEST_DEPLOY_DIR="${PARENT_DIR}/test-deploy"
mkdir -p "${TEST_DEPLOY_DIR}"

# Simulate deployment
echo -e "${YELLOW}Simulating deployment to test directory...${NC}"
rsync -avz --delete "${DEPLOYMENT_DIR}"/ "${TEST_DEPLOY_DIR}"/

# Note: No need to set up flespi token - users will log in through the UI

echo -e "${GREEN}Test deployment completed successfully!${NC}"
echo -e "${YELLOW}Your application is now deployed to: ${GREEN}${TEST_DEPLOY_DIR}${NC}"
echo -e "${YELLOW}You can test it with: ${GREEN}cd ${TEST_DEPLOY_DIR} && python3 -m http.server 8080${NC}"
echo -e "${YELLOW}Then open http://localhost:8080 in your browser${NC}"