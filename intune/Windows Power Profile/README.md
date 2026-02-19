# Windows Power Profile - Intune Package

PowerShell scripts to deploy and manage Windows power plans (power profiles) via Microsoft Intune.

## Overview

This package provides scripts to import, export, copy, and set Windows power plans across your organization. Useful for standardizing power settings like sleep timeouts, display brightness, and processor state management.

## Contents

| File | Purpose |
|------|---------|
| `Set-PowerProfile.ps1` | Main script to import/copy/set power plans |
| `Remove-PowerProfile.ps1` | Removes custom power plans |
| `Detect-PowerProfile.ps1` | Detects if power plan is active (Intune) |

## What Are Power Plans?

Windows power plans control how your computer manages power:
- **Balanced** (default) - Automatically balances performance with energy consumption
- **Power Saver** - Saves energy by reducing performance
- **High Performance** - Maximizes performance at the cost of higher energy consumption
- **Custom Plans** - User-defined settings for specific needs

## Quick Start

### List Available Plans

```powershell
.\Set-PowerProfile.ps1 -ListPlans
```

Output:
```
Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced) *
Power Scheme GUID: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (High performance)
Power Scheme GUID: a1841308-3541-4fab-bc81-f71556f20b4a  (Power saver)
```

### Export Current Plan (for reference/template)

```powershell
.\Set-PowerProfile.ps1 -ExportCurrentPlan -ExportPath "C:\PowerPlans\Template.pow"
```

### Import and Set a Power Plan

```powershell
.\Set-PowerProfile.ps1 -PowerPlanFile "C:\PowerPlans\Corporate.pow" -PlanName "Corporate Power Plan" -SetActive
```

### Copy Existing Plan

```powershell
.\Set-PowerProfile.ps1 -CopyExistingPlan -SourcePlanGUID "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" -NewPlanName "Corporate High Performance" -SetActive
```

## Creating Custom Power Plans

### Method 1: Export from Configured Machine

1. Configure power settings on a reference machine:
   - Control Panel → Power Options → Change plan settings
   - Adjust display/sleep timeouts, processor power management, etc.

2. Export the plan:
   ```powershell
   .\Set-PowerProfile.ps1 -ExportCurrentPlan -ExportPath "C:\PowerPlans\Corporate.pow"
   ```

3. Deploy the .pow file via Intune

### Method 2: Copy Built-in Plan and Modify

```powershell
# Copy High Performance as base
.\Set-PowerProfile.ps1 -CopyExistingPlan -SourcePlanGUID "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" -NewPlanName "Corporate Plan"
```

Then modify with powercfg commands:
```cmd
# Set display timeout (AC/DC in seconds)
powercfg /change monitor-timeout-ac 10
powercfg /change monitor-timeout-dc 5

# Set sleep timeout
powercfg /change standby-timeout-ac 30
powercfg /change standby-timeout-dc 15

# Set hard disk timeout
powercfg /change disk-timeout-ac 20
```

## Intune Deployment

### As Win32 App

1. **Prepare your files:**
   ```
   PowerProfile/
   ├── Set-PowerProfile.ps1
   ├── Remove-PowerProfile.ps1
   ├── Detect-PowerProfile.ps1
   └── Corporate.pow (your exported power plan)
   ```

2. **Create .intunewin package:**
   ```powershell
   IntuneWinAppUtil.exe -c "C:\PowerProfile" -s "Set-PowerProfile.ps1" -o "C:\Output"
   ```

3. **Configure in Intune:**
   - **Name**: Corporate Power Profile
   - **Description**: Deploys corporate power plan settings

