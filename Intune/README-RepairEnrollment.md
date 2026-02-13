# Intune Enrollment Repair Tool

PowerShell utility to diagnose and repair broken or partial Intune/Azure AD device registrations.

## Overview

This script identifies and fixes common enrollment issues including:

- **Partial Registrations** - Azure AD joined but MDM not enrolled
- **Orphaned States** - MDM enrolled but not Azure AD joined
- **Certificate Issues** - Expired or missing MDM certificates
- **Corrupted Registry** - Failed enrollment entries
- **Stuck Sync States** - Devices not syncing properly

## Features

- ✅ **Comprehensive Diagnosis** - Checks Azure AD, MDM, and certificate health
- ✅ **Automated Repairs** - Fixes registry, certificates, and triggers re-enrollment
- ✅ **Safe Operations** - WhatIf mode to preview changes
- ✅ **Detailed Logging** - Full audit trail of all actions
- ✅ **Reset Option** - Full registration reset if repairs fail
- ✅ **Certificate Management** - Detects and removes expired MDM certs

## Quick Start

### Diagnose and Repair Interactively
```powershell
.\Repair-IntuneEnrollment.ps1
```

### Auto-Repair (No Prompts)
```powershell
.\Repair-IntuneEnrollment.ps1 -AutoFix
```

### Check and Fix Certificates
```powershell
.\Repair-IntuneEnrollment.ps1 -CheckCertificates -TriggerSync
```

### Full Reset (Destructive)
```powershell
.\Repair-IntuneEnrollment.ps1 -ResetRegistration -Force
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `AutoFix` | switch | `$false` | Apply all safe fixes automatically |
| `ResetRegistration` | switch | `$false` | **WARNING**: Full reset of device registration |
| `ForceReenroll` | switch | `$false` | Forces unenrollment and re-enrollment |
| `CheckCertificates` | switch | `$false` | Verify and repair certificate issues |
| `TriggerSync` | switch | `$false` | Force MDM sync after repairs |
| `LogPath` | string | `%TEMP%\IntuneRepair_*.log` | Log file location |
| `WhatIf` | switch | `$false` | Preview changes without applying |

## Common Issues Fixed

### 1. Partial Registration (Most Common)
**Symptom:** Device shows as Azure AD joined in Settings, but Intune portal shows "Not Compliant" or device missing.

**Root Cause:** Azure AD join succeeded but MDM enrollment failed or was interrupted.

**Fix:** Script detects this state and triggers MDM auto-enrollment.

### 2. Expired MDM Certificates
**Symptom:** Device was enrolled but stopped syncing. Errors about certificate in logs.

**Fix:** Script detects expired certificates and removes them to allow renewal.

### 3. Corrupted Enrollment Registry
**Symptom:** Multiple failed enrollment attempts, stuck in "Enrollment failed" state.

**Fix:** Script cleans up failed enrollment entries from registry.

### 4. Orphaned MDM Enrollment
**Symptom:** Device shows MDM enrolled but Azure AD join is broken or missing.

**Fix:** Script detects orphaned state and recommends reset or manual re-enrollment.

## Enrollment States

The script detects and reports these states:

| State | Description | Action Taken |
|-------|-------------|--------------|
| **Healthy** | Azure AD joined + MDM enrolled + Valid cert | None - device is good |
| **Partial** | Azure AD joined, MDM not enrolled | Triggers MDM enrollment |
| **Orphaned** | MDM enrolled, Azure AD not joined | Manual reset required |
| **Degraded** | Enrolled but certificate issues | Repairs certificates |
| **NotRegistered** | Not in Azure AD or Intune | Manual enrollment required |

## Examples

### Basic Diagnosis
```powershell
.\Repair-IntuneEnrollment.ps1
```
Shows current enrollment status and offers to fix issues.

### Silent Auto-Repair
```powershell
.\Repair-IntuneEnrollment.ps1 -AutoFix -LogPath "C:\Logs\IntuneRepair.log"
```
Automatically applies safe fixes without prompting.

### Preview Changes
```powershell
.\Repair-IntuneEnrollment.ps1 -WhatIf
```
Shows what would be fixed without making changes.

### Fix Certificate Issues Only
```powershell
.\Repair-IntuneEnrollment.ps1 -CheckCertificates -AutoFix
```

### Complete Reset (Last Resort)
```powershell
.\Repair-IntuneEnrollment.ps1 -ResetRegistration
```
**WARNING:** This will completely unenroll the device. You'll need to manually re-enroll in Azure AD/Intune.

## What Gets Repaired

### Registry Fixes
- Enables MDM auto-enrollment policy
- Removes failed enrollment entries (EnrollmentState = 6)
- Cleans up corrupted OMADM entries

### Certificate Fixes
- Detects expired MDM certificates
- Removes expired certs from LocalMachine\My
- Removes expired certs from CurrentUser\My
- Allows fresh certificate enrollment

### Enrollment Triggers
- Runs dsregcmd /sync
- Triggers Device Enrollment scheduled task
- Opens MDM enrollment dialog (ms-device-enrollment:)
- Opens Work Access settings

### MDM Sync
- Triggers MDM policy sync
- Runs scheduled MDM tasks
- Opens Settings sync page

## Output Example

```
========================================
  Intune Enrollment Repair Tool v1.0
