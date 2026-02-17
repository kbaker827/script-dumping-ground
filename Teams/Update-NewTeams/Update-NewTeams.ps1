<#
.SYNOPSIS
    Installs or updates the new Microsoft Teams client locally or remotely.

.DESCRIPTION
    This script installs or updates Microsoft Teams with context-aware execution:
    - If Teams is NOT installed: Performs fresh installation
    - If Teams IS installed: Checks for and applies updates
    
    Execution context determines method:
    - SYSTEM context: Uses Teams Bootstrapper for machine-wide provisioning
    - User context: Uses WinGet for per-user installation
    - Remote: Can deploy to multiple computers via PowerShell Remoting
    
    Logs detailed version information before and after.

.PARAMETER ComputerName
    Remote computer(s) to target. If omitted, runs locally.

.PARAMETER Credential
    Credentials for remote authentication.

.PARAMETER UseCurrent
    Use current credentials for remote connection (no prompt).

.PARAMETER Force
    Force reinstallation even if already up to date.

.PARAMETER InstallMethod
    Override auto-detection: 'Bootstrapper', 'WinGet', or 'Auto' (default).

.PARAMETER BootstrapperUrl
    Custom URL for Teams Bootstrapper download.

.PARAMETER LogPath
    Path to save detailed log file.

.PARAMETER PassThru
    Return result object instead of exit code.

.EXAMPLE
    .\Update-NewTeams.ps1
    Installs or updates Teams locally using appropriate method.

.EXAMPLE
    .\Update-NewTeams.ps1 -ComputerName PC01 -UseCurrent
    Installs or updates Teams on remote computer PC01.

.EXAMPLE
    Get-ADComputer -Filter {Enabled -eq $true} | Select-Object -ExpandProperty Name | .\Update-NewTeams.ps1 -UseCurrent
    Installs/updates Teams on all domain computers.

.NOTES
    Version:        3.1
    Author:         IT Admin
    Updated:        2026-02-13
    
    Requirements:
    - Windows 10/11 (64-bit)
    - PowerShell 5.1 or PowerShell 7+
    - Internet connectivity
    - For remote: WinRM enabled
    
    Exit Codes:
    0   = Success (installed or updated)
    1   = WinGet not found (user context)
    2   = Bootstrapper download failed
    3   = Installation/Update failed
    4   = Remote connection failed
    5   = Invalid parameters
    9   = Unexpected error
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, Position=0)]
    [Alias('CN', 'MachineName', 'Name')]
    [string[]]$ComputerName,
    
    [PSCredential]$Credential,
    [switch]$UseCurrent,
    
    [switch]$Force,
    
    [ValidateSet('Auto', 'Bootstrapper', 'WinGet')]
    [string]$InstallMethod = 'Auto',
    
    [string]$BootstrapperUrl = 'https://go.microsoft.com/fwlink/?linkid=2243204',
    
    [string]$LogPath,
    
    [switch]$PassThru
)

#region Configuration
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Version = "3.1"
$script:StartTime = Get-Date
$script:Results = [System.Collections.Generic.List[object]]::new()

$WinGetPackageId = 'Microsoft.Teams'

if (-not $LogPath) {
    if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        $LogPath = Join-Path $env:ProgramData "IT\Logs\Update-NewTeams.log"
    } else {
        $LogPath = Join-Path $env:TEMP "Update-NewTeams_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    }
}
#endregion

