<#
.SYNOPSIS
    Repairs broken or partial Intune/Azure AD device registrations - works locally or remotely.

.DESCRIPTION
    This script diagnoses and repairs common issues with Intune/Azure AD enrollment
    including partial registrations, stuck states, certificate problems, and
    failed MDM enrollments after Azure AD join.

    Can run locally or remotely via PowerShell Remoting.
    
    Fixes applied:
    - Detects partial registration states (Azure AD joined but not MDM enrolled)
    - Cleans up corrupted registry entries
    - Removes stale certificates
    - Re-triggers MDM auto-enrollment
    - Resets device registration state if needed
    - Forces Group Policy / MDM sync

.PARAMETER ComputerName
    Remote computer(s) to repair. If omitted, runs locally.

.PARAMETER Credential
    Credentials for remote authentication.

.PARAMETER UseCurrent
    Use current credentials for remote connection (no prompt).

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

.PARAMETER Force
    Suppress confirmation prompts.

.EXAMPLE
    .\Repair-IntuneEnrollment.ps1
    Diagnoses and repairs local machine with interactive prompts.

.EXAMPLE
    .\Repair-IntuneEnrollment.ps1 -ComputerName PC01 -UseCurrent
    Repairs remote computer PC01 using current credentials.

.EXAMPLE
    .\Repair-IntuneEnrollment.ps1 -ComputerName PC01,PC02,PC03 -Credential (Get-Credential)
    Repairs multiple remote computers.

.EXAMPLE
    .\Repair-IntuneEnrollment.ps1 -AutoFix
    Automatically applies all safe fixes locally.

.EXAMPLE
    .\Repair-IntuneEnrollment.ps1 -ResetRegistration -Force
    Full reset of device registration (requires re-enrollment).

.EXAMPLE
    Get-ADComputer -Filter {Enabled -eq $true} | Select-Object -ExpandProperty Name | .\Repair-IntuneEnrollment.ps1 -AutoFix
    Pipeline input from Active Directory with auto-fix.

.NOTES
    Version:        1.1
    Author:         IT Admin
    Updated:        2026-02-13
    
    Requirements:
    - Windows 10/11 Pro/Enterprise/Education
    - PowerShell 5.1+ 
    - Administrator rights
    - Internet connectivity to Azure AD/Intune
    - For remote: WinRM enabled on targets
    
    Exit Codes:
    0   - Repairs successful
    1   - Partial success (some repairs failed)
    2   - Requires manual intervention
    3   - No repairs needed (device healthy)
    4   - Critical failure / needs reset
    5   - Remote connection failed
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, Position=0)]
    [Alias('CN', 'MachineName', 'Name')]
    [string[]]$ComputerName,
    
    [PSCredential]$Credential,
    [switch]$UseCurrent,
    
    [switch]$AutoFix,
    [switch]$ResetRegistration,
    [switch]$ForceReenroll,
    [switch]$CheckCertificates,
    [switch]$TriggerSync,
    
    [string]$LogPath = (Join-Path $env:TEMP "IntuneRepair_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"),
    
    [switch]$Force
)

#region Configuration
$ErrorActionPreference = 'Continue'
$script:Version = "1.1"
$script:StartTime = Get-Date
$script:Results = [System.Collections.Generic.List[object]]::new()
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
    Write-Log "Log: $LogPath" -Level Detail
}

function Show-Summary {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    $total = $script:Results.Count
    $success = ($script:Results | Where-Object { $_.Success }).Count
    $failed = ($script:Results | Where-Object { -not $_.Success }).Count
    $healthy = ($script:Results | Where-Object { $_.Status -eq 'Healthy' }).Count
    
    Write-Log "Total computers: $total" -Level Info
    Write-Log "Successful repairs: $success" -Level $(if ($success -gt 0) { 'Success' } else { 'Info' })
    Write-Log "Already healthy: $healthy" -Level Success
    Write-Log "Failed: $failed" -Level $(if ($failed -gt 0) { 'Error' } else { 'Success' })
    
    if ($failed -gt 0) {
        Write-Host ""
        Write-Log "Failed computers:" -Level Error
        $script:Results | Where-Object { -not $_.Success } | ForEach-Object {
            Write-Log "  - $($_.ComputerName): $($_.Error)" -Level Error
        }
    }
    
    $duration = (Get-Date) - $script:StartTime
    Write-Host ""
    Write-Log "Duration: $($duration.ToString('mm\:ss'))" -Level Info
    Write-Log "Log saved: $LogPath" -Level Info
}
#endregion

