# GlobalSearch Extension Cleanup Tool

PowerShell utility to remotely remove Square 9 GlobalSearch Extensions from Windows computers. Designed for IT administrators to perform comprehensive cleanup of GlobalSearch software.

## Overview

This script connects to remote computers via PowerShell Remoting and performs a thorough cleanup of Square 9 GlobalSearch Extensions, including:

- Stopping all related processes
- Running official uninstallers
- Cleaning ClickOnce application caches
- Removing user profile data
- Cleaning up shortcuts and registry entries
- Optionally removing Windows services

## Features

- ✅ **Remote Execution** - Clean multiple computers from central location
- ✅ **Parallel Processing** - Speed up bulk operations
- ✅ **Dry Run Mode** - Preview what would be removed
- ✅ **Comprehensive Logging** - Detailed logs on each target and central summary
- ✅ **Service Removal** - Optional removal of Windows services
- ✅ **Pipeline Support** - Accept input from Active Directory or files
- ✅ **WhatIf Support** - Safe preview before execution

## Quick Start

### Clean Single Computer
```powershell
.\Remove-GlobalSearchExtensions.ps1 -ComputerName "PC01"
```

### Clean Multiple Computers
```powershell
.\Remove-GlobalSearchExtensions.ps1 -ComputerName "PC01", "PC02", "PC03"
```

### Dry Run (Preview)
```powershell
.\Remove-GlobalSearchExtensions.ps1 -ComputerName "PC01" -DryRun
```

### Parallel Bulk Cleanup
```powershell
.\Remove-GlobalSearchExtensions.ps1 -ComputerName (Get-Content computers.txt) -Parallel -ThrottleLimit 10
```

### Pipeline from Active Directory
```powershell
Get-ADComputer -Filter {Enabled -eq $true} -SearchBase "OU=Workstations,DC=contoso,DC=com" | 
    Select-Object -ExpandProperty Name | 
    .\Remove-GlobalSearchExtensions.ps1 -Force
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ComputerName` | string[] | - | Target computer(s). Supports pipeline. |
| `Credential` | PSCredential | - | Credentials for remote connection. |
| `DryRun` | switch | `$false` | Preview mode - no changes made. |
| `Parallel` | switch | `$false` | Process computers in parallel. |
| `ThrottleLimit` | int | 5 | Max concurrent parallel operations. |
| `Force` | switch | `$false` | Skip confirmation prompts. |
| `IncludeServices` | switch | `$false` | Also remove Windows services. |
| `LogPath` | string | `%TEMP%\GlobalSearchCleanup_*.log` | Central log location. |
| `TimeoutMinutes` | int | 10 | Timeout for remote operations. |

## What Gets Removed

### Processes Stopped
- Square9.ExtensionsWebHelper
- GlobalSearchExtensions
- Square9Extensions
- Square9.Extensions
- Square9.GlobalSearch
- SmartSearch
- GlobalSearch.Desktop
- AdobeCollabSync (if related)

### Machine-Wide Uninstallers
Searches registry for products matching:
- `GlobalSearch Extension`
- `GlobalSearch Extensions`
- `Square 9*Extension`
- `GlobalSearch Desktop Extensions`
- `GlobalSearch Browser Extension`
- `SmartSearch`
- `Square9 SmartSearch`

Runs uninstallers with silent flags (`/qn`, `/S`)

### Per-User Cleanup
For each user profile on target computers:

**Folders Removed:**
- `%LOCALAPPDATA%\Square_9_Softworks\GlobalSearch_Extensions`
- `%LOCALAPPDATA%\Apps\Square9_Apps`
- `%LOCALAPPDATA%\Square9`
- `%APPDATA%\Square9`
- `%APPDATA%\Square_9_Softworks`
- `%APPDATA%\Adobe\Acrobat\DC\AcroCEF\Cache` (if GlobalSearch-related)

