# TrackIt Deployment Guide for t.backpedal.co

This guide provides specific instructions for deploying the TrackIt application to your t.backpedal.co server.

## Preparation

1. Make sure you have the required tools installed:
   ```bash
   sudo apt update
   sudo apt install -y jq rsync
   ```

2. Update the deployment configuration in `deploy-config.json`:
   ```json
   {
     "environments": {
       "production": {
         "host": "t.backpedal.co",
         "port": 22,
         "username": "your-username",  // Replace with your actual username
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
       "backupLocation": "/var/backups/trackit"
     }
   }
   ```

3. Set up SSH key authentication for passwordless login (optional but recommended):
   ```bash
   ssh-copy-id -i ~/.ssh/id_rsa.pub your-username@t.backpedal.co
   ```

## Test Locally

Before deploying to the server, it's a good idea to test the build locally:

```bash
./test-deployment.sh
```

This will create a local test deployment and provide instructions for testing with a local web server.

## Deployment Process

1. Build and prepare the application:
   ```bash
   ./deploy.sh
   ```

2. Deploy to the server:
   ```bash
   ./deploy-remote.sh --environment production
   ```

3. Verify the deployment by visiting: `https://t.backpedal.co`

## Server Configuration

If this is the first time setting up the server, you'll need to configure Nginx:

1. Connect to your server:
   ```bash
   ssh your-username@t.backpedal.co
   ```

2. Install Nginx if not already installed:
   ```bash
   sudo apt update
   sudo apt install -y nginx
   ```

3. Create an Nginx configuration file:
   ```bash
   sudo nano /etc/nginx/sites-available/trackit
   ```

4. Add the following configuration:
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
       
       # SSL configuration (install certbot and run it to get SSL certificates)
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

5. Create a symbolic link to enable the site:
   ```bash
   sudo ln -s /etc/nginx/sites-available/trackit /etc/nginx/sites-enabled/
   ```

6. Install SSL certificates with Let's Encrypt:
   ```bash
   sudo apt install -y certbot python3-certbot-nginx
   sudo certbot --nginx -d t.backpedal.co
   ```

7. Test Nginx configuration and restart:
   ```bash
   sudo nginx -t
   sudo systemctl restart nginx
   ```

## Troubleshooting

### Common Issues

1. **Permission Denied**: Make sure your user has write permissions to the specified directories.
   ```bash
   sudo chown -R your-username:your-username /var/www/trackit
   sudo chown -R your-username:your-username /var/backups/trackit
   ```

2. **Nginx Error**: Check the Nginx error logs for details.
   ```bash
   sudo tail -f /var/log/nginx/error.log
   ```

3. **Backup Fails**: Ensure the backup directory exists and has correct permissions.
   ```bash
   sudo mkdir -p /var/backups/trackit
   sudo chown -R your-username:your-username /var/backups/trackit
   ```

4. **App Not Loading**: Make sure the application is properly deployed. Users will need to log in with their flespi.io credentials when they access the app.

## Maintenance

### Manual Backup

To create a manual backup of your deployment:

```bash
ssh your-username@t.backpedal.co "tar -czf /var/backups/trackit/manual_$(date +%Y%m%d_%H%M%S).tar.gz -C /var/www/trackit ."
```

### Updating the Application

To update the application, simply run the deployment process again:

```bash
./deploy.sh
./deploy-remote.sh --environment production
```

### Cleaning Old Backups

To clean up old backups on the server:

```bash
ssh your-username@t.backpedal.co "find /var/backups/trackit -name \"*.tar.gz\" -type f -mtime +30 -delete"
```

This will remove backups older than 30 days.