========================================

[*] Started: 2026-02-13 08:30:15
[*] Computer: DESKTOP-ABC123
[*] Log: C:\Users\admin\AppData\Local\Temp\IntuneRepair_20260213_083015.log

[*] Analyzing current enrollment state...

========================================
  ENROLLMENT STATUS
========================================

[+] Azure AD Joined: True
[!] MDM Enrolled: False
[!] Certificate Valid: False
[!] Overall Status: Partial
    Tenant: Contoso
    User: user@contoso.com
    Device ID: a1b2c3d4-e5f6-7890-abcd-ef1234567890

[!] Issues Found:
[!]   - Azure AD joined but MDM not enrolled (partial registration)
[!]   - MDM certificate has expired or is not yet valid

========================================
  APPLYING REPAIRS
========================================

[*] Checking MDM registry entries...
[+] Enabled MDM auto-enrollment in registry
[*] Checking MDM certificates...
[+] Removed expired MDM certificate
[*] Syncing Azure AD registration...
[+] Azure AD sync completed successfully
[*] Triggering MDM enrollment...
[+] Triggered device enrollment task

[*] Re-checking enrollment state...

[+] Azure AD Joined: True
[+] MDM Enrolled: True
[+] Certificate Valid: True
[+] Overall Status: Healthy

========================================
  REPAIR SUMMARY
========================================

[*] Issues Found: 2
[+] Fixes Applied: 4
[+] Fixes Failed: 0

[+] Applied Fixes:
[+]   + Enabled MDM auto-enrollment
[+]   + Removed expired MDM certificate
[+]   + Azure AD sync
[+]   + Triggered device enrollment task

[*] Log saved: C:\Users\admin\AppData\Local\Temp\IntuneRepair_20260213_083015.log
[+] Device enrollment is now healthy!
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Repairs successful, device healthy |
| 1 | Partial success (some repairs failed) |
| 2 | Requires manual intervention / not admin |
| 3 | No repairs needed (device already healthy) |
| 4 | Critical failure / needs reset |

## Use Cases

### Device Shows in Azure AD but Not Intune
```powershell
.\Repair-IntuneEnrollment.ps1 -AutoFix
```

### Device Stopped Syncing
```powershell
.\Repair-IntuneEnrollment.ps1 -CheckCertificates -AutoFix -TriggerSync
```

### After Failed Enrollment Attempt
```powershell
.\Repair-IntuneEnrollment.ps1 -AutoFix
```

### Preparing for Fresh Enrollment
```powershell
# If repairs fail, do full reset
.\Repair-IntuneEnrollment.ps1 -ResetRegistration -Force
# Then manually enroll via Settings
```

## Troubleshooting

### "This script requires Administrator privileges"
Run PowerShell as Administrator:
1. Right-click PowerShell
2. Select "Run as administrator"
3. Run the script again

### "Azure AD sync completed but status unchanged"
- Network connectivity issue - check internet connection
- Azure AD service issue - try again later
- Device may need reboot after repairs

### "MDM enrollment task not found"
- Device may not have MDM enrollment capability
- Group Policy may be blocking MDM
- Check Intune licensing

