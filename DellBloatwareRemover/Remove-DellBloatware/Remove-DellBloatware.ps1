<#
.SYNOPSIS
    Removes Dell bloatware while preserving Dell Command Update.

.DESCRIPTION
    This script identifies and removes common Dell pre-installed software (bloatware)
    while preserving Dell Command Update, which is useful for driver/firmware updates.
    
    Removes: SupportAssist, Optimizer, Digital Delivery, CinemaColor, etc.
    Preserves: Dell Command | Update (and variants)

.PARAMETER WhatIf
    Show what would be removed without actually uninstalling.

.PARAMETER Force
    Skip confirmation prompts and proceed with removal.

.PARAMETER Keep
    Additional packages to preserve (comma-separated).

.PARAMETER Remove
    Additional packages to remove (comma-separated).

.PARAMETER LogPath
    Path to save the removal log. Default: %TEMP%\DellBloatwareRemoval.log

.EXAMPLE
    .\Remove-DellBloatware.ps1
    Interactive mode - shows what will be removed and asks for confirmation.

.EXAMPLE
    .\Remove-DellBloatware.ps1 -WhatIf
    Preview mode - shows what would be removed without making changes.

.EXAMPLE
    .\Remove-DellBloatware.ps1 -Force
    Silent removal without prompts (good for deployment).

.EXAMPLE
    .\Remove-DellBloatware.ps1 -Keep "Dell Power Manager"
    Keep Dell Power Manager in addition to Command Update.

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2026-02-12
    
    Requires:       PowerShell 5.1+ (Windows 10/11)
    Privileges:     Administrator (recommended for most apps)
    
    Exit Codes:
    0   - Success (all targeted apps removed or not found)
    1   - General error
    2   - User cancelled
    3   - Some apps failed to remove
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$Force,
    [switch]$WhatIf,
    [string[]]$Keep,
    [string[]]$Remove,
    [string]$LogPath = (Join-Path $env:TEMP "DellBloatwareRemoval_$(Get-Date -Format 'yyyyMMdd_HHmmss').log")
)

#region Configuration
$ErrorActionPreference = 'Stop'
$script:Version = "1.0"
$script:FailedRemovals = [System.Collections.Generic.List[string]]::new()
$script:RemovedApps = [System.Collections.Generic.List[string]]::new()
$script:SkippedApps = [System.Collections.Generic.List[string]]::new()

# Apps that are ALWAYS preserved (Dell Command Update variants)
$script:ProtectedApps = @(
    "Dell Command | Update",
    "Dell Command Update",
    "Dell Command | Update for Windows",
    "Dell Command | Update for Windows Universal",
    "Dell Command | Update for Windows (Universal)"
) + $Keep

# Common Dell bloatware to remove (will be matched with wildcards)
$script:BloatwarePatterns = @(
    # Support and Diagnostics
    "Dell SupportAssist*",
    "Dell SupportAssist Remediation*",
    "Dell SupportAssist OS Recovery Plugin*",
    "Dell SupportAssist Update Plugin*",
    "Dell SupportAssist for Dell Update*",
    
    # Performance and Optimization
    "Dell Optimizer*",
    "Dell Optimizer Service*",
    "Dell Power Manager*",
    "Dell Power Manager Service*",
    "Dell CinemaColor*",
    "Dell CinemaColor Service*",
    "Dell Digital Color*",
    
    # Audio and Video
    "Dell CinemaSound*",
    "Dell Waves MaxxAudio*",
    "Dell Audio*",
    "Dell Audio Service*",
    
    # Display
    "Dell Display Manager*",
    "Dell Display Manager 2*",
    "Dell PremierColor*",
    
    # Software Delivery
    "Dell Digital Delivery*",
    "Dell Digital Delivery Service*",
    "Dell Software Delivery*",
    
    # Productivity
    "Dell Mobile Connect*",
    "Dell QuickSet*",
    "Dell Customer Connect*",
    "Dell Featured Application*",
    
    # Peripheral Management
    "Dell Peripheral Manager*",
    "Dell Pair*",
    
    # Anti-Theft
    "Dell Encryption*",
    "Dell Data Protection*",
    
    # Other
    "Dell Foundation Services*",
    "Dell Help & Support*",
    "Dell Getting Started*",
    "Dell Registration*",
    "Dell Update*",  # Different from Command Update
    "Dell Update for Windows*",
    "Dell Support Center*",
    "Dell Customer Improvement Program*",
    "Dell Metrics*",
    "Dell Product Registration*",
    "Dell Touch*",
    "Dell PointStick*",
    "Dell ControlVault*",
    "Dell Trusted Device*",
    "Dell SafeGuard*",
    
    # Common third-party bloatware on Dell systems
    "McAfee*",
    "WildTangent*",
    "CyberLink*",
    "Dropbox*",
    "Adobe*",
    "ExpressVPN*",
    "Norton*"
) + $Remove
#endregion

#region Helper Functions
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    
    Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
    
    switch ($Level) {
        'Info'    { Write-Host $Message }
        'Warning' { Write-Warning $Message }
        'Error'   { Write-Host $Message -ForegroundColor Red }
        'Success' { Write-Host $Message -ForegroundColor Green }
    }
}

