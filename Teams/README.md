# Microsoft Teams Uninstaller

PowerShell utility to completely remove Microsoft Teams (new client/Teams 2.0) from Windows computers. Supports both local and remote execution.

## Overview

This script performs a thorough removal of the new Microsoft Teams client, including:

- Stopping all Teams processes
- Removing per-user AppxPackage installations
- Removing machine-wide provisioned packages (admin)
- Removing the machine-wide installer
- Cleaning up residual folders and caches
- Optional removal of Classic Teams (Teams 1.0)
- Support for cleaning all user profiles

## Features

- ✅ **Local & Remote** - Run on local machine or remote computers
- ✅ **New & Classic Teams** - Remove both versions if needed
- ✅ **Complete Cleanup** - Appx packages, provisioned packages, residual data
- ✅ **All Users Mode** - Clean all profiles on machine (requires admin)
- ✅ **Safe Mode** - Preserve user data option
- ✅ **WhatIf Support** - Preview changes before applying
- ✅ **Detailed Logging** - Track all actions

## Quick Start

### Remove Teams Locally
```powershell
.\Uninstall-NewTeams.ps1
```

### Remove Teams Remotely
```powershell
.\Uninstall-NewTeams.ps1 -ComputerName PC01 -UseCurrent
```

### Remove from Multiple Computers
```powershell
.\Uninstall-NewTeams.ps1 -ComputerName PC01,PC02,PC03 -Credential (Get-Credential)
```

### Remove Both New and Classic Teams
```powershell
.\Uninstall-NewTeams.ps1 -RemoveClassicTeams -AllUsers -Force
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ComputerName` | string[] | - | Remote computer(s) to process |
| `Credential` | PSCredential | - | Credentials for remote connection |
| `UseCurrent` | switch | `$false` | Use current credentials remotely |
| `KeepUserData` | switch | `$false` | Preserve user profile data |
| `AllUsers` | switch | `$false` | Clean all user profiles (requires admin) |
| `RemoveClassicTeams` | switch | `$false` | Also remove Classic Teams |
| `LogPath` | string | `%TEMP%\TeamsUninstall_*.log` | Log file location |
| `WhatIf` | switch | `$false` | Preview mode |
| `Force` | switch | `$false` | Skip confirmation prompts |

## What Gets Removed

### New Teams (Teams 2.0)

**Appx Packages:**
- `MSTeams` package for current user
- `MSTeams` package for all users (with `-AllUsers`)
- Provisioned package (admin only)

**Machine-Wide Installer:**
- `C:\Program Files (x86)\Teams Installer`
- Silent uninstall via `Teams.exe --uninstall -s`

**Residual Data:**
- `%LOCALAPPDATA%\Microsoft\Teams`
- `%LOCALAPPDATA%\Microsoft\TeamsMeetingAddin`
- `%LOCALAPPDATA%\Packages\MSTeams_8wekyb3d8bbwe`
- `%APPDATA%\Microsoft\Teams`
- `%PROGRAMDATA%\Microsoft\Teams` (admin)

### Classic Teams (Teams 1.0) - Optional

**MSI Uninstall:**
- Detected via registry uninstall strings
- Silent uninstall via `msiexec /x`

**Residual Data:**
- `%LOCALAPPDATA%\Microsoft\Teams`
- `%APPDATA%\Microsoft\Teams`

## Examples

### Basic Local Removal
```powershell
.\Uninstall-NewTeams.ps1
```

### Silent Local Removal
```powershell
.\Uninstall-NewTeams.ps1 -Force
```

### Remote Single Computer
```powershell
.\Uninstall-NewTeams.ps1 -ComputerName "WKSTN-12345" -UseCurrent
```

### Remove for All Users on Machine
```powershell
.\Uninstall-NewTeams.ps1 -AllUsers -Force
```

### Remove Both Versions
```powershell
.\Uninstall-NewTeams.ps1 -RemoveClassicTeams -AllUsers -Force
```

### Preview Mode
```powershell
.\Uninstall-NewTeams.ps1 -WhatIf
```

### Preserve User Data
```powershell
.\Uninstall-NewTeams.ps1 -KeepUserData
```

### Pipeline from AD
```powershell
Get-ADComputer -Filter {Enabled -eq $true} | 
    Select-Object -ExpandProperty Name | 
    .\Uninstall-NewTeams.ps1 -UseCurrent -Force
```

## Requirements

### Local Execution
- Windows 10/11
- PowerShell 5.1 or PowerShell 7+
- Administrator rights recommended (required for `-AllUsers`)

