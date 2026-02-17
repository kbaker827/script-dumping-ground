<#
.SYNOPSIS
    Exports Intune iOS/iPadOS devices that have been inactive since a specified date.

.DESCRIPTION
    This script queries Microsoft Graph to find iOS/iPadOS devices managed by Intune that
    haven't synced since a specified cutoff date. It includes device group memberships and
    exports comprehensive results to a CSV file.
    
    The script provides filtering options, group membership resolution, and multiple
    authentication methods for both interactive and automated scenarios.

.PARAMETER CutoffDate
    Devices that haven't synced since this date are considered inactive.
    Defaults to July 1 of the current year (typical fiscal year start).

.PARAMETER OutputPath
    Path for the output CSV file. Defaults to %TEMP% with timestamp.

.PARAMETER DaysInactive
    Alternative to CutoffDate - specify number of days of inactivity.
    Example: -DaysInactive 90 (devices inactive for 90+ days)

.PARAMETER UseDeviceCode
    Use device code authentication flow (useful for remote/headless sessions).

.PARAMETER UseManagedIdentity
    Use Azure Managed Identity authentication (for Azure Automation/Runbooks).

.PARAMETER TenantId
    Azure AD Tenant ID for device code authentication.

.PARAMETER IncludeTransitiveGroups
    Include nested (transitive) group memberships. By default, only direct memberships are shown.

.PARAMETER OsFilter
    Filter by OS type: iOS, iPadOS, or All. Default: All (both).

.PARAMETER ComplianceFilter
    Filter by compliance state: Compliant, NonCompliant, or All. Default: All.

.PARAMETER ExportFormat
    Output format: CSV, JSON, or Excel. Default: CSV.

.PARAMETER SendEmail
    Send the report via email (requires -SmtpServer, -To, -From).

.PARAMETER SmtpServer
    SMTP server for email delivery.

.PARAMETER To
    Email recipient(s).

.PARAMETER From
    Email sender address.

.PARAMETER WhatIf
    Show what would be queried without exporting data.

.EXAMPLE
    .\Get-IntuneInactiveIOSDevices.ps1
    Exports all iOS/iPadOS devices inactive since July 1 of current year.

.EXAMPLE
    .\Get-IntuneInactiveIOSDevices.ps1 -DaysInactive 90
    Exports devices inactive for 90+ days.

.EXAMPLE
    .\Get-IntuneInactiveIOSDevices.ps1 -CutoffDate '2025-01-01' -IncludeTransitiveGroups -OsFilter iPadOS
    Exports iPadOS devices inactive since Jan 1, 2025, including nested groups.

.EXAMPLE
    .\Get-IntuneInactiveIOSDevices.ps1 -DaysInactive 30 -ComplianceFilter NonCompliant -ExportFormat Excel
    Exports non-compliant devices inactive 30+ days to Excel format.

.EXAMPLE
    .\Get-IntuneInactiveIOSDevices.ps1 -DaysInactive 180 -SendEmail -SmtpServer "smtp.contoso.com" -To "admin@contoso.com" -From "intune@contoso.com"
    Exports devices inactive 180+ days and emails the report.

.NOTES
    Version:        3.0
    Author:         IT Admin
    Updated:        2026-02-12
    
    Requirements:
    - Microsoft.Graph PowerShell module (auto-installed)
    - Required Graph Permissions:
      * DeviceManagementManagedDevices.Read.All
      * Device.Read.All
      * Group.Read.All
      * Directory.Read.All (for transitive memberships)
    
    Exit Codes:
    0   - Success, devices found and exported
    1   - Authentication error
    2   - Query error
    3   - Export error
    4   - No devices found
    5   - Email delivery error
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(ParameterSetName='ByDate')]
    [datetime]$CutoffDate = (Get-Date -Year (Get-Date).Year -Month 7 -Day 1 -Hour 0 -Minute 0 -Second 0),
    
    [Parameter(ParameterSetName='ByDays')]
    [ValidateRange(1, 3650)]
    [int]$DaysInactive,
    
    [string]$OutputPath,
    
    [switch]$UseDeviceCode,
    [switch]$UseManagedIdentity,
    [string]$TenantId,
    
    [switch]$IncludeTransitiveGroups,
    
    [ValidateSet('iOS', 'iPadOS', 'All')]
    [string]$OsFilter = 'All',
    
    [ValidateSet('Compliant', 'NonCompliant', 'All')]
    [string]$ComplianceFilter = 'All',
    
    [ValidateSet('CSV', 'JSON', 'Excel')]
    [string]$ExportFormat = 'CSV',
    
    [switch]$SendEmail,
    [string]$SmtpServer,
    [string[]]$To,
    [string]$From,
    
    [switch]$WhatIf
)

