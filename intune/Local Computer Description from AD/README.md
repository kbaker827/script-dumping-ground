# Local Computer Description from AD - Intune Script

PowerShell script to sync the computer description from Active Directory to the local Windows machine.

## Overview

This script queries Active Directory for the computer object's `description` attribute and sets it as the local computer description. This ensures consistency between AD documentation and the local machine, making it easier to identify computers when browsing the network or viewing system information.

## How It Works

1. **Check Domain Join Status** — Verifies the computer is domain-joined
2. **Query Active Directory** — Looks up the computer object and reads the description attribute
3. **Set Local Description** — Updates the local computer description via WMI/CIM
4. **Register Completion** — Creates a registry marker for Intune detection

## Contents

| File | Purpose |
|------|---------|
| `Set-ComputerDescriptionFromAD.ps1` | Main script that syncs AD description to local machine |
| `Detect-ComputerDescriptionFromAD.ps1` | Detection script for Intune |

## Features

- ✅ **Dual Query Methods** — Uses ActiveDirectory module if available, falls back to LDAP
- ✅ **Domain Join Check** — Validates computer is domain-joined before attempting AD query
- ✅ **Fallback Support** — Can set a default description if AD query fails
- ✅ **Idempotent** — Won't update if description already matches (unless `-Force` is used)
- ✅ **Detailed Logging** — Logs all operations for troubleshooting

## Requirements

- Windows 10/11
- Domain-joined computer
- Network connectivity to a Domain Controller
- Active Directory module (optional - LDAP fallback available)

## Quick Start

### Basic Usage

```powershell
.\Set-ComputerDescriptionFromAD.ps1
```

### With Fallback Description

```powershell
.\Set-ComputerDescriptionFromAD.ps1 -FallbackDescription "Standard Workstation"
```

### Specific Domain Controller

```powershell
.\Set-ComputerDescriptionFromAD.ps1 -DomainController "dc01.company.com"
```

### Force Update

```powershell
.\Set-ComputerDescriptionFromAD.ps1 -Force
```

## Intune Deployment

### As Win32 App

1. **Prepare your files:**
   ```
   ComputerDescriptionAD/
   ├── Set-ComputerDescriptionFromAD.ps1
   └── Detect-ComputerDescriptionFromAD.ps1
   ```

2. **Create .intunewin package:**
   ```powershell
   IntuneWinAppUtil.exe -c "C:\ComputerDescriptionAD" -s "Set-ComputerDescriptionFromAD.ps1" -o "C:\Output"
   ```

3. **Configure in Intune:**
   - **Name**: Sync Computer Description from AD
   - **Description**: Sets local computer description from Active Directory

4. **Program Settings:**

   **Install command:**
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File "Set-ComputerDescriptionFromAD.ps1" -FallbackDescription "Company Workstation"
   ```

   **Uninstall command:** (optional - can leave blank or use remediation)
   ```powershell
   # No uninstall needed - description change persists
   ```

5. **Detection Rules:**
   - Use custom detection script: `Detect-ComputerDescriptionFromAD.ps1`

### As Proactive Remediation

**Detection Script:**
```powershell
# Check if description matches AD
$computer = Get-ADComputer -Identity $env:COMPUTERNAME -Properties Description
$localDesc = (Get-WmiObject -Class Win32_OperatingSystem).Description

if ($localDesc -eq $computer.Description) {
    exit 0  # Compliant
} else {
    exit 1  # Non-compliant
}
```

**Remediation Script:**
```powershell
.\Set-ComputerDescriptionFromAD.ps1
```

### As Scheduled Task

Deploy via Intune PowerShell script to run periodically:
```powershell
# Run daily to keep descriptions in sync
.\Set-ComputerDescriptionFromAD.ps1 -FallbackDescription "Workstation"
```

## Script Parameters

### Set-ComputerDescriptionFromAD.ps1

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `DomainController` | No | Auto-detect | Specific DC to query |
| `Credential` | No | Computer account | Alternate credentials for AD query |
| `FallbackDescription` | No | `""` | Description to use if AD query fails |
| `LogPath` | No | Intune logs | Path for log files |
| `Force` | No | `$false` | Force update even if descriptions match |

## How to Set AD Computer Description

### Via Active Directory Users and Computers (ADUC)

1. Open **Active Directory Users and Computers**
2. Navigate to the computer object
3. Right-click → **Properties**
4. Enter description in the **Description** field
5. Click **OK**

### Via PowerShell

```powershell
# Set description for a single computer
Set-ADComputer -Identity "COMPUTER01" -Description "John's Laptop - Marketing Dept"