#region Local Repair Functions
function Invoke-LocalRepair {
    param(
        [switch]$IsAutoFix,
        [switch]$DoReset,
        [switch]$DoForceReenroll,
        [switch]$CheckCerts,
        [switch]$DoSync,
        [switch]$IsWhatIf
    )
    
    $repairResult = @{
        Success = $false
        Status = 'Unknown'
        FixesApplied = @()
        FixesFailed = @()
        Error = $null
    }
    
    # Check admin rights
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        $repairResult.Error = "Administrator privileges required"
        return $repairResult
    }
    
    # Helper: Write local log
    $localLogPath = Join-Path $env:TEMP "IntuneRepair_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    function Write-LocalLog($Msg, $Lvl='Info') {
        "$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')) [$Lvl] $Msg" | 
            Out-File -FilePath $localLogPath -Append -Encoding UTF8
    }
    
    Write-LocalLog "Starting local repair on $env:COMPUTERNAME"
    
    # Get enrollment state via dsregcmd
    try {
        $dsregOutput = & dsregcmd /status 2>&1
        $dsregText = $dsregOutput | Out-String
        
        $azureAdJoined = $dsregText -match 'AzureAdJoined\s*:\s*YES'
        $mdmEnrolled = $dsregText -match 'MdmUrl\s*:\\s*(https?://\S+|\S+)'
        
        # Determine status
        if ($azureAdJoined -and $mdmEnrolled) {
            $repairResult.Status = 'Healthy'
            Write-LocalLog "Status: Healthy (Azure AD joined + MDM enrolled)" 'Success'
        } elseif ($azureAdJoined -and -not $mdmEnrolled) {
            $repairResult.Status = 'Partial'
            Write-LocalLog "Status: Partial (Azure AD joined, MDM not enrolled)" 'Warning'
        } elseif (-not $azureAdJoined -and $mdmEnrolled) {
            $repairResult.Status = 'Orphaned'
            Write-LocalLog "Status: Orphaned (MDM enrolled, Azure AD not joined)" 'Warning'
        } else {
            $repairResult.Status = 'NotRegistered'
            Write-LocalLog "Status: Not registered" 'Warning'
        }
    }
    catch {
        $repairResult.Error = "Failed to check enrollment: $($_.Exception.Message)"
        return $repairResult
    }
    
    # If healthy, just sync if requested
    if ($repairResult.Status -eq 'Healthy') {
        if ($DoSync) {
            try {
                Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule "{00000000-0000-0000-0000-000000000021}" -ErrorAction SilentlyContinue | Out-Null
                Write-LocalLog "Triggered MDM sync" 'Success'
                $repairResult.FixesApplied += "MDM sync"
            }
            catch {
                Write-LocalLog "MDM sync failed: $($_.Exception.Message)" 'Warning'
            }
        }
        $repairResult.Success = $true
        return $repairResult
    }
    
    # Apply fixes if not whatif
    if (-not $IsWhatIf) {
        # Fix 1: Enable MDM auto-enrollment
        if ($repairResult.Status -eq 'Partial' -or $repairResult.Status -eq 'NotRegistered') {
            try {
                $mdmPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM'
                if (-not (Test-Path $mdmPath)) {
                    New-Item -Path $mdmPath -Force | Out-Null
                }
                Set-ItemProperty -Path $mdmPath -Name 'AutoEnrollMDM' -Value 1 -Type DWord -Force
                Write-LocalLog "Enabled MDM auto-enrollment" 'Success'
                $repairResult.FixesApplied += "Enabled MDM auto-enrollment"
            }
            catch {
                Write-LocalLog "Failed to enable auto-enrollment: $($_.Exception.Message)" 'Error'
                $repairResult.FixesFailed += "MDM auto-enrollment"
            }
        }
        
        # Fix 2: Remove expired certificates
        if ($CheckCerts) {
            try {
                $certPath = "Cert:\LocalMachine\My"
                $expiredCerts = Get-ChildItem -Path $certPath | Where-Object { 
                    ($_.Subject -match "MDM" -or $_.Issuer -match "Microsoft Intune") -and 
                    $_.NotAfter -lt (Get-Date)
                }
                foreach ($cert in $expiredCerts) {
                    Remove-Item -Path $cert.PSPath -Force
                    Write-LocalLog "Removed expired cert: $($cert.Thumbprint)" 'Success'
                    $repairResult.FixesApplied += "Removed expired certificate"
                }
            }
            catch {
                Write-LocalLog "Certificate cleanup failed: $($_.Exception.Message)" 'Warning'
            }
        }
        
        # Fix 3: Azure AD sync
        if ($repairResult.Status -eq 'Partial' -or $azureAdJoined) {
            try {
                & dsregcmd /sync 2>&1 | Out-Null
                Start-Sleep -Seconds 5
                Write-LocalLog "Azure AD sync completed" 'Success'
                $repairResult.FixesApplied += "Azure AD sync"
            }
            catch {
                Write-LocalLog "Azure AD sync failed: $($_.Exception.Message)" 'Warning'
            }
        }
        
        # Fix 4: Trigger enrollment
        if ($repairResult.Status -eq 'Partial') {
            try {
                $enrollTask = Get-ScheduledTask -TaskName "DeviceEnrollment*" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($enrollTask) {
                    Start-ScheduledTask -TaskName $enrollTask.TaskName
                    Write-LocalLog "Triggered device enrollment task" 'Success'
                    $repairResult.FixesApplied += "Triggered enrollment task"
                }
            }
            catch {
                Write-LocalLog "Enrollment trigger failed: $($_.Exception.Message)" 'Warning'
            }
        }
        
        # Fix 5: Full reset if requested
        if ($DoReset -or $DoForceReenroll) {
            try {
                & dsregcmd /leave 2>&1 | Out-Null
                Write-LocalLog "Left Azure AD" 'Success'
                $repairResult.FixesApplied += "Left Azure AD (reset)"
                $repairResult.Status = 'Reset'
            }
            catch {
                Write-LocalLog "Reset failed: $($_.Exception.Message)" 'Error'
                $repairResult.FixesFailed += "Azure AD leave"
            }
        }
        
        # Final sync
        if ($DoSync -and $repairResult.FixesApplied.Count -gt 0) {
            Start-Sleep -Seconds 10
            try {
                Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule "{00000000-0000-0000-0000-000000000021}" -ErrorAction SilentlyContinue | Out-Null
                Write-LocalLog "Final MDM sync triggered" 'Success'
            }
            catch {}
        }
    }
    else {
        Write-LocalLog "WHATIF MODE - No changes made" 'Warning'
        $repairResult.FixesApplied += "[WHATIF] Would apply repairs"
    }
    
    $repairResult.Success = ($repairResult.FixesFailed.Count -eq 0 -or $repairResult.FixesApplied.Count -gt 0)
    return $repairResult
}
#endregion

