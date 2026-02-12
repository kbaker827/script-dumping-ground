# Adobe Sign Cache Reset Tool

PowerShell utility to clear Adobe identity and Acrobat Sign caches to fix "Request e-signatures" issues. Supports both local and remote execution.

## Overview

When users experience issues with the "Request e-signatures" feature in Adobe Acrobat, it's often due to stale identity tokens or corrupted caches. This script:

- Safely closes Adobe processes
- Backs up existing cache folders
- Removes identity/token caches
- Clears Windows Web Credentials for Adobe
- Restarts Creative Cloud helper

## Features

- ✅ **Local Execution** - Run for current user
- ✅ **Remote Execution** - Run on remote machines via PowerShell Remoting
- ✅ **All Users Mode** - Clear caches for all profiles on machine
- ✅ **Safe Backups** - All caches backed up before removal
- ✅ **Process Management** - Automatically closes Adobe applications
- ✅ **Credential Cleanup** - Removes stale Adobe Windows credentials
- ✅ **Comprehensive Logging** - Detailed logs for troubleshooting
- ✅ **WhatIf Support** - Preview changes before applying

## Quick Start

### Local Cleanup
```powershell
.\Reset-AdobeSignCache.ps1
```

### Remote Cleanup (Single Machine)
```powershell
.\Reset-AdobeSignCache.ps1 -ComputerName PC01 -UseCurrent
```

### Remote Cleanup (Multiple Machines)
```powershell
.\Reset-AdobeSignCache.ps1 -ComputerName PC01,PC02,PC03 -Credential (Get-Credential)
```

### All Users on Local Machine
```powershell
.\Reset-AdobeSignCache.ps1 -RemoveAllUsers -Force
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ComputerName` | string[] | - | Remote computer(s) to process |
| `Credential` | PSCredential | - | Credentials for remote auth |
| `UseCurrent` | switch | `$false` | Use current credentials for remote |
| `Quiet` | switch | `$false` | Suppress console output |
| `SkipProcessClose` | switch | `$false` | Don't close Adobe processes |
| `SkipBackup` | switch | `$false` | Don't backup caches (not recommended) |
| `BackupPath` | string | `%LOCALAPPDATA%\Adobe\_CacheBackups` | Custom backup location |
| `RemoveAllUsers` | switch | `$false` | Process all user profiles |
| `RestartAcrobat` | switch | `$false` | Restart Acrobat after cleanup |
| `LogPath` | string | `%TEMP%\AdobeSignCacheReset_*.log` | Log file path |
| `WhatIf` | switch | `$false` | Preview mode |
| `Force` | switch | `$false` | Skip confirmation prompts |

## Cache Locations Cleared

The script clears the following Adobe cache locations:

### Identity/Entitlement Caches
- `%LOCALAPPDATA%\Adobe\OOBE`
- `%APPDATA%\Adobe\OOBE`

### Acrobat CEF (Chromium) Caches
- `%APPDATA%\Adobe\Acrobat\DC\AcroCEF\Cache`
- `%APPDATA%\Adobe\Acrobat\DC\AcroCEF\GPUCache`
- `%LOCALAPPDATA%\Adobe\Acrobat\DC\AcroCEF\Cache`
- `%LOCALAPPDATA%\Adobe\Acrobat\DC\AcroCEF\GPUCache`

### Legacy Cache Locations
- `%APPDATA%\Adobe\Acrobat\DC\JSCache`
- `%APPDATA%\Adobe\Acrobat\DC\Security\csi`

## Examples

### Basic Local Cleanup
```powershell
.\Reset-AdobeSignCache.ps1
```
Clears caches for current user with full console output.

### Silent Mode (Deployment)
```powershell
.\Reset-AdobeSignCache.ps1 -Quiet -LogPath "C:\Logs\AdobeReset.log"
```
Runs silently, logs to specified file.

### Remote Single Computer
```powershell
.\Reset-AdobeSignCache.ps1 -ComputerName USER-PC01 -UseCurrent
```
Uses your current credentials to connect and clean remote PC.

### Remote with Explicit Credentials
```powershell
$cred = Get-Credential -Message "Enter admin credentials for remote PC"
.\Reset-AdobeSignCache.ps1 -ComputerName USER-PC01 -Credential $cred
```

### Multiple Remote Computers
```powershell
$computers = Get-Content computers.txt
.\Reset-AdobeSignCache.ps1 -ComputerName $computers -UseCurrent
```

### All Users on Local Machine
```powershell
.\Reset-AdobeSignCache.ps1 -RemoveAllUsers -Force
```
Clears Adobe caches for every user profile on the machine (requires admin).

### Preview Mode
```powershell
.\Reset-AdobeSignCache.ps1 -WhatIf
```
Shows what would be cleared without making changes.

### Custom Backup Location
```powershell
.\Reset-AdobeSignCache.ps1 -BackupPath "D:\AdobeBackups" -RemoveAllUsers
```

### Skip Process Close (Use with Caution)
```powershell
.\Reset-AdobeSignCache.ps1 -SkipProcessClose
```
Clears caches without closing Adobe apps (may cause issues).

## Remote Execution Requirements

### Target Machine Must Have:
- Windows PowerShell/WinRM enabled
- Windows Firewall allowing WinRM (port 5985)
- User account with administrative rights

### Enable WinRM on Targets
Run on target computers (as Administrator):
```powershell
Enable-PSRemoting -Force
# Or:
winrm quickconfig -q
```

