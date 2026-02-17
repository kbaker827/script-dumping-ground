# Repair-IntuneEnrollment.ps1

A comprehensive PowerShell tool to diagnose and repair Intune/Azure AD enrollment issues on Windows devices. Works locally or remotely via PowerShell Remoting.

## Overview

This script diagnoses and repairs common Intune enrollment problems including:

- **Partial registrations** - Azure AD joined but MDM not enrolled
- **PRT (Primary Refresh Token) issues** - Authentication token problems
- **Certificate problems** - Expired or invalid MDM certificates
- **Enrollment finalization failures** - Stuck in pending enrollment state
- **User token issues** - 0x80070520 logon session errors
- **TLS/SSL errors** - Security package failures (-2146893051)
- **Network connectivity** - Blocked Intune/Azure endpoints
- **Orphaned enrollments** - Corrupted registry entries

## Features

- ✅ **Self-Elevating** - Automatically requests admin rights if not running elevated
- ✅ **Local & Remote** - Repair local machine or multiple remote computers
- ✅ **Safe Registry Cleanup** - Removes only orphaned/corrupted entries
- ✅ **Network Diagnostics** - Tests all required Azure/Intune endpoints
- ✅ **PRT Repair** - Fixes Primary Refresh Token authentication issues
- ✅ **Certificate Management** - Cleans expired MDM certificates
- ✅ **TLS/SSL Repair** - Configures modern TLS protocols
- ✅ **Comprehensive Logging** - Detailed logs for troubleshooting
- ✅ **Pipeline Support** - Accepts computer names from pipeline

## Requirements

- Windows 10/11 Pro, Enterprise, or Education
- PowerShell 5.1 or later
- Administrator privileges (auto-elevates)
- Internet connectivity to Azure AD/Intune endpoints
- For remote: WinRM enabled on target machines

## Quick Start

### Download and Run Locally

```powershell
# Download the script
# Save as: Repair-IntuneEnrollment.ps1

# Run with diagnostics only (no changes)
.\Repair-IntuneEnrollment.ps1 -WhatIf

# Run with auto-fix enabled
.\Repair-IntuneEnrollment.ps1 -AutoFix

# Full repair (all operations)
.\Repair-IntuneEnrollment.ps1 -FullRepair
```

## Parameters

| Parameter | Description |
|-----------|-------------|
| `ComputerName` | Remote computer(s) to repair. Supports pipeline input. |
| `Credential` | PSCredential object for remote authentication. |
| `UseCurrent` | Use current credentials for remote connections (no prompt). |
| `AutoFix` | Automatically apply safe fixes without prompting. |
| `FullRepair` | Run all repair operations (equivalent to `-AutoFix -CheckCertificates -FixPRT -TriggerSync`). |
| `ResetRegistration` | **WARNING**: Full device registration reset. Requires re-enrollment. |
| `ForceReenroll` | Forces complete unenrollment and re-enrollment (destructive). |
| `CheckCertificates` | Verify and repair MDM certificate issues. |
| `FixPRT` | Attempt to repair Primary Refresh Token issues. |
| `TriggerSync` | Force MDM sync after repairs. |
| `LogPath` | Path to save detailed log file (default: `%TEMP%\IntuneRepair_[timestamp].log`). |
| `WhatIf` | Show what would be done without making changes. |
| `Force` | Suppress confirmation prompts for destructive operations. |

## Usage Examples

### Local Machine

```powershell
# Diagnose only (no changes)
.\Repair-IntuneEnrollment.ps1

# Auto-fix common issues
.\Repair-IntuneEnrollment.ps1 -AutoFix

# Fix PRT issues specifically
.\Repair-IntuneEnrollment.ps1 -FixPRT

# Full repair with certificate cleanup and sync
.\Repair-IntuneEnrollment.ps1 -FullRepair

# Reset device registration (destructive)
.\Repair-IntuneEnrollment.ps1 -ResetRegistration -Force
```

### Remote Machines