function Show-Header {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Dell Bloatware Remover v$Version" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "This script removes Dell pre-installed software" -ForegroundColor Yellow
    Write-Host "while preserving Dell Command Update." -ForegroundColor Yellow
    Write-Host ""
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-InstalledApps {
    $apps = [System.Collections.Generic.List[PSObject]]::new()
    
    # Registry paths for installed software
    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    
    foreach ($path in $regPaths) {
        try {
            Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.DisplayName) {
                    $apps.Add([PSCustomObject]@{
                        Name = $_.DisplayName
                        Version = $_.DisplayVersion
                        Publisher = $_.Publisher
                        UninstallString = $_.UninstallString
                        QuietUninstallString = $_.QuietUninstallString
                        RegistryPath = $_.PSPath
                        Guid = if ($_.UninstallString -match '\{[A-F0-9-]+\}') { $matches[0] } else { $null }
                    })
                }
            }
        } catch {
            # Ignore permission errors on some registry keys
        }
    }
    
    # Also check Windows Apps (AppX/MSIX) for Dell apps
    try {
        Get-AppxPackage -AllUsers | Where-Object { 
            $_.Publisher -like "*Dell*" -or $_.Name -like "*Dell*" 
        } | ForEach-Object {
            $apps.Add([PSCustomObject]@{
                Name = $_.Name
                Version = $_.Version
                Publisher = $_.Publisher
                UninstallString = "Remove-AppxPackage"
                QuietUninstallString = "Remove-AppxPackage"
                RegistryPath = $_.PackageFullName
                PackageFullName = $_.PackageFullName
                IsAppx = $true
            })
        }
    } catch {
        Write-Log "Could not enumerate AppX packages: $($_.Exception.Message)" -Level Warning
    }
    
    return $apps | Sort-Object Name -Unique
}

function Test-ProtectedApp {
    param([string]$AppName)
    
    foreach ($protected in $script:ProtectedApps) {
        if ($AppName -like "*$protected*" -or $protected -like "*$AppName*") {
            return $true
        }
    }
    return $false
}

function Test-BloatwareMatch {
    param([string]$AppName)
    
    foreach ($pattern in $script:BloatwarePatterns) {
        if ($AppName -like $pattern) {
            return $true
        }
    }
    return $false
}

function Get-AppsToRemove {
    param([System.Collections.Generic.List[PSObject]]$AllApps)
    
    $toRemove = [System.Collections.Generic.List[PSObject]]::new()
    
    foreach ($app in $AllApps) {
        # Skip if protected
        if (Test-ProtectedApp -AppName $app.Name) {
            $script:SkippedApps.Add($app.Name)
            continue
        }
        
        # Check if matches bloatware patterns
        if (Test-BloatwareMatch -AppName $app.Name) {
            $toRemove.Add($app)
        }
    }
    
    return $toRemove
}