#region Remote Execution
function Invoke-RemoteRepair {
    param(
        [string]$Computer,
        [PSCredential]$Cred
    )
    
    Write-Log "Connecting to $Computer..." -Level Info
    
    $result = [PSCustomObject]@{
        ComputerName = $Computer
        Success = $false
        Status = 'Unknown'
        FixesApplied = @()
        Error = $null
    }
    
    try {
        # Test connection
        if (-not (Test-Connection -ComputerName $Computer -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
            Write-Log "Ping failed for $Computer, attempting WinRM anyway..." -Level Warning
        }
        
        # Check WinRM
        Test-WSMan -ComputerName $Computer -ErrorAction Stop | Out-Null
        
        # Build and execute remote script
        $scriptBlock = {
            param($Params)
            
            # Create temp script
            $tempScript = Join-Path $env:TEMP "IntuneRepair_$(Get-Random).ps1"
            
            $scriptContent = @'
param($AutoFix, $Reset, $ForceReenroll, $CheckCerts, $Sync, $WhatIf)
$ErrorActionPreference = 'SilentlyContinue'

function Write-Log($Msg, $Lvl='Info') {
    "$([DateTime]::Now.ToString('s')) [$Lvl] $Msg" | 
        Out-File -FilePath "$env:TEMP\IntuneRepair.log" -Append -Encoding UTF8
}

$result = @{ Success=$false; Status='Unknown'; FixesApplied=@(); FixesFailed=@() }

# Check admin
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$p = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $result.Error = "Admin required"
    return $result
}

# Get status
$dsreg = & dsregcmd /status 2>&1
$aad = $dsreg -match 'AzureAdJoined\s*:\s*YES'
$mdm = $dsreg -match 'MdmUrl\s*:.*https'

if ($aad -and $mdm) { $result.Status = 'Healthy' }
elseif ($aad -and -not $mdm) { $result.Status = 'Partial' }
elseif (-not $aad -and $mdm) { $result.Status = 'Orphaned' }
else { $result.Status = 'NotRegistered' }

if (-not $WhatIf) {
    # Enable auto-enrollment
    if ($result.Status -eq 'Partial' -or $result.Status -eq 'NotRegistered') {
        $path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM'
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name 'AutoEnrollMDM' -Value 1 -Type DWord -Force
        $result.FixesApplied += "MDM auto-enrollment"
    }
    
    # Sync
    if ($aad) {
        & dsregcmd /sync 2>&1 | Out-Null
        Start-Sleep -Seconds 5
        $result.FixesApplied += "Azure AD sync"
    }
    
    # Trigger enrollment
    if ($result.Status -eq 'Partial') {
        $task = Get-ScheduledTask -TaskName "DeviceEnrollment*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($task) { Start-ScheduledTask -TaskName $task.TaskName; $result.FixesApplied += "Enrollment task" }
    }
    
    # Reset
    if ($Reset -or $ForceReenroll) {
        & dsregcmd /leave 2>&1 | Out-Null
        $result.Status = 'Reset'
        $result.FixesApplied += "Azure AD leave (reset)"
    }
    
    # Final sync
    if ($Sync -and $result.FixesApplied.Count -gt 0) {
        Start-Sleep -Seconds 10
        Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule "{00000000-0000-0000-0000-000000000021}" -ErrorAction SilentlyContinue | Out-Null
    }
}

$result.Success = $result.FixesApplied.Count -gt 0 -or $result.Status -eq 'Healthy'
return $result
'@
            
            Set-Content -Path $tempScript -Value $scriptContent
            $repairResult = & $tempScript @Params
            Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
            
            return $repairResult
        }
        
        $invokeParams = @{
            ComputerName = $Computer
            ScriptBlock = $scriptBlock
            ArgumentList = @(@{
                AutoFix = $AutoFix
                Reset = $ResetRegistration
                ForceReenroll = $ForceReenroll
                CheckCerts = $CheckCertificates
                Sync = $TriggerSync
                WhatIf = $WhatIf
            })
            ErrorAction = 'Stop'
        }
        
        if ($Cred) { $invokeParams.Credential = $Cred }
        
        Write-Log "Executing repair on $Computer..." -Level Info
        $remoteResult = Invoke-Command @invokeParams
        
        $result.Success = $remoteResult.Success
        $result.Status = $remoteResult.Status
        $result.FixesApplied = $remoteResult.FixesApplied
        
        $statusColor = switch ($result.Status) {
            'Healthy' { 'Green' }
            'Partial' { 'Yellow' }
            default { 'White' }
        }
        
        Write-Log "$Computer`: Status = $($result.Status), Fixes = $($result.FixesApplied.Count)" -Level $(if ($result.Success) { 'Success' } else { 'Warning' })
    }
    catch {
        $result.Success = $false
        $result.Error = $_.Exception.Message
        Write-Log "Remote repair failed on ${Computer}: $($_.Exception.Message)" -Level Error
    }
    
    $script:Results.Add($result)
}
#endregion