```powershell
# Single remote computer
.\Repair-IntuneEnrollment.ps1 -ComputerName PC01 -UseCurrent

# Multiple computers with credentials
$cred = Get-Credential
.\Repair-IntuneEnrollment.ps1 -ComputerName PC01,PC02,PC03 -Credential $cred

# From Active Directory (requires RSAT)
Get-ADComputer -Filter {Enabled -eq $true} | 
    Select-Object -ExpandProperty Name | 
    .\Repair-IntuneEnrollment.ps1 -AutoFix
```

### Pipeline Input

```powershell
# From text file
Get-Content computers.txt | .\Repair-IntuneEnrollment.ps1 -AutoFix

# From CSV
Import-Csv computers.csv | Select-Object -ExpandProperty Name | .\Repair-IntuneEnrollment.ps1

# Filtered AD query
Get-ADComputer -Filter {OperatingSystem -like "*Windows 10*"} | 
    .\Repair-IntuneEnrollment.ps1 -FullRepair
```

## Repair Operations

### Automatic Fixes Applied

1. **Orphaned Enrollment Cleanup**
   - Removes corrupted registry entries under `HKLM:\SOFTWARE\Microsoft\Enrollments`
   - Cleans up enrollment cache
   - Safe deletion only (checks for valid UPN)

2. **MDM Auto-Enrollment**
   - Enables `AutoEnrollMDM` registry setting
   - Triggers scheduled enrollment tasks

3. **PRT (Primary Refresh Token) Repair**
   - Runs `dsregcmd /forcerecovery`
   - Restarts Azure AD broker services
   - Clears WAM (Web Account Manager) cache

4. **Certificate Cleanup**
   - Removes expired MDM certificates from Machine and User stores
   - Identifies certificates by Subject/Issuer

5. **TLS/SSL Configuration**
   - Enables TLS 1.2 for system and .NET applications
   - Resets WinHTTP proxy settings

6. **Network Stack Reset**
   - Flushes DNS cache
   - Resets WinSock catalog (if connectivity issues detected)

7. **Azure AD Sync**
   - Runs `dsregcmd /sync`
   - Forces token refresh

8. **MDM Sync**
   - Triggers Intune scheduled tasks
   - Runs CheckPoint sync

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Repairs successful / all devices healthy |
| 1 | Partial success (some repairs failed) |
| 2 | Requires manual intervention |
| 3 | No repairs needed (device healthy) |
| 4 | Critical failure / needs reset |
| 5 | Remote connection failed |
| 6 | Pre-flight checks failed |

## Network Endpoints Tested

The script tests connectivity to these Azure/Intune endpoints:

| Endpoint | Purpose | Required |
|----------|---------|----------|
| login.microsoftonline.com | Azure AD Authentication | ✅ |
| enterpriseregistration.windows.net | Device Registration | ✅ |
| enrollment.manage.microsoft.com | Intune Enrollment | ✅ |
| r.manage.microsoft.com | Intune Gateway | ✅ |
| manage.microsoft.com | Intune Management | ✅ |
| graph.microsoft.com | Microsoft Graph API | ✅ |
| ocsp.msocsp.com | Certificate Revocation | ✅ |
| naprodimedatapri.azureedge.net | Win32 App Download | ❌ |

## Common Scenarios

### Scenario 1: "Device is Azure AD joined but not showing in Intune"

```powershell
.\Repair-IntuneEnrollment.ps1 -AutoFix -TriggerSync
```

**Likely fixes applied:**
- Enables MDM auto-enrollment
- Triggers enrollment finalization
- Cleans orphaned entries

### Scenario 2: "SSO not working, users prompted for password"

```powershell
.\Repair-IntuneEnrollment.ps1 -FixPRT -AutoFix
```

**Likely fixes applied:**
- Repairs Primary Refresh Token
- Clears WAM cache
- Restarts token broker services

### Scenario 3: "MDM enrollment stuck at 'Pending'"

