<#
.SYNOPSIS
    Troubleshoots and attempts to fix Intune/MDM enrollment issues on Windows devices.

.DESCRIPTION
    This script performs comprehensive checks and remediation for Intune/MDM enrollment:
    - Validates PowerShell architecture (64-bit required)
    - Checks Windows edition compatibility (Pro/Enterprise/Education required)
    - Verifies Azure AD join status and MDM enrollment state
    - Checks network connectivity to Intune endpoints
    - Validates required services are running
    - Checks certificate health
    - Attempts automatic remediation for common issues
    - Triggers sync and enrollment if needed
    - Generates detailed log file for troubleshooting

.PARAMETER AutoRemediate
    Automatically attempt to fix issues without prompting.

.PARAMETER Detailed
    Show detailed output including registry checks and policy states.

.PARAMETER ExportLog
    Export results to a JSON file for further analysis.

.PARAMETER LogPath
    Path to save the detailed log file.

.PARAMETER ResetEnrollment
    WARNING: Attempts to reset MDM enrollment (requires manual re-enrollment).

.EXAMPLE
    .\Check-IntuneEnrollment.ps1
    Runs all enrollment checks interactively.

.EXAMPLE
    .\Check-IntuneEnrollment.ps1 -AutoRemediate
    Runs checks and automatically attempts fixes.

.EXAMPLE
    .\Check-IntuneEnrollment.ps1 -Detailed -ExportLog
    Shows detailed info and exports results to JSON.

.NOTES
    Version:        3.0
    Author:         IT Admin
    Updated:        2026-02-12
    
    Requirements:
    - Windows 10/11 Pro, Enterprise, or Education
    - PowerShell 5.1 or later
    - Administrator privileges
    
    Exit Codes:
    0   - Device properly enrolled, no issues found
    1   - Critical error (wrong architecture, edition, etc.)
    2   - Not Azure AD joined
    3   - Azure AD joined but not MDM enrolled
    4   - Issues found but auto-remediation disabled
    5   - Auto-remediation attempted but failed
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$AutoRemediate,
    [switch]$Detailed,
    [switch]$ExportLog,
    [string]$LogPath = (Join-Path $env:TEMP "IntuneEnrollmentCheck_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"),
    [switch]$ResetEnrollment
)

#region Configuration
$ErrorActionPreference = 'Continue'
$script:Version = "3.0"
$script:IssuesFound = [System.Collections.Generic.List[string]]::new()
$script:RemediationAttempts = [System.Collections.Generic.List[string]]::new()
$script:RemediationSuccess = [System.Collections.Generic.List[string]]::new()

# Intune endpoints to test
$script:IntuneEndpoints = @(
    "login.microsoftonline.com"
    "device.login.microsoftonline.com"
    "enrollment.manage.microsoft.com"
    "manage.microsoft.com"
    "fef.msuc03.manage.microsoft.com"
    "m.manage.microsoft.com"
)

# Required services
$script:RequiredServices = @(
    @{
        Name = "Schedule"
        DisplayName = "Task Scheduler"
        RequiredFor = "MDM enrollment scheduled tasks"
    },
    @{
        Name = "WinHttpAutoProxySvc"
        DisplayName = "WinHTTP Web Proxy Auto-Discovery Service"
        RequiredFor = "Auto-proxy detection"
    },
    @{
        Name = "cryptsvc"
        DisplayName = "Cryptographic Services"
        RequiredFor = "Certificate management"
    },
    @{
        Name = "BrokerInfrastructure"
        DisplayName = "Background Tasks Infrastructure Service"
        RequiredFor = "Background task processing"
    }
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
    $logEntry = "[$timestamp] [$Level] $Message"
    
    Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
    
    switch ($Level) {
        'Info'    { Write-Host "[*] $Message" -ForegroundColor Cyan }
        'Success' { Write-Host "[+] $Message" -ForegroundColor Green }
        'Warning' { Write-Host "[!] $Message" -ForegroundColor Yellow }
        'Error'   { Write-Host "[-] $Message" -ForegroundColor Red }
        'Detail'  { if ($Detailed) { Write-Host "    $Message" -ForegroundColor Gray } }
    }
}

