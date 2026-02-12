# Remote Group Policy Update Tool

PowerShell utility to remotely execute `gpupdate /force` on Windows computers via WinRM, with GUI support for interactive use and comprehensive parameters for automation.

## Overview

This script provides a flexible solution for refreshing Group Policy on remote machines. It supports both GUI-based interactive selection and command-line automation, making it suitable for both ad-hoc administrative tasks and scheduled maintenance operations.

## Features

- ✅ **GUI Selection Dialog** - Point-and-click computer selection
- ✅ **Native CredUI** - Windows native credential prompt (with WinForms fallback)
- ✅ **Multiple Authentication** - Current user, explicit credentials, or prompted
- ✅ **Policy Target Selection** - Computer policies, user policies, or both
- ✅ **Connectivity Checks** - ICMP ping and WinRM availability tests
- ✅ **Bulk Operations** - Process multiple computers (sequential or parallel)
- ✅ **Comprehensive Logging** - File logging with optional Event Log integration
- ✅ **WhatIf Support** - Preview mode for testing
- ✅ **Export Results** - CSV export of operation results

## Quick Start

### Interactive GUI Mode
```powershell
.\Invoke-RemoteGPUpdate.ps1
```

### Single Computer (Command Line)
```powershell
.\Invoke-RemoteGPUpdate.ps1 -ComputerName PC01 -PolicyTarget Both
```

### Multiple Computers
```powershell
.\Invoke-RemoteGPUpdate.ps1 -ComputerList PC01,PC02,PC03 -UseCurrent
```

### Skip Connectivity Check
```powershell
.\Invoke-RemoteGPUpdate.ps1 -ComputerName SERVER01 -SkipPing -UseCurrent
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ComputerName` | string[] | - | Target computer(s). Supports pipeline input. |
| `ComputerList` | string[] | - | Array of computers for bulk processing. |
| `Credential` | PSCredential | - | Pre-defined credential object. |
| `DefaultUser` | string | - | Pre-fill username in credential prompts. |
| `PolicyTarget` | string | "Both" | Which policies: "Both", "Computer", or "User". |
| `CommonComputers` | string[] | See below | Computers shown in GUI dropdown. |
| `SkipPing` | switch | `$false` | Skip ICMP connectivity test. |
| `UseCurrent` | switch | `$false` | Use current Windows credentials. |
| `ForcePrompt` | switch | `$false` | Always show credential prompt. |
| `LogPath` | string | `%ProgramData%\GpupdateRemote\*.log` | Log file location. |
| `LogToEventLog` | switch | `$false` | Also write to Windows Event Log. |
| `TimeoutSec` | int | 60 | Timeout for remote execution. |
| `Retries` | int | 2 | Credential prompt retry attempts. |
| `Parallel` | switch | `$false` | Process computers in parallel. |
| `ThrottleLimit` | int | 5 | Max concurrent parallel operations. |
| `ExportResults` | switch | `$false` | Export results to CSV. |
| `Quiet` | switch | `$false` | Suppress console output. |

## Authentication Methods

### Use Current Credentials
```powershell
.\Invoke-RemoteGPUpdate.ps1 -ComputerName PC01 -UseCurrent
```
No credential prompt; uses your current Windows login.

### Prompt for Credentials
```powershell
.\Invoke-RemoteGPUpdate.ps1 -ComputerName PC01
```
Shows native Windows credential dialog (CredUI).

### Pre-defined Credentials
```powershell
$cred = Get-Credential
.\Invoke-RemoteGPUpdate.ps1 -ComputerName PC01 -Credential $cred
```

### Pre-fill Username
```powershell
.\Invoke-RemoteGPUpdate.ps1 -ComputerName PC01 -DefaultUser "DOMAIN\Admin" -ForcePrompt
```

## Examples

### Basic GUI Mode
```powershell
.\Invoke-RemoteGPUpdate.ps1
```
Opens the selection dialog with dropdown of common computers.

### Target Only Computer Policies
```powershell
.\Invoke-RemoteGPUpdate.ps1 -ComputerName PC01 -PolicyTarget Computer -UseCurrent
```

### Bulk Update with Export
```powershell
.\Invoke-RemoteGPUpdate.ps1 `
    -ComputerList PC01,PC02,PC03,PC04,PC05 `
    -UseCurrent `
    -ExportResults `
    -LogPath "C:\Logs\GPUpdate.log"
```

### Pipeline Input
```powershell
Get-Content computers.txt | .\Invoke-RemoteGPUpdate.ps1 -UseCurrent -Quiet
```

### Parallel Processing
```powershell
.\Invoke-RemoteGPUpdate.ps1 `
    -ComputerList (Get-Content computers.txt) `
    -Parallel `
    -ThrottleLimit 10 `
    -UseCurrent
```

### With Event Logging
```powershell
.\Invoke-RemoteGPUpdate.ps1 -ComputerName PC01 -UseCurrent -LogToEventLog
```

### Preview Mode (WhatIf)
```powershell
.\Invoke-RemoteGPUpdate.ps1 -ComputerName PC01 -WhatIf
```

## Requirements

### Local Computer (Running the Script)
- Windows PowerShell 5.1 or PowerShell 7+
- .NET Framework (for GUI components)
- Network connectivity to target computers

### Target Computers
- Windows PowerShell/WinRM enabled
- Windows Firewall allowing WinRM (port 5985 HTTP, 5986 HTTPS)
- User account with administrative rights

### Enabling WinRM on Targets
Run on target computers (as Administrator):
```powershell
Enable-PSRemoting -Force
# Or for quick config:
winrm quickconfig -q
```