**ClickOnce Cache:**
- `%LOCALAPPDATA%\Apps\2.0\*square9*`
- `%LOCALAPPDATA%\Apps\2.0\*globalsearch*`
- `%LOCALAPPDATA%\Apps\2.0\*smartsearch*`
- Lock files (`square9.loginclient-update.lock`)

### Shortcuts Removed
From:
- `C:\ProgramData\Microsoft\Windows\Start Menu\Programs`
- `C:\Users\Public\Desktop`
- `C:\ProgramData\Desktop`

Matching patterns:
- `*GlobalSearch*.lnk`
- `*Square9*.lnk`
- `*Extensions*.lnk`
- `*SmartSearch*.lnk`

### Registry Keys Removed
- `HKLM:\SOFTWARE\Square9Softworks`
- `HKLM:\SOFTWARE\Square_9_Softworks`
- `HKLM:\SOFTWARE\WOW6432Node\Square9Softworks`
- `HKLM:\SOFTWARE\WOW6432Node\Square_9_Softworks`

## Examples

### Basic Single Computer
```powershell
.\Remove-GlobalSearchExtensions.ps1 -ComputerName "WKSTN-12345"
```

### With Service Removal
```powershell
.\Remove-GlobalSearchExtensions.ps1 -ComputerName "SERVER01" -IncludeServices -Force
```

### From Text File
```powershell
$computers = Get-Content "C:\Scripts\GlobalSearchComputers.txt"
.\Remove-GlobalSearchExtensions.ps1 -ComputerName $computers -Parallel
```

### Dry Run All Domain Computers
```powershell
Get-ADComputer -Filter {Enabled -eq $true} | 
    Select-Object -ExpandProperty Name | 
    .\Remove-GlobalSearchExtensions.ps1 -DryRun
```

### Silent Deployment
```powershell
.\Remove-GlobalSearchExtensions.ps1 -ComputerName PC01,PC02,PC03 -Force -LogPath "C:\Logs\GS_Cleanup.log"
```

## Requirements

### Local Machine (Running the Script)
- Windows PowerShell 5.1 or PowerShell 7+
- Network connectivity to target computers
- Administrative credentials on target computers

### Target Computers
- Windows PowerShell/WinRM enabled
- Windows Firewall allowing WinRM (port 5985 HTTP, 5986 HTTPS)
- User account with local administrator rights

### Enable WinRM on Targets
Run on target computers (as Administrator):
```powershell
Enable-PSRemoting -Force
# Or:
winrm quickconfig -q
```

## Output

### Console Output Example
```
==========================================
  GlobalSearch Extension Cleanup v3.0
==========================================

[*] Started: 2026-02-12 10:30:15
[*] Central log: C:\Users\admin\AppData\Local\Temp\GlobalSearchCleanup_20260212_103015.log
[*] DryRun: False, Parallel: True

[*] Target computers: PC01, PC02, PC03, PC04, PC05
[*] Total: 5 computer(s)

Proceed with cleanup on 5 computer(s)? (Y/N): Y

[*] Processing in parallel (max 5 concurrent)...

[PC01] Processes: 2, Uninstallers: 1, Folders: 5
[PC02] Processes: 1, Uninstallers: 1, Folders: 4
[PC03] Processes: 3, Uninstallers: 0, Folders: 6
[PC04] Processes: 0, Uninstallers: 1, Folders: 3
[PC05] Processes: 2, Uninstallers: 1, Folders: 5

==========================================
  SUMMARY
==========================================

[*] Total computers: 5
[+] Successful: 5
[+] Failed: 0

[*] Duration: 02:34
[*] Central log: C:\Users\admin\AppData\Local\Temp\GlobalSearchCleanup_20260212_103015.log
```

### Remote Log Location
On each target computer:
- `C:\ProgramData\Square9-Cleanup\cleanup_YYYYMMDD_HHMMSS.log`