function Uninstall-App {
    param([PSCustomObject]$App)
    
    Write-Log "Removing: $($App.Name)" -Level Info
    
    try {
        if ($App.IsAppx) {
            # Remove AppX package
            if ($PSCmdlet.ShouldProcess($App.PackageFullName, "Remove AppX Package")) {
                Remove-AppxPackage -Package $App.PackageFullName -ErrorAction Stop
                Write-Log "Successfully removed AppX: $($App.Name)" -Level Success
            }
        }
        elseif ($App.QuietUninstallString) {
            # Use quiet uninstall string
            if ($PSCmdlet.ShouldProcess($App.Name, "Uninstall")) {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = "cmd.exe"
                $psi.Arguments = "/c `"$($App.QuietUninstallString)`""
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                
                $proc = [System.Diagnostics.Process]::Start($psi)
                $proc.WaitForExit(300000)  # 5 minute timeout
                
                if ($proc.ExitCode -eq 0) {
                    Write-Log "Successfully removed: $($App.Name)" -Level Success
                } else {
                    throw "Exit code: $($proc.ExitCode)"
                }
            }
        }
        elseif ($App.UninstallString) {
            # Use regular uninstall string (try to make it quiet)
            if ($PSCmdlet.ShouldProcess($App.Name, "Uninstall")) {
                $uninstallCmd = $App.UninstallString
                
                # If it's an MSI, use msiexec
                if ($App.Guid) {
                    $uninstallCmd = "msiexec.exe /X `"$($App.Guid)`" /qn /norestart"
                }
                elseif ($uninstallCmd -match '\.exe') {
                    # Try to add silent flags
                    $uninstallCmd = $uninstallCmd -replace '"$', '" /S'
                }
                
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = "cmd.exe"
                $psi.Arguments = "/c `"$uninstallCmd`""
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                
                $proc = [System.Diagnostics.Process]::Start($psi)
                $proc.WaitForExit(300000)
                
                Write-Log "Removed (exit code $($proc.ExitCode)): $($App.Name)" -Level Success
            }
        }
        else {
            Write-Log "No uninstall method for: $($App.Name)" -Level Warning
            return $false
        }
        
        return $true
    }
    catch {
        Write-Log "Failed to remove $($App.Name): $($_.Exception.Message)" -Level Error
        $script:FailedRemovals.Add($App.Name)
        return $false
    }
}

function Remove-DellServices {
    $services = Get-Service -Name "*Dell*" -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -notlike "*CommandUpdate*" -and $_.Name -notlike "*DCU*" }
    
    foreach ($svc in $services) {
        Write-Log "Stopping service: $($svc.Name)" -Level Info
        try {
            if ($PSCmdlet.ShouldProcess($svc.Name, "Stop Service")) {
                Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
                Write-Log "Stopped service: $($svc.Name)" -Level Success
            }
        } catch {
            Write-Log "Could not stop service $($svc.Name): $($_.Exception.Message)" -Level Warning
        }
    }
}

function Remove-DellScheduledTasks {
    $tasks = Get-ScheduledTask -TaskName "*Dell*" -ErrorAction SilentlyContinue |
        Where-Object { $_.TaskName -notlike "*CommandUpdate*" -and $_.TaskName -notlike "*DCU*" }
    
    foreach ($task in $tasks) {
        Write-Log "Removing scheduled task: $($task.TaskName)" -Level Info
        try {
            if ($PSCmdlet.ShouldProcess($task.TaskName, "Remove Scheduled Task")) {
                Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false -ErrorAction Stop
                Write-Log "Removed task: $($task.TaskName)" -Level Success
            }
        } catch {
            Write-Log "Could not remove task $($task.TaskName): $($_.Exception.Message)" -Level Warning
        }
    }
}
#endregion

#region Main Execution
Show-Header

# Check if running as admin
if (-not (Test-Admin)) {
    Write-Warning "Not running as Administrator. Some apps may not be removable."
    if (-not $Force) {
        $continue = Read-Host "Continue anyway? (Y/N)"
        if ($continue -notmatch '^[Yy]') { exit 2 }
    }
}

# Check for WhatIf
if ($WhatIf) {
    Write-Host "WHATIF MODE: No changes will be made." -ForegroundColor Yellow
    Write-Host ""
}

Write-Log "Scanning for installed applications..." -Level Info
Write-Host "This may take a moment..." -ForegroundColor DarkGray

# Get all installed apps
$allApps = Get-InstalledApps
Write-Log "Found $($allApps.Count) total installed applications" -Level Info

# Find apps to remove
$appsToRemove = Get-AppsToRemove -AllApps $allApps

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SCAN RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($appsToRemove.Count -eq 0) {
    Write-Host "No Dell bloatware found!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Protected apps preserved:" -ForegroundColor Yellow
    $script:ProtectedApps | ForEach-Object { Write-Host "  ✓ $_" -ForegroundColor Green }
    exit 0
}

Write-Host "Found $($appsToRemove.Count) app(s) to remove:" -ForegroundColor Yellow
Write-Host ""

$appsToRemove | ForEach-Object {
    $color = if (Test-ProtectedApp -AppName $_.Name) { 'Green' } else { 'Red' }
    Write-Host "  × $($_.Name)" -ForegroundColor $color
    if ($_.Version) { Write-Host "    Version: $($_.Version)" -ForegroundColor DarkGray }
}

Write-Host ""
Write-Host "Preserving (protected):" -ForegroundColor Green
$script:SkippedApps | Select-Object -Unique | ForEach-Object {
    Write-Host "  ✓ $_" -ForegroundColor Green
}

Write-Host ""

# Confirmation
if (-not $Force -and -not $WhatIf) {
    $confirm = Read-Host "Proceed with removal? (Y/N)"
    if ($confirm -notmatch '^[Yy]') {
        Write-Log "User cancelled" -Level Warning
        exit 2
    }
}

# Stop services first
Write-Log "Stopping Dell services..." -Level Info
Remove-DellServices

# Remove scheduled tasks
Write-Log "Removing Dell scheduled tasks..." -Level Info
Remove-DellScheduledTasks

# Remove apps
Write-Host ""
Write-Log "Removing applications..." -Level Info
Write-Host ""

foreach ($app in $appsToRemove) {
    if (Uninstall-App -App $app) {
        $script:RemovedApps.Add($app.Name)
    }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  REMOVAL COMPLETE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Successfully removed: $($script:RemovedApps.Count)" -ForegroundColor Green
$script:RemovedApps | ForEach-Object { Write-Host "  ✓ $_" -ForegroundColor Green }

if ($script:FailedRemovals.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed to remove: $($script:FailedRemovals.Count)" -ForegroundColor Red
    $script:FailedRemovals | ForEach-Object { Write-Host "  ✗ $_" -ForegroundColor Red }
}

Write-Host ""
Write-Host "Preserved: $($script:SkippedApps.Count)" -ForegroundColor Green
$script:SkippedApps | Select-Object -Unique | ForEach-Object { Write-Host "  ✓ $_" -ForegroundColor Green }

Write-Host ""
Write-Log "Log saved to: $LogPath" -Level Info

if ($script:FailedRemovals.Count -gt 0) {
    exit 3
}
exit 0
#endregion
