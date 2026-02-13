<#
.SYNOPSIS
    Repairs broken or partial Intune/Azure AD device registrations.

.DESCRIPTION
    This script diagnoses and repairs common issues with Intune/Azure AD enrollment
    including partial registrations, stuck states, certificate problems, and
    failed MDM enrollments after Azure AD join.

    Fixes applied:
    - Detects partial registration states (Azure AD joined but not MDM enrolled)
    - Cleans up corrupted registry entries
    - Removes stale certificates
    - Re-triggers MDM auto-enrollment
    - Resets device registration state if needed
    - Forces Group Policy / MDM sync

.PARAMETER AutoFix
    Automatically apply fixes without prompting for each step.

.PARAMETER ResetRegistration
    WARNING: Performs a full reset of device registration. Requires re-enrollment.

.PARAMETER ForceReenroll
    Forces complete unenrollment and re-enrollment (destructive).

.PARAMETER CheckCertificates
    Verify and repair MDM certificate issues.

.PARAMETER TriggerSync
    Force MDM sync after repairs.

.PARAMETER LogPath
    Path to save detailed log file.

.PARAMETER WhatIf
    Show what would be done without making changes.

.EXAMPLE
    .\Repair-IntuneEnrollment.ps1
    Diagnoses and repairs with interactive prompts.

.EXAMPLE
    .\Repair-IntuneEnrollment.ps1 -AutoFix
    Automatically applies all safe fixes.

.EXAMPLE
    .\Repair-IntuneEnrollment.ps1 -ResetRegistration -Force
    Full reset of device registration (requires re-enrollment).

.EXAMPLE
    .\Repair-IntuneEnrollment.ps1 -CheckCertificates -TriggerSync
    Fixes certificate issues and forces sync.

.NOTES
    Version:        1.0
    Author:         IT Admin
    Updated:        2026-02-13
    
    Requirements:
    - Windows 10/11 Pro/Enterprise/Education
    - PowerShell 5.1+ 
    - Administrator rights
    - Internet connectivity to Azure AD/Intune
    
    Exit Codes:
    0   - Repairs successful
    1   - Partial success (some repairs failed)
    2   - Requires manual intervention
    3   - No repairs needed (device healthy)
    4   - Critical failure / needs reset
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$AutoFix,
    [switch]$ResetRegistration,
    [switch]$ForceReenroll,
    [switch]$CheckCertificates,
    [switch]$TriggerSync,
    [string]$LogPath = (Join-Path $env:TEMP "IntuneRepair_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"),
    [switch]$WhatIf
)

#region Configuration
$ErrorActionPreference = 'Continue'
$script:Version = "1.0"
$script:StartTime = Get-Date
$script:IssuesFound = [System.Collections.Generic.List[string]]::new()
$script:FixesApplied = [System.Collections.Generic.List[string]]::new()
$script:FixesFailed = [System.Collections.Generic.List[string]]::new()

# Registry paths
$script:MDMRegistryPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Enrollments',
    'HKLM:\SOFTWARE\Microsoft\Enrollments\Status',
    'HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts',
    'HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Logger',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MDM'
)