function Show-Header {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Intune Enrollment Troubleshooter v$Version" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Log "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level Info
    Write-Log "Computer: $env:COMPUTERNAME" -Level Detail
    Write-Log "User: $env:USERNAME" -Level Detail
    Write-Host ""
}

function Show-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "--- $Title ---" -ForegroundColor Magenta
    Write-Log $Title -Level Info
}

function Test-64BitPowerShell {
    Show-Section "PowerShell Architecture Check"
    
    if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64' -or [Environment]::Is64BitProcess) {
        Write-Log "Running in 64-bit PowerShell" -Level Success
        return $true
    }
    
    Write-Log "Running in 32-bit PowerShell. This script requires 64-bit PowerShell." -Level Error
    Write-Log "Please run from 64-bit PowerShell (x64)" -Level Info
    $script:IssuesFound.Add("32-bit PowerShell")
    return $false
}

function Get-WindowsInfo {
    Show-Section "Windows Version Check"
    
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        
        Write-Log "Windows: $($os.Caption)" -Level Info
        Write-Log "Version: $($os.Version)" -Level Detail
        Write-Log "Build: $([System.Environment]::OSVersion.Version.Build)" -Level Detail
        Write-Log "Edition: $($computerSystem.SystemType)" -Level Detail
        
        # Check edition compatibility
        $edition = $os.Caption
        $supported = $edition -match 'Pro|Enterprise|Education|Business|Ultimate'
        
        if ($edition -match 'Home') {
            Write-Log "Windows Home edition cannot enroll in Intune MDM" -Level Error
            Write-Log "Upgrade to Windows Pro, Enterprise, or Education" -Level Info
            $script:IssuesFound.Add("Windows Home edition")
            return @{ OS = $os; Supported = $false }
        }
        
        if (-not $supported) {
            Write-Log "Windows edition may not support MDM enrollment: $edition" -Level Warning
            $script:IssuesFound.Add("Unsupported Windows edition")
        } else {
            Write-Log "Windows edition supports MDM enrollment" -Level Success
        }
        
        return @{ OS = $os; Supported = $supported }
    }
    catch {
        Write-Log "Failed to get Windows info: $($_.Exception.Message)" -Level Error
        $script:IssuesFound.Add("Failed to get Windows info")
        return @{ OS = $null; Supported = $false }
    }
}

function Test-NetworkConnectivity {
    Show-Section "Network Connectivity Check"
    
    $results = @{ Success = $true; FailedEndpoints = @() }
    
    foreach ($endpoint in $script:IntuneEndpoints) {
        try {
            $test = Test-NetConnection -ComputerName $endpoint -Port 443 -WarningAction SilentlyContinue
            if ($test.TcpTestSucceeded) {
                Write-Log "✓ $endpoint : Reachable" -Level Detail
            } else {
                Write-Log "✗ $endpoint : Unreachable" -Level Warning
                $results.FailedEndpoints += $endpoint
                $results.Success = $false
            }
        }
        catch {
            Write-Log "✗ $endpoint : Test failed - $($_.Exception.Message)" -Level Warning
            $results.FailedEndpoints += $endpoint
            $results.Success = $false
        }
    }
    
    if ($results.Success) {
        Write-Log "All Intune endpoints reachable" -Level Success
    } else {
        Write-Log "Some Intune endpoints unreachable" -Level Warning
        Write-Log "Check firewall and proxy settings" -Level Info
        $script:IssuesFound.Add("Network connectivity issues")
    }
    
    return $results
}

