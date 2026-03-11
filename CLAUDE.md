# TrackIt Project Notes for Claude

## Common Commands
- Start development server: `npm run dev`
- Build for production: `npm run build`
- Lint the code: `npm run lint`
- Run development server with local mode: `npm run dev_local`

## Deployment Commands
- Create versioned build: `cd /home/james/my-claude-project && ./deploy.sh --create-version "Your version message"`
- Build without version: `cd /home/james/my-claude-project && ./deploy.sh`
- View version history: `cd /home/james/my-claude-project && ./deploy.sh --version`
- Deploy to production: `cd /home/james/my-claude-project && ./deploy-remote.sh`
- Deploy with options: `cd /home/james/my-claude-project && ./deploy-remote.sh --environment production --preserve`
- Test deployment (dry run): `cd /home/james/my-claude-project && ./deploy-remote.sh --dry-run`
- Check deployment status: `cd /home/james/my-claude-project && ./check-deployment.sh --diff`
- Full deployment diff: `cd /home/james/my-claude-project && ./check-deployment.sh --full-diff`
- Rollback to previous version: `cd /home/james/my-claude-project && ./deploy-remote.sh --rollback`

## Server Information
- Production Server: t.backpedal.co (IP: 209.97.135.99)
- Deployment Path: /var/www/trackit
- Web Server: Nginx with SSL configured via Let's Encrypt
- Config Location: /etc/nginx/sites-available/trackit
- Backup Location: /var/backups/trackit

## Git Workflow
1. Create feature branch: `git checkout -b feature/your-feature-name`
2. Make changes and commit: `git add . && git commit -m "Description of changes"`
3. Push branch: `git push origin feature/your-feature-name`
4. Create pull request on GitHub
5. After PR is merged: `git checkout master && git pull origin master`

## Custom Configurations
1. **Circle Device Icons**: Modified the device markers to display as simple circles instead of car icons
   - Changed in `/src/assets/getIconHTML.js`
   - Updated icon size in `/src/components/Map.vue`

2. **Custom Default Columns**: Changed the default columns in the message list to show:
   - timestamp
   - device.name
   - report.code
   - power.reason.text
   - google.address
   - position.satellites
   - position.source
   - position.accuracy
   - position.hdop
   - battery.level
   - etc (additional parameters)

   Implementation:
   - Created a patch script in `custom_patches/install_custom_columns.sh`
   - Added a postinstall script to apply the patch automatically

## Deployment Notes
- The deployment scripts are located in `/home/james/my-claude-project/`
- Configuration for deployment is in `deploy-config.json`
- The deployment includes version tracking in `deployment-info.json` and `version.json`
- Server setup script is in `setup-server.sh`
- Users authenticate with their own flespi.io credentials when using the app
- Backups are automatically created at /var/backups/trackit before each deployment
- GitHub Actions can be used for automated CI/CD (configured in `.github/workflows/deploy.yml`)

## Development Notes
- The app requires a flespi.io token to access data
- Device colors have no predefined meaning and can be customized to suit specific needs
- Flag markers (inverted water drop icons) indicate start and end points of device tracks
- Node.js >=18.x is required for development

## Troubleshooting
- If deployment fails, check permissions on the server with `ssh root@t.backpedal.co "ls -la /var/www/trackit"`
- Ensure proper SSH connection is configured (root@t.backpedal.co)
- Check Nginx logs with `ssh root@t.backpedal.co "cat /var/log/nginx/error.log"`
- If SSL issues occur, run certbot manually with `ssh root@t.backpedal.co "certbot --nginx -d t.backpedal.co"`
- To verify current deployment version: `./deploy-remote.sh --version`
- If changes are not showing up, try force deploying with `./deploy-remote.sh --force`
- To rollback to a previous version: `./deploy-remote.sh --rollback`