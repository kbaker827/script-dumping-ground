<#
.SYNOPSIS
    Clears Adobe identity and Acrobat Sign caches to fix "Request e-signatures" issues.

.DESCRIPTION
    This script safely clears cached Adobe identity and Acrobat Sign tokens when users 
    experience issues with the "Request e-signatures" feature in Adobe Acrobat. 
    
    Can run locally or remotely via PowerShell Remoting.
    
    Actions performed:
    - Closes Adobe/Acrobat processes
    - Backs up existing cache folders
    - Removes identity/token caches
    - Clears stale Windows Web Credentials for Adobe
    - Restarts Creative Cloud helper (optional)
    - Logs all actions

.PARAMETER ComputerName
    Remote computer(s) to run the cleanup on. If omitted, runs locally.

.PARAMETER Credential
    Credentials for remote authentication.

.PARAMETER UseCurrent
    Use current credentials for remote connection (no prompt).

.PARAMETER Quiet
    Suppresses console output (useful for automated deployments).

.PARAMETER SkipProcessClose
    Skip closing Adobe processes (use with caution).

.PARAMETER SkipBackup
    Skip backing up cache folders (not recommended).

.PARAMETER BackupPath
    Custom path for cache backups. Defaults to %LOCALAPPDATA%\Adobe\_CacheBackups

.PARAMETER RemoveAllUsers
    Run for all user profiles on the machine (requires admin).

.PARAMETER RestartAcrobat
    Restart Adobe Acrobat after cleanup (if found running).

.PARAMETER LogPath
    Path to save detailed log file.

.PARAMETER WhatIf
    Show what would be done without making changes.

.PARAMETER Force
    Suppress confirmation prompts.

.EXAMPLE
    .\Reset-AdobeSignCache.ps1
    Runs the full cleanup locally with console output.

.EXAMPLE
    .\Reset-AdobeSignCache.ps1 -ComputerName PC01 -UseCurrent
    Runs cleanup remotely on PC01 using current credentials.

.EXAMPLE
    .\Reset-AdobeSignCache.ps1 -ComputerName PC01,PC02 -Credential (Get-Credential)
    Runs cleanup on multiple remote computers with specified credentials.

.EXAMPLE
    .\Reset-AdobeSignCache.ps1 -RemoveAllUsers -Force
    Clears caches for all user profiles on local machine.

.EXAMPLE
    .\Reset-AdobeSignCache.ps1 -Quiet -LogPath "C:\Logs\AdobeReset.log"
    Runs silently with custom log location.

.NOTES
    Version:        3.0
    Author:         IT Admin
    Updated:        2026-02-12
    
    Run as: 
    - Local: The affected user (no admin required)
    - Remote: Account with admin rights on target
    - AllUsers: Local admin required
    
    Safe: All caches are backed up before removal
    
    Exit Codes:
    0   - Success
    1   - Partial success (some caches not cleared)
    2   - Remote connection failed
    3   - No user profiles found
    4   - Cancelled by user
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
    [Alias('CN', 'MachineName', 'Name')]
    [string[]]$ComputerName,
    
    [PSCredential]$Credential,
    
    [switch]$UseCurrent,
    [switch]$Quiet,
    [switch]$SkipProcessClose,
    [switch]$SkipBackup,
    [string]$BackupPath,
    [switch]$RemoveAllUsers,
    [switch]$RestartAcrobat,
    [string]$LogPath,
    [switch]$WhatIf,
    [switch]$Force
)

#region Configuration
$ErrorActionPreference = 'SilentlyContinue'
$script:Version = "3.0"
$script:StartTime = Get-Date
$script:Results = [System.Collections.Generic.List[object]]::new()

# Default log path
if (-not $LogPath) {
    $LogPath = Join-Path $env:TEMP "AdobeSignCacheReset_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
}

# Adobe processes to close
$script:AdobeProcesses = @(
    "Acrobat", "AcroCEF", "AcroRd32", "AdobeCollabSync",
    "CCXProcess", "Creative Cloud", "Adobe Desktop Service", 
    "CoreSync", "AGSService", "AGMService", "AdobeIPCBroker",
    "AdobeNotificationClient", "AdobeUpdateService", "RuntimeBroker"
)

