# Intune Inactive iOS Device Reporter

PowerShell utility to identify and report iOS/iPadOS devices managed by Microsoft Intune that haven't synced within a specified time period.

## Overview

This script queries Microsoft Graph to find iOS and iPadOS devices that have been inactive (no sync) for a specified number of days or since a specific date. It's useful for:

- Identifying stale devices for cleanup
- Compliance auditing
- Device lifecycle management
- Cost optimization (removing inactive licenses)

## Features

- ✅ **Flexible Date Filtering** - By specific date or days of inactivity
- ✅ **OS Filtering** - iOS only, iPadOS only, or both
- ✅ **Compliance Filtering** - Focus on non-compliant devices
- ✅ **Group Memberships** - Shows device group memberships
- ✅ **Multiple Export Formats** - CSV, JSON, or Excel
- ✅ **Email Reports** - Automatic email delivery of reports
- ✅ **Multiple Auth Methods** - Interactive, Device Code, or Managed Identity
- ✅ **WhatIf Support** - Preview queries without exporting

## Quick Start

### Basic Usage (Inactive since July 1)
```powershell
.\Get-IntuneInactiveIOSDevices.ps1
```

### Inactive for 90+ Days
```powershell
.\Get-IntuneInactiveIOSDevices.ps1 -DaysInactive 90
```

### Non-Compliant Devices Only
```powershell
.\Get-IntuneInactiveIOSDevices.ps1 -DaysInactive 30 -ComplianceFilter NonCompliant
```

### Email the Report
```powershell
.\Get-IntuneInactiveIOSDevices.ps1 -DaysInactive 180 -SendEmail -SmtpServer "smtp.contoso.com" -To "admin@contoso.com" -From "intune@contoso.com"
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `CutoffDate` | datetime | July 1 current year | Find devices inactive since this date |
| `DaysInactive` | int | - | Alternative: number of days inactive |
| `OutputPath` | string | %TEMP%\*.csv | Export file path |
| `UseDeviceCode` | switch | `$false` | Use device code authentication |
| `UseManagedIdentity` | switch | `$false` | Use Azure Managed Identity |
| `TenantId` | string | - | Tenant ID for device code auth |
| `IncludeTransitiveGroups` | switch | `$false` | Include nested group memberships |
| `OsFilter` | string | "All" | "iOS", "iPadOS", or "All" |
| `ComplianceFilter` | string | "All" | "Compliant", "NonCompliant", or "All" |
| `ExportFormat` | string | "CSV" | "CSV", "JSON", or "Excel" |
| `SendEmail` | switch | `$false` | Email the report |
| `SmtpServer` | string | - | SMTP server for email |
| `To` | string[] | - | Email recipient(s) |
| `From` | string | - | Email sender address |
| `WhatIf` | switch | `$false` | Preview mode |

## Required Permissions

The script requires these Microsoft Graph permissions:

- `DeviceManagementManagedDevices.Read.All` - Read Intune devices
- `Device.Read.All` - Read Entra device objects
- `Group.Read.All` - Read group memberships
- `Directory.Read.All` - For transitive group memberships

### Grant Permissions

**Interactive (first run):**
```powershell
Connect-MgGraph -Scopes @(
    'DeviceManagementManagedDevices.Read.All',
    'Device.Read.All',
    'Group.Read.All',
    'Directory.Read.All'
)
```

**App Registration (for automation):**
1. Azure Portal → App Registrations → New
2. API Permissions → Add:
   - Microsoft Graph → Application permissions → Add all four above
3. Grant admin consent

## Examples

### Find Devices Inactive Since Specific Date
```powershell
.\Get-IntuneInactiveIOSDevices.ps1 -CutoffDate '2025-01-01'
```

### Find iPadOS Devices Only
```powershell
.\Get-IntuneInactiveIOSDevices.ps1 -DaysInactive 60 -OsFilter iPadOS
```

### Include Nested Group Memberships
```powershell
.\Get-IntuneInactiveIOSDevices.ps1 -DaysInactive 90 -IncludeTransitiveGroups
```

### Export to JSON
```powershell
.\Get-IntuneInactiveIOSDevices.ps1 -DaysInactive 30 -ExportFormat JSON
```

### Use Device Code Authentication
```powershell
.\Get-IntuneInactiveIOSDevices.ps1 -DaysInactive 120 -UseDeviceCode -TenantId "contoso.onmicrosoft.com"
```

### Azure Automation with Managed Identity
```powershell
.\Get-IntuneInactiveIOSDevices.ps1 -DaysInactive 180 -UseManagedIdentity -SendEmail -SmtpServer "smtp.contoso.com" -To "admin@contoso.com" -From "automation@contoso.com"
```

### Preview Only (WhatIf)
```powershell
.\Get-IntuneInactiveIOSDevices.ps1 -DaysInactive 30 -WhatIf
```

## Output

### Console Output
```
============================================
  Intune Inactive iOS Device Reporter v3.0
