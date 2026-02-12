# Intune Enrollment Troubleshooter

Comprehensive PowerShell script to diagnose and remediate Intune/MDM enrollment issues on Windows devices.

## Overview

This script performs a complete health check of Intune enrollment status and attempts to fix common issues automatically. It's designed for IT administrators troubleshooting devices that won't enroll or sync with Microsoft Intune.

## Features

- ✅ **Architecture Check** - Validates 64-bit PowerShell (required for some operations)
- ✅ **Windows Edition Check** - Verifies Pro/Enterprise/Education (Home is not supported)
- ✅ **Network Connectivity** - Tests all Intune endpoints (login.microsoftonline.com, manage.microsoft.com, etc.)
- ✅ **Service Health** - Checks required services (Task Scheduler, Cryptographic Services, etc.)
- ✅ **Azure AD Status** - Detailed parsing of dsregcmd output
- ✅ **MDM Enrollment** - Checks certificate health and enrollment state
- ✅ **Automatic Remediation** - Can attempt to fix issues automatically
- ✅ **Detailed Logging** - Comprehensive logs saved to %TEMP%
- ✅ **JSON Export** - Export results for further analysis

## Quick Start

### Interactive Mode (Recommended)
```powershell
.\Check-IntuneEnrollment.ps1
```

### Auto-Remediation Mode
```powershell
.\Check-IntuneEnrollment.ps1 -AutoRemediate
```

### Detailed Output with Export
```powershell
.\Check-IntuneEnrollment.ps1 -Detailed -ExportLog
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `AutoRemediate` | Switch | `$false` | Automatically attempt to fix issues |
| `Detailed` | Switch | `$false` | Show detailed registry and policy output |
| `ExportLog` | Switch | `$false` | Export results to JSON |
| `LogPath` | String | `%TEMP%\IntuneEnrollmentCheck_*.log` | Custom log file path |
| `ResetEnrollment` | Switch | `$false` | ⚠️ Attempt to reset MDM enrollment |

## What It Checks

### 1. PowerShell Architecture
- Validates 64-bit execution environment
- Exits with error if running 32-bit PowerShell

### 2. Windows Edition
- Pro, Enterprise, Education ✅ Supported
- Home ❌ Not supported (requires upgrade)
- Shows Windows build and version info

### 3. Network Connectivity
Tests these Intune endpoints:
- `login.microsoftonline.com`
- `device.login.microsoftonline.com`
- `enrollment.manage.microsoft.com`
- `manage.microsoft.com`
- `fef.msuc03.manage.microsoft.com`
- `m.manage.microsoft.com`

### 4. Required Services
Checks and can auto-start:
- Task Scheduler (MDM scheduled tasks)
- WinHTTP Web Proxy Auto-Discovery
- Cryptographic Services (certificates)
- Background Tasks Infrastructure Service

### 5. Azure AD Status
Parses `dsregcmd /status` for:
- Azure AD Join state
- Workplace Join state
- Tenant ID and Name
- User Email
- Device ID

### 6. MDM Enrollment
- MDM URL configuration
- MDM certificate in LocalMachine\My
- Certificate expiration check

## Remediation Actions

When `-AutoRemediate` is specified, the script attempts to:

1. **Start Required Services** - Starts any stopped critical services
2. **Azure AD Sync** - Runs `dsregcmd /sync` to refresh join status
3. **MDM Auto-Enrollment** - Enables registry key for automatic MDM enrollment
4. **Trigger Scheduled Tasks** - Runs MDM enrollment and sync tasks
5. **Policy Sync** - Attempts WMI-based policy refresh

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Device properly enrolled, no issues |
| 1 | Critical error (wrong architecture, Windows Home, etc.) |
| 2 | Not Azure AD joined |
| 3 | Azure AD joined but not MDM enrolled |
| 4 | Issues found but auto-remediation not enabled |
| 5 | Auto-remediation attempted but failed |

## Examples

### Basic Check
```powershell
.\Check-IntuneEnrollment.ps1
```
Runs all checks and shows results interactively.

### Silent Check with Auto-Remediate
```powershell
.\Check-IntuneEnrollment.ps1 -AutoRemediate
```
Attempts to fix issues automatically without prompts.

### Detailed Analysis
```powershell
.\Check-IntuneEnrollment.ps1 -Detailed -ExportLog
```
Shows detailed info and exports to JSON for ticketing systems.

### Custom Log Location
```powershell
.\Check-IntuneEnrollment.ps1 -LogPath "C:\Logs\IntuneCheck.log"
```

### For Deployment Scripts
```powershell
$exitCode = (Start-Process powershell.exe -ArgumentList "-File Check-IntuneEnrollment.ps1 -AutoRemediate" -Wait -PassThru).ExitCode
switch ($exitCode) {
    0 { Write-Host "Success" -ForegroundColor Green }
    2 { Write-Host "Not Azure AD joined" -ForegroundColor Yellow }
    3 { Write-Host "Not MDM enrolled" -ForegroundColor Yellow }
    default { Write-Host "Issues found" -ForegroundColor Red }
}
```

## Log Locations

The script checks and reports on:
- `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs`
- `C:\Windows\IntuneLogs`
- `C:\Windows\Logs\Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider`

## Output Example

```
========================================
  Intune Enrollment Troubleshooter v3.0
