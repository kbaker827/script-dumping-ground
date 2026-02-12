# Microsoft Office 365 Removal Script for macOS

A comprehensive bash script to completely remove Microsoft Office 365 applications and all related files from macOS systems.

## What It Removes

- **Applications:**
  - Microsoft Word
  - Microsoft Excel
  - Microsoft PowerPoint
  - Microsoft Outlook
  - Microsoft OneNote

- **User Data:**
  - Preferences (plists)
  - Containers and Group Containers
  - Application Support files
  - Caches
  - Logs
  - Saved Application States
  - Cookies

- **System Files:**
  - Microsoft fonts
  - System-wide Application Support
  - LaunchAgents and LaunchDaemons
  - PrivilegedHelperTools
  - Installer receipts
  - Downloaded installer packages

## What It Preserves

- **Microsoft Teams** - Not touched
- **OneDrive** - Not touched
- **Microsoft AutoUpdate** - Only removed if Teams and OneDrive are also not installed

## Usage

```bash
sudo ./remove-office365.sh
```

### Requirements
- macOS
- Root privileges (sudo)

### Safety Features
- Confirmation prompt before proceeding
- Gracefully handles missing files
- Closes running Office applications before removal
- Logs actions to console

## How It Works

1. **Checks for root privileges** - Exits if not running as sudo
2. **Prompts for confirmation** - Prevents accidental execution
3. **Closes Office apps** - Uses `pkill` to terminate running applications
4. **Removes applications** - Deletes `.app` bundles from `/Applications`
5. **Cleans user data** - Iterates through all user home directories
6. **Removes system files** - Cleans system-wide Office components
7. **Handles installers** - Removes downloaded PKG/DMG files
8. **Manages AutoUpdate** - Only removes if no other MS apps exist

## Warning

⚠️ **This script permanently deletes data.** 

- Office applications will need to be reinstalled if needed later
- User preferences and settings will be lost
- Document files are NOT deleted (they remain in your Documents folder)

## License

MIT License - Feel free to use and modify as needed.

## Author

Created for IT administrators who need a clean way to remove Office 365 from macOS devices.