============================================

[*] Finding devices inactive for 90+ days (since 2025-11-14)
    OS Filter: All
    Compliance Filter: All
    Include Transitive Groups: False

[*] Checking Microsoft.Graph module...
[+] Microsoft.Graph v2.0.0 found
[*] Connecting to Microsoft Graph...
[+] Connected as: admin@contoso.com
[*] Query filter: ((operatingSystem eq 'iOS') or (operatingSystem eq 'iPadOS')) and lastSyncDateTime lt 2025-11-14T00:00:00.0000000Z
[*] Querying Intune for inactive devices...
[+] Found 247 inactive device(s)
[*] Resolving group memberships...
[*] Exporting to CSV format...
[+] Report saved: C:\Users\admin\AppData\Local\Temp\Intune_iOS_Inactive_20260212_155030.csv

============================================
  SUMMARY
============================================

[*] Total inactive devices: 247
    iOS devices: 198
    iPadOS devices: 49
[!] Non-compliant: 23
[+] Jailbroken: 0

[*] Top users with inactive devices:
    john.smith@contoso.com: 5 devices
    jane.doe@contoso.com: 3 devices
    ...

[*] Devices with oldest last sync:
    iPhone-JSmith: 2024-03-15 (333 days)
    iPad-Accounting: 2024-04-01 (316 days)
    ...

Sample output (first 5 devices):

DeviceName         UPN                       OS        OSVersion DaysSinceLastSync ComplianceState
----------         ---                       --        --------- ----------------- ---------------
iPhone-JDoe        john.doe@contoso.com      iOS       17.1.1                  95 NonCompliant
iPad-Accounting    finance@contoso.com       iPadOS    16.7.2                 112 Compliant
iPhone-Sales01     sales01@contoso.com       iOS       16.6.1                  88 Compliant
iPad-HR-Director   hr@contoso.com            iPadOS    17.0.3                  67 Compliant
iPhone-Executive   ceo@contoso.com           iOS       17.2.1                  45 Compliant

