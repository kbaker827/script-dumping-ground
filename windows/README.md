# Microsoft Office 365 Removal Script for Windows

A comprehensive PowerShell script to completely remove Microsoft Office 365 applications and all related files from Windows systems.

## What It Removes

- **Applications:**
  - Microsoft Word
  - Microsoft Excel
  - Microsoft PowerPoint
  - Microsoft Outlook
  - Microsoft OneNote
  - Microsoft Access
  - Microsoft Publisher

- **Installation Methods Handled:**
  - Click-to-Run (C2R) installations
  - MSI-based installations
  - Office 2013, 2016, 2019, 2021, and Microsoft 365

- **User Data:**
  - AppData\Local Office folders
  - AppData\Roaming Office folders
  - User templates and document building blocks

- **System Components:**
  - Program Files directories
  - Registry entries (HKCU and HKLM)
  - Office licensing data
  - Scheduled tasks
  - Windows services
  - Installer files from Downloads
  - Temp folder cleanup

## What It Preserves

- **Microsoft Teams** - Not touched
- **OneDrive** - Not touched

## Usage

### Basic Usage
```powershell
.\Remove-Office365.ps1
```

### Silent/Force Mode (No Prompts)
```powershell
.\Remove-Office365.ps1 -Force
```

### Requirements
- Windows 10/11 or Windows Server 2016+
- Administrator privileges (script will error if not elevated)
- PowerShell 5.1 or later

### Safety Features
- Confirmation prompt before proceeding (unless -Force used)
- Gracefully handles missing files/registry keys
- Closes running Office applications before removal
- Skips Teams and OneDrive related components
- Optional automatic restart at completion

## How It Works

1. **Checks for Administrator privileges** - Uses `#Requires -RunAsAdministrator`
2. **Prompts for confirmation** - Unless -Force switch is used
3. **Closes Office apps** - Stops all running Office processes
4. **Attempts Click-to-Run removal** - Uses OfficeC2RClient for clean uninstall
5. **Attempts MSI removal** - Finds and uninstalls MSI-based Office products
6. **Removes directories** - Deletes Program Files folders
7. **Cleans user data** - Iterates through all user profiles
8. **Cleans registry** - Removes Office keys (preserving Teams/OneDrive)
9. **Removes licensing** - Clears activation data
10. **Cleans tasks/services** - Removes Office scheduled tasks and services
11. **Handles installers** - Removes downloaded setup files
12. **Prompts for restart** - Optional reboot to complete cleanup

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Force` | Switch | Skip confirmation prompts and auto-restart if needed |

## Example Scenarios

### Standard Removal (Interactive)
```powershell
.\Remove-Office365.ps1
```
User will be prompted to confirm, then again for restart.

### Silent Removal (For Deployment)
```powershell
.\Remove-Office365.ps1 -Force
```
No prompts, suitable for SCCM/Intune deployment.

### Remote Execution
```powershell
Invoke-Command -ComputerName PC01 -FilePath .\Remove-Office365.ps1 -ArgumentList @("-Force")
```

## Warning

⚠️ **This script permanently deletes data.**

- Office applications will need to be reinstalled if needed later
- User preferences and settings will be lost
- Document files are NOT deleted (they remain in your Documents folder)
- License/activation data will be removed

## Troubleshooting

### Script won't run (execution policy)
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Office still appears in Settings > Apps
Some components may require a restart to fully disappear from the apps list.

### Registry access denied
Ensure you're running PowerShell as Administrator, not just a standard user.

## License

MIT License - Feel free to use and modify as needed.

## Author

Created for IT administrators who need a clean way to remove Office 365 from Windows devices, especially when standard uninstall methods fail.