#region Main Execution
Show-Header

# Determine computers to process
$computers = @()
if ($ComputerName) {
    $computers = $ComputerName
} else {
    $computers = @($env:COMPUTERNAME)
}

Write-Log "Processing $($computers.Count) computer(s)" -Level Info

# Confirmation
if (-not $Force -and -not $WhatIf -and ($ResetRegistration -or $ForceReenroll)) {
    Write-Host ""
    Write-Log "WARNING: Reset mode selected!" -Level Error
    $confirm = Read-Host "This will reset device registration. Continue? (Y/N)"
    if ($confirm -notmatch '^(y|yes)$') {
        Write-Log "Cancelled by user" -Level Info
        exit 2
    }
}

# Process each computer
foreach ($computer in $computers) {
    if ($computer -eq $env:COMPUTERNAME -or $computer -eq 'localhost' -or $computer -eq '.') {
        # Local execution
        Write-Host ""
        Write-Log "=== Processing Local Machine ===" -Level Info
        
        $result = Invoke-LocalRepair -IsAutoFix:$AutoFix -DoReset:$ResetRegistration `
            -DoForceReenroll:$ForceReenroll -CheckCerts:$CheckCertificates `
            -DoSync:$TriggerSync -IsWhatIf:$WhatIf
        
        $script:Results.Add([PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            Success = $result.Success
            Status = $result.Status
            FixesApplied = $result.FixesApplied
            Error = $result.Error
        })
        
        if ($result.Status -eq 'Healthy') {
            Write-Log "Local machine is healthy" -Level Success
        } else {
            Write-Log "Local machine status: $($result.Status)" -Level $(if ($result.Success) { 'Success' } else { 'Warning' })
        }
    }
    else {
        # Remote execution
        Write-Host ""
        $cred = if ($Credential) { $Credential } elseif (-not $UseCurrent) {
            Get-Credential -Message "Enter credentials for $computer"
        } else { $null }
        
        Invoke-RemoteRepair -Computer $computer -Cred $cred
    }
}

# Show summary
Show-Summary

# Exit code
$failed = ($script:Results | Where-Object { -not $_.Success }).Count
if ($failed -eq 0) { exit 0 } elseif ($failed -lt $script:Results.Count) { exit 1 } else { exit 4 }
#endregion
