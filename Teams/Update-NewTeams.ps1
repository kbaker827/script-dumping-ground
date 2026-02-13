<#
.SYNOPSIS
    Updates or installs the new Microsoft Teams client locally or remotely.

.DESCRIPTION
    This script handles Teams updates/installation with context-aware execution:
    - SYSTEM context: Uses Teams Bootstrapper for machine-wide provisioning
    - User context: Uses WinGet for per-user installation
    - Remote execution: Can update Teams on remote computers via PowerShell Remoting
    
    Logs detailed version information before and after updates.

.PARAMETER ComputerName
    Remote computer(s) to update. If omitted, runs locally.

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

.PARAMETER WhatIf
    Show what would be done without making changes.

.PARAMETER PassThru
    Return result object instead of exit code.

.EXAMPLE
    .\Update-NewTeams.ps1
    Updates Teams locally using appropriate method for current context.

.EXAMPLE
    .\Update-NewTeams.ps1 -ComputerName PC01 -UseCurrent
    Updates Teams on remote computer PC01.

.EXAMPLE
    .\Update-NewTeams.ps1 -Force
    Forces reinstallation of Teams locally.

.EXAMPLE
    Get-ADComputer -Filter {Enabled -eq $true} | Select-Object -ExpandProperty Name | .\Update-NewTeams.ps1 -UseCurrent
    Updates Teams on all domain computers via pipeline.

.NOTES
    Version:        3.0
    Author:         IT Admin
    Updated:        2026-02-13
    
    Requirements:
    - Windows 10/11 (64-bit)
    - PowerShell 5.1 or PowerShell 7+
    - Internet connectivity for downloads
    - For remote: WinRM enabled on targets
    
    Exit Codes:
    0   = Success
    1   = WinGet not found (user context)
    2   = Bootstrapper download failed
    3   = Installation failed
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
$script:Version = "3.0"
$script:StartTime = Get-Date
$script:Results = [System.Collections.Generic.List[object]]::new()

$WinGetPackageId = 'Microsoft.Teams'

# Set default log path if not provided
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
            # Fallback to temp
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
    
    # Also output to console with colors
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
    Write-Host "  Microsoft Teams Updater v$Version" -ForegroundColor Cyan
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
    $failed = ($script:Results | Where-Object { $_.ExitCode -ne 0 }).Count
    
    Write-Log "Computers processed: $total"
    Write-Log "Successful: $success" $(if ($success -gt 0) { 'Success' } else { 'Info' })
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

function Get-TeamsUserVersion {
    try {
        $package = Get-AppxPackage -Name MSTeams -ErrorAction SilentlyContinue
        if ($package) {
            return [PSCustomObject]@{
                Scope = 'Per-User'
                Version = $package.Version.ToString()
                PackageFullName = $package.PackageFullName
                Installed = $true
            }
        }
    }
    catch {}
    
    return [PSCustomObject]@{
        Scope = 'Per-User'
        Version = $null
        PackageFullName = $null
        Installed = $false
    }
}

function Get-TeamsProvisionedInfo {
    $info = [PSCustomObject]@{
        Provisioned = $false
        ProvisionedVersion = $null
        InstalledUsers = 0
        SampleUserVersion = $null
    }
    
    try {
        $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction Stop | 
            Where-Object { $_.DisplayName -eq 'MSTeams' }
        if ($provisioned) {
            $info.Provisioned = $true
            $info.ProvisionedVersion = $provisioned.Version
        }
    }
    catch {}
    
    try {
        $allPackages = Get-AppxPackage -AllUsers -Name MSTeams -ErrorAction SilentlyContinue
        if ($allPackages) {
            $installedCount = @($allPackages | Select-Object -ExpandProperty PackageUserInformation -ErrorAction SilentlyContinue | 
                Where-Object { $_.InstallState -eq 'Installed' }).Count
            $info.InstalledUsers = $installedCount
            $sample = $allPackages | Select-Object -First 1
            if ($sample) {
                $info.SampleUserVersion = $sample.Version.ToString()
            }
        }
    }
    catch {}
    
    return $info
}