#region Configuration
$ErrorActionPreference = 'Stop'
$script:Version = "3.0"
$script:StartTime = Get-Date

# Required Microsoft Graph permissions
$script:RequiredScopes = @(
    'DeviceManagementManagedDevices.Read.All',
    'Device.Read.All',
    'Group.Read.All',
    'Directory.Read.All'
)

# Device properties to retrieve
$script:DeviceProperties = @(
    'id', 'deviceName', 'operatingSystem', 'osVersion', 'serialNumber', 'udid',
    'azureAdDeviceId', 'userId', 'userDisplayName', 'userPrincipalName',
    'lastSyncDateTime', 'enrolledDateTime', 'ownerType', 'managementState',
    'complianceState', 'deviceEnrollmentType', 'jailBroken', 'wiFiMacAddress',
    'imei', 'easActivated', 'easDeviceId', 'deviceActionResults'
)
#endregion

#region Helper Functions
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Detail')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $colors = @{
        Info = 'Cyan'
        Success = 'Green'
        Warning = 'Yellow'
        Error = 'Red'
        Detail = 'Gray'
    }
    
    $prefix = switch ($Level) {
        'Info'    { '[*]' }
        'Success' { '[+]' }
        'Warning' { '[!]' }
        'Error'   { '[-]' }
        'Detail'  { '   ' }
    }
    
    Write-Host "$prefix $Message" -ForegroundColor $colors[$Level]
}

function Show-Header {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  Intune Inactive iOS Device Reporter v$Version" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    
    if ($DaysInactive) {
        $script:EffectiveCutoff = (Get-Date).AddDays(-$DaysInactive)
        Write-Log "Finding devices inactive for $DaysInactive+ days (since $($script:EffectiveCutoff.ToString('yyyy-MM-dd')))" -Level Info
    } else {
        $script:EffectiveCutoff = $CutoffDate
        Write-Log "Finding devices inactive since $($CutoffDate.ToString('yyyy-MM-dd'))" -Level Info
    }
    
    Write-Log "OS Filter: $OsFilter" -Level Detail
    Write-Log "Compliance Filter: $ComplianceFilter" -Level Detail
    Write-Log "Include Transitive Groups: $IncludeTransitiveGroups" -Level Detail
    Write-Host ""
}

function Install-GraphModule {
    Write-Log "Checking Microsoft.Graph module..." -Level Info
    
    $module = Get-Module -ListAvailable -Name Microsoft.Graph
    
    if (-not $module) {
        Write-Log "Microsoft.Graph not found. Installing..." -Level Warning
        try {
            Install-Module Microsoft.Graph -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            Write-Log "Microsoft.Graph installed successfully" -Level Success
        }
        catch {
            Write-Log "Failed to install Microsoft.Graph: $($_.Exception.Message)" -Level Error
            Write-Log "Install manually: Install-Module Microsoft.Graph -Scope CurrentUser -Force" -Level Info
            exit 1
        }
    } else {
        Write-Log "Microsoft.Graph v$($module.Version) found" -Level Success
    }
    
    Import-Module Microsoft.Graph -ErrorAction Stop
}

