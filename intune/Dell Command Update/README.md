# Dell Command Update - Intune Package

Automated Dell driver, BIOS, and firmware updates via Dell Command Update for Intune deployment.

## Overview

This package provides scripts to:
1. Check if Dell Command Update is installed
2. Download and install it if missing
3. Update all Dell drivers, BIOS, and firmware
4. Update Dell Command Update itself
5. Control reboot behavior

**Important:** This only installs Dell Command Update and runs updates. No other Dell software is installed.

## Contents

| File | Purpose |
|------|---------|
| `Install-DellCommandUpdate.ps1` | Main script - installs DCU and runs updates |
| `Remove-DellCommandUpdate.ps1` | Removes Dell Command Update |
| `Detect-DellCommandUpdate.ps1` | Detection script for Intune |

## Features

- ✅ **Auto-detect Dell hardware** — Only runs on Dell computers
- ✅ **Download & Install** — Downloads Dell Command Update if not present
- ✅ **Comprehensive Updates** — Drivers, BIOS, firmware, and DCU itself
- ✅ **Reboot Control** — Option to suppress, schedule, or allow immediate reboot
- ✅ **Update Filtering** — Control severity and types of updates
- ✅ **WhatIf Mode** — Preview updates without installing

## Quick Start

### Basic Usage (Install and Update)

```powershell
.\Install-DellCommandUpdate.ps1
```

This will:
- Check if Dell Command Update is installed
- Download and install if missing
- Update all drivers, BIOS, and firmware
- Reboot automatically if required

### Suppress Reboot

```powershell
.\Install-DellCommandUpdate.ps1 -NoReboot
```

Updates install but system won't reboot. Updates requiring restart will be pending.

### Schedule Reboot for Later

```powershell
.\Install-DellCommandUpdate.ps1 -ScheduleReboot -RebootDelayMinutes 120
```

Installs updates and schedules reboot in 2 hours.

### Preview Only (WhatIf)

```powershell
.\Install-DellCommandUpdate.ps1 -WhatIf
```

Shows what would be updated without making any changes.

## Intune Deployment

### As Win32 App

1. **Prepare your files:**
   ```
   DellCommandUpdate/
   ├── Install-DellCommandUpdate.ps1
   ├── Remove-DellCommandUpdate.ps1
   └── Detect-DellCommandUpdate.ps1
   ```

2. **Create .intunewin package:**
   ```powershell
   IntuneWinAppUtil.exe -c "C:\DellCommandUpdate" -s "Install-DellCommandUpdate.ps1" -o "C:\Output"
   ```

3. **Configure in Intune:**
   - **Name**: Dell Command Update
   - **Description**: Installs Dell Command Update and applies driver/BIOS updates
   - **Publisher**: Dell

