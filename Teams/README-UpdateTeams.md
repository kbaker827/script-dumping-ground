# Update-NewTeams.ps1

Updates or installs the new Microsoft Teams client with context-aware execution and remote deployment support.

## Overview

This script handles Teams updates/installation intelligently based on execution context:
- **SYSTEM context**: Uses Teams Bootstrapper for machine-wide provisioning
- **User context**: Uses WinGet for per-user installation
- **Remote**: Can deploy to multiple computers via PowerShell Remoting

## Features

- ✅ **Context-Aware**: Auto-detects SYSTEM vs User context and chooses appropriate method
- ✅ **Remote Deployment**: Update Teams on multiple computers from central location
- ✅ **Version Tracking**: Logs before/after versions for audit trail
- ✅ **Flexible**: Override auto-detection with explicit method selection
- ✅ **Comprehensive Logging**: Detailed logs in appropriate locations

## Quick Start

### Update Locally (Auto-Detect)
```powershell
.\Update-NewTeams.ps1
```

### Force Reinstall
```powershell
.\Update-NewTeams.ps1 -Force
```

### Update Remote Computer
```powershell
.\Update-NewTeams.ps1 -ComputerName PC01 -UseCurrent
```

### Bulk Update Domain
```powershell
Get-ADComputer -Filter {Enabled -eq $true} | 
    Select-Object -ExpandProperty Name | 
    .\Update-NewTeams.ps1 -UseCurrent
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ComputerName` | string[] | - | Remote computer(s) to update |
| `Credential` | PSCredential | - | Credentials for remote authentication |
| `UseCurrent` | switch | `$false` | Use current credentials for remote |
| `Force` | switch | `$false` | Force reinstallation |
| `InstallMethod` | string | 'Auto' | 'Auto', 'Bootstrapper', or 'WinGet' |
| `BootstrapperUrl` | string | Microsoft | Custom bootstrapper download URL |
| `LogPath` | string | Auto | Custom log file path |
| `PassThru` | switch | `$false` | Return result object |

## Installation Methods

### SYSTEM Context (Bootstrapper)
When running as SYSTEM (NT AUTHORITY\SYSTEM), the script uses the Teams Bootstrapper:

1. Downloads `teamsbootstrapper.exe` from Microsoft
2. Runs with `-p` flag for machine-wide provisioning
3. Creates provisioned package for all users

**Best for:**
- SCCM/Intune deployments
- Windows deployment task sequences
- Scheduled maintenance tasks
- Golden image preparation

**Log location:** `C:\ProgramData\IT\Logs\Update-NewTeams.log`

### User Context (WinGet)
When running as standard user, the script uses Windows Package Manager:

1. Refreshes WinGet sources
2. Attempts `winget upgrade Microsoft.Teams`
3. Falls back to `winget install` if needed

**Best for:**
- End-user self-service
- Manual updates
- Testing

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

#### Single Remote
```powershell
.\Update-NewTeams.ps1 -ComputerName "WKSTN-12345" -UseCurrent
```

#### Multiple Remotes
```powershell
.\Update-NewTeams.ps1 -ComputerName "PC01", "PC02", "PC03" -Credential (Get-Credential)
```

#### Pipeline from AD
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

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | WinGet not found |
| 2 | Bootstrapper download failed |
| 3 | Installation failed |
| 4 | Remote connection failed |
| 5 | Invalid parameters |
| 9 | Unexpected error |

## Use Cases

### SCCM/Intune Deployment
```powershell
# Runs as SYSTEM
powershell.exe -ExecutionPolicy Bypass -File Update-NewTeams.ps1
```

### Weekly Scheduled Update
```powershell
# Task Scheduler (as SYSTEM)
powershell.exe -ExecutionPolicy Bypass -File "C:\Scripts\Update-NewTeams.ps1"
```

### Force Update Campaign
```powershell
# All domain computers
Get-ADComputer -Filter {Enabled -eq $true} | 
    Select-Object -ExpandProperty Name | 
    .\Update-NewTeams.ps1 -Force -UseCurrent
```

## Troubleshooting

### "WinGet not found"
Install App Installer from Microsoft Store, or switch to Bootstrapper method.

### "Download failed"
Check internet connectivity and proxy settings.

### "Access denied" (Remote)
Ensure credentials have admin rights on target computers.

### Exit code -1978335189
This is normal from WinGet - means "no update found". Script auto-falls back to install.

## Requirements

- Windows 10 (1809+) or Windows 11
- PowerShell 5.1+
- Internet connectivity
- For remote: WinRM enabled

## Version History

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