function Write-VersionComparison {
    param(
        [string]$Label,
        [PSCustomObject]$Before,
        [PSCustomObject]$After
    )
    
    $beforeVer = if ($Before.Installed) { $Before.Version } else { '(not installed)' }
    $afterVer = if ($After.Installed) { $After.Version } else { '(not installed)' }
    
    Write-Log "$Label version: $beforeVer -> $afterVer"
    if ($After.Installed -and $After.PackageFullName) {
        Write-Log "$Label package: $($After.PackageFullName)"
    }
}
#endregion

#region Local Update Functions
function Update-TeamsAsSystem {
    Write-Log "Running in SYSTEM context - using Teams Bootstrapper"
    
    # Get pre-update state
    $preProv = Get-TeamsProvisionedInfo
    Write-Log "Pre-update: Provisioned=$($preProv.Provisioned), Version=$($preProv.ProvisionedVersion), InstalledUsers=$($preProv.InstalledUsers)"
    
    # Check WhatIf
    if (-not $PSCmdlet.ShouldProcess("Teams Bootstrapper", "Download and Execute")) {
        Write-Log "[WHATIF] Would download and run Teams Bootstrapper"
        return [PSCustomObject]@{ ExitCode = 0; WhatIf = $true }
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
    
    # Download bootstrapper if needed
    if (-not (Test-Path $bootstrapperPath) -or $Force) {
        Write-Log "Downloading Teams Bootstrapper from $BootstrapperUrl..."
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -UseBasicParsing -Uri $BootstrapperUrl -OutFile $bootstrapperPath -TimeoutSec 180
            Write-Log "Download completed successfully" 'Success'
        }
        catch {
            Write-Log "ERROR: Failed to download Bootstrapper: $($_.Exception.Message)" 'Error'
            return [PSCustomObject]@{ ExitCode = 2; Error = $_.Exception.Message }
        }
    } else {
        Write-Log "Using existing Bootstrapper at $bootstrapperPath"
    }
    
    # Run bootstrapper
    Write-Log "Running: teamsbootstrapper.exe -p"
    try {
        $proc = Start-Process -FilePath $bootstrapperPath -ArgumentList "-p" -Wait -PassThru -WindowStyle Hidden
        Write-Log "Bootstrapper exit code: $($proc.ExitCode)"
    }
    catch {
        Write-Log "ERROR: Failed to run Bootstrapper: $($_.Exception.Message)" 'Error'
        return [PSCustomObject]@{ ExitCode = 3; Error = $_.Exception.Message }
    }
    
    # Get post-update state
    Start-Sleep -Seconds 3
    $postProv = Get-TeamsProvisionedInfo
    Write-Log "Post-update: Provisioned=$($postProv.Provisioned), Version=$($postProv.ProvisionedVersion), InstalledUsers=$($postProv.InstalledUsers)"
    
    if ($proc.ExitCode -eq 0) {
        Write-Log "Machine-wide Teams provisioned/updated successfully" 'Success'
        return [PSCustomObject]@{ ExitCode = 0; ProvisionedVersion = $postProv.ProvisionedVersion }
    } else {
        Write-Log "ERROR: Bootstrapper returned exit code $($proc.ExitCode)" 'Error'
        return [PSCustomObject]@{ ExitCode = 3; ExitCodeDetail = $proc.ExitCode }
    }
}

