# Update-NewTeams.ps1

Installs or updates the new Microsoft Teams client with context-aware execution and remote deployment support.

## Overview

This script **intelligently handles both installation and updates** based on current state:
- **If Teams is NOT installed** → Performs fresh installation
- **If Teams IS installed** → Checks for and applies updates

Execution context determines the method:
- **SYSTEM context**: Uses Teams Bootstrapper for machine-wide provisioning
- **User context**: Uses WinGet for per-user installation
- **Remote**: Can deploy to multiple computers via PowerShell Remoting

## Features

- ✅ **Install OR Update**: Automatically detects if Teams is present and acts accordingly
- ✅ **Context-Aware**: Auto-detects SYSTEM vs User context
- ✅ **Remote Deployment**: Update Teams on multiple computers from central location
- ✅ **Version Tracking**: Logs before/after versions for audit trail
- ✅ **Flexible**: Override auto-detection with explicit method selection
- ✅ **Comprehensive Logging**: Detailed logs in appropriate locations

## Quick Start

### Install/Update Locally (Auto-Detect)
```powershell
.\Update-NewTeams.ps1
```
*Works whether Teams is installed or not*

### Force Reinstall (Even if Current)
```powershell
.\Update-NewTeams.ps1 -Force
```

### Install/Update Remote Computer
```powershell
.\Update-NewTeams.ps1 -ComputerName PC01 -UseCurrent
```

### Bulk Install/Update Domain
```powershell
Get-ADComputer -Filter {Enabled -eq $true} | 
    Select-Object -ExpandProperty Name | 
    .\Update-NewTeams.ps1 -UseCurrent
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ComputerName` | string[] | - | Remote computer(s) to target |
| `Credential` | PSCredential | - | Credentials for remote authentication |
| `UseCurrent` | switch | `$false` | Use current credentials for remote |
| `Force` | switch | `$false` | Force reinstallation even if current |
| `InstallMethod` | string | 'Auto' | 'Auto', 'Bootstrapper', or 'WinGet' |
| `BootstrapperUrl` | string | Microsoft | Custom bootstrapper download URL |
| `LogPath` | string | Auto | Custom log file path |
| `PassThru` | switch | `$false` | Return result object |

## How It Works

### Detection Logic

The script first checks if Teams is installed:

```powershell
# For current user
$status = Get-AppxPackage -Name MSTeams

# For all users (admin)
$status = Get-AppxPackage -AllUsers -Name MSTeams
```

**If NOT installed:**
- Logs: *"Teams is NOT installed. Will install..."*
- Performs fresh installation
- Action logged as: `Installed`

**If installed:**
- Logs: *"Teams is installed (Version: x.x.x). Checking for updates..."*
- Attempts upgrade
- Action logged as: `Updated` or `UpToDate`

### Installation Methods

#### SYSTEM Context (Bootstrapper)
When running as SYSTEM:

1. Checks provisioned status machine-wide
2. Downloads `teamsbootstrapper.exe` from Microsoft
3. Runs with `-p` flag for machine-wide provisioning
4. Creates provisioned package for all users

**Best for:**
- SCCM/Intune deployments
- Windows deployment task sequences
- Scheduled maintenance tasks
- Golden image preparation
- **Fresh installs on new machines**

**Log location:** `C:\ProgramData\IT\Logs\Update-NewTeams.log`

#### User Context (WinGet)
When running as standard user:

1. Checks if Teams is installed for current user
2. Refreshes WinGet sources
3. If not installed: `winget install Microsoft.Teams`
4. If installed: `winget upgrade Microsoft.Teams`
5. Handles package agreements automatically

**Best for:**
- End-user self-service
- Manual updates
- Testing
- **Fresh installs for single user**

**Requirements:**
- WinGet installed (Windows 11 or App Installer on Windows 10)

**Log location:** `%TEMP%\Update-NewTeams_YYYYMMDD_HHmmss.log`

## Remote Execution

### Prerequisites
**On Target Computers:**
```powershell
Enable-PSRemoting -Force
# Or:
winrm quickconfig -q
```

### Examples

#### Single Remote (Install or Update)
```powershell
.\Update-NewTeams.ps1 -ComputerName "WKSTN-12345" -UseCurrent
```
*Will install if not present, or update if already installed*

#### Multiple Remotes
```powershell
.\Update-NewTeams.ps1 -ComputerName "PC01", "PC02", "PC03" -Credential (Get-Credential)
```

#### Pipeline from Active Directory (All Computers)
```powershell
Get-ADComputer -Filter {Enabled -eq $true} | 
    Select-Object -ExpandProperty Name | 
    .\Update-NewTeams.ps1 -UseCurrent
```

#### Specific OU
```powershell
Get-ADComputer -SearchBase "OU=Workstations,DC=contoso,DC=com" -Filter * | 
    Select-Object -ExpandProperty Name | 
    .\Update-NewTeams.ps1 -UseCurrent
```

#### From Text File
```powershell
$computers = Get-Content "C:\Scripts\ComputersToUpdate.txt"
.\Update-NewTeams.ps1 -ComputerName $computers -UseCurrent
```