Example log content:
```
2026-02-12 10:30:18 [INFO] === GlobalSearch Extensions cleanup started (DryRun=False) ===
2026-02-12 10:30:18 [INFO] Stopping process: Square9.ExtensionsWebHelper (1 instance(s))
2026-02-12 10:30:20 [INFO] Stopping process: GlobalSearchExtensions (2 instance(s))
2026-02-12 10:30:22 [INFO] Uninstalling: GlobalSearch Desktop Extensions
2026-02-12 10:30:45 [INFO] Uninstall exit code for GlobalSearch Desktop Extensions: 0
2026-02-12 10:30:45 [INFO] Removing folder: C:\Users\jdoe\AppData\Local\Square9
2026-02-12 10:30:46 [INFO] Removing ClickOnce cache: C:\Users\jdoe\AppData\Local\Apps\2.0\ABC123\square9...
2026-02-12 10:31:05 [INFO] === Cleanup completed. Reboot recommended. ===
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success - all computers cleaned |
| 1 | Partial success - some computers failed |
| 2 | All computers failed |
| 3 | No valid computer names provided |
| 4 | Cancelled by user |

## Use Cases

### Software Migration
Removing old GlobalSearch before deploying new version:
```powershell
.\Remove-GlobalSearchExtensions.ps1 -ComputerName (Get-Content old-versions.txt) -Force
```

### Post-Uninstall Cleanup
When standard uninstall leaves remnants:
```powershell
.\Remove-GlobalSearchExtensions.ps1 -ComputerName "TROUBLE-PC" -IncludeServices
```

### Department Cleanup
Remove from entire OU:
```powershell
Get-ADComputer -SearchBase "OU=Sales,OU=Users,DC=contoso,DC=com" -Filter * | 
    Select-Object -ExpandProperty Name | 
    .\Remove-GlobalSearchExtensions.ps1 -Parallel -ThrottleLimit 20
```

### Verification Run
Preview what would be removed:
```powershell
.\Remove-GlobalSearchExtensions.ps1 -ComputerName "PC01" -DryRun
```

## Troubleshooting

### "Access Denied" Errors
- Verify credentials have local admin rights on target
- Check that target computer allows remote administration

### "WinRM not available"
Enable PowerShell Remoting on target:
```powershell
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
```

### "No uninstall entries found"
Software may have been partially removed. The script will still clean:
- Leftover processes
- Cache folders
- Registry keys

### Slow Performance on Many Computers
Use parallel processing:
```powershell
.\Remove-GlobalSearchExtensions.ps1 -ComputerName $computers -Parallel -ThrottleLimit 10
```

### Need to Remove Services
Some GlobalSearch versions install Windows services. Use `-IncludeServices`:
```powershell
.\Remove-GlobalSearchExtensions.ps1 -ComputerName "SERVER01" -IncludeServices
```

## Safety Features

- **Dry Run Mode**: Preview all actions before making changes
- **Confirmation Prompts**: Asks before execution (unless `-Force`)
- **Detailed Logging**: Every action logged on target and central host
- **Graceful Degradation**: Continues if individual components fail
- **Process Safety**: Stops processes before attempting removal

## Version History

### 3.0 (2026-02-12)
- Added parallel processing support
- Added service removal option (`-IncludeServices`)
- Added pipeline input support
- Improved error handling
- Added comprehensive summary reporting
- Added central logging
- Better parameter validation

### 2.0 (2026-02-04)
- Basic remote cleanup functionality
- Dry run support
- Process and uninstaller management
- ClickOnce cache cleanup

### 1.0
- Initial release

## Related Scripts

- `Invoke-RemoteGPUpdate.ps1` - Remote Group Policy refresh
- `Remove-DellBloatware.ps1` - Dell software cleanup
- `Reset-AdobeSignCache.ps1` - Adobe cache cleanup

## License

MIT License - Use at your own risk. Always test on non-production systems first.

## Disclaimer

This script performs aggressive cleanup of Square 9 GlobalSearch software. Ensure you have:
- Proper authorization
- Backups of critical data
- Understanding of what will be removed
- Plan for reinstalling if needed