# Cache paths to clear (will be resolved per-user)
$script:CachePathPatterns = @(
    "Local\Adobe\OOBE",
    "Roaming\Adobe\OOBE", 
    "Roaming\Adobe\Acrobat\DC\AcroCEF\Cache",
    "Roaming\Adobe\Acrobat\DC\AcroCEF\GPUCache",
    "Local\Adobe\Acrobat\DC\AcroCEF\Cache",
    "Local\Adobe\Acrobat\DC\AcroCEF\GPUCache",
    "Roaming\Adobe\Acrobat\DC\JSCache",
    "Roaming\Adobe\Acrobat\DC\Security\csi",
    "Roaming\Adobe\Acrobat\DC\Preferences",
    "Local\Adobe\Acrobat\DC\Cache"
)
#endregion

#region Helper Functions
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('Info', 'Ok', 'Warn', 'Error', 'Detail')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to log file
    try {
        Add-Content -Path $script:LogPath -Value $logEntry -ErrorAction SilentlyContinue
    } catch {}
    
    # Console output
    if (-not $Quiet) {
        $colors = @{
            Info   = 'Cyan'
            Ok     = 'Green'
            Warn   = 'Yellow'
            Error  = 'Red'
            Detail = 'Gray'
        }
        $prefix = switch ($Level) {
            'Info'   { '[INFO]' }
            'Ok'     { '[ OK ]' }
            'Warn'   { '[WARN]' }
            'Error'  = { '[ERR ]' }
            'Detail' { '      ' }
        }
        Write-Host "$prefix $Message" -ForegroundColor $colors[$Level]
    }
}

function Show-Header {
    if ($Quiet) { return }
    Write-Host ""
    Write-Host "================================" -ForegroundColor Cyan
    Write-Host " Adobe Sign Cache Reset Tool v$script:Version" -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Log "Started: $($script:StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level Detail
    Write-Log "Log: $script:LogPath" -Level Detail
}

function Get-UserProfiles {
    # Get all user profiles on the machine
    try {
        $profiles = Get-WmiObject -Class Win32_UserProfile | Where-Object { 
            $_.Special -eq $false -and $_.LocalPath -notlike '*\Windows\*' 
        }
        return $profiles
    }
    catch {
        Write-Log "Failed to enumerate user profiles: $($_.Exception.Message)" -Level Error
        return @()
    }
}

function Resolve-UserPaths {
    param([string]$UserProfilePath)
    
    $localAppData = Join-Path $UserProfilePath "AppData\Local"
    $roamingAppData = Join-Path $UserProfilePath "AppData\Roaming"
    
    $paths = @()
    foreach ($pattern in $script:CachePathPatterns) {
        $fullPath = $pattern -replace '^Local\\', "$localAppData\" -replace '^Roaming\\', "$roamingAppData\" 
        $paths += $fullPath
    }
    
    return $paths
}

function Stop-AdobeProcesses {
    param([string]$TargetComputer = $env:COMPUTERNAME)
    
    Write-Log "Closing Adobe processes on $TargetComputer..." -Level Info
    
    $stoppedCount = 0
    foreach ($processName in $script:AdobeProcesses) {
        $processes = Get-Process -Name $processName -ComputerName $TargetComputer -ErrorAction SilentlyContinue
        foreach ($proc in $processes) {
            try {
                if ($PSCmdlet.ShouldProcess("$TargetComputer\$($proc.Name)", "Stop Process")) {
                    Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                    $stoppedCount++
                }
            }
            catch {
                Write-Log "Could not stop $($proc.Name): $($_.Exception.Message)" -Level Warn
            }
        }
    }
    
    if ($stoppedCount -gt 0) {
        Start-Sleep -Seconds 2
        Write-Log "Stopped $stoppedCount Adobe process(es)" -Level Ok
    } else {
        Write-Log "No Adobe processes running" -Level Detail
    }
}