$script:AzureADRegistryPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CDJ\AAD'
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
    $line = "[$timestamp] [$Level] $Message"
    
    try {
        Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
    } catch {}
    
    $colors = @{
        Info    = 'Cyan'
        Success = 'Green'
        Warning = 'Yellow'
        Error   = 'Red'
        Detail  = 'Gray'
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
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Intune Enrollment Repair Tool v$Version" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Log "Started: $($script:StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level Detail
    Write-Log "Computer: $env:COMPUTERNAME" -Level Detail
    Write-Log "Log: $LogPath" -Level Detail
    Write-Host ""
}

function Test-AdminRights {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-EnrollmentState {
    $state = @{
        AzureAdJoined = $false
        AzureAdJoinType = $null
        MdmEnrolled = $false
        MdmUrl = $null
        DeviceId = $null
        TenantId = $null
        TenantName = $null
        UserEmail = $null
        CertThumbprint = $null
        CertValid = $false
        EnrollmentStatus = 'Unknown'
        Issues = [System.Collections.Generic.List[string]]::new()
    }
    
    try {
        $dsregOutput = dsregcmd /status 2>&1
        $dsregText = $dsregOutput | Out-String
        
        # Azure AD Join
        if ($dsregText -match 'AzureAdJoined\s*:\s*(\w+)') {
            $state.AzureAdJoined = $matches[1] -eq 'YES'
        }
        
        # Workplace Join
        if ($dsregText -match 'WorkplaceJoined\s*:\s*(\w+)') {
            if ($matches[1] -eq 'YES' -and -not $state.AzureAdJoined) {
                $state.AzureAdJoinType = "Workplace"
                $state.Issues.Add("Device is Workplace joined but not Azure AD joined")
            }
        }
        
        # MDM Enrollment
        if ($dsregText -match 'MdmUrl\s*:\\s*(https?://\S+)') {
            $state.MdmUrl = $matches[1].Trim()
            $state.MdmEnrolled = $true
        } elseif ($dsregText -match 'MdmUrl\s*:\\s*(\S+)') {
            $mdmValue = $matches[1].Trim()
            if ($mdmValue -and $mdmValue -ne '') {
                $state.MdmUrl = $mdmValue
                $state.MdmEnrolled = $true
            }
        }
        
        # Device ID
        if ($dsregText -match 'DeviceId\s*:\\s*([a-f0-9-]+)') {
            $state.DeviceId = $matches[1].Trim()
        }
        
        # Tenant
        if ($dsregText -match 'TenantId\s*:\\s*([a-f0-9-]+)') {
            $state.TenantId = $matches[1].Trim()
        }
        if ($dsregText -match 'TenantName\s*:\\s*(.+)') {
            $state.TenantName = $matches[1].Trim()
        }
        
        # User
        if ($dsregText -match 'UserEmail\s*:\\s*(\S+@\S+)') {
            $state.UserEmail = $matches[1].Trim()
        }
        
        # Check certificate
        $certPath = "Cert:\LocalMachine\My"
        $mdmCert = Get-ChildItem -Path $certPath | Where-Object { 
            $_.Subject -match "MDM" -or $_.Issuer -match "Microsoft Intune" 
        } | Select-Object -First 1
        
        if ($mdmCert) {
            $state.CertThumbprint = $mdmCert.Thumbprint
            $state.CertValid = ($mdmCert.NotAfter -gt (Get-Date)) -and ($mdmCert.NotBefore -lt (Get-Date))
            
            if (-not $state.CertValid) {
                $state.Issues.Add("MDM certificate has expired or is not yet valid")
            }
        } else {
            if ($state.MdmEnrolled) {
                $state.Issues.Add("MDM enrolled but no certificate found")
            }
        }
        
        # Determine enrollment status
        if ($state.AzureAdJoined -and $state.MdmEnrolled -and $state.CertValid) {
            $state.EnrollmentStatus = 'Healthy'
        } elseif ($state.AzureAdJoined -and -not $state.MdmEnrolled) {
            $state.EnrollmentStatus = 'Partial'
            $state.Issues.Add("Azure AD joined but MDM not enrolled (partial registration)")
        } elseif (-not $state.AzureAdJoined -and $state.MdmEnrolled) {
            $state.EnrollmentStatus = 'Orphaned'
            $state.Issues.Add("MDM enrolled but not Azure AD joined (orphaned state)")
        } elseif (-not $state.AzureAdJoined -and -not $state.MdmEnrolled) {
            $state.EnrollmentStatus = 'NotRegistered'
            $state.Issues.Add("Device not enrolled in Azure AD or Intune")
        } else {
            $state.EnrollmentStatus = 'Degraded'
            $state.Issues.Add("Enrollment state degraded - certificate or connectivity issues")
        }
    }
    catch {
        Write-Log "Error checking enrollment state: $($_.Exception.Message)" -Level Error
        $state.Issues.Add("Failed to check enrollment state: $($_.Exception.Message)")
    }
    
    return $state
}

function Show-EnrollmentStatus {
    param([hashtable]$State)
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  ENROLLMENT STATUS" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Log "Azure AD Joined: $($State.AzureAdJoined)" -Level $(if ($State.AzureAdJoined) { 'Success' } else { 'Warning' })
    Write-Log "MDM Enrolled: $($State.MdmEnrolled)" -Level $(if ($State.MdmEnrolled) { 'Success' } else { 'Warning' })
    Write-Log "Certificate Valid: $($State.CertValid)" -Level $(if ($State.CertValid) { 'Success' } else { 'Warning' })
    Write-Log "Overall Status: $($State.EnrollmentStatus)" -Level $(
        switch ($State.EnrollmentStatus) {
            'Healthy' { 'Success' }
            'Partial' { 'Warning' }
            'Orphaned' { 'Error' }
            'Degraded' { 'Warning' }
            default { 'Info' }
        }
    )
    
    if ($State.TenantName) {
        Write-Log "Tenant: $($State.TenantName)" -Level Detail
    }
    if ($State.UserEmail) {
        Write-Log "User: $($State.UserEmail)" -Level Detail
    }
    if ($State.DeviceId) {
        Write-Log "Device ID: $($State.DeviceId)" -Level Detail
    }
    
    if ($State.Issues.Count -gt 0) {
        Write-Host ""
        Write-Log "Issues Found:" -Level Warning
        foreach ($issue in $State.Issues) {
            Write-Log "  - $issue" -Level Warning
            $script:IssuesFound.Add($issue)
        }
    }
    
    Write-Host ""
}

function Repair-MDMRegistry {
    Write-Log "Checking MDM registry entries..." -Level Info
    
    $fixed = $false
    
    # Check MDM auto-enrollment setting
    $mdmPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM'
    if (Test-Path $mdmPath) {
        $autoEnroll = Get-ItemProperty -Path $mdmPath -Name 'AutoEnrollMDM' -ErrorAction SilentlyContinue
        if (-not $autoEnroll -or $autoEnroll.AutoEnrollMDM -ne 1) {
            if ($PSCmdlet.ShouldProcess($mdmPath, "Enable MDM Auto-Enrollment")) {
                try {
                    if (-not (Test-Path $mdmPath)) {
                        New-Item -Path $mdmPath -Force | Out-Null
                    }
                    Set-ItemProperty -Path $mdmPath -Name 'AutoEnrollMDM' -Value 1 -Type DWord -Force
                    Write-Log "Enabled MDM auto-enrollment in registry" -Level Success
                    $script:FixesApplied.Add("Enabled MDM auto-enrollment")
                    $fixed = $true
                }
                catch {
                    Write-Log "Failed to set MDM auto-enrollment: $($_.Exception.Message)" -Level Error
                    $script:FixesFailed.Add("MDM auto-enrollment registry")
                }
            }
        }
    }
    
    # Check for corrupt enrollment entries
    $enrollmentsPath = 'HKLM:\SOFTWARE\Microsoft\Enrollments'
    if (Test-Path $enrollmentsPath) {
        $enrollments = Get-ChildItem -Path $enrollmentsPath -ErrorAction SilentlyContinue | 
            Where-Object { $_.PSChildName -match '^[0-9a-f]{8}-' }
        
        foreach ($enrollment in $enrollments) {
            $props = Get-ItemProperty -Path $enrollment.PSPath -ErrorAction SilentlyContinue
            if ($props -and ($props.PSObject.Properties.Name -contains 'EnrollmentState')) {
                if ($props.EnrollmentState -eq 6) { # 6 = Enrollment failed
                    Write-Log "Found failed enrollment: $($enrollment.PSChildName)" -Level Warning
                    
                    if ($AutoFix -or $PSCmdlet.ShouldProcess($enrollment.PSChildName, "Remove failed enrollment")) {
                        try {
                            Remove-Item -Path $enrollment.PSPath -Recurse -Force
                            Write-Log "Removed failed enrollment entry" -Level Success
                            $script:FixesApplied.Add("Removed failed enrollment: $($enrollment.PSChildName)")
                            $fixed = $true
                        }
                        catch {
                            Write-Log "Failed to remove enrollment: $($_.Exception.Message)" -Level Error
                            $script:FixesFailed.Add("Remove enrollment: $($enrollment.PSChildName)")
                        }
                    }
                }
            }
        }
    }
    
    return $fixed
}

function Repair-MDMCertificates {
    Write-Log "Checking MDM certificates..." -Level Info
    
    $fixed = $false
    $certPath = "Cert:\LocalMachine\My"
    
    # Find expired or invalid MDM certificates
    $mdmCerts = Get-ChildItem -Path $certPath | Where-Object { 
        $_.Subject -match "MDM" -or $_.Issuer -match "Microsoft Intune" 
    }
    
    foreach ($cert in $mdmCerts) {
        if ($cert.NotAfter -lt (Get-Date)) {
            Write-Log "Found expired MDM certificate: $($cert.Thumbprint)" -Level Warning
            
            if ($AutoFix -or $PSCmdlet.ShouldProcess($cert.Thumbprint, "Remove expired certificate")) {
                try {
                    Remove-Item -Path $cert.PSPath -Force
                    Write-Log "Removed expired certificate" -Level Success
                    $script:FixesApplied.Add("Removed expired MDM certificate")
                    $fixed = $true
                }
                catch {
                    Write-Log "Failed to remove certificate: $($_.Exception.Message)" -Level Error
                    $script:FixesFailed.Add("Remove expired certificate")
                }
            }
        }
    }
    
    # Also check and remove from Personal store if needed
    $userCertPath = "Cert:\CurrentUser\My"
    $userMdmCerts = Get-ChildItem -Path $userCertPath | Where-Object { 
        $_.Subject -match "MDM" -or $_.Issuer -match "Microsoft Intune" 
    }
    
    foreach ($cert in $userMdmCerts) {
        if ($cert.NotAfter -lt (Get-Date)) {
            Write-Log "Found expired user MDM certificate: $($cert.Thumbprint)" -Level Warning
            
            if ($AutoFix -or $PSCmdlet.ShouldProcess($cert.Thumbprint, "Remove expired user certificate")) {
                try {
                    Remove-Item -Path $cert.PSPath -Force
                    Write-Log "Removed expired user certificate" -Level Success
                    $script:FixesApplied.Add("Removed expired user MDM certificate")
                    $fixed = $true
                }
                catch {
                    Write-Log "Failed to remove user certificate: $($_.Exception.Message)" -Level Error
                }
            }
        }
    }
    
    return $fixed
}

function Invoke-MDMEnrollmentTrigger {
    Write-Log "Triggering MDM enrollment..." -Level Info
    
    $triggered = $false
    
    # Method 1: Device enrollment scheduled task
    $enrollTask = Get-ScheduledTask -TaskName "DeviceEnrollment*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($enrollTask) {
        try {
            Start-ScheduledTask -TaskName $enrollTask.TaskName
            Write-Log "Triggered device enrollment task" -Level Success
            $script:FixesApplied.Add("Triggered device enrollment task")
            $triggered = $true
        }
        catch {
            Write-Log "Failed to trigger enrollment task: $($_.Exception.Message)" -Level Warning
        }
    }
    
    # Method 2: MDM enrollment URL
    try {
        $enrollUrl = "ms-device-enrollment:?mode=mdm"
        Start-Process $enrollUrl -ErrorAction SilentlyContinue
        Write-Log "Opened MDM enrollment dialog" -Level Info
    }
    catch {
        Write-Log "Failed to open enrollment dialog: $($_.Exception.Message)" -Level Warning
    }
    
    # Method 3: Auto-enrollment via settings
    try {
        $settingsPath = "ms-settings:workplace"
        Start-Process $settingsPath -ErrorAction SilentlyContinue
    }
    catch {}
    
    return $triggered
}

function Invoke-AzureADSync {
    Write-Log "Syncing Azure AD registration..." -Level Info
    
    try {
        $result = dsregcmd /sync 2>&1
        Start-Sleep -Seconds 5
        
        # Check if sync worked
        $newStatus = Get-EnrollmentState
        if ($newStatus.AzureAdJoined) {
            Write-Log "Azure AD sync completed successfully" -Level Success
            $script:FixesApplied.Add("Azure AD sync")
            return $true
        } else {
            Write-Log "Azure AD sync completed but status unchanged" -Level Warning
            return $false
        }
    }
    catch {
        Write-Log "Azure AD sync failed: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Reset-DeviceRegistration {
    param([switch]$Force)
    
    Write-Log "WARNING: This will reset device registration completely!" -Level Error
    Write-Log "Device will need to be re-enrolled in Azure AD and Intune!" -Level Error
    
    if (-not $Force) {
        $confirm = Read-Host "Are you sure you want to reset device registration? Type 'RESET' to confirm"
        if ($confirm -ne 'RESET') {
            Write-Log "Reset cancelled by user" -Level Info
            return $false
        }
    }
    
    Write-Log "Resetting device registration..." -Level Info
    
    try {
        # Leave Azure AD
        $leaveResult = dsregcmd /leave 2>&1
        Write-Log "Left Azure AD" -Level Info
        
        # Clear enrollment data
        $enrollmentsPath = 'HKLM:\SOFTWARE\Microsoft\Enrollments'
        if (Test-Path $enrollmentsPath) {
            Remove-Item -Path $enrollmentsPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Cleared enrollment registry" -Level Success
        }
        
        # Clear certificates
        $certPaths = @("Cert:\LocalMachine\My", "Cert:\CurrentUser\My")
        foreach ($certPath in $certPaths) {
            $mdmCerts = Get-ChildItem -Path $certPath | Where-Object { 
                $_.Subject -match "MDM|AzureAD|Microsoft" 
            }
            foreach ($cert in $mdmCerts) {
                Remove-Item -Path $cert.PSPath -Force -ErrorAction SilentlyContinue
            }
        }
        Write-Log "Cleared MDM certificates" -Level Success
        
        $script:FixesApplied.Add("Complete device registration reset")
        
        Write-Log "Device registration reset complete" -Level Success
        Write-Log "You must re-enroll this device in Azure AD/Intune manually!" -Level Warning
        Write-Log "Go to Settings > Accounts > Access work or school > Connect" -Level Info
        
        return $true
    }
    catch {
        Write-Log "Reset failed: $($_.Exception.Message)" -Level Error
        $script:FixesFailed.Add("Device registration reset")
        return $false
    }
}

function Invoke-MDMSync {
    Write-Log "Triggering MDM policy sync..." -Level Info
    
    try {
        # Method 1: Scheduled task
        $mdmTask = Get-ScheduledTask -TaskName "Schedule created by MDM*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($mdmTask) {
            Start-ScheduledTask -TaskName $mdmTask.TaskName
            Write-Log "Triggered MDM scheduled task" -Level Success
        }
        
        # Method 2: WMI
        Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule "{00000000-0000-0000-0000-000000000021}" -ErrorAction SilentlyContinue | Out-Null
        
        # Method 3: Settings sync
        $syncPath = "ms-settings:sync"
        Start-Process $syncPath -ErrorAction SilentlyContinue
        
        $script:FixesApplied.Add("Triggered MDM sync")
        return $true
    }
    catch {
        Write-Log "MDM sync trigger failed: $($_.Exception.Message)" -Level Warning
        return $false
    }
}
#endregion

#region Main Execution
Show-Header

# Check admin rights
if (-not (Test-AdminRights)) {
    Write-Log "This script requires Administrator privileges!" -Level Error
    Write-Log "Please run PowerShell as Administrator and try again." -Level Warning
    exit 2
}

# Get current enrollment state
Write-Log "Analyzing current enrollment state..." -Level Info
$enrollmentState = Get-EnrollmentState
Show-EnrollmentStatus -State $enrollmentState

# If healthy, exit early
if ($enrollmentState.EnrollmentStatus -eq 'Healthy' -and -not $ResetRegistration -and -not $ForceReenroll) {
    Write-Log "Device enrollment is healthy! No repairs needed." -Level Success
    
    if ($TriggerSync) {
        Invoke-MDMSync
    }
    
    exit 3
}

# Perform repairs based on state
if ($ResetRegistration -or $ForceReenroll) {
    # Full reset
    $resetResult = Reset-DeviceRegistration -Force:$ForceReenroll
    
    if ($resetResult) {
        exit 0
    } else {
        exit 4
    }
}

# Apply fixes
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  APPLYING REPAIRS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Fix 1: Registry repairs
if ($enrollmentState.EnrollmentStatus -eq 'Partial' -or $enrollmentState.EnrollmentStatus -eq 'Degraded') {
    Repair-MDMRegistry | Out-Null
}

# Fix 2: Certificate repairs
if ($CheckCertificates -or $enrollmentState.Issues -match 'certificate') {
    Repair-MDMCertificates | Out-Null
}

# Fix 3: Azure AD sync
if ($enrollmentState.AzureAdJoined -and $enrollmentState.EnrollmentStatus -ne 'Healthy') {
    Invoke-AzureADSync | Out-Null
}

# Fix 4: Trigger MDM enrollment
if ($enrollmentState.AzureAdJoined -and -not $enrollmentState.MdmEnrolled) {
    Invoke-MDMEnrollmentTrigger | Out-Null
}

# Fix 5: Final sync
if ($TriggerSync -or $script:FixesApplied.Count -gt 0) {
    Start-Sleep -Seconds 10
    Invoke-MDMSync | Out-Null
}

# Re-check state
Write-Host ""
Write-Log "Re-checking enrollment state..." -Level Info
Start-Sleep -Seconds 5
$newState = Get-EnrollmentState
Show-EnrollmentStatus -State $newState

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  REPAIR SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Log "Issues Found: $($script:IssuesFound.Count)" -Level Info
Write-Log "Fixes Applied: $($script:FixesApplied.Count)" -Level $(if ($script:FixesApplied.Count -gt 0) { 'Success' } else { 'Info' })
Write-Log "Fixes Failed: $($script:FixesFailed.Count)" -Level $(if ($script:FixesFailed.Count -gt 0) { 'Error' } else { 'Success' })

if ($script:FixesApplied.Count -gt 0) {
    Write-Host ""
    Write-Log "Applied Fixes:" -Level Success
    foreach ($fix in $script:FixesApplied) {
        Write-Log "  + $fix" -Level Success
    }
}

if ($script:FixesFailed.Count -gt 0) {
    Write-Host ""
    Write-Log "Failed Fixes:" -Level Error
    foreach ($fix in $script:FixesFailed) {
        Write-Log "  - $fix" -Level Error
    }
}

Write-Host ""
Write-Log "Log saved: $LogPath" -Level Info

# Exit code
if ($newState.EnrollmentStatus -eq 'Healthy') {
    Write-Log "Device enrollment is now healthy!" -Level Success
    exit 0
} elseif ($newState.EnrollmentStatus -ne $enrollmentState.EnrollmentStatus -or $script:FixesApplied.Count -gt 0) {
    Write-Log "Partial repairs completed. Reboot may be required." -Level Warning
    exit 1
} else {
    Write-Log "Repairs failed. Manual intervention or reset may be required." -Level Error
    exit 4
}
#endregion