# Set description for multiple computers
Get-ADComputer -Filter "Name -like 'LAPTOP-*'" | 
    Set-ADComputer -Description "Sales Team Laptop"

# Bulk import from CSV
Import-Csv "computers.csv" | ForEach-Object {
    Set-ADComputer -Identity $_.ComputerName -Description $_.Description
}
```

### Via Command Line (dsmod)

```cmd
dsmod computer "CN=COMPUTER01,OU=Workstations,DC=company,DC=com" -desc "Marketing Laptop"
```

## Viewing the Description

### Locally

```powershell
# View current local description
Get-WmiObject -Class Win32_OperatingSystem | Select-Object Description

# Or
[System.Environment]::MachineName
# Check System Properties → Computer Name tab
```

### In Windows Explorer (Network)

When browsing the network, the description appears in the "Description" column alongside computer names.

### In Active Directory

```powershell
# View AD description
Get-ADComputer -Identity "COMPUTER01" -Properties Description | Select-Object Name, Description
```

## Logging

Logs are written to:
```
%ProgramData%\Microsoft\IntuneManagementExtension\Logs\ComputerDescriptionFromAD.log
```

Example log output:
```
[2025-02-19 10:30:15] [INFO] === Computer Description from AD Sync Started ===
[2025-02-19 10:30:15] [SUCCESS] Computer is domain joined to: company.com
[2025-02-19 10:30:16] [INFO] Current local description: Old Description
[2025-02-19 10:30:16] [SUCCESS] Found AD description: Marketing Laptop - John Smith
[2025-02-19 10:30:17] [SUCCESS] Local description updated successfully
```

## Troubleshooting

### "Computer is not domain joined"

**Cause:** Device is not joined to the domain or can't reach DC

**Solution:**
- Verify domain join status: `nltest /dsgetdc:company.com`
- Check network connectivity to DC
- Use `-FallbackDescription` for non-domain devices

### "AD query failed"

**Cause:** Permission issues or DC connectivity

**Solution:**
- Verify computer account can read AD
- Specify domain controller: `-DomainController "dc01.company.com"`
- Check firewall rules for LDAP (port 389)
- Try installing RSAT: `Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0`

### "Failed to set local description"

**Cause:** Permission issues

**Solution:**
- Script requires Administrator rights
- Verify WMI service is running: `Get-Service winmgmt`
- Check local security policy for description modification rights

### Description Not Updating

Run manually to see detailed output:
```powershell
.\Set-ComputerDescriptionFromAD.ps1 -Verbose
```

### Detection Fails

Run detection manually:
```powershell
.\Detect-ComputerDescriptionFromAD.ps1
echo $LASTEXITCODE  # 0 = synced, 1 = not synced
```

## Benefits

### IT Asset Management
- Quickly identify computers in network browsing
- See department/owner information at a glance
- Consistent documentation across AD and local systems

### Remote Support
- Help desk can identify computers by description
- Users can provide computer description for support tickets

### Compliance
- Standardized naming across the organization
- Easy identification of machine purpose/owner

## Examples

### Standard Deployment

```powershell
.\Set-ComputerDescriptionFromAD.ps1
```

### With Department Fallback

```powershell
.\Set-ComputerDescriptionFromAD.ps1 -FallbackDescription "Corporate Workstation"
```

### Run with Specific DC

```powershell
.\Set-ComputerDescriptionFromAD.ps1 -DomainController "dc01.company.com"
```

### Force Refresh

```powershell
# Update even if descriptions match
.\Set-ComputerDescriptionFromAD.ps1 -Force
```

## Best Practices

1. **Set Descriptions in AD** — Establish a naming convention for AD computer descriptions
2. **Use Proactive Remediation** — Run daily/weekly to keep descriptions in sync
3. **Standardize Format** — Use consistent format like "[Department] - [User] - [Asset Tag]"
4. **Document Exceptions** — Use fallback for non-domain or special-use devices

## Registry Tracking

Successful operations create:
```
HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\ComputerDescriptionAD
  LastRun = "2025-02-19 10:30:17"
  ADDescription = "Marketing Laptop - John Smith"
  LocalDescription = "Marketing Laptop - John Smith"
  Success = "True"
```

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-02-19 | Initial release |

## References

- [Set-ADComputer Documentation](https://docs.microsoft.com/en-us/powershell/module/addsadministration/set-adcomputer)
- [Win32_OperatingSystem Class](https://docs.microsoft.com/en-us/windows/win32/cimwin32prov/win32-operatingsystem)
- [Intune Proactive Remediations](https://docs.microsoft.com/en-us/mem/intune/protect/proactive-remediations)

## License

MIT License — Modify for your environment as needed.