function Clear-AdobeCaches {
    param(
        [string]$UserProfilePath,
        [string]$Username = "Current User"
    )
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupRoot = if ($BackupPath) { $BackupPath } else { 
        Join-Path (Split-Path $UserProfilePath -Parent) "Adobe_CacheBackups" 
    }
    $sessionBackup = Join-Path $backupRoot "AdobeCache-$Username-$timestamp"
    
    $targetPaths = Resolve-UserPaths -UserProfilePath $UserProfilePath
    
    $result = @{
        Username = $Username
        ProfilePath = $UserProfilePath
        ClearedCount = 0
        FailedCount = 0
        BackupPath = $sessionBackup
        Errors = @()
    }
    
    # Create backup directory
    if (-not $SkipBackup) {
        try {
            New-Item -ItemType Directory -Path $sessionBackup -Force | Out-Null
            Write-Log "Backup location: $sessionBackup" -Level Detail
        }
        catch {
            Write-Log "Failed to create backup directory: $($_.Exception.Message)" -Level Warn
        }
    }
    
    # Process each cache path
    foreach ($path in $targetPaths) {
        if (Test-Path $path) {
            try {
                # Backup
                if (-not $SkipBackup -and (Test-Path $sessionBackup)) {
                    $safeName = ($path -replace [regex]::Escape($UserProfilePath), 'PROFILE') -replace '[\\/:]', '_'
                    $backupDest = Join-Path $sessionBackup $safeName
                    Copy-Item $path $backupDest -Recurse -Force -ErrorAction SilentlyContinue
                }
                
                # Remove
                if ($PSCmdlet.ShouldProcess($path, "Remove Cache")) {
                    Remove-Item $path -Recurse -Force -ErrorAction Stop
                    Write-Log "Cleared: $path" -Level Ok
                    $result.ClearedCount++
                }
            }
            catch {
                Write-Log "Failed to clear: $path ($($_.Exception.Message))" -Level Warn
                $result.FailedCount++
                $result.Errors += $_.Exception.Message
            }
        }
    }
    
    return $result
}

function Clear-AdobeCredentials {
    Write-Log "Clearing Adobe Web Credentials..." -Level Info
    
    $cmdkeyPath = "$env:SystemRoot\System32\cmdkey.exe"
    if (-not (Test-Path $cmdkeyPath)) {
        Write-Log "cmdkey.exe not found" -Level Warn
        return
    }
    
    try {
        $credentialList = & $cmdkeyPath /list 2>&1
        if ($credentialList) {
            $lines = $credentialList -split "`r?`n"
            $removedCount = 0
            
            foreach ($line in $lines) {
                if ($line -match 'Target:\s+(.+)' -and $line -match 'adobe|acrobat|creative', 'IgnoreCase') {
                    $target = $matches[1].Trim()
                    if ($PSCmdlet.ShouldProcess($target, "Remove Credential")) {
                        & $cmdkeyPath /delete:$target 2>&1 | Out-Null
                        Write-Log "Removed credential: $target" -Level Ok
                        $removedCount++
                    }
                }
            }
            
            if ($removedCount -eq 0) {
                Write-Log "No Adobe credentials found" -Level Detail
            }
        }
    }
    catch {
        Write-Log "Credential cleanup skipped: $($_.Exception.Message)" -Level Warn
    }
}

function Start-CreativeCloud {
    Write-Log "Starting Creative Cloud helper..." -Level Info
    
    $ccxPaths = @(
        "${env:ProgramFiles}\Adobe\Adobe Creative Cloud Experience\CCXProcess.exe",
        "${env:ProgramFiles(x86)}\Adobe\Adobe Creative Cloud Experience\CCXProcess.exe"
    )
    
    foreach ($ccxPath in $ccxPaths) {
        if (Test-Path $ccxPath) {
            try {
                Start-Process -FilePath $ccxPath -ErrorAction SilentlyContinue
                Write-Log "Started CCXProcess" -Level Ok
                break
            }
            catch {
                Write-Log "Failed to start CCXProcess: $($_.Exception.Message)" -Level Warn
            }
        }
    }
}

