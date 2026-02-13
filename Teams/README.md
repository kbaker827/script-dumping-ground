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

---

## Update-NewTeams.ps1

Updates or installs the new Microsoft Teams client with context-aware execution (SYSTEM vs User) and remote deployment support.

### Features

- ✅ **Context-Aware Installation**
  - **SYSTEM context**: Uses Teams Bootstrapper for machine-wide provisioning
  - **User context**: Uses WinGet for per-user installation
- ✅ **Remote Deployment**: Update Teams on multiple computers via PowerShell Remoting
- ✅ **Version Detection**: Logs before/after versions for audit trail
- ✅ **Flexible Methods**: Auto-detect, force Bootstrapper, or force WinGet
- ✅ **Comprehensive Logging**: Detailed logs in SYSTEM or user temp

### Quick Start

#### Update Locally (Auto-Detect Method)
```powershell
.\Update-NewTeams.ps1
```

#### Force Reinstallation
```powershell
.\Update-NewTeams.ps1 -Force
```

#### Update Remote Computer
```powershell
.\Update-NewTeams.ps1 -ComputerName PC01 -UseCurrent
```

#### Update All Domain Computers
```powershell
Get-ADComputer -Filter {Enabled -eq $true} | 
    Select-Object -ExpandProperty Name | 
    .\Update-NewTeams.ps1 -UseCurrent
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ComputerName` | string[] | - | Remote computer(s) to update |
| `Credential` | PSCredential | - | Credentials for remote auth |
| `UseCurrent` | switch | `$false` | Use current credentials |
| `Force` | switch | `$false` | Force reinstallation |
| `InstallMethod` | string | 'Auto' | 'Auto', 'Bootstrapper', or 'WinGet' |
| `BootstrapperUrl` | string | Microsoft URL | Custom bootstrapper URL |
| `LogPath` | string | Auto | Custom log file path |
| `PassThru` | switch | `$false` | Return result object |

### Context-Aware Execution

The script automatically detects the execution context and chooses the appropriate method:

| Context | Method | Use Case |
|---------|--------|----------|
| SYSTEM (NT AUTHORITY\SYSTEM) | Bootstrapper | SCCM/Intune deployment, scheduled tasks |
| User (standard account) | WinGet | Manual user installation, self-service |

**Override with `-InstallMethod`:**
```powershell
# Force Bootstrapper even in user context
.\Update-NewTeams.ps1 -InstallMethod Bootstrapper

# Force WinGet even in SYSTEM context
.\Update-NewTeams.ps1 -InstallMethod WinGet
```

### SYSTEM Context (Bootstrapper Method)

Downloads and runs the official Teams Bootstrapper for machine-wide provisioning:

1. Downloads `teamsbootstrapper.exe` from Microsoft
2. Runs with `-p` flag to provision for all users
3. Creates provisioned package that installs for each user at login

**Best for:**
- SCCM/Intune deployments
- Windows deployment task sequences
- Scheduled maintenance tasks
- Golden image preparation

**Log location:** `C:\ProgramData\IT\Logs\Update-NewTeams.log`

### User Context (WinGet Method)

Uses Windows Package Manager (WinGet) to install/update Teams:

1. Refreshes WinGet sources
2. Attempts `winget upgrade Microsoft.Teams`
3. Falls back to `winget install` if upgrade not applicable
4. Handles package agreements automatically

**Best for:**
- End-user self-service
- Manual updates
- Testing

**Requirements:**
- WinGet must be installed (comes with Windows 11, App Installer on Windows 10)
- Microsoft Store access (or WinGet source available)

**Log location:** `%TEMP%\Update-NewTeams_YYYYMMDD_HHmmss.log`

### Remote Execution Examples

#### Single Remote Computer
```powershell
.\Update-NewTeams.ps1 -ComputerName "WKSTN-12345" -UseCurrent
```

#### Multiple Remote Computers
```powershell
.\Update-NewTeams.ps1 -ComputerName "PC01", "PC02", "PC03" -Credential (Get-Credential)
```

#### Pipeline from Active Directory
```powershell
Get-ADComputer -Filter {Enabled -eq $true} | 
    Select-Object -ExpandProperty Name | 
    .\Update-NewTeams.ps1 -UseCurrent
```

#### Specific OU
```powershell
Get-ADComputer -SearchBase "OU=Workstations,OU=Sales,DC=contoso,DC=com" -Filter * | 
    Select-Object -ExpandProperty Name | 
    .\Update-NewTeams.ps1 -UseCurrent
```

#### From Text File
```powershell
$computers = Get-Content "C:\Scripts\ComputersToUpdate.txt"
.\Update-NewTeams.ps1 -ComputerName $computers -UseCurrent
```

#### Force Reinstall on Multiple Computers
```powershell
Get-ADComputer -Filter {Enabled -eq $true} | 
    Select-Object -ExpandProperty Name | 
    .\Update-NewTeams.ps1 -Force -UseCurrent
```

### Output Examples