### Repairs complete but device still not enrolled
1. Reboot the computer
2. Check Settings > Accounts > Access work or school
3. Look for "Connect" button or enrollment prompt
4. If still failing, try `-ResetRegistration` as last resort

### Certificate keeps expiring
- Check system time is correct
- Verify NTP sync is working
- May indicate deeper PKI issues

## Requirements

- Windows 10/11 Pro, Enterprise, or Education
- PowerShell 5.1 or PowerShell 7+
- Administrator rights
- Internet connectivity to Azure AD/Intune endpoints

## Related Scripts

- `Check-IntuneEnrollment.ps1` - Comprehensive enrollment health check
- `Get-IntuneInactiveIOSDevices.ps1` - iOS device management
- `Invoke-DomainJoinPrompt.ps1` - Active Directory domain join

## Safety Notes

- **Always run WhatIf first** if unsure: `Repair-IntuneEnrollment.ps1 -WhatIf`
- **Log files** are created for every run - review if issues occur
- **ResetRegistration** is destructive - only use as last resort
- **Reboot** may be required after repairs for full effect

## Version History

### 1.0 (2026-02-13)
- Initial release
- Comprehensive enrollment state detection
- Registry, certificate, and sync repairs
- Full reset capability
- Detailed logging

## License

MIT License - Use at your own risk. Always test on non-production systems first.

## See Also

- Microsoft Docs: [Troubleshoot Windows device enrollment in Microsoft Intune](https://docs.microsoft.com/mem/intune/troubleshoot-device-enrollment)
- dsregcmd documentation: [Azure AD joined device verification](https://docs.microsoft.com/azure/active-directory/devices/troubleshoot-device-dsregcmd)

---

## Remote Execution

The script supports running repairs on remote computers via PowerShell Remoting.

### Requirements for Remote Execution

**Target Computers Must Have:**
- Windows PowerShell/WinRM enabled
- Windows Firewall allowing WinRM (port 5985/5986)
- Administrator rights for the connecting account

### Enable WinRM on Targets
```powershell
Enable-PSRemoting -Force
# Or:
winrm quickconfig -q
```

### Remote Examples

#### Single Remote Computer
```powershell
.\Repair-IntuneEnrollment.ps1 -ComputerName "PC01" -UseCurrent
```

#### Multiple Remote Computers
```powershell
.\Repair-IntuneEnrollment.ps1 -ComputerName "PC01", "PC02", "PC03" -Credential (Get-Credential)
```

#### Pipeline from Active Directory
```powershell
Get-ADComputer -Filter {Enabled -eq $true} | 
    Select-Object -ExpandProperty Name | 
    .\Repair-IntuneEnrollment.ps1 -AutoFix -UseCurrent
```

#### Auto-Fix All Domain Computers
```powershell
Get-ADComputer -Filter {Enabled -eq $true} | 
    Select-Object -ExpandProperty Name | 
    .\Repair-IntuneEnrollment.ps1 -AutoFix -TriggerSync
```

#### Check Certificates on Remote Machines
```powershell
.\Repair-IntuneEnrollment.ps1 -ComputerName (Get-Content computers.txt) -CheckCertificates -TriggerSync -UseCurrent
```

### Remote Output

When running remotely, the script connects to each computer and:
1. Tests connectivity (ping then WinRM)
2. Executes repairs via embedded script block
3. Returns status and fix summary
4. Logs details on the remote machine

**Example Remote Output:**
```
[*] Connecting to PC01...
[!] Ping failed for PC01, attempting WinRM anyway...
[*] Executing repair on PC01...
[+] PC01: Status = Partial, Fixes = 3
[*] Connecting to PC02...
[+] PC02: Status = Healthy, Fixes = 0
```

### Remote Log Locations

On each target computer, logs are saved to:
- `C:\Users\<username>\AppData\Local\Temp\IntuneRepair_*.log`

The central log on the executing machine contains:
- Connection status for each computer
- Summary of fixes applied
- Errors encountered

### Security Notes

- Credentials are never logged
- Use `-UseCurrent` for pass-through authentication when possible
- For bulk operations, consider using a service account
- Ensure target computers are in TrustedHosts if workgroup: `Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force`