## Output Examples

### Fresh Install (SYSTEM Context)
```
========================================
  Microsoft Teams Installer/Updater v3.1
========================================

2026-02-13T11:30:15 [Info] Started: 2026-02-13 11:30:15
2026-02-13T11:30:15 [Info] User: SYSTEM, IsSystem: True
2026-02-13T11:30:15 [Info] Auto-detected method: Bootstrapper
2026-02-13T11:30:15 [Info] Teams is NOT installed. Will install...
2026-02-13T11:30:15 [Info] Downloading Teams Bootstrapper...
2026-02-13T11:30:25 [Success] Download completed
2026-02-13T11:30:25 [Info] Running: teamsbootstrapper.exe -p
2026-02-13T11:30:55 [Info] Bootstrapper exit code: 0
2026-02-13T11:30:58 [Success] Teams installed successfully
```

### Update Existing (User Context)
```
========================================
  Microsoft Teams Installer/Updater v3.1
========================================

2026-02-13T11:35:22 [Info] Started: 2026-02-13 11:35:22
2026-02-13T11:35:22 [Info] User: jdoe, IsSystem: False
2026-02-13T11:35:22 [Info] Auto-detected method: WinGet
2026-02-13T11:35:22 [Info] Teams is installed (Version: 23272.2707.2453.769)
2026-02-13T11:35:22 [Info] Checking for updates via WinGet...
2026-02-13T11:35:22 [Info] Executing: winget upgrade --id Microsoft.Teams ...
2026-02-13T11:35:58 [Info] WinGet exit code: 0
2026-02-13T11:36:01 [Success] Teams updated successfully (Version: 23320.3021.2567.479)
```

### Already Current
```
2026-02-13T11:40:10 [Info] Teams is installed (Version: 23320.3021.2567.479)
2026-02-13T11:40:10 [Info] Checking for updates via WinGet...
2026-02-13T11:40:10 [Info] Executing: winget upgrade --id Microsoft.Teams ...
2026-02-13T11:40:15 [Success] No update available - Teams is current
```

## Summary Output (Multiple Computers)
```
========================================
  SUMMARY
========================================

2026-02-13T12:00:45 [Info] Computers processed: 10
2026-02-13T12:00:45 [Success] Successful: 10
2026-02-13T12:00:45 [Success] New installations: 3
2026-02-13T12:00:45 [Success] Updates applied: 6
2026-02-13T12:00:45 [Success] Failed: 0
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (installed, updated, or already current) |
| 1 | WinGet not found (user context) |
| 2 | Bootstrapper download failed |
| 3 | Installation/Update failed |
| 4 | Remote connection failed |
| 5 | Invalid parameters |
| 9 | Unexpected error |

## Use Cases

### New Machine Setup
```powershell
# Part of onboarding script - works for fresh installs
.\Update-NewTeams.ps1
```

### SCCM/Intune Deployment
```powershell
# Deploy to all machines - handles both install and update
powershell.exe -ExecutionPolicy Bypass -File Update-NewTeams.ps1
```

### Weekly Maintenance (All Domain Computers)
```powershell
# Update existing or install on new machines
Get-ADComputer -Filter {Enabled -eq $true} | 
    Select-Object -ExpandProperty Name | 
    .\Update-NewTeams.ps1 -UseCurrent
```

### Force Reinstall Campaign
```powershell
# Force reinstall on all machines
Get-ADComputer -Filter {Enabled -eq $true} | 
    Select-Object -ExpandProperty Name | 
    .\Update-NewTeams.ps1 -Force -UseCurrent
```

### Check Status (WhatIf)
```powershell
# Preview what would happen without making changes
.\Update-NewTeams.ps1 -WhatIf
```

## Troubleshooting

### "WinGet not found"
Install App Installer from Microsoft Store, or use SYSTEM context with Bootstrapper method.

### "Download failed" (Bootstrapper)
Check internet connectivity and proxy settings. Try manual download of bootstrapper URL.

### "Access denied" (Remote)
Ensure credentials have admin rights on target computers.

### Exit code -1978335189
This is normal from WinGet - means "no update available". Script reports as `UpToDate`.

### Teams not detected as installed
The script checks for `MSTeams` AppX package. If you have classic Teams installed, it won't be detected (this is expected - this script is for the *new* Teams only).

## Requirements

- Windows 10 (1809+) or Windows 11
- PowerShell 5.1+
- Internet connectivity
- For remote: WinRM enabled

## Version History

### 3.1 (2026-02-13)
- **Now installs Teams if not present** (was update-only)
- Added `Test-TeamsInstalled` function
- Added `Test-TeamsProvisioned` function
- Added `Get-TeamsStatus` function
- Reports action: `Installed`, `Updated`, or `UpToDate`
- Summary shows new installations vs updates

### 3.0 (2026-02-13)
- Added remote execution support
- Pipeline input from AD
- PassThru option
- Improved logging

### 2.0 (2026-02-04)
- Context-aware execution
- Bootstrapper and WinGet methods
- Version comparison

### 1.0
- Initial release