#### Local Update (SYSTEM Context)
```
========================================
  Microsoft Teams Updater v3.0
========================================

2026-02-13T10:30:15 [Info] Started: 2026-02-13 10:30:15
2026-02-13T10:30:15 [Info] Log: C:\ProgramData\IT\Logs\Update-NewTeams.log
2026-02-13T10:30:15 [Info] Force: False, InstallMethod: Auto
2026-02-13T10:30:15 [Info] Processing 1 computer(s)
2026-02-13T10:30:15 [Info] === Processing Local Machine ===
2026-02-13T10:30:15 [Info] User: SYSTEM, IsSystem: True
2026-02-13T10:30:15 [Info] Auto-detected install method: Bootstrapper
2026-02-13T10:30:15 [Info] Running in SYSTEM context - using Teams Bootstrapper
2026-02-13T10:30:15 [Info] Pre-update: Provisioned=True, Version=23272.2707.2453.769, InstalledUsers=15
2026-02-13T10:30:15 [Info] Using existing Bootstrapper at C:\Windows\TEMP\TeamsBootstrapper\teamsbootstrapper.exe
2026-02-13T10:30:15 [Info] Running: teamsbootstrapper.exe -p
2026-02-13T10:30:45 [Info] Bootstrapper exit code: 0
2026-02-13T10:30:48 [Info] Post-update: Provisioned=True, Version=23320.3021.2567.479, InstalledUsers=15
2026-02-13T10:30:48 [Success] Machine-wide Teams provisioned/updated successfully
```

#### Local Update (User Context)
```
========================================
  Microsoft Teams Updater v3.0
========================================

2026-02-13T10:35:22 [Info] Started: 2026-02-13 10:35:22
2026-02-13T10:35:22 [Info] Log: C:\Users\jdoe\AppData\Local\Temp\Update-NewTeams_20260213_103522.log
2026-02-13T10:35:22 [Info] Force: False, InstallMethod: Auto
2026-02-13T10:35:22 [Info] Processing 1 computer(s)
2026-02-13T10:35:22 [Info] === Processing Local Machine ===
2026-02-13T10:35:22 [Info] User: jdoe, IsSystem: False
2026-02-13T10:35:22 [Info] Auto-detected install method: WinGet
2026-02-13T10:35:22 [Info] Running in user context - using WinGet
2026-02-13T10:35:22 [Info] WinGet found at: C:\Users\jdoe\AppData\Local\Microsoft\WindowsApps\winget.exe
2026-02-13T10:35:22 [Info] Pre-update: Installed=True, Version=23272.2707.2453.769
2026-02-13T10:35:22 [Info] Refreshing WinGet sources...
2026-02-13T10:35:25 [Info] Executing: winget upgrade --id Microsoft.Teams --exact --accept-package-agreements --accept-source-agreements --disable-interactivity
2026-02-13T10:35:58 [Info] WinGet exit code: 0
2026-02-13T10:36:01 [Info] Per-user MSTeams version: 23272.2707.2453.769 -> 23320.3021.2567.479
2026-02-13T10:36:01 [Info] Per-user MSTeams package: Microsoft.MicrosoftTeams_23320.3021.2567.479_x64__8wekyb3d8bbwe
2026-02-13T10:36:01 [Success] Per-user Teams installed/updated successfully
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | WinGet not found (user context only) |
| 2 | Bootstrapper download failed |
| 3 | Installation failed |
| 4 | Remote connection failed |
| 5 | Invalid parameters |
| 9 | Unexpected error |

### Use Cases

#### SCCM/Intune Deployment
Deploy as SYSTEM to provision Teams for all users:
```powershell
# Deployment command (runs as SYSTEM)
powershell.exe -ExecutionPolicy Bypass -File Update-NewTeams.ps1
```

#### User Self-Service
Users run manually to update their own Teams:
```powershell
# User runs from desktop shortcut
.\Update-NewTeams.ps1
```

#### Scheduled Maintenance
Update Teams weekly via scheduled task:
```powershell
# Task Scheduler Action (as SYSTEM)
powershell.exe -ExecutionPolicy Bypass -File "C:\Scripts\Update-NewTeams.ps1"

# Or force update
powershell.exe -ExecutionPolicy Bypass -File "C:\Scripts\Update-NewTeams.ps1" -Force
```

#### Post-Image Deployment
Part of MDT/SCCM task sequence:
```powershell
# In task sequence (SYSTEM context)
.\Update-NewTeams.ps1 -InstallMethod Bootstrapper
```

#### Bulk Update Campaign
Update all domain computers:
```powershell
Get-ADComputer -Filter {Enabled -eq $true} | 
    Select-Object -ExpandProperty Name | 
    .\Update-NewTeams.ps1 -UseCurrent
```

### Requirements

**Local Execution:**
- Windows 10 (64-bit) version 1809+ or Windows 11
- PowerShell 5.1 or PowerShell 7+
- Internet connectivity
- For WinGet method: App Installer from Microsoft Store
- For Bootstrapper method: SYSTEM context recommended

**Remote Execution:**
- WinRM enabled on target computers
- Administrator rights on targets
- Windows Firewall allowing WinRM (port 5985/5986)

### Troubleshooting

#### "WinGet not found"
Install App Installer from Microsoft Store, or use Bootstrapper method.

#### "Download failed" (Bootstrapper)
Check internet connectivity and proxy settings. Try manual download of bootstrapper URL.

#### "Access denied" (Remote)
Ensure credentials have admin rights on target computers.

#### "WinRM not available" (Remote)
Enable PowerShell Remoting on targets: `Enable-PSRemoting -Force`

#### Exit code -1978335189 from WinGet
This is normal - means "no applicable update found". Script automatically falls back to install.

### Version History

#### 3.0 (2026-02-13)
- Added remote execution support
- Added ComputerName, Credential, UseCurrent parameters
- Added Pipeline support
- Added PassThru option
- Improved error handling
- Better logging

#### 2.0 (2026-02-04)
- Context-aware execution (SYSTEM vs User)
- Bootstrapper and WinGet methods
- Version comparison logging

#### 1.0
- Initial release
