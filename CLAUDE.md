# TrackIt Project Notes for Claude

## Common Commands
- Start development server: `npm run dev`
- Build for production: `npm run build`
- Lint the code: `npm run lint`
- Run development server with local mode: `npm run dev_local`

## Deployment Commands
All deployment is handled by a single unified script. Run from the TrackIt repo root:
- Deploy to production: `./deploy.sh`
- Dry run (preview without deploying): `./deploy.sh --dry-run`
- Deploy without confirmation prompt: `./deploy.sh --force`
- Deploy with version tag: `./deploy.sh --create-version "Your version message"`
- Skip build (use existing dist/): `./deploy.sh --skip-build`
- Check remote deployment version: `./deploy.sh --version`
- Rollback to previous backup: `./deploy.sh --rollback`
- Deploy to a different environment: `./deploy.sh --environment staging`
- CI/CD: Pushes to master auto-deploy via GitHub Actions (`.github/workflows/deploy.yml`)

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
- Single unified deploy script: `./deploy.sh` (build + deploy + verify in one command)
- Configuration: `deploy-config.json`
- Version tracking: `deployment-info.json` and `version.json`
- Server setup: `setup-server.sh` (run on server to configure nginx)
- Users authenticate with their own flespi.io credentials when using the app
- Backups are automatically created at /var/backups/trackit before each deployment
- CI/CD: GitHub Actions auto-deploys on push to master (`.github/workflows/deploy.yml`)
- Required GitHub secrets for CI/CD: `SSH_PRIVATE_KEY`, `SSH_KNOWN_HOSTS`

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
- To verify current deployment version: `./deploy.sh --version`
- If changes are not showing up, the nginx config now prevents caching index.html. Redeploy with `./deploy.sh --force`
- To rollback to a previous version: `./deploy.sh --rollback`