[+] Complete!
```

### CSV Export Columns

| Column | Description |
|--------|-------------|
| `DeviceName` | Device display name |
| `UPN` | User Principal Name of primary user |
| `PrimaryUser` | Display name of primary user |
| `IntuneManagedDeviceId` | Intune device ID |
| `AzureAdDeviceId` | Entra ID device ID |
| `SerialNumber` | Device serial number |
| `UDID` | Unique Device Identifier |
| `OS` | iOS or iPadOS |
| `OSVersion` | OS version (e.g., 17.1.1) |
| `Ownership` | Corporate or Personal |
| `EnrollmentType` | How device was enrolled |
| `ManagementState` | Current management state |
| `ComplianceState` | Compliant or NonCompliant |
| `IsJailbroken` | Jailbreak detection status |
| `WiFiMacAddress` | MAC address |
| `IMEI` | Device IMEI |
| `EnrolledDateTime` | When device was enrolled |
| `LastSyncDateTimeUtc` | Last Intune sync timestamp |
| `DaysSinceLastSync` | Calculated days since sync |
| `GroupCount` | Number of group memberships |
| `Groups` | Semicolon-separated group names |
| `GroupIds` | Semicolon-separated group IDs |
| `GroupTypes` | Group types (Microsoft 365/Security) |

## Authentication Methods

### Interactive (Default)
Opens browser for login:
```powershell
.\Get-IntuneInactiveIOSDevices.ps1 -DaysInactive 90
```

### Device Code
For remote/SSH sessions:
```powershell
.\Get-IntuneInactiveIOSDevices.ps1 -DaysInactive 90 -UseDeviceCode
```
Copy the code and open the URL in a browser.

### Managed Identity
For Azure Automation:
```powershell
.\Get-IntuneInactiveIOSDevices.ps1 -DaysInactive 90 -UseManagedIdentity
```

## Use Cases

### Monthly Device Cleanup
```powershell
# Run on first of each month via Task Scheduler
.\Get-IntuneInactiveIOSDevices.ps1 -DaysInactive 90 -SendEmail -SmtpServer "smtp.contoso.com" -To "deviceadmins@contoso.com" -From "intune@contoso.com"
```

### Compliance Audit
```powershell
# Focus on non-compliant devices
.\Get-IntuneInactiveIOSDevices.ps1 -DaysInactive 30 -ComplianceFilter NonCompliant -OsFilter iPadOS
```

### Retire Stale Devices
```powershell
# Export for bulk retirement
$devices = Import-Csv (Get-IntuneInactiveIOSDevices.ps1 -DaysInactive 180).OutputPath
$devices | ForEach-Object {
    Remove-MgDeviceManagementManagedDevice -ManagedDeviceId $_.IntuneManagedDeviceId
}
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success, devices found and exported |
| 1 | Authentication error |
| 2 | Query error |
| 3 | Export error |
| 4 | No devices found |
| 5 | Email delivery error |

## Automation

### Azure Automation Runbook

```powershell
# Runbook script
param(
    [int]$DaysInactive = 90,
    [string]$SmtpServer = "smtp.contoso.com",
    [string]$To = "admin@contoso.com",
    [string]$From = "automation@contoso.com"
)

.\Get-IntuneInactiveIOSDevices.ps1 `
    -DaysInactive $DaysInactive `
    -UseManagedIdentity `
    -SendEmail `
    -SmtpServer $SmtpServer `
    -To $To `
    -From $From
```

### Scheduled Task

```powershell
# Create daily report at 8 AM
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-File C:\Scripts\Get-IntuneInactiveIOSDevices.ps1 -DaysInactive 30 -OutputPath C:\Reports"

$trigger = New-ScheduledTaskTrigger -Daily -At "8:00 AM"
Register-ScheduledTask -TaskName "Intune iOS Device Report" -Action $action -Trigger $trigger
```

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Microsoft.Graph PowerShell module (auto-installed)
- Internet connectivity to Microsoft Graph
- Appropriate permissions (see above)

## Troubleshooting

### "Failed to connect"
- Verify you have required Graph permissions
- Check network connectivity to graph.microsoft.com
- For device code: ensure you complete the auth within timeout

### "No inactive devices found"
- Verify your CutoffDate or DaysInactive value
- Check that you have devices in Intune
- Verify you have DeviceManagementManagedDevices.Read.All permission

### "Access denied"
- Ensure you have all required Graph permissions
- Grant admin consent for application permissions
- Check that your account has Intune admin role

### "Module installation failed"
```powershell
# Install manually
Install-Module Microsoft.Graph -Scope CurrentUser -Force
```

## Version History

### 3.0 (2026-02-12)
- Added DaysInactive parameter as alternative to CutoffDate
- Added OsFilter and ComplianceFilter options
- Added multiple export formats (CSV, JSON, Excel)
- Added email report delivery
- Added WhatIf support
- Added managed identity authentication
- Improved summary statistics
- Added top users and oldest sync reporting

### 2.0 (2026-02-04)
- Basic inactive device querying
- Group membership resolution
- CSV export
- Interactive and device code auth

### 1.0
- Initial release

## Related Scripts

- `Check-IntuneEnrollment.ps1` - Check device enrollment status
- `Find-OrphanedSharePointSync.ps1` - Find orphaned OneDrive sync folders
- `Remove-DellBloatware.ps1` - Clean up Dell pre-installed software

## License

MIT License - Use at your own risk. Always verify results before taking action on devices.