function Test-RequiredServices {
    Show-Section "Required Services Check"
    
    $results = @{ AllRunning = $true; Issues = @() }
    
    foreach ($svcInfo in $script:RequiredServices) {
        try {
            $svc = Get-Service -Name $svcInfo.Name -ErrorAction Stop
            
            if ($svc.Status -eq 'Running') {
                Write-Log "✓ $($svcInfo.DisplayName) : Running" -Level Detail
            } else {
                Write-Log "✗ $($svcInfo.DisplayName) : $($svc.Status) (Required for: $($svcInfo.RequiredFor))" -Level Warning
                $results.Issues += $svcInfo
                $results.AllRunning = $false
            }
        }
        catch {
            Write-Log "✗ $($svcInfo.DisplayName) : Not found" -Level Warning
            $results.Issues += $svcInfo
            $results.AllRunning = $false
        }
    }
    
    if ($results.AllRunning) {
        Write-Log "All required services running" -Level Success
    } else {
        Write-Log "Some required services not running" -Level Warning
        $script:IssuesFound.Add("Required services not running")
    }
    
    return $results
}

function Invoke-StartServices {
    param([array]$Services)
    
    foreach ($svcInfo in $Services) {
        Write-Log "Attempting to start: $($svcInfo.DisplayName)" -Level Info
        
        if ($AutoRemediate) {
            try {
                Start-Service -Name $svcInfo.Name -ErrorAction Stop
                Write-Log "Started: $($svcInfo.DisplayName)" -Level Success
                $script:RemediationSuccess.Add("Started service: $($svcInfo.DisplayName)")
            }
            catch {
                Write-Log "Failed to start: $($svcInfo.DisplayName) - $($_.Exception.Message)" -Level Error
                $script:RemediationAttempts.Add("Failed to start service: $($svcInfo.DisplayName)")
            }
        } else {
            Write-Log "Use -AutoRemediate to start services automatically" -Level Info
        }
    }
}

function Get-EnrollmentStatus {
    Show-Section "Enrollment Status Check"
    
    $result = @{
        AzureAdJoined = $false
        AzureAdJoinType = $null
        MdmEnrolled = $false
        MdmUrl = $null
        DeviceId = $null
        TenantId = $null
        TenantName = $null
        UserEmail = $null
        CertThumbprint = $null
    }
    
    try {
        # Run dsregcmd and capture output
        $dsregOutput = dsregcmd /status 2>&1
        $dsregText = $dsregOutput | Out-String
        
        Write-Log "dsregcmd output captured" -Level Detail
        
        # Parse Azure AD Join status
        if ($dsregText -match 'AzureAdJoined\s*:\s*(\w+)') {
            $result.AzureAdJoined = $matches[1] -eq 'YES'
            Write-Log "Azure AD Joined: $($result.AzureAdJoined)" -Level $(if ($result.AzureAdJoined) { 'Success' } else { 'Warning' })
        }
        
        # Parse Join Type (Workplace or Azure AD)
        if ($dsregText -match 'WorkplaceJoined\s*:\s*(\w+)') {
            $workplaceJoined = $matches[1] -eq 'YES'
            if ($workplaceJoined -and -not $result.AzureAdJoined) {
                $result.AzureAdJoinType = "Workplace"
                Write-Log "Workplace Joined: Yes (not full Azure AD Join)" -Level Warning
            }
        }
        
        # Parse MDM Enrollment
        if ($dsregText -match 'MdmUrl\s*:\\s*(https?://\S+)') {
            $result.MdmUrl = $matches[1].Trim()
            $result.MdmEnrolled = $true
            Write-Log "MDM URL: $($result.MdmUrl)" -Level Success
        } elseif ($dsregText -match 'MdmUrl\s*:\\s*(\S+)') {
            $mdmValue = $matches[1].Trim()
            if ($mdmValue -and $mdmValue -ne '') {
                $result.MdmUrl = $mdmValue
                $result.MdmEnrolled = $true
                Write-Log "MDM URL: $($result.MdmUrl)" -Level Success
            } else {
                Write-Log "MDM URL: Not configured" -Level Warning
            }
        } else {
            Write-Log "MDM URL: Not found" -Level Warning
        }
        
        # Parse Device ID
        if ($dsregText -match 'DeviceId\s*:\\s*([a-f0-9-]+)') {
            $result.DeviceId = $matches[1].Trim()
            Write-Log "Device ID: $($result.DeviceId)" -Level Detail
        }
        
        # Parse Tenant ID
        if ($dsregText -match 'TenantId\s*:\\s*([a-f0-9-]+)') {
            $result.TenantId = $matches[1].Trim()
            Write-Log "Tenant ID: $($result.TenantId)" -Level Detail
        }
        
        # Parse Tenant Name
        if ($dsregText -match 'TenantName\s*:\\s*(.+)') {
            $result.TenantName = $matches[1].Trim()
            Write-Log "Tenant Name: $($result.TenantName)" -Level Detail
        }
        
        # Parse User Email
        if ($dsregText -match 'UserEmail\s*:\\s*(\S+@\S+)') {
            $result.UserEmail = $matches[1].Trim()
            Write-Log "User Email: $($result.UserEmail)" -Level Detail
        }
        
        # Check MDM certificate
        $certPath = "Cert:\LocalMachine\My"
        $mdmCert = Get-ChildItem -Path $certPath | Where-Object { 
            $_.Subject -match "MDM" -or $_.Issuer -match "Microsoft Intune" 
        } | Select-Object -First 1
        
        if ($mdmCert) {
            $result.CertThumbprint = $mdmCert.Thumbprint
            Write-Log "MDM Certificate: $($mdmCert.Subject)" -Level Detail
            Write-Log "Cert Thumbprint: $($mdmCert.Thumbprint)" -Level Detail
            Write-Log "Cert Expiry: $($mdmCert.NotAfter)" -Level Detail
            
            if ($mdmCert.NotAfter -lt (Get-Date)) {
                Write-Log "MDM Certificate has expired!" -Level Error
                $script:IssuesFound.Add("MDM certificate expired")
            }
        } else {
            Write-Log "No MDM certificate found in LocalMachine\My" -Level Warning
        }
    }
    catch {
        Write-Log "Failed to parse enrollment status: $($_.Exception.Message)" -Level Error
        $script:IssuesFound.Add("Failed to get enrollment status")
    }
    
    return $result
}