## GUI Dialog

When run without parameters, the script displays a Windows Forms dialog:

```
┌─────────────────────────────────────┐
│      Remote GPUpdate                │
├─────────────────────────────────────┤
│ Computer: [Dropdown/Text    ▼]      │
│                                     │
│ [ ] Skip ping (ICMP)                │
│ [ ] Use current Windows sign-in     │
│ [ ] Always prompt for credentials   │
│                                     │
│ Policy target:                      │
│ (•) Both    ( ) Computer ( ) User   │
│                                     │
│              [OK]    [Cancel]       │
└─────────────────────────────────────┘
```

## Credential Dialog

The script uses Windows native CredUI for credential prompts:

```
┌─────────────────────────────────────┐
│  Windows Security                   │
├─────────────────────────────────────┤
│                                     │
│  Enter your credentials             │
│                                     │
│  User name: [________________]      │
│  Password:  [________________]      │
│                                     │
│  [ ] Remember my credentials        │
│                                     │
│         [OK]      [Cancel]          │
└─────────────────────────────────────┘
```

If CredUI fails, it falls back to a WinForms dialog.

## Logging

### File Logging
Default location: `%ProgramData%\GpupdateRemote\gpupdate_YYYYMMDD_HHmmss.log`

Example log output:
```
[2026-02-12 10:30:15][INFO] Started: 2026-02-12 10:30:15
[2026-02-12 10:30:15][DEBUG] Log file: C:\ProgramData\GpupdateRemote\gpupdate_20260212_103015.log
[2026-02-12 10:30:22][INFO] Processing PC01
[2026-02-12 10:30:22][DEBUG] Checking WinRM on PC01...
[2026-02-12 10:30:23][DEBUG] WinRM available on PC01
[2026-02-12 10:30:23][INFO] Executing 'gpupdate /force' on PC01
[2026-02-12 10:30:45][SUCCESS] GPUpdate succeeded on PC01
```

### Event Log
When `-LogToEventLog` is specified, events are written to:
- Log: `Application`
- Source: `RemoteGPUpdate`

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (all computers) |
| 1 | Remote execution failed (one or more computers) |
| 2 | WinRM unavailable |
| 3 | Timeout |
| 4 | Cancelled by user |
| 5 | Credentials required but not provided |
| 6 | Invalid parameters |

## Use Cases

### Help Desk Scenario
User reports Group Policy not applying:
```powershell
# Quick remote refresh
.\Invoke-RemoteGPUpdate.ps1 -ComputerName USER-PC01 -UseCurrent -PolicyTarget Both
```

### Post-GPO Deployment
After deploying new Group Policy:
```powershell
# Refresh all domain computers
$computers = Get-ADComputer -Filter {Enabled -eq $true} | Select-Object -ExpandProperty Name
$computers | .\Invoke-RemoteGPUpdate.ps1 -UseCurrent -Parallel -ThrottleLimit 20
```

### Scheduled Maintenance
Run weekly GP refresh:
```powershell
# Task Scheduler Action:
powershell.exe -File "C:\Scripts\Invoke-RemoteGPUpdate.ps1" `
    -ComputerList PC01,PC02,PC03 `
    -UseCurrent `
    -ExportResults `
    -LogPath "C:\Logs\WeeklyGPUpdate.log"
```

### Troubleshooting
When user GPOs aren't applying:
```powershell
.\Invoke-RemoteGPUpdate.ps1 `
    -ComputerName USER-PC `
    -PolicyTarget User `
    -ForcePrompt `
    -DefaultUser "DOMAIN\Admin"
```

## Troubleshooting

### "WinRM not available"
Enable WinRM on target:
```powershell
# On target computer (as Admin)
Enable-PSRemoting -Force
# Or
winrm quickconfig -q
```

### "Access denied"
- Verify credentials have admin rights on target
- Check Windows Firewall allows WinRM
- Ensure target is in TrustedHosts (for workgroup):
  ```powershell
  Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
  ```

### "GUI dialog failed"
Run in console mode:
```powershell
.\Invoke-RemoteGPUpdate.ps1 -ComputerName PC01 -UseCurrent
```

### CredUI not appearing
The script automatically falls back to WinForms if CredUI fails. To force WinForms:
```powershell
# Not possible directly, but CredUI errors are logged
```

### Slow performance
Use parallel processing for bulk operations:
```powershell
.\Invoke-RemoteGPUpdate.ps1 -ComputerList $computers -Parallel -ThrottleLimit 10
```

## Security Considerations

- Credentials are never logged
- Passwords are stored in SecureString objects
- Password memory is cleared after use
- Use `-UseCurrent` to avoid credential prompts in scripts
- Consider using managed service accounts for automation

## Version History

### 3.0 (2026-02-12)
- Complete rewrite with improved structure
- Added bulk operations and parallel processing
- Added pipeline input support
- Added WhatIf support
- Added Event Log integration
- Added export results functionality
- Improved error handling and logging
- Better parameter validation

### 2.0 (2026-02-04)
- Basic remote GPUpdate functionality
- GUI dialog for selection
- CredUI and WinForms credential prompts
- Basic logging

### 1.0
- Initial release

## See Also

- `Check-IntuneEnrollment.ps1` - Intune device enrollment
- `Get-IntuneInactiveIOSDevices.ps1` - iOS device reporting
- Microsoft Docs: [About Remote Troubleshooting](https://docs.microsoft.com/powershell/module/microsoft.powershell.core/about/about_remote_troubleshooting)

## License

MIT License - Use at your own risk. Ensure you have proper authorization before executing remote commands.