#region Helper Functions
function Initialize-LogPath {
    $logDir = Split-Path -Parent $LogPath
    if ($logDir -and -not (Test-Path $logDir)) {
        try {
            New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        }
        catch {
            $script:LogPath = Join-Path $env:TEMP "Update-NewTeams_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        }
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
    $line = "$timestamp [$Level] $Message"
    
    try {
        $line | Out-File -FilePath $LogPath -Append -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    catch {}
    
    $colors = @{
        Info    = 'White'
        Success = 'Green'
        Warning = 'Yellow'
        Error   = 'Red'
    }
    Write-Host $line -ForegroundColor $colors[$Level]
}

function Show-Header {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Microsoft Teams Installer/Updater v$Version" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Log "Started: $($script:StartTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Log "Log: $LogPath"
    Write-Log "Force: $Force, InstallMethod: $InstallMethod"
}

function Show-Summary {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    $total = $script:Results.Count
    $success = ($script:Results | Where-Object { $_.ExitCode -eq 0 }).Count
    $installed = ($script:Results | Where-Object { $_.Action -eq 'Installed' }).Count
    $updated = ($script:Results | Where-Object { $_.Action -eq 'Updated' }).Count
    $failed = ($script:Results | Where-Object { $_.ExitCode -ne 0 }).Count
    
    Write-Log "Computers processed: $total"
    Write-Log "Successful: $success" $(if ($success -gt 0) { 'Success' } else { 'Info' })
    if ($installed -gt 0) { Write-Log "New installations: $installed" 'Success' }
    if ($updated -gt 0) { Write-Log "Updates applied: $updated" 'Success' }
    Write-Log "Failed: $failed" $(if ($failed -gt 0) { 'Error' } else { 'Success' })
    
    if ($failed -gt 0) {
        Write-Host ""
        Write-Log "Failed computers:" 'Error'
        $script:Results | Where-Object { $_.ExitCode -ne 0 } | ForEach-Object {
            Write-Log "  - $($_.ComputerName): Exit $($_.ExitCode)" 'Error'
        }
    }
    
    $duration = (Get-Date) - $script:StartTime
    Write-Host ""
    Write-Log "Duration: $($duration.ToString('mm\:ss'))"
    Write-Log "Log saved: $LogPath"
}

function Test-TeamsInstalled {
    <#
    .SYNOPSIS
    Checks if Microsoft Teams (new) is installed.
    #>
    param([switch]$CheckAllUsers)
    
    try {
        if ($CheckAllUsers) {
            $package = Get-AppxPackage -AllUsers -Name MSTeams -ErrorAction SilentlyContinue | Select-Object -First 1
        } else {
            $package = Get-AppxPackage -Name MSTeams -ErrorAction SilentlyContinue
        }
        
        if ($package) {
            return [PSCustomObject]@{
                Installed = $true
                Version = $package.Version.ToString()
                PackageFullName = $package.PackageFullName
                InstallLocation = $package.InstallLocation
            }
        }
    }
    catch {}
    
    return [PSCustomObject]@{
        Installed = $false
        Version = $null
        PackageFullName = $null
        InstallLocation = $null
    }
}

function Test-TeamsProvisioned {
    <#
    .SYNOPSIS
    Checks if Teams is machine-wide provisioned (admin only).
    #>
    try {
        $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -eq 'MSTeams' }
        
        if ($provisioned) {
            return [PSCustomObject]@{
                Provisioned = $true
                Version = $provisioned.Version
            }
        }
    }
    catch {}
    
    return [PSCustomObject]@{
        Provisioned = $false
        Version = $null
    }
}

function Get-TeamsStatus {
    <#
    .SYNOPSIS
    Gets comprehensive Teams installation status.
    #>
    $status = [PSCustomObject]@{
        Installed = $false
        Version = $null
        Provisioned = $false
        ProvisionedVersion = $null
        UserCount = 0
        Action = 'None'
    }
    
    # Check current user
    $userInstall = Test-TeamsInstalled
    if ($userInstall.Installed) {
        $status.Installed = $true
        $status.Version = $userInstall.Version
    }
    
    # Check provisioned (admin only)
    $provStatus = Test-TeamsProvisioned
    if ($provStatus.Provisioned) {
        $status.Provisioned = $true
        $status.ProvisionedVersion = $provStatus.Version
    }
    
    # Count installed users
    try {
        $allPackages = Get-AppxPackage -AllUsers -Name MSTeams -ErrorAction SilentlyContinue
        if ($allPackages) {
            $status.UserCount = $allPackages.Count
        }
    }
    catch {}
    
    return $status
}
#endregion

#region Local Functions
function Install-UpdateTeamsAsSystem {
    Write-Log "Running in SYSTEM context"
    
    # Check current status
    $status = Get-TeamsStatus
    
    if ($status.Provisioned -and -not $Force) {
        Write-Log "Teams is already provisioned (Version: $($status.ProvisionedVersion))" 'Success'
        Write-Log "Checking for updates via Bootstrapper..."
        $action = 'Update'
    } else {
        if ($Force -and $status.Provisioned) {
            Write-Log "Teams provisioned but -Force specified. Re-provisioning..." 'Warning'
        } else {
            Write-Log "Teams is NOT provisioned. Will install..."
        }
        $action = 'Install'
    }
    
    if (-not $PSCmdlet.ShouldProcess("Teams Bootstrapper", "$action Teams")) {
        Write-Log "[WHATIF] Would $action Teams using Bootstrapper"
        return [PSCustomObject]@{ ExitCode = 0; WhatIf = $true; Action = $action }
    }
    
    # Prepare working directory
    $workDir = Join-Path $env:TEMP "TeamsBootstrapper"
    try {
        New-Item -ItemType Directory -Force -Path $workDir | Out-Null
    }
    catch {
        Write-Log "Failed to create working directory: $($_.Exception.Message)" 'Error'
        return [PSCustomObject]@{ ExitCode = 9; Error = $_.Exception.Message }
    }
    
    $bootstrapperPath = Join-Path $workDir "teamsbootstrapper.exe"
    
    # Download bootstrapper
    if (-not (Test-Path $bootstrapperPath) -or $Force) {
        Write-Log "Downloading Teams Bootstrapper..."
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -UseBasicParsing -Uri $BootstrapperUrl -OutFile $bootstrapperPath -TimeoutSec 180
            Write-Log "Download completed" 'Success'
        }
        catch {
            Write-Log "Download failed: $($_.Exception.Message)" 'Error'
            return [PSCustomObject]@{ ExitCode = 2; Error = $_.Exception.Message }
        }
    } else {
        Write-Log "Using existing Bootstrapper"
    }
    
    # Run bootstrapper
    Write-Log "Running: teamsbootstrapper.exe -p"
    try {
        $proc = Start-Process -FilePath $bootstrapperPath -ArgumentList "-p" -Wait -PassThru -WindowStyle Hidden
        Write-Log "Bootstrapper exit code: $($proc.ExitCode)"
    }
    catch {
        Write-Log "Failed to run Bootstrapper: $($_.Exception.Message)" 'Error'
        return [PSCustomObject]@{ ExitCode = 3; Error = $_.Exception.Message }
    }
    
    # Check result
    Start-Sleep -Seconds 3
    $newStatus = Get-TeamsStatus
    
    if ($proc.ExitCode -eq 0) {
        if ($action -eq 'Install') {
            Write-Log "Teams installed successfully" 'Success'
        } else {
            Write-Log "Teams updated successfully" 'Success'
        }
        return [PSCustomObject]@{ 
            ExitCode = 0 
            Action = $action
            Version = $newStatus.ProvisionedVersion 
        }
    } else {
        Write-Log "Bootstrapper failed with code $($proc.ExitCode)" 'Error'
        return [PSCustomObject]@{ ExitCode = 3; ExitCodeDetail = $proc.ExitCode }
    }
}

function Install-UpdateTeamsAsUser {
    Write-Log "Running in user context"
    
    # Check if already installed
    $status = Test-TeamsInstalled
    
    if ($status.Installed -and -not $Force) {
        Write-Log "Teams is installed (Version: $($status.Version))" 'Success'
        Write-Log "Checking for updates via WinGet..."
        $action = 'Update'
    } else {
        if ($Force -and $status.Installed) {
            Write-Log "Teams installed but -Force specified. Reinstalling..." 'Warning'
        } else {
            Write-Log "Teams is NOT installed. Will install..."
        }
        $action = 'Install'
    }
    
    # Check WinGet
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Log "WinGet not found. Install App Installer from Microsoft Store." 'Error'
        return [PSCustomObject]@{ ExitCode = 1; Error = "WinGet not found" }
    }
    
    Write-Log "WinGet found: $($winget.Source)"
    
    if (-not $PSCmdlet.ShouldProcess("Microsoft.Teams via WinGet", "$action Teams")) {
        Write-Log "[WHATIF] Would $action Teams using WinGet"
        return [PSCustomObject]@{ ExitCode = 0; WhatIf = $true; Action = $action }
    }
    
    # Update WinGet sources
    try {
        Write-Log "Refreshing WinGet sources..."
        & $winget.Source update 2>&1 | Out-Null
    }
    catch {
        Write-Log "Source update warning: $($_.Exception.Message)" 'Warning'
    }
    
    # Build arguments based on action
    if ($action -eq 'Update') {
        $arguments = @("upgrade", "--id", $WinGetPackageId, "--exact", "--accept-package-agreements", "--accept-source-agreements", "--disable-interactivity")
    } else {
        $arguments = @("install", "--id", $WinGetPackageId, "--exact", "--accept-package-agreements", "--accept-source-agreements", "--disable-interactivity")
    }
    
    if ($Force) {
        $arguments += "--force"
    }
    
    Write-Log "Executing: winget $($arguments -join ' ')"
    
    try {
        $proc = Start-Process -FilePath $winget.Source -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
        Write-Log "WinGet exit code: $($proc.ExitCode)"
        
        # Handle "no update available" as success for updates
        if ($action -eq 'Update' -and $proc.ExitCode -eq -1978335189) {
            Write-Log "No update available - Teams is current" 'Success'
            return [PSCustomObject]@{ ExitCode = 0; Action = 'UpToDate'; Version = $status.Version }
        }
        
        if ($proc.ExitCode -eq 0) {
            Start-Sleep -Seconds 3
            $newStatus = Test-TeamsInstalled
            Write-Log "Teams $action completed (Version: $($newStatus.Version))" 'Success'
            return [PSCustomObject]@{ ExitCode = 0; Action = $action; Version = $newStatus.Version }
        } else {
            Write-Log "WinGet failed with code $($proc.ExitCode)" 'Error'
            return [PSCustomObject]@{ ExitCode = 3; ExitCodeDetail = $proc.ExitCode }
        }
    }
    catch {
        Write-Log "Unexpected error: $($_.Exception.Message)" 'Error'
        return [PSCustomObject]@{ ExitCode = 9; Error = $_.Exception.Message }
    }
}

function Invoke-LocalInstallUpdate {
    $isSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
    Write-Log "User: $env:USERNAME, IsSystem: $isSystem"
    
    # Determine method
    $method = $InstallMethod
    if ($method -eq 'Auto') {
        $method = if ($isSystem) { 'Bootstrapper' } else { 'WinGet' }
        Write-Log "Auto-detected method: $method"
    }
    
    switch ($method) {
        'Bootstrapper' {
            if (-not $isSystem) {
                Write-Log "WARNING: Bootstrapper works best in SYSTEM context" 'Warning'
            }
            return Install-UpdateTeamsAsSystem
        }
        'WinGet' {
            return Install-UpdateTeamsAsUser
        }
        default {
            Write-Log "Unknown method: $method" 'Error'
            return [PSCustomObject]@{ ExitCode = 5; Error = "Unknown method: $method" }
        }
    }
}
#endregion

#region Remote Execution
function Invoke-RemoteInstallUpdate {
    param([string]$Computer, [PSCredential]$Cred)
    
    Write-Log "Connecting to $Computer..."
    
    $result = [PSCustomObject]@{
        ComputerName = $Computer
        ExitCode = 0
        Action = 'None'
        Version = $null
        Error = $null
    }
    
    try {
        if (-not (Test-Connection -ComputerName $Computer -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
            Write-Log "Ping failed for $Computer, trying WinRM..." 'Warning'
        }
        
        Test-WSMan -ComputerName $Computer -ErrorAction Stop | Out-Null
        
        $scriptBlock = {
            param($Force, $Method, $BootstrapperUrl)
            
            $tempScript = Join-Path $env:TEMP "UpdateTeams_$(Get-Random).ps1"
            
            $scriptContent = @'
param($Force, $Method, $BootstrapperUrl)
$ErrorActionPreference = 'SilentlyContinue'
$logPath = Join-Path $env:TEMP "Update-NewTeams_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log($Msg) { "$([DateTime]::Now.ToString('s')) $Msg" | Out-File -FilePath $logPath -Append -Encoding UTF8 }

$isSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
Write-Log "Starting on $env:COMPUTERNAME, IsSystem=$isSystem"

# Check if installed
$installed = Get-AppxPackage -Name MSTeams -ErrorAction SilentlyContinue
if ($installed -and -not $Force) {
    Write-Log "Teams installed, checking for updates"
    $action = 'Update'
} else {
    Write-Log "Teams not installed or Force specified"
    $action = 'Install'
}

if ($isSystem -or $Method -eq 'Bootstrapper') {
    $workDir = Join-Path $env:TEMP "TeamsBootstrapper"
    New-Item -ItemType Directory -Force -Path $workDir | Out-Null
    $bootstrapperPath = Join-Path $workDir "teamsbootstrapper.exe"
    
    if (-not (Test-Path $bootstrapperPath) -or $Force) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -UseBasicParsing -Uri $BootstrapperUrl -OutFile $bootstrapperPath -TimeoutSec 180
        } catch {
            Write-Log "Download failed: $($_.Exception.Message)"
            return @{ ExitCode = 2; Error = $_.Exception.Message }
        }
    }
    
    $proc = Start-Process -FilePath $bootstrapperPath -ArgumentList "-p" -Wait -PassThru -WindowStyle Hidden
    Write-Log "Bootstrapper exit: $($proc.ExitCode)"
    
    if ($proc.ExitCode -eq 0) {
        return @{ ExitCode = 0; Action = $action }
    } else {
        return @{ ExitCode = 3; ExitCodeDetail = $proc.ExitCode }
    }
} else {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) { return @{ ExitCode = 1; Error = "WinGet not found" } }
    
    if ($action -eq 'Update') {
        $args = @("upgrade", "--id", "Microsoft.Teams", "--exact", "--accept-package-agreements", "--accept-source-agreements", "--disable-interactivity")
    } else {
        $args = @("install", "--id", "Microsoft.Teams", "--exact", "--accept-package-agreements", "--accept-source-agreements", "--disable-interactivity")
    }
    
    $proc = Start-Process -FilePath $winget.Source -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
    
    if ($proc.ExitCode -eq -1978335189 -and $action -eq 'Update') {
        Write-Log "No update available"
        return @{ ExitCode = 0; Action = 'UpToDate' }
    }
    
    if ($proc.ExitCode -eq 0) {
        return @{ ExitCode = 0; Action = $action }
    } else {
        return @{ ExitCode = 3; ExitCodeDetail = $proc.ExitCode }
    }
}
'@
            
            Set-Content -Path $tempScript -Value $scriptContent
            $updateResult = & $tempScript @Params
            Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
            
            return $updateResult
        }
        
        $invokeParams = @{
            ComputerName = $Computer
            ScriptBlock = $scriptBlock
            ArgumentList = @(@{ Force = $Force; Method = $InstallMethod; BootstrapperUrl = $BootstrapperUrl })
            ErrorAction = 'Stop'
        }
        
        if ($Cred) { $invokeParams.Credential = $Cred }
        
        Write-Log "Executing on $Computer..."
        $remoteResult = Invoke-Command @invokeParams
        
        $result.ExitCode = $remoteResult.ExitCode
        $result.Action = $remoteResult.Action
        
        if ($result.ExitCode -eq 0) {
            Write-Log "$Computer`: $($result.Action) successful" 'Success'
        } else {
            Write-Log "$Computer`: Failed (Exit: $($result.ExitCode))" 'Error'
            $result.Error = $remoteResult.Error
        }
    }
    catch {
        $result.ExitCode = 4
        $result.Error = $_.Exception.Message
        Write-Log "Remote failed on ${Computer}: $($_.Exception.Message)" 'Error'
    }
    
    $script:Results.Add($result)
}
#endregion