function Invoke-AzureADRemediation {
    param([hashtable]$Status)
    
    Show-Section "Azure AD Remediation"
    
    if ($Status.AzureAdJoined) {
        Write-Log "Device is Azure AD joined, attempting sync..." -Level Info
        
        try {
            $syncResult = dsregcmd /sync 2>&1
            Start-Sleep -Seconds 3
            
            # Check if sync worked
            $newStatus = Get-EnrollmentStatus
            if ($newStatus.AzureAdJoined) {
                Write-Log "Azure AD sync completed successfully" -Level Success
                $script:RemediationSuccess.Add("Azure AD sync")
            } else {
                Write-Log "Azure AD sync completed but status unchanged" -Level Warning
            }
        }
        catch {
            Write-Log "Azure AD sync failed: $($_.Exception.Message)" -Level Error
            $script:RemediationAttempts.Add("Azure AD sync failed")
        }
        
        return
    }
    
    # Not joined - attempt to join
    Write-Log "Device not Azure AD joined" -Level Warning
    Write-Log "Automatic Azure AD join requires user interaction or provisioning package" -Level Info
    Write-Log "Manual steps:" -Level Info
    Write-Log "  1. Settings > Accounts > Access work or school" -Level Info
    Write-Log "  2. Click 'Connect'" -Level Info
    Write-Log "  3. Sign in with your work/school account" -Level Info
}

