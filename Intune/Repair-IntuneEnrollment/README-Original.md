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
- ✅ **Remote Execution** - Repair multiple computers from central location
- ✅ **Safe Operations** - WhatIf mode to preview changes
- ✅ **Detailed Logging** - Full audit trail on each target and central summary
- ✅ **Reset Option** - Full registration reset if repairs fail
- ✅ **Certificate Management** - Detects and removes expired MDM certs

## Quick Start

### Diagnose and Repair Interactively (Local)
```powershell
.\Repair-IntuneEnrollment.ps1
```

### Auto-Repair Local Machine
```powershell
.\Repair-IntuneEnrollment.ps1 -AutoFix
```

### Repair Remote Computer
```powershell
.\Repair-IntuneEnrollment.ps1 -ComputerName "PC01" -UseCurrent
```

### Bulk Repair Multiple Computers
```powershell
.\Repair-IntuneEnrollment.ps1 -ComputerName PC01,PC02,PC03 -Credential (Get-Credential)
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ComputerName` | string[] | - | Remote computer(s) to repair. Omit for local. |
| `Credential` | PSCredential | - | Credentials for remote authentication. |
| `UseCurrent` | switch | `$false` | Use current credentials for remote (no prompt). |
| `AutoFix` | switch | `$false` | Apply all safe fixes automatically. |
| `ResetRegistration` | switch | `$false` | **WARNING**: Full reset of device registration. |
| `ForceReenroll` | switch | `$false` | Forces unenrollment and re-enrollment. |
| `CheckCertificates` | switch | `$false` | Verify and repair certificate issues. |
| `TriggerSync` | switch | `$false` | Force MDM sync after repairs. |
| `LogPath` | string | `%TEMP%\IntuneRepair_*.log` | Log file location. |
| `WhatIf` | switch | `$false` | Preview changes without applying. |

---

## Local Execution

### Basic Diagnosis (Local)
```powershell
.\Repair-IntuneEnrollment.ps1
```
Shows current enrollment status and offers to fix issues.

### Silent Auto-Repair (Local)
```powershell
.\Repair-IntuneEnrollment.ps1 -AutoFix -LogPath "C:\Logs\IntuneRepair.log"
```
Automatically applies safe fixes without prompting.

### Preview Changes (Local)
```powershell
.\Repair-IntuneEnrollment.ps1 -WhatIf
```
Shows what would be fixed without making changes.

---

## Remote Execution

The script supports running repairs on remote computers via **PowerShell Remoting (WinRM)**.

### Prerequisites for Remote Execution

**On the Target Computers (Run as Administrator):**
```powershell
# Enable PowerShell Remoting
Enable-PSRemoting -Force

# Or use quick config
winrm quickconfig -q

# Verify WinRM is listening
Test-WSMan -ComputerName localhost
```

**Firewall Requirements:**
- Windows Firewall must allow WinRM (port 5985 for HTTP, 5986 for HTTPS)
- Or run: `netsh advfirewall firewall set rule group="Windows Remote Management" new enable=yes`

**Authentication:**
- Target computer must accept credentials from source
- For workgroup computers: Add to TrustedHosts: `Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force`
- For domain computers: Standard Kerberos/NTLM authentication works

### Remote Execution Examples

#### Single Remote Computer
Repair one computer using current credentials:
```powershell
.\Repair-IntuneEnrollment.ps1 -ComputerName "WKSTN-12345" -UseCurrent
```

#### Single Remote with Explicit Credentials
```powershell
$cred = Get-Credential -Message "Enter admin credentials for remote PC"
.\Repair-IntuneEnrollment.ps1 -ComputerName "WKSTN-12345" -Credential $cred
```

#### Multiple Remote Computers
```powershell
.\Repair-IntuneEnrollment.ps1 -ComputerName "PC01", "PC02", "PC03" -UseCurrent
```

