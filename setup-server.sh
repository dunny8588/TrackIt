#!/bin/bash

# Script to set up the web server for TrackIt on t.backpedal.co
# Must be run as root on the server

set -e  # Exit immediately if a command exits with a non-zero status

# Colors for prettier output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Setting up web server for TrackIt on t.backpedal.co${NC}"

# Update package lists
echo -e "${BLUE}Updating package lists...${NC}"
apt update

# Install required packages
echo -e "${BLUE}Installing required packages...${NC}"
apt install -y nginx certbot python3-certbot-nginx

# Create web directory
echo -e "${BLUE}Creating web directory...${NC}"
mkdir -p /var/www/trackit
chown -R www-data:www-data /var/www/trackit

# Create backup directory
echo -e "${BLUE}Creating backup directory...${NC}"
mkdir -p /var/backups/trackit
chown -R root:root /var/backups/trackit

# Create Nginx configuration
echo -e "${BLUE}Creating Nginx configuration...${NC}"
cat > /etc/nginx/sites-available/trackit << 'EOF'
server {
    listen 80;
    server_name t.backpedal.co;
    
    root /var/www/trackit;
    index index.html;
    
    # Enable gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript;
    
    location / {
        try_files $uri $uri/ /index.html;
    }
    
    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }
}
EOF

# Enable the site
echo -e "${BLUE}Enabling the site...${NC}"
ln -sf /etc/nginx/sites-available/trackit /etc/nginx/sites-enabled/

# Remove default site if it exists
if [ -f /etc/nginx/sites-enabled/default ]; then
    echo -e "${BLUE}Removing default site...${NC}"
    rm -f /etc/nginx/sites-enabled/default
fi

# Test Nginx configuration
echo -e "${BLUE}Testing Nginx configuration...${NC}"
nginx -t

# Restart Nginx
echo -e "${BLUE}Restarting Nginx...${NC}"
systemctl restart nginx

# Set up SSL with Let's Encrypt
echo -e "${BLUE}Setting up SSL with Let's Encrypt...${NC}"
certbot --nginx -d t.backpedal.co --non-interactive --agree-tos --email admin@backpedal.co

echo -e "${GREEN}Server setup complete!${NC}"
echo -e "${YELLOW}You can now deploy the TrackIt application using the deployment scripts.${NC}"