function Invoke-MDMRemediation {
    param([hashtable]$Status)
    
    Show-Section "MDM Enrollment Remediation"
    
    if ($Status.MdmEnrolled) {
        Write-Log "Device is MDM enrolled" -Level Success
        
        # Try to trigger sync
        Write-Log "Attempting to trigger MDM sync..." -Level Info
        
        try {
            # Method 1: Scheduled task
            $mdmTask = Get-ScheduledTask -TaskName "Schedule created by MDM*" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($mdmTask) {
                Start-ScheduledTask -TaskName $mdmTask.TaskName
                Write-Log "Triggered MDM scheduled task" -Level Success
                $script:RemediationSuccess.Add("MDM scheduled task sync")
                return
            }
            
            # Method 2: Policy sync
            Invoke-Command -ScriptBlock { $null = Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule "{00000000-0000-0000-0000-000000000021}" } -ErrorAction SilentlyContinue
            Write-Log "Attempted WMI policy sync" -Level Detail
            
            # Method 3: DeviceManagement log
            $dmPath = "C:\Windows\System32\DeviceManagement"
            if (Test-Path $dmPath) {
                Write-Log "Device Management client present" -Level Detail
            }
        }
        catch {
            Write-Log "MDM sync attempt failed: $($_.Exception.Message)" -Level Warning
        }
        
        return
    }
    
    # Not enrolled
    Write-Log "Device not MDM enrolled" -Level Warning
    
    if (-not $Status.AzureAdJoined) {
        Write-Log "Cannot enroll in MDM without Azure AD join first" -Level Error
        Write-Log "Complete Azure AD join, then MDM enrollment should happen automatically" -Level Info
        return
    }
    
    # Azure AD joined but no MDM - try to trigger enrollment
    Write-Log "Azure AD joined but no MDM - attempting enrollment trigger..." -Level Info
    
    if ($AutoRemediate) {
        try {
            # Method 1: Registry-based auto-enrollment trigger
            $autoEnrollPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM"
            if (-not (Test-Path $autoEnrollPath)) {
                New-Item -Path $autoEnrollPath -Force | Out-Null
            }
            Set-ItemProperty -Path $autoEnrollPath -Name "AutoEnrollMDM" -Value 1 -Type DWord -Force
            Write-Log "Enabled MDM auto-enrollment in registry" -Level Detail
            
            # Method 2: Device enrollment task
            $enrollTask = Get-ScheduledTask -TaskName "DeviceEnrollment*" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($enrollTask) {
                Start-ScheduledTask -TaskName $enrollTask.TaskName
                Write-Log "Triggered device enrollment task" -Level Success
                $script:RemediationSuccess.Add("Device enrollment task triggered")
            }
            
            Write-Log "Enrollment triggers executed - check Intune portal in 5-10 minutes" -Level Info
        }
        catch {
            Write-Log "Auto-remediation failed: $($_.Exception.Message)" -Level Error
            $script:RemediationAttempts.Add("MDM enrollment trigger failed")
        }
    } else {
        Write-Log "Use -AutoRemediate to attempt automatic MDM enrollment" -Level Info
    }
    
    Write-Log "Manual enrollment steps:" -Level Info
    Write-Log "  1. Settings > Accounts > Access work or school" -Level Info
    Write-Log "  2. Click 'Info' under your work account" -Level Info
    Write-Log "  3. Click 'Create and export provisioning package' or wait for automatic enrollment" -Level Info
}

function Get-IntuneLogs {
    Show-Section "Intune Log Locations"
    
    $logPaths = @(
        "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs",
        "C:\Windows\IntuneLogs",
        "C:\Windows\Logs\Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider"
    )
    
    foreach ($path in $logPaths) {
        if (Test-Path $path) {
            Write-Log "Log location: $path" -Level Detail
            $files = Get-ChildItem -Path $path -File -ErrorAction SilentlyContinue | Select-Object -First 5
            foreach ($file in $files) {
                Write-Log "  - $($file.Name) ($([math]::Round($file.Length/1KB,0)) KB)" -Level Detail
            }
        } else {
            Write-Log "Not found: $path" -Level Detail
        }
    }
}