## What Gets Closed

The script closes these Adobe processes before clearing caches:
- Acrobat
- AcroCEF
- AcroRd32
- AdobeCollabSync
- CCXProcess
- Creative Cloud
- Adobe Desktop Service
- CoreSync
- AGSService
- AGMService
- AdobeIPCBroker

## Output Example

```
================================
 Adobe Sign Cache Reset Tool v3.0
================================

[INFO] Started: 2026-02-12 10:30:15
[INFO] Log: C:\Users\jdoe\AppData\Local\Temp\AdobeSignCacheReset_20260212_103015.log

[INFO] === Processing USER-PC01 ===
[INFO] Closing Adobe processes on USER-PC01...
[ OK ] Stopped 3 Adobe process(es)
[INFO] Processing 1 user profile(s)...
[INFO] Processing user: jdoe
[INFO] Backup location: C:\Users\jdoe\AppData\Local\Adobe\_CacheBackups\AdobeCache-jdoe-20260212-103015
[ OK ] Cleared: C:\Users\jdoe\AppData\Local\Adobe\OOBE
[ OK ] Cleared: C:\Users\jdoe\AppData\Roaming\Adobe\Acrobat\DC\AcroCEF\Cache
[ OK ] Cleared: C:\Users\jdoe\AppData\Roaming\Adobe\Acrobat\DC\AcroCEF\GPUCache
[INFO] Clearing Adobe Web Credentials...
[ OK ] Removed credential: AdobeApp:jdoe@contoso.com
[INFO] Starting Creative Cloud helper...
[ OK ] Started CCXProcess
[ OK ] Cleared 5 cache location(s), 0 failed

================================
  SUMMARY
================================

ComputerName Username Cleared Failed
------------ -------- ------- ------
USER-PC01    jdoe           5      0

Next steps:
  1. Open Adobe Acrobat and sign in
  2. Try File > Request e-signatures again
  3. If still failing, reboot once

[INFO] Log saved: C:\Users\jdoe\AppData\Local\Temp\AdobeSignCacheReset_20260212_103015.log
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success - all caches cleared |
| 1 | Partial success - some caches not cleared |
| 2 | Remote connection failed |
| 3 | No user profiles found |
| 4 | Cancelled by user |

## Use Cases

### Help Desk Support
User reports "Request e-signatures" not working:
```powershell
# Remote fix
.\Reset-AdobeSignCache.ps1 -ComputerName USER-PC01 -UseCurrent
```

### Mass Deployment
Deploy via SCCM/Intune to fix widespread issues:
```powershell
# Silent deployment
.\Reset-AdobeSignCache.ps1 -Quiet -Force
```

### Terminal Server Cleanup
Clear all user profiles on RDS/Terminal Server:
```powershell
.\Reset-AdobeSignCache.ps1 -RemoveAllUsers -Force -LogPath "C:\Logs\AdobeReset.log"
```

### Scheduled Maintenance
Weekly cleanup of stale caches:
```powershell
# Task Scheduler
powershell.exe -File "C:\Scripts\Reset-AdobeSignCache.ps1" -Quiet -Force
```

## Backup Structure

Backups are organized as:
```
%LOCALAPPDATA%\Adobe\_CacheBackups\
  └── AdobeCache-<username>-<timestamp>
      ├── C__Users_<user>_AppData_Local_Adobe_OOBE
      ├── C__Users_<user>_AppData_Roaming_Adobe_Acrobat_DC_AcroCEF_Cache
      └── ...
```

To restore a backup, simply copy the folder contents back to the original location.

## Troubleshooting

### "Access Denied" Errors
- Run as Administrator for `-RemoveAllUsers`
- For remote execution, ensure account has admin rights

### "WinRM not available" (Remote)
Enable PowerShell Remoting on target:
```powershell
Enable-PSRemoting -Force
```

### Adobe Still Not Working After Reset
1. Reboot the computer
2. Sign out/in of Adobe Creative Cloud
3. Reinstall Adobe Acrobat (last resort)

### Missing Cache Folders
Some folders may not exist depending on Adobe version. This is normal.

### Large Backup Size
If backups are consuming space:
```powershell
# Delete old backups (keeps last 7 days)
Get-ChildItem "$env:LOCALAPPDATA\Adobe\_CacheBackups" | 
    Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-7) } |
    Remove-Item -Recurse -Force
```

## Safety Features

- **Automatic Backups**: All caches backed up before removal
- **Process Termination**: Adobe apps safely closed first
- **Selective Cleanup**: Only Adobe-related caches touched
- **Credential Cleanup**: Removes only Adobe-related Windows credentials
- **WhatIf Mode**: Preview changes before applying

## Version History

### 3.0 (2026-02-12)
- Added remote execution support
- Added `-RemoveAllUsers` for multi-profile cleanup
- Added pipeline input support
- Added comprehensive logging
- Added WhatIf support
- Improved error handling
- Better backup organization

### 2.0 (2026-02-04)
- Basic local cache cleanup
- Process management
- Windows credential cleanup
- Backup functionality

### 1.0
- Initial release

## See Also

- `Force-SharePointPageCheckIn.ps1` - SharePoint administrative tool
- `Invoke-RemoteGPUpdate.ps1` - Remote Group Policy refresh
- Adobe Support: [Acrobat Sign Help](https://helpx.adobe.com/sign.html)

## License

MIT License - Use at your own risk. Always test on non-production systems first.