function Update-TeamsAsUser {
    Write-Log "Running in user context - using WinGet"
    
    # Check for WinGet
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Log "ERROR: WinGet not found. Install App Installer from Microsoft Store." 'Error'
        return [PSCustomObject]@{ ExitCode = 1; Error = "WinGet not found" }
    }
    
    Write-Log "WinGet found at: $($winget.Source)"
    
    # Get pre-update version
    $before = Get-TeamsUserVersion
    Write-Log "Pre-update: Installed=$($before.Installed), Version=$($before.Version)"
    
    # Check WhatIf
    if (-not $PSCmdlet.ShouldProcess("Microsoft.Teams via WinGet", "Install or Upgrade")) {
        Write-Log "[WHATIF] Would run: winget upgrade/install Microsoft.Teams"
        return [PSCustomObject]@{ ExitCode = 0; WhatIf = $true }
    }
    
    # Update sources
    try {
        Write-Log "Refreshing WinGet sources..."
        & $winget.Source update 2>&1 | Out-Null
    }
    catch {
        Write-Log "WARN: Source update failed (continuing anyway): $($_.Exception.Message)" 'Warning'
    }
    
    # Try upgrade first, then install
    $arguments = @(
        "upgrade",
        "--id", $WinGetPackageId,
        "--exact",
        "--accept-package-agreements",
        "--accept-source-agreements",
        "--disable-interactivity"
    )
    
    if ($Force) {
        $arguments += "--force"
    }
    
    Write-Log "Executing: winget $($arguments -join ' ')"
    
    try {
        $proc = Start-Process -FilePath $winget.Source -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
        Write-Log "WinGet exit code: $($proc.ExitCode)"
        
        # WinGet exit codes: 0 = success, -1978335189 = no applicable update found (try install)
        if ($proc.ExitCode -eq -1978335189 -or $proc.ExitCode -eq 0x8A150014) {
            Write-Log "Upgrade not applicable; attempting fresh install..."
            $arguments[0] = "install"
            Write-Log "Executing: winget $($arguments -join ' ')"
            $proc = Start-Process -FilePath $winget.Source -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
            Write-Log "WinGet install exit code: $($proc.ExitCode)"
        }
        
        if ($proc.ExitCode -eq 0) {
            # Get post-update version
            Start-Sleep -Seconds 3
            $after = Get-TeamsUserVersion
            Write-VersionComparison -Label 'Per-user MSTeams' -Before $before -After $after
            Write-Log "Per-user Teams installed/updated successfully" 'Success'
            return [PSCustomObject]@{ ExitCode = 0; Version = $after.Version }
        } else {
            Write-Log "ERROR: WinGet returned exit code $($proc.ExitCode)" 'Error'
            return [PSCustomObject]@{ ExitCode = 3; ExitCodeDetail = $proc.ExitCode }
        }
    }
    catch {
        Write-Log "UNEXPECTED ERROR: $($_.Exception.Message)" 'Error'
        return [PSCustomObject]@{ ExitCode = 9; Error = $_.Exception.Message }
    }
}

function Invoke-LocalUpdate {
    $isSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
    Write-Log "User: $env:USERNAME, IsSystem: $isSystem"
    
    # Determine method
    $method = $InstallMethod
    if ($method -eq 'Auto') {
        $method = if ($isSystem) { 'Bootstrapper' } else { 'WinGet' }
        Write-Log "Auto-detected install method: $method"
    }
    
    # Execute appropriate method
    switch ($method) {
        'Bootstrapper' {
            if (-not $isSystem) {
                Write-Log "WARNING: Bootstrapper works best in SYSTEM context" 'Warning'
            }
            return Update-TeamsAsSystem
        }
        'WinGet' {
            return Update-TeamsAsUser
        }
        default {
            Write-Log "ERROR: Unknown install method: $method" 'Error'
            return [PSCustomObject]@{ ExitCode = 5; Error = "Unknown method: $method" }
        }
    }
}
#endregion