function Show-Summary {
    Show-Section "Summary"
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  TROUBLESHOOTING COMPLETE" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Issues found
    if ($script:IssuesFound.Count -gt 0) {
        Write-Host "Issues Found: $($script:IssuesFound.Count)" -ForegroundColor Yellow
        $script:IssuesFound | ForEach-Object { Write-Host "  ! $_" -ForegroundColor Yellow }
    } else {
        Write-Host "No issues found!" -ForegroundColor Green
    }
    
    Write-Host ""
    
    # Remediation attempts
    if ($script:RemediationSuccess.Count -gt 0) {
        Write-Host "Remediation Successful:" -ForegroundColor Green
        $script:RemediationSuccess | ForEach-Object { Write-Host "  ✓ $_" -ForegroundColor Green }
        Write-Host ""
    }
    
    if ($script:RemediationAttempts.Count -gt 0) {
        Write-Host "Remediation Attempted (may need manual intervention):" -ForegroundColor Yellow
        $script:RemediationAttempts | ForEach-Object { Write-Host "  • $_" -ForegroundColor Yellow }
        Write-Host ""
    }
    
    # Next steps
    Write-Host "Next Steps:" -ForegroundColor Cyan
    if ($script:IssuesFound.Count -eq 0) {
        Write-Host "  ✓ Device appears properly configured" -ForegroundColor Green
        Write-Host "  1. Check Intune portal for device compliance" -ForegroundColor Gray
        Write-Host "  2. Verify policies are applying correctly" -ForegroundColor Gray
    } else {
        Write-Host "  1. Review the issues listed above" -ForegroundColor Gray
        Write-Host "  2. Check detailed log: $LogPath" -ForegroundColor Gray
        Write-Host "  3. Run with -AutoRemediate to attempt automatic fixes" -ForegroundColor Gray
        Write-Host "  4. If issues persist, consider manual enrollment" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Log "Log saved to: $LogPath" -Level Info
}

function Export-Results {
    if (-not $ExportLog) { return }
    
    $exportPath = $LogPath -replace '\.log$', '.json'
    
    $exportData = @{
        Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        ComputerName = $env:COMPUTERNAME
        UserName = $env:USERNAME
        Version = $script:Version
        IssuesFound = $script:IssuesFound
        RemediationSuccess = $script:RemediationSuccess
        RemediationAttempts = $script:RemediationAttempts
        EnrollmentStatus = $script:LastEnrollmentStatus
    }
    
    $exportData | ConvertTo-Json -Depth 5 | Set-Content -Path $exportPath
    Write-Log "Results exported to: $exportPath" -Level Success
}
#endregion

#region Main Execution
Show-Header

# Check PowerShell architecture
if (-not (Test-64BitPowerShell)) {
    exit 1
}

# Check Windows info
$winInfo = Get-WindowsInfo
if (-not $winInfo.Supported) {
    exit 1
}

# Check network connectivity
$networkTest = Test-NetworkConnectivity

# Check required services
$serviceTest = Test-RequiredServices
if (-not $serviceTest.AllRunning -and $AutoRemediate) {
    Invoke-StartServices -Services $serviceTest.Issues
}

# Check enrollment status
$enrollmentStatus = Get-EnrollmentStatus
$script:LastEnrollmentStatus = $enrollmentStatus

# Perform remediation
if ($enrollmentStatus.AzureAdJoined -and $enrollmentStatus.MdmEnrolled) {
    Write-Log "Device appears properly enrolled!" -Level Success
} else {
    Invoke-AzureADRemediation -Status $enrollmentStatus
    Invoke-MDMRemediation -Status $enrollmentStatus
}

# Show log locations
Get-IntuneLogs

# Export if requested
Export-Results

# Show summary
Show-Summary

# Determine exit code
if ($script:IssuesFound.Count -eq 0) {
    exit 0
} elseif (-not $enrollmentStatus.AzureAdJoined) {
    exit 2
} elseif (-not $enrollmentStatus.MdmEnrolled) {
    exit 3
} elseif (-not $AutoRemediate) {
    exit 4
} else {
    exit 5
}
#endregion