#### Pipeline from Active Directory
Get all enabled computers from AD and repair them:
```powershell
Get-ADComputer -Filter {Enabled -eq $true} | 
    Select-Object -ExpandProperty Name | 
    .\Repair-IntuneEnrollment.ps1 -AutoFix -UseCurrent
```

#### Pipeline with Specific OU
Repair computers in a specific Organizational Unit:
```powershell
Get-ADComputer -SearchBase "OU=Workstations,OU=Sales,DC=contoso,DC=com" -Filter * | 
    Select-Object -ExpandProperty Name | 
    .\Repair-IntuneEnrollment.ps1 -AutoFix -TriggerSync
```

#### From Text File
```powershell
$computers = Get-Content "C:\Scripts\ComputersToRepair.txt"
.\Repair-IntuneEnrollment.ps1 -ComputerName $computers -Credential (Get-Credential)
```

#### Bulk Auto-Repair with Certificate Check
```powershell
Get-ADComputer -Filter {Enabled -eq $true} | 
    Select-Object -ExpandProperty Name | 
    .\Repair-IntuneEnrollment.ps1 -AutoFix -CheckCertificates -TriggerSync
```

#### Repair and Force Sync
```powershell
.\Repair-IntuneEnrollment.ps1 -ComputerName PC01,PC02,PC03 -AutoFix -TriggerSync -UseCurrent
```

### How Remote Execution Works

1. **Connection Test**
   - Attempts ping (optional, continues if fails)
   - Tests WinRM availability with `Test-WSMan`

2. **Script Delivery**
   - Embeds repair logic in a script block
   - Transmits to target via `Invoke-Command`
   - Executes locally on target with admin rights

3. **Status Collection**
   - Returns enrollment status from target
   - Lists fixes applied
   - Reports any errors

4. **Logging**
   - Creates log file on target: `%TEMP%\IntuneRepair_*.log`
   - Creates central log on source: `%TEMP%\IntuneRepair_*.log`

### Remote Output Example

```
========================================
  Intune Enrollment Repair Tool v1.1
========================================

[*] Started: 2026-02-13 10:30:15
[*] Log: C:\Users\admin\AppData\Local\Temp\IntuneRepair_20260213_103015.log
[*] Processing 3 computer(s)

[*] Connecting to PC01...
[!] Ping failed for PC01, attempting WinRM anyway...
[*] Executing repair on PC01...
[+] PC01: Status = Partial → Healthy, Fixes = 3

[*] Connecting to PC02...
[*] Executing repair on PC02...
[+] PC02: Status = Healthy, Fixes = 0

[*] Connecting to PC03...
[!] Ping failed for PC03, attempting WinRM anyway...
[*] Executing repair on PC03...
[+] PC03: Status = Partial → Healthy, Fixes = 2

========================================
  SUMMARY
========================================

[*] Total computers: 3
[+] Successful repairs: 2
[+] Already healthy: 1
[+] Failed: 0

[*] Duration: 00:45
[*] Log saved: C:\Users\admin\AppData\Local\Temp\IntuneRepair_20260213_103015.log
```

### Troubleshooting Remote Execution

#### "WinRM cannot complete the operation"
**Cause:** WinRM not enabled on target  
**Fix:** Run `Enable-PSRemoting -Force` on target

#### "Access is denied"
**Cause:** Credentials don't have admin rights on target  
**Fix:** Use domain admin or local admin credentials for target

#### "The RPC server is unavailable"
**Cause:** Network connectivity or firewall blocking  
**Fix:** 
- Check network connectivity
- Enable Windows Firewall rule for WinRM
- Verify target computer is online

#### "The WinRM client cannot process the request"
**Cause:** TrustedHosts not configured for workgroup  
**Fix:** On source computer: `Set-Item WSMan:\localhost\Client\TrustedHosts -Value "TargetPC" -Force`

### Security Best Practices for Remote