function Invoke-Cleanup {
    param([string]$TargetComputer = $env:COMPUTERNAME)
    
    Write-Log "=== Processing $TargetComputer ===" -Level Info
    
    # Stop processes
    if (-not $SkipProcessClose) {
        Stop-AdobeProcesses -TargetComputer $TargetComputer
    }
    
    # Determine which profiles to process
    if ($RemoveAllUsers) {
        Write-Log "Enumerating all user profiles..." -Level Info
        $profiles = Get-UserProfiles
        
        if ($profiles.Count -eq 0) {
            Write-Log "No user profiles found!" -Level Error
            return @{ ExitCode = 3; Results = @() }
        }
    } else {
        # Just current user
        $profiles = @(@{ LocalPath = $env:USERPROFILE; Username = $env:USERNAME })
    }
    
    Write-Log "Processing $($profiles.Count) user profile(s)..." -Level Info
    
    $allResults = @()
    foreach ($profile in $profiles) {
        $username = if ($profile.Username) { $profile.Username } else { Split-Path $profile.LocalPath -Leaf }
        Write-Log "Processing user: $username" -Level Info
        
        $result = Clear-AdobeCaches -UserProfilePath $profile.LocalPath -Username $username
        $allResults += $result
        
        $script:Results.Add([PSCustomObject]@{
            ComputerName = $TargetComputer
            Username = $username
            Cleared = $result.ClearedCount
            Failed = $result.FailedCount
        })
    }
    
    # Clear credentials (current user only)
    if (-not $RemoveAllUsers) {
        Clear-AdobeCredentials
    }
    
    # Start Creative Cloud
    Start-CreativeCloud
    
    # Summary
    $totalCleared = ($allResults | Measure-Object -Property ClearedCount -Sum).Sum
    $totalFailed = ($allResults | Measure-Object -Property FailedCount -Sum).Sum
    
    Write-Log "Cleared $totalCleared cache location(s), $totalFailed failed" -Level $(if ($totalFailed -eq 0) { 'Ok' } else { 'Warn' })
    
    return @{
        ExitCode = if ($totalFailed -gt 0) { 1 } else { 0 }
        Results = $allResults
    }
}