function Connect-Graph {
    Write-Log "Connecting to Microsoft Graph..." -Level Info
    
    try {
        $existingContext = Get-MgContext
        if ($existingContext) {
            # Check if we have required scopes
            $hasAllScopes = $script:RequiredScopes | ForEach-Object { $existingContext.Scopes -contains $_ } | Where-Object { $_ -eq $false } | Measure-Object
            if ($hasAllScopes.Count -eq 0) {
                Write-Log "Already connected as: $($existingContext.Account)" -Level Success
                return $true
            }
            Write-Log "Existing connection missing required scopes, reconnecting..." -Level Warning
        }
        
        $connectParams = @{
            Scopes = $script:RequiredScopes
            NoWelcome = $true
            ErrorAction = 'Stop'
        }
        
        if ($UseDeviceCode) {
            $connectParams['UseDeviceCode'] = $true
            if ($TenantId) {
                $connectParams['TenantId'] = $TenantId
            }
            Write-Log "Using device code authentication" -Level Info
        }
        elseif ($UseManagedIdentity) {
            $connectParams = @{
                Identity = $true
                NoWelcome = $true
                ErrorAction = 'Stop'
            }
            Write-Log "Using managed identity authentication" -Level Info
        }
        
        Connect-MgGraph @connectParams | Out-Null
        $context = Get-MgContext
        Write-Log "Connected as: $($context.Account)" -Level Success
        return $true
    }
    catch {
        Write-Log "Connection failed: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Build-DeviceFilter {
    $conditions = [System.Collections.Generic.List[string]]::new()
    
    # OS Filter
    switch ($OsFilter) {
        'iOS' { $conditions.Add("(operatingSystem eq 'iOS')") }
        'iPadOS' { $conditions.Add("(operatingSystem eq 'iPadOS')") }
        'All' { $conditions.Add("((operatingSystem eq 'iOS') or (operatingSystem eq 'iPadOS'))") }
    }
    
    # Inactivity filter
    $cutoffUtc = $script:EffectiveCutoff.ToUniversalTime()
    $cutoffIso = $cutoffUtc.ToString('o')
    $conditions.Add("lastSyncDateTime lt $cutoffIso")
    
    # Compliance filter
    switch ($ComplianceFilter) {
        'Compliant' { $conditions.Add("(complianceState eq 'compliant')") }
        'NonCompliant' { $conditions.Add("(complianceState eq 'noncompliant')") }
    }
    
    return $conditions -join ' and '
}

function Get-DeviceGroupMemberships {
    param(
        [Parameter(Mandatory)]
        [string]$EntraDeviceObjectId
    )
    
    $groups = [System.Collections.Generic.List[object]]::new()
    
    try {
        if ($IncludeTransitiveGroups) {
            $memberships = Get-MgDeviceTransitiveMemberOf -DeviceId $EntraDeviceObjectId -All -ErrorAction SilentlyContinue
        } else {
            $memberships = Get-MgDeviceMemberOf -DeviceId $EntraDeviceObjectId -All -ErrorAction SilentlyContinue
        }
        
        foreach ($membership in $memberships) {
            $odataType = $membership.AdditionalProperties.'@odata.type'
            if ($odataType -eq '#microsoft.graph.group') {
                $groups.Add([PSCustomObject]@{
                    DisplayName = $membership.AdditionalProperties.displayName
                    Id = $membership.Id
                    GroupType = if ($membership.AdditionalProperties.groupTypes -contains 'Unified') { 'Microsoft 365' } else { 'Security' }
                })
            }
        }
    }
    catch {
        Write-Log "Failed to get groups for device $EntraDeviceObjectId : $($_.Exception.Message)" -Level Warning
    }
    
    return $groups
}

function Get-InactiveDevices {
    $filter = Build-DeviceFilter
    
    Write-Log "Query filter: $filter" -Level Detail
    Write-Log "Querying Intune for inactive devices..." -Level Info
    
    try {
        if ($PSCmdlet.ShouldProcess("Intune", "Query inactive devices")) {
            $devices = Get-MgDeviceManagementManagedDevice -Filter $filter -All -Property $script:DeviceProperties -ErrorAction Stop
            return $devices
        } else {
            Write-Log "[WHATIF] Would query devices with filter: $filter" -Level Warning
            return @()
        }
    }
    catch {
        Write-Log "Query error: $($_.Exception.Message)" -Level Error
        exit 2
    }
}

function Process-Devices {
    param([array]$Devices)
    
    Write-Log "Found $($Devices.Count) inactive device(s)" -Level Success
    Write-Log "Resolving group memberships..." -Level Info
    
    $results = [System.Collections.Generic.List[object]]::new()
    $processedCount = 0
    $totalCount = $Devices.Count
    
    foreach ($device in $Devices) {
        $processedCount++
        Write-Progress -Activity "Processing devices" -Status "Device $processedCount of $totalCount : $($device.DeviceName)" -PercentComplete (($processedCount / $totalCount) * 100)
        
        $groupNames = ''
        $groupIds = ''
        $groupTypes = ''
        $groupCount = 0
        
        # Resolve Entra device and get group memberships
        if ($device.AzureAdDeviceId) {
            try {
                $entraDevice = Get-MgDevice -Filter "deviceId eq '$($device.AzureAdDeviceId)'" -ConsistencyLevel eventual -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($entraDevice) {
                    $deviceGroups = Get-DeviceGroupMemberships -EntraDeviceObjectId $entraDevice.Id
                    if ($deviceGroups) {
                        $groupNames = ($deviceGroups | Select-Object -ExpandProperty DisplayName) -join '; '
                        $groupIds = ($deviceGroups | Select-Object -ExpandProperty Id) -join '; '
                        $groupTypes = ($deviceGroups | Select-Object -ExpandProperty GroupType -Unique) -join '; '
                        $groupCount = $deviceGroups.Count
                    }
                }
            }
            catch {
                Write-Log "Error resolving groups for $($device.DeviceName): $($_.Exception.Message)" -Level Warning
            }
        }
        
        # Calculate days since last sync
        $lastSync = [datetime]$device.LastSyncDateTime
        $daysSinceSync = (Get-Date) - $lastSync
        
        $results.Add([PSCustomObject]@{
            DeviceName = $device.DeviceName
            UPN = $device.UserPrincipalName
            PrimaryUser = $device.UserDisplayName
            IntuneManagedDeviceId = $device.Id
            AzureAdDeviceId = $device.AzureAdDeviceId
            SerialNumber = $device.SerialNumber
            UDID = $device.Udid
            OS = $device.OperatingSystem
            OSVersion = $device.OsVersion
            Ownership = $device.OwnerType
            EnrollmentType = $device.DeviceEnrollmentType
            ManagementState = $device.ManagementState
            ComplianceState = $device.ComplianceState
            IsJailbroken = $device.JailBroken
            WiFiMacAddress = $device.WiFiMacAddress
            IMEI = $device.Imei
            EnrolledDateTime = $device.EnrolledDateTime
            LastSyncDateTimeUtc = $lastSync
            DaysSinceLastSync = [math]::Round($daysSinceSync.TotalDays, 0)
            GroupCount = $groupCount
            Groups = $groupNames
            GroupIds = $groupIds
            GroupTypes = $groupTypes
        })
    }
    
    Write-Progress -Activity "Processing devices" -Completed
    return $results
}

function Export-Results {
    param(
        [array]$Data,
        [string]$Path
    )
    
    Write-Log "Exporting to $ExportFormat format..." -Level Info
    
    try {
        switch ($ExportFormat) {
            'CSV' {
                $Data | Sort-Object DaysSinceLastSync -Descending | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $Path
            }
            'JSON' {
                $Data | Sort-Object DaysSinceLastSync -Descending | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
            }
            'Excel' {
                # For Excel, we export as CSV with .xlsx extension indication
                # In production, you'd use ImportExcel module
                $csvPath = $Path -replace '\.xlsx$', '.csv'
                $Data | Sort-Object DaysSinceLastSync -Descending | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csvPath
                Write-Log "Excel export requires ImportExcel module. Saved as CSV: $csvPath" -Level Warning
                $Path = $csvPath
            }
        }
        
        Write-Log "Report saved: $Path" -Level Success
        return $Path
    }
    catch {
        Write-Log "Export failed: $($_.Exception.Message)" -Level Error
        exit 3
    }
}

function Send-ReportEmail {
    param([string]$FilePath)
    
    if (-not $SendEmail) { return }
    
    Write-Log "Sending email report..." -Level Info
    
    # Validate email parameters
    if (-not $SmtpServer -or -not $To -or -not $From) {
        Write-Log "Email parameters missing. Required: -SmtpServer, -To, -From" -Level Error
        exit 5
    }
    
    try {
        $subject = "Intune Inactive iOS Device Report - $(Get-Date -Format 'yyyy-MM-dd')"
        $body = @"
Intune Inactive iOS/iPadOS Device Report

Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Cutoff Date: $($script:EffectiveCutoff.ToString('yyyy-MM-dd'))
Total Inactive Devices: $($script:DeviceCount)

Filters Applied:
- OS: $OsFilter
- Compliance: $ComplianceFilter
- Days Inactive: $(if ($DaysInactive) { $DaysInactive } else { "Since $($script:EffectiveCutoff.ToString('yyyy-MM-dd'))" })

See attached CSV for full details.
"@
        
        $emailParams = @{
            SmtpServer = $SmtpServer
            To = $To
            From = $From
            Subject = $subject
            Body = $body
            Attachments = $FilePath
            ErrorAction = 'Stop'
        }
        
        Send-MailMessage @emailParams
        Write-Log "Email sent to: $($To -join ', ')" -Level Success
    }
    catch {
        Write-Log "Email delivery failed: $($_.Exception.Message)" -Level Error
        exit 5
    }
}

function Show-Summary {
    param([array]$Data)
    
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  SUMMARY" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Statistics
    $iosCount = ($Data | Where-Object { $_.OS -eq 'iOS' }).Count
    $ipadCount = ($Data | Where-Object { $_.OS -eq 'iPadOS' }).Count
    $nonCompliantCount = ($Data | Where-Object { $_.ComplianceState -eq 'noncompliant' }).Count
    $jailbrokenCount = ($Data | Where-Object { $_.IsJailbroken -eq $true }).Count
    
    Write-Log "Total inactive devices: $($Data.Count)" -Level Info
    Write-Log "  iOS devices: $iosCount" -Level Detail
    Write-Log "  iPadOS devices: $ipadCount" -Level Detail
    Write-Log "  Non-compliant: $nonCompliantCount" -Level $(if ($nonCompliantCount -gt 0) { 'Warning' } else { 'Success' })
    Write-Log "  Jailbroken: $jailbrokenCount" -Level $(if ($jailbrokenCount -gt 0) { 'Error' } else { 'Success' })
    
    # Top users
    Write-Host ""
    Write-Log "Top users with inactive devices:" -Level Info
    $Data | Group-Object UPN | Sort-Object Count -Descending | Select-Object -First 5 | 
        ForEach-Object { Write-Log "  $($_.Name): $($_.Count) devices" -Level Detail }
    
    # Oldest sync
    Write-Host ""
    Write-Log "Devices with oldest last sync:" -Level Info
    $Data | Sort-Object LastSyncDateTimeUtc | Select-Object -First 5 | 
        ForEach-Object { Write-Log "  $($_.DeviceName): $($_.LastSyncDateTimeUtc.ToString('yyyy-MM-dd')) ($($_.DaysSinceLastSync) days)" -Level Detail }
    
    Write-Host ""
    $duration = (Get-Date) - $script:StartTime
    Write-Log "Execution time: $($duration.ToString('mm\:ss'))" -Level Info
}
#endregion

#region Main Execution
Show-Header

# Install and connect
Install-GraphModule

if (-not (Connect-Graph)) {
    exit 1
}

# Determine output path
if (-not $OutputPath) {
    $outputDir = $env:TEMP
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutputPath = Join-Path $outputDir "Intune_iOS_Inactive_$timestamp.$($ExportFormat.ToLower())"
}

# Query devices
$inactiveDevices = Get-InactiveDevices

if ($inactiveDevices.Count -eq 0) {
    Write-Log "No inactive iOS/iPadOS devices found" -Level Warning
    
    # Create empty report
    if (-not $WhatIf) {
        "No inactive devices found matching criteria" | Out-File -FilePath $OutputPath
        Write-Log "Empty report created: $OutputPath" -Level Info
    }
    
    exit 4
}

# Process devices
$processedDevices = Process-Devices -Devices $inactiveDevices
$script:DeviceCount = $processedDevices.Count

# Export
$exportPath = Export-Results -Data $processedDevices -Path $OutputPath

# Show summary
Show-Summary -Data $processedDevices

# Display sample
Write-Host ""
Write-Log "Sample output (first 5 devices):" -Level Info
$processedDevices | Select-Object -First 5 | 
    Select-Object DeviceName, UPN, OS, OSVersion, DaysSinceLastSync, ComplianceState |
    Format-Table -AutoSize

# Send email if requested
Send-ReportEmail -FilePath $exportPath

Write-Host ""
Write-Log "Complete!" -Level Success
exit 0
#endregion