4. **Program Settings:**

   **Install command:**
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File "Set-PowerProfile.ps1" -PowerPlanFile ".\Corporate.pow" -PlanName "Corporate Plan" -SetActive
   ```

   **Uninstall command:**
   ```powershell
   # Get the GUID from registry first, or use detection
   powershell.exe -ExecutionPolicy Bypass -Command "& {$reg=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\PowerProfile' -Name PlanGUID -EA 0); if($reg.PlanGUID){.\Remove-PowerProfile.ps1 -PlanGUID $reg.PlanGUID}}"
   ```

5. **Detection Rules:**
   - Use custom detection script: `Detect-PowerProfile.ps1`
   - Or use registry detection:
     - Path: `HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\PowerProfile`
     - Value name: `Success`
     - Value data: `True`

### As PowerShell Script

Deploy directly through Intune PowerShell scripts:
```powershell
.\Set-PowerProfile.ps1 -CopyExistingPlan -SourcePlanGUID "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" -NewPlanName "Corporate Performance" -SetActive
```

## Script Parameters

### Set-PowerProfile.ps1

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `PowerPlanFile` | No* | - | Path to .pow file to import |
| `PlanName` | No | Filename | Name for imported plan |
| `SetActive` | No | `$false` | Set as active power plan |
| `CopyExistingPlan` | No | `$false` | Copy an existing plan |
| `SourcePlanGUID` | No* | - | GUID of plan to copy |
| `NewPlanName` | No* | - | Name for copied plan |
| `ExportCurrentPlan` | No | `$false` | Export current plan |
| `ExportPath` | No | Temp | Path for export |
| `ListPlans` | No | `$false` | List all plans and exit |

*Required for specific operations

### Remove-PowerProfile.ps1

| Parameter | Required | Description |
|-----------|----------|-------------|
| `PlanGUID` | **Yes** | GUID of plan to remove |

### Detect-PowerProfile.ps1

| Parameter | Required | Description |
|-----------|----------|-------------|
| `PlanGUID` | No | Check specific plan by GUID |
| `PlanName` | No | Check specific plan by name |

## Power Plan GUIDs (Built-in)

| Plan | GUID |
|------|------|
| Balanced | 381b4222-f694-41f0-9685-ff5bb260df2e |
| High Performance | 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c |
| Power Saver | a1841308-3541-4fab-bc81-f71556f20b4a |
| Ultimate Performance | e9a42b02-d5df-448d-aa00-03f14749eb61 |

## Common Customizations

### Corporate Desktop Plan

```cmd
# After importing, customize:
powercfg /change monitor-timeout-ac 20      ; Turn off display after 20 min (plugged in)
powercfg /change monitor-timeout-dc 10      ; Turn off display after 10 min (battery)
powercfg /change standby-timeout-ac 0       ; Never sleep (plugged in)
powercfg /change standby-timeout-dc 30      ; Sleep after 30 min (battery)
powercfg /change disk-timeout-ac 0          ; Never turn off hard disk
```

### Always-On Laptop Plan

```cmd
powercfg /change monitor-timeout-ac 10
powercfg /change standby-timeout-ac 0       ; Never sleep when plugged in
powercfg /change hibernate-timeout-ac 0     ; Never hibernate
```

### Power Saver Plan for Field Workers

```cmd
powercfg /change monitor-timeout-dc 5
powercfg /change standby-timeout-dc 10
powercfg /change processor-throttle-ac 50   ; Limit CPU to 50%
```

## Troubleshooting

### "Access Denied" Errors

- Script must run as Administrator
- Verify with: `Test-Path "HKLM:\SOFTWARE"`

### Plan Not Appearing After Import

Run manually to see output:
```powershell
.\Set-PowerProfile.ps1 -ListPlans
```

### Detection Fails

Check if plan GUID exists:
```cmd
powercfg /list
```

### Built-in Plans Can't Be Deleted

The script can only remove custom imported plans, not built-in Windows plans.

## Logging

Logs are written to:
```
%ProgramData%\Microsoft\IntuneManagementExtension\Logs\PowerProfile.log
```

## Registry Tracking

Successful operations create:
```
HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\PowerProfile
  PlanGUID = "{your-plan-guid}"
  PlanName = "Corporate Power Plan"
  IsActive = "True"
  LastRun = "2025-02-19 10:30:00"
  Success = "True"
```

## Requirements

- Windows 10/11
- PowerShell 5.1 or higher
- Administrator rights
- Domain-joined or standalone (no domain requirement)

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-02-19 | Initial release |

## References

- [Powercfg Command-Line Options](https://docs.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options)
- [Power Management in Windows](https://docs.microsoft.com/en-us/windows-hardware/design/device-experiences/power-management)

## License

MIT License — Modify for your environment as needed.