### Remote Execution
- PowerShell Remoting (WinRM) enabled on targets
- Administrative rights on target computers
- Windows Firewall allowing WinRM (port 5985/5986)

### Enable WinRM on Targets
```powershell
Enable-PSRemoting -Force
winrm quickconfig -q
```

## Output Example

```
=================================
 Microsoft Teams Uninstaller v3.0
=================================

[*] Started: 2026-02-12 10:30:15
[*] Log: C:\Users\admin\AppData\Local\Temp\TeamsUninstall_20260212_103015.log
[*] KeepUserData: False, AllUsers: False, RemoveClassic: False

[*] Remove Microsoft Teams from local machine? (Y/N): Y

[-] Stopping Teams processes...
[+] Stopped: ms-teams (PID: 12345)
[+] Stopped: Teams (PID: 12346)
[+] Stopped 2 process(es)

[*] Checking for new Teams Appx packages...
[*] Found 1 Appx package(s)
[+] Removed: MSTeams_23272.2707.2453.769_x64__8wekyb3d8bbwe

[*] Checking for provisioned Teams package...
[*] Found provisioned package: MSTeams_23272.2707.2453.769_x64__8wekyb3d8bbwe
[+] Removed provisioned package

[*] Checking for machine-wide installer...
[-] Running machine-wide uninstaller...
[*] Uninstaller exit code: 0
[+] Removed: C:\Program Files (x86)\Teams Installer

[-] Cleaning up residual data for admin...
[+] Removed: C:\Users\admin\AppData\Local\Microsoft\Teams
[+] Removed: C:\Users\admin\AppData\Local\Packages\MSTeams_8wekyb3d8bbwe
[+] Removed 2 residual folder(s)

[+] Uninstall complete

=================================
 SUMMARY
=================================

[*] Computers processed: 1
[+] Successful: 1
[+] Failed: 0

[*] Duration: 00:15
[*] Log saved: C:\Users\admin\AppData\Local\Temp\TeamsUninstall_20260212_103015.log
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Partial success or remote failures |

## Use Cases

### Migration to Classic Teams
User needs to revert from new Teams back to classic:
```powershell
.\Uninstall-NewTeams.ps1 -Force
```

### Complete Teams Removal
Removing all traces of Teams from a machine:
```powershell
.\Uninstall-NewTeams.ps1 -RemoveClassicTeams -AllUsers -Force
```

### Bulk Removal
Removing Teams from entire department:
```powershell
$computers = Get-ADComputer -SearchBase "OU=Sales,DC=contoso,DC=com" -Filter * | 
    Select-Object -ExpandProperty Name

.\Uninstall-NewTeams.ps1 -ComputerName $computers -UseCurrent -Force
```

### Troubleshooting
Teams won't start or keeps crashing:
```powershell
.\Uninstall-NewTeams.ps1 -Force
# Then reinstall from Microsoft 365 portal
```

## Troubleshooting

### "Access Denied" Errors
- Run PowerShell as Administrator
- For remote, ensure account has local admin rights

### "Appx Package In Use"
- Ensure all Teams processes are stopped (script attempts this automatically)
- Reboot and try again

### "WinRM not available" (Remote)
Enable PowerShell Remoting:
```powershell
Enable-PSRemoting -Force
```

### Classic Teams Still Present
Use `-RemoveClassicTeams` flag:
```powershell
.\Uninstall-NewTeams.ps1 -RemoveClassicTeams -Force
```

## Notes

### New Teams vs Classic Teams
- **New Teams** (Teams 2.0): Installed via Microsoft Store (Appx)
- **Classic Teams** (Teams 1.0): Installed via MSI or machine-wide installer

This script primarily targets New Teams. Use `-RemoveClassicTeams` to also remove the classic version.

### Reinstalling Teams
After removal, users can reinstall:
1. From Microsoft 365 portal (office.com)
2. From Microsoft Store
3. Using company deployment tools (Intune, SCCM)

## Version History

### 3.0 (2026-02-12)
- Added remote execution support
- Added Classic Teams removal option
- Added pipeline input support
- Improved logging
- Better error handling
- WhatIf support

### 2.0 (2026-02-04)
- Basic new Teams removal
- Appx package management
- Machine-wide installer removal
- Residual data cleanup

### 1.0
- Initial release

## Related Scripts

- `Remove-DellBloatware.ps1` - Remove Dell pre-installed software
- `Remove-GlobalSearchExtensions.ps1` - Square 9 cleanup
- `Reset-AdobeSignCache.ps1` - Adobe Acrobat troubleshooting

## License

MIT License - Use at your own risk.