4. **Program Settings:**

   **Install command (with no reboot):**
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File "Install-DellCommandUpdate.ps1" -NoReboot
   ```

   **Install command (with scheduled reboot):**
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File "Install-DellCommandUpdate.ps1" -ScheduleReboot -RebootDelayMinutes 60
   ```

   **Uninstall command:**
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File "Remove-DellCommandUpdate.ps1"
   ```

5. **Detection Rules:**
   - Use custom detection script: `Detect-DellCommandUpdate.ps1`

### As Proactive Remediation

Run weekly to keep drivers updated:

**Detection Script:**
```powershell
# Check if updates are available
$dcu = "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe"
if (Test-Path $dcu) {
    $scan = & $dcu /scan 2>&1
    if ($scan -match "updates available") {
        exit 1  # Updates needed
    }
}
exit 0
```

**Remediation Script:**
```powershell
.\Install-DellCommandUpdate.ps1 -NoReboot
```

## Script Parameters

### Install-DellCommandUpdate.ps1

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `DownloadURL` | No | Dell official | URL to download DCU installer |
| `InstallerPath` | No | - | Local path to installer (if pre-staged) |
| `NoReboot` | No | `$false` | Suppress automatic reboot |
| `ScheduleReboot` | No | `$false` | Schedule reboot for later |
| `RebootDelayMinutes` | No | `60` | Minutes before scheduled reboot |
| `UpdateSeverity` | No | `recommended` | Minimum severity: critical/recommended/optional |
| `UpdateType` | No | `all` | Types: bios,firmware,driver,application,utility |
| `LogPath` | No | Intune logs | Path for log files |
| `WhatIf` | No | `$false` | Preview updates without installing |

## Update Severity Levels

- **Critical** — Only critical security and stability updates
- **Recommended** — Recommended updates including feature improvements (default)
- **Optional** — All available updates including minor improvements

## Update Types

Comma-separated list or `all`:
- **bios** — BIOS/UEFI updates
- **firmware** — Firmware updates (RAID, NIC, etc.)
- **driver** — Device drivers
- **application** — Dell applications
- **utility** — Dell utilities

## Examples

### Critical Updates Only

```powershell
.\Install-DellCommandUpdate.ps1 -UpdateSeverity critical -NoReboot
```

### BIOS and Firmware Only

```powershell
.\Install-DellCommandUpdate.ps1 -UpdateType bios,firmware -ScheduleReboot
```

### Use Pre-staged Installer

```powershell
.\Install-DellCommandUpdate.ps1 -InstallerPath "C:\Software\DellCommandUpdate.exe" -NoReboot
```

### Custom Download URL

```powershell
.\Install-DellCommandUpdate.ps1 -DownloadURL "https://internal.company.com/dcu.exe" -NoReboot
```

## Logging

Logs are written to:
```
%ProgramData%\Microsoft\IntuneManagementExtension\Logs\DellCommandUpdate.log
```

Example log output:
```
[2025-02-19 10:00:00] [INFO] === Dell Command Update Script Started ===
[2025-02-19 10:00:01] [SUCCESS] Confirmed Dell computer: OptiPlex 7090
[2025-02-19 10:00:05] [INFO] Dell Command Update not found - installation required
[2025-02-19 10:00:30] [SUCCESS] Dell Command Update installed successfully
[2025-02-19 10:00:35] [INFO] Starting Dell updates (Severity: recommended, Types: all)
[2025-02-19 10:15:00] [SUCCESS] Updates completed successfully
[2025-02-19 10:15:01] [WARN] Reboot is required to complete updates
```

## Registry Tracking

Successful operations create:
```
HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\DellCommandUpdate
  LastRun = "2025-02-19 10:15:00"
  DCUInstalled = "True"
  UpdatesApplied = "True"
  RebootRequired = "True"
  NoRebootFlag = "True"
  Success = "True"
```

## Reboot Behavior

### NoReboot Mode
```powershell
.\Install-DellCommandUpdate.ps1 -NoReboot
```
- Updates install immediately
- No automatic restart
- Updates requiring reboot remain pending
- User sees Windows Update-style "Restart required" notification

### ScheduleReboot Mode
```powershell
.\Install-DellCommandUpdate.ps1 -ScheduleReboot -RebootDelayMinutes 120
```
- Updates install immediately
- Reboot scheduled for specified time
- User sees countdown notification
- Cancel with: `shutdown /a`

### Default Mode (Immediate)
```powershell
.\Install-DellCommandUpdate.ps1
```
- Updates install immediately
- If reboot required, system restarts immediately after script completes
- Use only when immediate restart is acceptable

## Troubleshooting

### "Not a Dell computer"

Script checks WMI for Dell manufacturer. If your Dell shows differently:
```powershell
Get-WmiObject -Class Win32_ComputerSystem | Select Manufacturer, Model
```

### Download Fails

- Check internet connectivity
- Try custom URL with internal hosting:
  ```powershell
  .\Install-DellCommandUpdate.ps1 -DownloadURL "https://internal.company.com/dcu.exe"
  ```

### Updates Fail

Run manually to see DCU output:
```powershell
& "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe" /scan
& "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe" /applyUpdates
```

### Detection Issues

Check if installed:
```powershell
Test-Path "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe"
```

## DCU CLI Reference

Common Dell Command Update CLI commands:

```cmd
# Scan for updates
dcu-cli.exe /scan

# Apply all updates
dcu-cli.exe /applyUpdates

# Apply only critical updates
dcu-cli.exe /applyUpdates -updateSeverity=critical

# Apply only BIOS updates
dcu-cli.exe /applyUpdates -updateType=bios

# Apply updates without reboot
dcu-cli.exe /applyUpdates -reboot=disable
```

## Requirements

- Dell computer (hardware check included)
- Windows 10/11
- PowerShell 5.1 or higher
- Administrator rights
- Internet connection (for downloads)
- Approximately 500MB free space

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-02-19 | Initial release |

## Important Notes

- **BIOS updates** will always require a reboot
- **Firmware updates** may require a reboot
- Driver updates typically don't require reboot but some do
- The script only installs Dell Command Update - no other Dell bloatware
- On non-Dell computers, the script exits gracefully without error

## Support

- Dell Command Update Documentation: https://www.dell.com/support/kbdoc/000178866/
- Dell Support: https://www.dell.com/support

## License

MIT License — Modify for your environment as needed.
