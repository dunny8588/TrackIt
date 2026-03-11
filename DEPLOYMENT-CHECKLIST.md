# TrackIt Deployment Checklist

This checklist will help you deploy the TrackIt application using the improved deployment process with version tracking and rollback capabilities.

## Prerequisites

- [x] Node.js >=18.x and npm >=10.x installed
- [x] Git installed and repository cloned
- [x] SSH access to deployment server
- [x] `jq` utility installed (run `sudo apt-get install jq` if needed)
- [x] `rsync` installed (standard on most systems)

## Initial Server Setup

When setting up a new server:

- [ ] Upload the setup script: `scp setup-server.sh root@t.backpedal.co:~/`
- [ ] Run the setup script: `ssh root@t.backpedal.co "bash ~/setup-server.sh"`

This script:
- Installs Nginx and Certbot
- Creates necessary directories
- Configures Nginx with a basic configuration
- Sets up SSL with Let's Encrypt

## Git Workflow

1. **Create Feature Branch**

   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make Changes and Commit**

   ```bash
   git add .
   git commit -m "Descriptive message about your changes"
   ```

3. **Push Changes to GitHub**

   ```bash
   git push origin feature/your-feature-name
   ```

4. **Create Pull Request**
   - Go to GitHub and create a PR from your feature branch to the master branch
   - Get code review if needed
   - Merge the PR when approved

5. **Switch to Master and Pull Latest**

   ```bash
   git checkout master
   git pull origin master
   ```

## Deployment Steps

1. **Build for Deployment**

   ```bash
   cd /home/james/my-claude-project
   ./deploy.sh --create-version "Version description here"
   ```

   This will:
   - Record version information linked to the Git commit
   - Build the TrackIt app for production
   - Copy the built files to the deployment directory
   - Include version tracking files

2. **Test Deployment Locally** (Optional)

   ```bash
   ./deploy-remote.sh --dry-run
   ```

   This will:
   - Show what would be deployed without making changes
   - Verify SSH connection and configuration

3. **Deploy to Server**

   ```bash
   ./deploy-remote.sh --environment production
   ```

   This will:
   - Confirm the deployment interactively
   - Connect to the server using SSH
   - Back up any existing deployment
   - Upload the new files with version tracking
   - Run any post-deployment commands

4. **Verify the Deployment**

   ```bash
   ./deploy-remote.sh --version
   ```

   This will show the currently deployed version information.

   Then:
   - [ ] Visit https://t.backpedal.co in a browser
   - [ ] Confirm the site loads correctly
   - [ ] Verify users can log in with their flespi.io credentials

## GitHub Actions CI/CD (Optional)

If you've set up GitHub Actions, you can use the automated CI/CD pipeline:

1. **Push to master to trigger deployment**
   - Automatic deployment is configured for the master branch
   - The workflow will build, test, and deploy the application

2. **Manual deployment from GitHub**
   - Go to your GitHub repository
   - Click on "Actions"
   - Find the "Deploy TrackIt" workflow
   - Click "Run workflow" and select the environment

## Rollback Process

If you need to roll back to a previous version:

```bash
./deploy-remote.sh --rollback
```

This will:
- Show a list of available backups with timestamps
- Allow you to select which backup to restore
- Restore the selected backup to the server

## Updating Deployment Configuration

If you need to modify the deployment configuration:

1. Edit the `deploy-config.json` file:
   ```bash
   nano /home/james/my-claude-project/deploy-config.json
   ```

2. Key settings:
   - `username`: Server username (currently "root")
   - `host`: Server hostname or IP (t.backpedal.co)
   - `remotePath`: Directory on server (/var/www/trackit)
   - `preDeployCommands`: Commands to run before deployment
   - `postDeployCommands`: Commands to run after deployment

3. Commit the changes to track configuration updates:
   ```bash
   git add deploy-config.json
   git commit -m "Update deployment configuration"
   git push
   ```

## Advanced Deployment Options

- **Preserve Mode**: `./deploy-remote.sh --preserve` (keeps files on server that don't exist locally)
- **Force Deploy**: `./deploy-remote.sh --force` (skips confirmation prompts)
- **Dry Run**: `./deploy-remote.sh --dry-run` (shows what would happen without making changes)
- **View Version History**: `./deploy.sh --version` (shows local version history)
- **Skip Build**: `./deploy.sh --skip-build` (uses existing built files)
- **Deploy to Staging**: `./deploy-remote.sh --environment staging` (deploys to staging environment)

## Troubleshooting

- **Deployment Directory Issues**: Run `./deploy.sh` to rebuild the deployment directory
- **Connection Issues**: Verify SSH access using `ssh root@t.backpedal.co`
- **Server Errors**: Check Nginx logs with `ssh root@t.backpedal.co "cat /var/log/nginx/error.log"`
- **SSL Problems**: Manually run certbot on server with `ssh root@t.backpedal.co "certbot --nginx -d t.backpedal.co"`
- **Deployment Backup**: Previous deployments are backed up at `/var/backups/trackit/`
- **Version Issues**: View the deployment info using `./deploy-remote.sh --version`

## Security Considerations

- For production, consider creating a dedicated deployment user instead of using root
- Set up SSH keys for passwordless authentication: `ssh-copy-id -i ~/.ssh/id_rsa.pub root@t.backpedal.co`
- For GitHub Actions, add your server's SSH private key as a repository secret named `SSH_PRIVATE_KEY`
- Restrict SSH access as appropriate
- Regularly update the server and application dependencies
- Users authenticate directly with flespi.io when using the application