# Maintenance Scripts

Scripts for system maintenance and health checks.

## Scripts

### `verify_backups.sh`
macOS backup verification script for Time Machine and cloud sync.

**Features:**
- Time Machine backup status
- Last backup age check
- iCloud Drive sync status
- Dropbox/Google Drive/OneDrive running check
- Backup drive space monitoring
- Critical files backup verification

**Usage:**
```bash
# Run backup verification
./verify_backups.sh

# Add to crontab for daily checks
0 9 * * * /path/to/verify_backups.sh
```

**Exit Codes:**
- 0: All backups healthy
- 1: Critical issues found
- 2: Warnings only

**Monitored Paths:**
- ~/Documents
- ~/Desktop
- ~/Pictures

**Log Location:**
`~/Library/Logs/BackupVerification.log`

## Requirements

- macOS
- Bash shell
- Time Machine configured (optional)
