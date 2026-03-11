# TrackIt Deployment Guide

This document explains how to deploy the TrackIt application using the provided deployment scripts.

## Prerequisites

- Node.js (>=18.x) and npm (>=10.x)
- Git
- SSH access to your deployment server
- `jq` installed locally (for parsing JSON config)
- `rsync` for file transfers

To install the required tools on Ubuntu/Debian:
```bash
sudo apt update
sudo apt install -y jq rsync
```

## Configuration

The deployment process uses a configuration file called `deploy-config.json`. You should update this file with your specific server details:

1. Update the `username` field with your server username
2. Verify the `host` field has the correct server hostname/IP
3. Set the correct `remotePath` where you want the application deployed
4. Add your flespi.io token to the `flespiToken` field if needed
5. Customize any pre/post deployment commands as needed

Example configuration:
```json
{
  "environments": {
    "production": {
      "host": "t.backpedal.co",
      "port": 22,
      "username": "your-username",
      "remotePath": "/var/www/trackit",
      "preDeployCommands": [
        "mkdir -p /var/www/trackit",
        "chown -R $USER:$USER /var/www/trackit"
      ],
      "postDeployCommands": [
        "systemctl restart nginx"
      ]
    }
  },
  "deploymentSettings": {
    "deleteRemote": true,
    "backupBeforeDeploy": true,
    "backupLocation": "/var/backups/trackit",
    "flespiToken": "YOUR_FLESPI_TOKEN_HERE"
  }
}
```

## Deployment Process

### Local Deployment

To prepare the application for deployment:

```bash
./deploy.sh
```

This script:
1. Installs dependencies if needed
2. Lints the code (continues even if linting fails)
3. Builds the production version
4. Copies the build artifacts to the `deployment` directory

### Test Deployment (Local)

For testing your deployment locally without connecting to a remote server:

```bash
./test-deployment.sh
```

This script:
1. Runs the local deployment script
2. Creates a test deployment directory (`test-deploy`)
3. Copies all files from the deployment directory to the test directory
4. Sets up a test flespi token configuration
5. Provides instructions for testing with a local web server

### Remote Deployment

To deploy to your server:

```bash
./deploy-remote.sh --environment production
```

This script:
1. Reads configuration from `deploy-config.json`
2. Runs any configured pre-deployment commands on the remote server
3. Creates a backup of the existing deployment if configured
4. Uploads the application to the remote server using rsync
5. Sets up flespi token configuration if provided
6. Runs any configured post-deployment commands

### Deployment Options

The `deploy-remote.sh` script accepts the following options:

- `-e, --environment`: The environment to deploy to (default: production)
- `-c, --config`: Path to the configuration file (default: deploy-config.json)

Example:
```bash
./deploy-remote.sh --environment staging --config custom-config.json
```

## Nginx Configuration (Example)

Here's an example Nginx configuration for hosting the TrackIt application:

```nginx
server {
    listen 80;
    server_name t.backpedal.co;
    
    # Redirect HTTP to HTTPS
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name t.backpedal.co;
    
    ssl_certificate /etc/letsencrypt/live/t.backpedal.co/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/t.backpedal.co/privkey.pem;
    
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
```

## Troubleshooting

### Permission Issues
If you encounter permission issues on the remote server, ensure your user has write access to the deployment directory:

```bash
sudo chown -R your-username:your-username /var/www/trackit
```

### Backup Failures
If backups are failing, ensure the backup directory exists and has correct permissions:

```bash
sudo mkdir -p /var/backups/trackit
sudo chown -R your-username:your-username /var/backups/trackit
```

### Nginx Issues
If the application is deployed but not accessible, check your Nginx configuration and restart Nginx:

```bash
sudo nginx -t
sudo systemctl restart nginx
```

### SSH Key Authentication
For passwordless deployment, set up SSH key authentication:

```bash
ssh-copy-id -i ~/.ssh/id_rsa.pub username@t.backpedal.co
```