#region Remote Execution
function Invoke-RemoteUpdate {
    param(
        [string]$Computer,
        [PSCredential]$Cred
    )
    
    Write-Log "Connecting to $Computer..."
    
    $result = [PSCustomObject]@{
        ComputerName = $Computer
        ExitCode = 0
        Version = $null
        Error = $null
    }
    
    try {
        # Test connection
        if (-not (Test-Connection -ComputerName $Computer -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
            Write-Log "Ping failed for $Computer, trying WinRM anyway..." 'Warning'
        }
        
        # Check WinRM
        Test-WSMan -ComputerName $Computer -ErrorAction Stop | Out-Null
        
        # Build remote script
        $scriptBlock = {
            param($Params)
            
            $tempScript = Join-Path $env:TEMP "UpdateTeams_$(Get-Random).ps1"
            
            $scriptContent = @'
param($Force, $Method, $BootstrapperUrl)
$ErrorActionPreference = 'SilentlyContinue'
$logPath = Join-Path $env:TEMP "Update-NewTeams_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log($Msg) {
    "$([DateTime]::Now.ToString('s')) $Msg" | Out-File -FilePath $logPath -Append -Encoding UTF8
}

$isSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
Write-Log "Starting update on $env:COMPUTERNAME, IsSystem=$isSystem"

if ($isSystem -or $Method -eq 'Bootstrapper') {
    # System/Bootstrapper method
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
        return @{ ExitCode = 0; Method = 'Bootstrapper' }
    } else {
        return @{ ExitCode = 3; ExitCodeDetail = $proc.ExitCode }
    }
} else {
    # WinGet method
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        return @{ ExitCode = 1; Error = "WinGet not found" }
    }
    
    $args = @("upgrade", "--id", "Microsoft.Teams", "--exact", "--accept-package-agreements", "--accept-source-agreements", "--disable-interactivity")
    $proc = Start-Process -FilePath $winget.Source -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
    
    if ($proc.ExitCode -eq -1978335189) {
        $args[0] = "install"
        $proc = Start-Process -FilePath $winget.Source -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
    }
    
    if ($proc.ExitCode -eq 0) {
        return @{ ExitCode = 0; Method = 'WinGet' }
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
            ArgumentList = @(@{
                Force = $Force
                Method = $InstallMethod
                BootstrapperUrl = $BootstrapperUrl
            })
            ErrorAction = 'Stop'
        }
        
        if ($Cred) { $invokeParams.Credential = $Cred }
        
        Write-Log "Executing update on $Computer..."
        $remoteResult = Invoke-Command @invokeParams
        
        $result.ExitCode = $remoteResult.ExitCode
        $result.Version = $remoteResult.Version
        
        if ($result.ExitCode -eq 0) {
            Write-Log "$Computer`: Update successful (Method: $($remoteResult.Method))" 'Success'
        } else {
            Write-Log "$Computer`: Update failed (Exit: $($result.ExitCode))" 'Error'
            $result.Error = $remoteResult.Error
        }
    }
    catch {
        $result.ExitCode = 4
        $result.Error = $_.Exception.Message
        Write-Log "Remote update failed on ${Computer}: $($_.Exception.Message)" 'Error'
    }
    
    $script:Results.Add($result)
    return $result
}
#endregion

#region Main Execution
Initialize-LogPath
Show-Header

# Determine computers to process
$computers = @()
if ($ComputerName) {
    $computers = $ComputerName
} else {
    $computers = @($env:COMPUTERNAME)
}

Write-Log "Processing $($computers.Count) computer(s)"

# Process each computer
foreach ($computer in $computers) {
    if ($computer -eq $env:COMPUTERNAME -or $computer -eq 'localhost' -or $computer -eq '.') {
        # Local execution
        Write-Host ""
        Write-Log "=== Processing Local Machine ==="
        $localResult = Invoke-LocalUpdate
        
        $script:Results.Add([PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            ExitCode = $localResult.ExitCode
            Version = $localResult.Version
            Error = $localResult.Error
        })
        
        if (-not $PassThru) {
            exit $localResult.ExitCode
        }
    }
    else {
        # Remote execution
        Write-Host ""
        $cred = if ($Credential) { $Credential } elseif (-not $UseCurrent) {
            Get-Credential -Message "Enter credentials for $computer"
        } else { $null }
        
        Invoke-RemoteUpdate -Computer $computer -Cred $cred | Out-Null
    }
}

# Show summary for multi-computer operations
if ($computers.Count -gt 1 -or $ComputerName) {
    Show-Summary
}

# Return results if PassThru
if ($PassThru) {
    return $script:Results
}

# Exit with worst exit code
$worstExit = ($script:Results | Measure-Object -Property ExitCode -Maximum).Maximum
exit $worstExit
#endregion