```powershell
.\Repair-IntuneEnrollment.ps1 -FullRepair
```

**Likely fixes applied:**
- All of the above plus:
- Certificate cleanup
- Network stack reset
- Multiple sync triggers

### Scenario 4: "Error 0x80070520 - Logon session errors"

```powershell
.\Repair-IntuneEnrollment.ps1 -AutoFix
```

**Likely fixes applied:**
- Clears WAM cache
- Restarts TokenBroker service
- Repairs user tokens

### Scenario 5: "Multiple devices need repair"

```powershell
# Get all domain computers and repair
Get-ADComputer -Filter {Enabled -eq $true} | 
    Select-Object -ExpandProperty Name | 
    .\Repair-IntuneEnrollment.ps1 -AutoFix
```

## Logging

Logs are saved to: `%TEMP%\IntuneRepair_[timestamp].log`

Example log output:
```
[2026-02-17 10:30:15] [Info] Starting repair on DESKTOP-ABC123
[2026-02-17 10:30:16] [Info] Status: Partial (Azure AD joined, MDM not enrolled)
[2026-02-17 10:30:17] [Success] Enabled MDM auto-enrollment
[2026-02-17 10:30:18] [Success] Cleaned orphaned enrollments
[2026-02-17 10:30:20] [Success] MDM sync triggered
```

## Troubleshooting

### Issue: "Not running as administrator"
**Solution:** The script auto-elevates. If UAC is disabled, run from elevated PowerShell manually.

### Issue: "Unsupported Windows edition"
**Cause:** Windows Home edition doesn't support Intune enrollment
**Solution:** Upgrade to Pro/Enterprise/Education

### Issue: "Remote connection failed"
**Check:**
- WinRM is enabled on target: `Enable-PSRemoting -Force`
- Firewall allows WinRM (port 5985/5986)
- CredSSP or Kerberos is configured for multi-hop

### Issue: "Repairs don't persist after reboot"
**Cause:** Underlying group policy or MDM policy conflict
**Solution:** Check Intune enrollment restrictions and group policy MDM settings

### Issue: "Certificate cleanup fails"
**Cause:** Certificate store permissions
**Solution:** Script runs as SYSTEM/Admin - should have access. Check for antivirus interference.

## Security Considerations

1. **Execution Policy**: Script temporarily sets Bypass for its process only
2. **Credentials**: Use `-UseCurrent` for SSO or secure credential objects
3. **Remote Access**: Requires WinRM - ensure proper firewall rules
4. **Registry Changes**: Only removes orphaned entries (no valid UPN)
5. **Certificate Cleanup**: Only removes expired MDM/Intune certificates

## Integration Examples

### As Intune Remediation Script

1. Create new **Proactive Remediation** in Intune
2. **Detection script**: Check for enrollment issues
3. **Remediation script**: Upload this script
4. Assign to device group

### As Startup Script (GPO)

```powershell
# Deploy via Group Policy to run at startup
powershell.exe -ExecutionPolicy Bypass -File "\\server\share\Repair-IntuneEnrollment.ps1" -AutoFix
```

### As Scheduled Task

```powershell
# Create scheduled task for periodic check
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File C:\Scripts\Repair-IntuneEnrollment.ps1 -AutoFix"
$trigger = New-ScheduledTaskTrigger -Daily -At 2am
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "Intune Enrollment Repair" -User "SYSTEM"
```

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.1 | 2026-02-17 | Initial GitHub release with full documentation |

## References

- [Troubleshoot Windows device enrollment in Microsoft Intune](https://docs.microsoft.com/en-us/mem/intune/troubleshoot-device-enrollment)
- [Azure AD device management troubleshooting](https://docs.microsoft.com/en-us/azure/active-directory/devices/troubleshoot-device-dsregcmd)
- [Intune network endpoints](https://docs.microsoft.com/en-us/mem/intune/fundamentals/intune-endpoints)

## Author

Kyle Baker

## License

MIT License - Free for personal and commercial use