#region Main
Initialize-LogPath
Show-Header

$computers = @()
if ($ComputerName) {
    $computers = $ComputerName
} else {
    $computers = @($env:COMPUTERNAME)
}

Write-Log "Processing $($computers.Count) computer(s)"

foreach ($computer in $computers) {
    if ($computer -eq $env:COMPUTERNAME -or $computer -eq 'localhost' -or $computer -eq '.') {
        Write-Host ""
        Write-Log "=== Processing Local Machine ==="
        $localResult = Invoke-LocalInstallUpdate
        
        $script:Results.Add([PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            ExitCode = $localResult.ExitCode
            Action = $localResult.Action
            Version = $localResult.Version
            Error = $localResult.Error
        })
        
        if (-not $PassThru -and $computers.Count -eq 1) {
            exit $localResult.ExitCode
        }
    }
    else {
        Write-Host ""
        $cred = if ($Credential) { $Credential } elseif (-not $UseCurrent) {
            Get-Credential -Message "Enter credentials for $computer"
        } else { $null }
        
        Invoke-RemoteInstallUpdate -Computer $computer -Cred $cred
    }
}

if ($computers.Count -gt 1 -or $ComputerName) {
    Show-Summary
}

if ($PassThru) {
    return $script:Results
}

$worstExit = ($script:Results | Measure-Object -Property ExitCode -Maximum).Maximum
exit $worstExit
#endregion
