# Dell Bloatware Remover

PowerShell script to remove Dell pre-installed software (bloatware) while preserving Dell Command Update for driver/firmware management.

## Overview

Dell systems often come with numerous pre-installed applications that consume resources and clutter the system. This script intelligently identifies and removes the bloatware while keeping useful tools like Dell Command Update intact.

## What Gets Removed

### Support and Diagnostics
- Dell SupportAssist (and all plugins)
- Dell Support Center
- Dell Help & Support
- Dell Customer Connect

### Performance and Optimization
- Dell Optimizer (and service)
- Dell Power Manager (and service)
- Dell CinemaColor / Digital Color

### Audio and Video
- Dell CinemaSound
- Dell Waves MaxxAudio
- Dell Audio (various versions)

### Display
- Dell Display Manager
- Dell PremierColor

### Software Delivery
- Dell Digital Delivery
- Dell Update (the consumer version, not Command Update)

### Productivity
- Dell Mobile Connect
- Dell QuickSet
- Dell Featured Application

### Other
- Dell Foundation Services
- Dell Registration
- Dell Getting Started
- Dell Customer Improvement Program
- Dell Peripheral Manager
- Dell Encryption/Security apps
- Dell Trusted Device

### Common Third-Party Bloatware
- McAfee trials
- Norton trials
- WildTangent games
- CyberLink trials
- Dropbox promotions
- Adobe trials
- ExpressVPN

## What Gets Preserved

### Always Protected
- **Dell Command | Update** (all variants)
  - Dell Command | Update
  - Dell Command | Update for Windows
  - Dell Command | Update for Windows Universal
  - Dell Command | Update for Windows (Universal)

### Can Be Added to Preserve List
Use the `-Keep` parameter to preserve additional apps:
```powershell
.\Remove-DellBloatware.ps1 -Keep "Dell Power Manager", "Dell Digital Delivery"
```

## Quick Start

### Interactive Mode (Recommended)
```powershell
.\Remove-DellBloatware.ps1
```
Scans your system, shows what will be removed, and asks for confirmation.

### Preview Mode (Safe)
```powershell
.\Remove-DellBloatware.ps1 -WhatIf
```
Shows what would be removed without making any changes.

### Silent Mode (Deployment)
```powershell
.\Remove-DellBloatware.ps1 -Force
```
Removes bloatware without prompts (good for SCCM/Intune deployment).

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `WhatIf` | Switch | `$false` | Preview mode - show what would be removed |
| `Force` | Switch | `$false` | Skip confirmation prompts |
| `Keep` | string[] | (none) | Additional packages to preserve |
| `Remove` | string[] | (none) | Additional packages to remove |
| `LogPath` | string | `%TEMP%\DellBloatwareRemoval_*.log` | Path to save the removal log |

## Examples

### Basic Interactive Removal
```powershell
.\Remove-DellBloatware.ps1
```

### Preview Before Removal
```powershell
.\Remove-DellBloatware.ps1 -WhatIf
```

### Silent Deployment
```powershell
.\Remove-DellBloatware.ps1 -Force
```

### Keep Dell Power Manager
```powershell
.\Remove-DellBloatware.ps1 -Keep "Dell Power Manager"
```

### Also Remove Microsoft Office
```powershell
.\Remove-DellBloatware.ps1 -Remove "Microsoft Office*"
```

### Custom Log Location
```powershell
.\Remove-DellBloatware.ps1 -LogPath "C:\Logs\DellCleanup.log"
```

## How It Works

1. **Scanning** - Enumerates all installed applications via registry and AppX
2. **Filtering** - Identifies Dell apps matching bloatware patterns
3. **Protection** - Excludes Dell Command Update and user-specified apps
4. **Preparation** - Stops Dell services and scheduled tasks
5. **Removal** - Uninstalls each application using native uninstallers
6. **Logging** - Records all actions to a timestamped log file

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.1 or PowerShell 7+
- Administrator privileges (recommended)

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success - all targeted apps removed or not found |
| 1 | General error |
| 2 | User cancelled |
| 3 | Some apps failed to remove |

## Logging

All actions are logged to `%TEMP%\DellBloatwareRemoval_YYYYMMDD_HHMMSS.log`

Example log entries:
```
[2026-02-12 10:30:15] [Info] Scanning for installed applications...
[2026-02-12 10:30:22] [Info] Found 12 app(s) to remove:
[2026-02-12 10:30:45] [Success] Successfully removed: Dell SupportAssist
[2026-02-12 10:31:02] [Success] Successfully removed: Dell Optimizer
[2026-02-12 10:31:15] [Error] Failed to remove Dell Digital Delivery: Exit code: 1603
```

## Troubleshooting

### "Access Denied" Errors
Some applications require Administrator privileges to uninstall. Right-click PowerShell and select "Run as Administrator".

### Some Apps Won't Remove
Some Dell services run with elevated protection. You may need to:
1. Boot into Safe Mode and run the script
2. Use Dell's own removal tools for stubborn apps
3. Manually uninstall from Control Panel

### Dell Command Update Gets Removed
If this happens, the app name likely doesn't match the protected patterns. Use `-Keep` to add it:
```powershell
.\Remove-DellBloatware.ps1 -Keep "Your Specific Dell Command Update Name"
```

### Script Finds No Apps
- Verify the apps are actually installed (check Control Panel)
- Some newer Dell apps use different registry locations
- Try running as Administrator

## Adding Custom Apps

### To Remove Additional Apps
```powershell
.\Remove-DellBloatware.ps1 -Remove "MyCompanyApp*", "VendorTool*"
```

### To Preserve Additional Apps
```powershell
.\Remove-DellBloatware.ps1 -Keep "Dell Power Manager", "Dell Display Manager"
```

## Deployment

### Intune / Endpoint Manager
Package the script and deploy with:
```powershell
powershell.exe -ExecutionPolicy Bypass -File Remove-DellBloatware.ps1 -Force
```

### SCCM
Use as a Task Sequence step:
- **Command line:** `powershell.exe -ExecutionPolicy Bypass -File Remove-DellBloatware.ps1 -Force`
- **Timeout:** 30 minutes

### MDT
Add to your task sequence after OS installation but before user profile creation.

## Why Preserve Dell Command Update?

Dell Command | Update is the **only** Dell tool worth keeping because:
- Updates BIOS/firmware automatically
- Keeps drivers current
- Can be configured for silent/scheduled updates
- Actually useful for system maintenance

All other Dell software is essentially marketing, telemetry, or redundant.

## Alternatives

### Manual Removal
Control Panel → Programs and Features (but who has time for that?)

### Dell's Official Tool
Dell provides a "Dell Digital Delivery" removal tool, but it's specific to that one app.

### Third-Party Debloaters
Scripts like Windows10Debloater or Chris Titus Tech's Windows Utility can remove Dell apps, but may be too aggressive.

## Version History

### 1.0 (2026-02-12)
- Initial release
- Scans registry and AppX packages
- Preserves Dell Command Update variants
- Supports WhatIf, Force, Keep, and Remove parameters
- Comprehensive logging

## License

MIT License - Use at your own risk. Always test on non-production systems first.

## Disclaimer

This script is provided as-is. Dell may change their software names or installation methods. Always review what the script plans to remove before confirming. The authors are not responsible for accidentally removed software.