1. **Use Current Credentials When Possible**
   ```powershell
   # Better (uses Kerberos)
   .\Repair-IntuneEnrollment.ps1 -ComputerName PC01 -UseCurrent
   
   # Instead of (requires password entry)
   .\Repair-IntuneEnrollment.ps1 -ComputerName PC01 -Credential (Get-Credential)
   ```

2. **Limit TrustedHosts**
   ```powershell
   # Instead of "*" (all), specify specific computers
   Set-Item WSMan:\localhost\Client\TrustedHosts -Value "PC01,PC02,PC03" -Force
   ```

3. **Use HTTPS for WinRM** (if configured)
   ```powershell
   # Requires WinRM HTTPS setup on targets
   $so = New-PSSessionOption -SkipCACheck -SkipCNCheck
   Invoke-Command -ComputerName PC01 -ScriptBlock { ... } -SessionOption $so -UseSSL
   ```

---

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

---

## Enrollment States

The script detects and reports these states:

| State | Description | Action Taken |
|-------|-------------|--------------|
| **Healthy** | Azure AD joined + MDM enrolled + Valid cert | None - device is good |
| **Partial** | Azure AD joined, MDM not enrolled | Triggers MDM enrollment |
| **Orphaned** | MDM enrolled, Azure AD not joined | Manual reset required |
| **Degraded** | Enrolled but certificate issues | Repairs certificates |
| **NotRegistered** | Not in Azure AD or Intune | Manual enrollment required |

---

## Output Example

```
========================================
  Intune Enrollment Repair Tool v1.1
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

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Repairs successful, device healthy |
| 1 | Partial success (some repairs failed) |
| 2 | Requires manual intervention / not admin |
| 3 | No repairs needed (device already healthy) |
| 4 | Critical failure / needs reset |

---

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

### Bulk Department Repair
```powershell
Get-ADComputer -SearchBase "OU=Sales,DC=contoso,DC=com" -Filter * | 
    Select-Object -ExpandProperty Name | 
    .\Repair-IntuneEnrollment.ps1 -AutoFix -UseCurrent
```

### Preparing for Fresh Enrollment
```powershell
# If repairs fail, do full reset
.\Repair-IntuneEnrollment.ps1 -ResetRegistration -Force
# Then manually enroll via Settings
```

---

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

---

## Requirements

- Windows 10/11 Pro, Enterprise, or Education
- PowerShell 5.1 or PowerShell 7+
- Administrator rights
- Internet connectivity to Azure AD/Intune endpoints
- For remote: WinRM enabled on target computers

---

## Related Scripts

- `Check-IntuneEnrollment.ps1` - Comprehensive enrollment health check
- `Get-IntuneInactiveIOSDevices.ps1` - iOS device management
- `Invoke-DomainJoinPrompt.ps1` - Active Directory domain join

---

## Safety Notes

- **Always run WhatIf first** if unsure: `Repair-IntuneEnrollment.ps1 -WhatIf`
- **Log files** are created for every run - review if issues occur
- **ResetRegistration** is destructive - only use as last resort
- **Reboot** may be required after repairs for full effect

---

## Version History

### 1.1 (2026-02-13)
- Added remote execution support
- ComputerName parameter for targeting remote machines
- Credential and UseCurrent parameters for authentication
- Pipeline input support from AD or files
- Central and remote logging

### 1.0 (2026-02-13)
- Initial release
- Comprehensive enrollment state detection
- Registry, certificate, and sync repairs
- Full reset capability
- Detailed logging

---

## License

MIT License - Use at your own risk. Always test on non-production systems first.

---

## See Also

- Microsoft Docs: [Troubleshoot Windows device enrollment in Microsoft Intune](https://docs.microsoft.com/mem/intune/troubleshoot-device-enrollment)
- dsregcmd documentation: [Azure AD joined device verification](https://docs.microsoft.com/azure/active-directory/devices/troubleshoot-device-dsregcmd)