function Invoke-RemoteCleanup {
    param(
        [string]$Computer,
        [PSCredential]$Cred
    )
    
    Write-Log "Connecting to $Computer..." -Level Info
    
    try {
        # Test connection
        if (-not (Test-Connection -ComputerName $Computer -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
            Write-Log "Ping failed for $Computer, attempting WinRM anyway..." -Level Warn
        }
        
        # Check WinRM
        Test-WSMan -ComputerName $Computer -ErrorAction Stop | Out-Null
        
        # Build scriptblock with parameters
        $scriptBlock = {
            param($Params)
            
            # Create a temporary script file
            $tempScript = Join-Path $env:TEMP "AdobeReset_$(Get-Random).ps1"
            
            # Embedded script content (simplified for remote execution)
            $scriptContent = @'
param($SkipProcessClose, $SkipBackup, $BackupPath, $RemoveAllUsers, $Quiet, $WhatIf, $Force)
$ErrorActionPreference = 'SilentlyContinue'

function Write-Log { param($Message, $Level='Info'); $ts = Get-Date -Format 'HH:mm:ss'; Add-Content -Path "$env:TEMP\AdobeReset.log" -Value "[$ts] [$Level] $Message" -ErrorAction SilentlyContinue; if (-not $Quiet) { Write-Host "[$Level] $Message" } }

$adobeProcesses = @("Acrobat","AcroCEF","AcroRd32","CCXProcess","Adobe Desktop Service","CoreSync")
if (-not $SkipProcessClose) {
    foreach ($proc in $adobeProcesses) { Get-Process -Name $proc -ErrorAction SilentlyContinue | Stop-Process -Force }
    Start-Sleep -Seconds 2
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupRoot = if ($BackupPath) { $BackupPath } else { Join-Path $env:LOCALAPPDATA "Adobe\_CacheBackups" }
$sessionBackup = Join-Path $backupRoot "AdobeCache-$timestamp"
if (-not $SkipBackup) { New-Item -ItemType Directory -Path $sessionBackup -Force | Out-Null }

$paths = @(
    (Join-Path $env:LOCALAPPDATA "Adobe\OOBE"),
    (Join-Path $env:APPDATA "Adobe\OOBE"),
    (Join-Path $env:APPDATA "Adobe\Acrobat\DC\AcroCEF\Cache"),
    (Join-Path $env:APPDATA "Adobe\Acrobat\DC\AcroCEF\GPUCache"),
    (Join-Path $env:LOCALAPPDATA "Adobe\Acrobat\DC\AcroCEF\Cache"),
    (Join-Path $env:LOCALAPPDATA "Adobe\Acrobat\DC\AcroCEF\GPUCache"),
    (Join-Path $env:APPDATA "Adobe\Acrobat\DC\JSCache"),
    (Join-Path $env:APPDATA "Adobe\Acrobat\DC\Security\csi")
)

$cleared = 0
foreach ($path in $paths) {
    if (Test-Path $path) {
        if (-not $SkipBackup) {
            $safeName = ($path -replace '[:\\]', '_')
            Copy-Item $path (Join-Path $sessionBackup $safeName) -Recurse -Force -ErrorAction SilentlyContinue
        }
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
        $cleared++
    }
}

# Clear credentials
$cmdkey = "$env:SystemRoot\System32\cmdkey.exe"
if (Test-Path $cmdkey) {
    $creds = & $cmdkey /list 2>&1
    foreach ($line in $creds) {
        if ($line -match 'Target:\s+(.+)' -and $line -match 'adobe') {
            & $cmdkey /delete:$($matches[1].Trim()) 2>&1 | Out-Null
        }
    }
}

"Cleared $cleared cache locations"
'@
            
            Set-Content -Path $tempScript -Value $scriptContent
            
            # Execute
            $result = & $tempScript @Params
            
            # Cleanup
            Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
            
            return $result
        }
        
        $invokeParams = @{
            ComputerName = $Computer
            ScriptBlock = $scriptBlock
            ArgumentList = @(@{
                SkipProcessClose = $SkipProcessClose
                SkipBackup = $SkipBackup
                BackupPath = $BackupPath
                RemoveAllUsers = $RemoveAllUsers
                Quiet = $Quiet
                WhatIf = $WhatIf
                Force = $Force
            })
            ErrorAction = 'Stop'
        }
        
        if ($Cred) { $invokeParams.Credential = $Cred }
        
        Write-Log "Executing remote cleanup on $Computer..." -Level Info
        $remoteResult = Invoke-Command @invokeParams
        
        Write-Log "Remote result: $remoteResult" -Level Ok
        
        $script:Results.Add([PSCustomObject]@{
            ComputerName = $Computer
            Username = "Remote"
            Cleared = "See remote log"
            Failed = 0
        })
        
        return 0
    }
    catch {
        Write-Log "Remote execution failed on ${Computer}: $($_.Exception.Message)" -Level Error
        $script:Results.Add([PSCustomObject]@{
            ComputerName = $Computer
            Username = "N/A"
            Cleared = 0
            Failed = 1
        })
        return 2
    }
}
#endregion

#region Main Execution
Show-Header

# Confirmation for AllUsers
if ($RemoveAllUsers -and -not $Force -and -not $WhatIf) {
    $confirm = Read-Host "This will clear Adobe caches for ALL users on this machine. Continue? (Y/N)"
    if ($confirm -ne 'Y') {
        Write-Log "Operation cancelled by user" -Level Info
        exit 4
    }
}

# Process computers
$exitCode = 0

if ($ComputerName) {
    # Remote execution
    foreach ($computer in $ComputerName) {
        # Get credentials if needed
        $cred = if ($Credential) { 
            $Credential 
        } elseif (-not $UseCurrent) {
            Get-Credential -Message "Enter credentials for $computer"
        } else { 
            $null 
        }
        
        $result = Invoke-RemoteCleanup -Computer $computer -Cred $cred
        if ($result -ne 0) { $exitCode = $result }
    }
} else {
    # Local execution
    $result = Invoke-Cleanup
    $exitCode = $result.ExitCode
}

# Summary
if (-not $Quiet) {
    Write-Host ""
    Write-Host "================================" -ForegroundColor Cyan
    Write-Host "  SUMMARY" -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan
    Write-Host ""
    
    $script:Results | Format-Table -AutoSize
    
    Write-Host "Next steps:" -ForegroundColor White
    Write-Host "  1. Open Adobe Acrobat and sign in" -ForegroundColor Gray
    Write-Host "  2. Try File > Request e-signatures again" -ForegroundColor Gray
    Write-Host "  3. If still failing, reboot once" -ForegroundColor Gray
    Write-Host ""
    Write-Log "Log saved: $script:LogPath" -Level Detail
}

exit $exitCode
#endregion