========================================

--- PowerShell Architecture Check ---
[+] Running in 64-bit PowerShell

--- Windows Version Check ---
[*] Windows: Microsoft Windows 11 Pro
[+] Edition supports MDM enrollment

--- Network Connectivity Check ---
[+] All Intune endpoints reachable

--- Required Services Check ---
[+] All required services running

--- Enrollment Status Check ---
[+] Azure AD Joined: True
[*] Tenant: Contoso
[*] Device ID: a1b2c3d4-e5f6...
[+] MDM URL: https://enrollment.manage.microsoft.com
[*] Cert Expiry: 2027-02-12

========================================
  TROUBLESHOOTING COMPLETE
========================================

No issues found!

Next Steps:
  ✓ Device appears properly configured
  1. Check Intune portal for device compliance
  2. Verify policies are applying correctly
```

## Troubleshooting Common Issues

### "Running in 32-bit PowerShell"
**Solution:** Run from 64-bit PowerShell (PowerShell x64)

### "Windows Home edition cannot enroll"
**Solution:** Upgrade to Windows Pro, Enterprise, or Education

### "Some Intune endpoints unreachable"
**Solution:** Check firewall, proxy, and network connectivity

### "Not Azure AD joined"
**Solution:**
1. Settings → Accounts → Access work or school
2. Click "Connect"
3. Sign in with work/school account
4. Run script again with `-AutoRemediate`

### "Azure AD joined but no MDM URL"
**Solution:**
- Run with `-AutoRemediate` to trigger enrollment
- Or manually: Settings → Accounts → Access work or school → Info → "Create and export provisioning package"

### "MDM Certificate has expired"
**Solution:** Device needs re-enrollment. Contact IT to retire and re-enroll device.

## Deployment

### Intune / Endpoint Manager
Deploy as a Remediation script or Proactive Remediation:
- **Detection script:** Check for enrollment state
- **Remediation script:** This script with `-AutoRemediate`

### SCCM / ConfigMgr
Run as a Configuration Item in a Baseline:
- **Settings:** Script-based setting
- **Compliance Rule:** Exit code 0 = Compliant

### MDT / OSD
Add to task sequence for new builds:
```powershell
powershell.exe -ExecutionPolicy Bypass -File Check-IntuneEnrollment.ps1 -AutoRemediate
```

## Requirements

- Windows 10/11 Pro, Enterprise, or Education
- PowerShell 5.1 or PowerShell 7+
- Administrator privileges (for service management and registry access)
- Network connectivity to Microsoft endpoints

## Limitations

- Cannot automatically perform Azure AD join (requires user interaction or provisioning package)
- Some MDM enrollment issues require manual steps in Settings
- Resetting MDM enrollment (`-ResetEnrollment`) requires manual re-enrollment afterward

## Version History

### 3.0 (2026-02-12)
- Comprehensive network endpoint testing
- Service health checks with auto-start capability
- Certificate expiration validation
- Detailed JSON export option
- Improved dsregcmd parsing
- Better exit codes for automation

### 2.0 (2026-02-04)
- Basic enrollment checks
- Azure AD sync capability
- MDM enrollment triggering

### 1.0
- Initial release

## Related Scripts

See other scripts in the Intune folder for:
- Device compliance checking
- Policy sync forcing
- Intune app deployment troubleshooting

## License

MIT License - Use at your own risk. Always test in non-production environments first.
