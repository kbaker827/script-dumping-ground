<#
.SYNOPSIS
    Completely removes Microsoft Teams (new client) from Windows computers.

.DESCRIPTION
    This script performs a thorough removal of the new Microsoft Teams client (Teams 2.0).
    It can run locally or remotely via PowerShell Remoting.
    
    Actions performed:
    - Stops all Teams processes
    - Removes per-user AppxPackage installations
    - Removes machine-wide provisioned packages (admin)
    - Removes the machine-wide installer
    - Cleans up residual folders and caches
    - Optionally cleans up all user profiles
    - Generates detailed logs

.PARAMETER ComputerName
    Remote computer(s) to clean. If omitted, runs locally.

.PARAMETER Credential
    Credentials for remote connection.

.PARAMETER UseCurrent
    Use current credentials for remote connection.

.PARAMETER KeepUserData
    Preserves user profile data in AppData folders.

.PARAMETER AllUsers
    Removes Teams for all user profiles on the machine (requires admin).

.PARAMETER RemoveClassicTeams
    Also remove Classic Teams (Teams 1.0) if found.

.PARAMETER LogPath
    Path to save detailed log file.

.PARAMETER WhatIf
    Show what would be done without making changes.

.PARAMETER Force
    Suppress confirmation prompts.

.EXAMPLE
    .\Uninstall-NewTeams.ps1
    Removes new Teams completely from the local system.

.EXAMPLE
    .\Uninstall-NewTeams.ps1 -ComputerName PC01 -UseCurrent
    Removes Teams from remote computer PC01.

.EXAMPLE
    .\Uninstall-NewTeams.ps1 -ComputerName PC01,PC02 -Credential (Get-Credential)
    Removes Teams from multiple remote computers.

.EXAMPLE
    .\Uninstall-NewTeams.ps1 -AllUsers -Force
    Removes Teams for all users on local machine (no prompts).

.NOTES
    Version:        3.0
    Author:         IT Admin
    Updated:        2026-02-12
    
    Requirements:
    - Windows 10/11
    - PowerShell 5.1 or PowerShell 7+
    - Administrator rights for full cleanup (AllUsers, provisioned packages)
    
    Exit Codes:
    0   - Success
    1   - Partial success (some components not removed)
    2   - Remote connection failed
    3   - No removal performed
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
    [Alias('CN', 'MachineName', 'Name')]
    [string[]]$ComputerName,
    
    [PSCredential]$Credential,
    [switch]$UseCurrent,
    
    [switch]$KeepUserData,
    [switch]$AllUsers,
    [switch]$RemoveClassicTeams,
    
    [string]$LogPath = (Join-Path $env:TEMP "TeamsUninstall_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"),
    
    [switch]$WhatIf,
    [switch]$Force
)

#region Configuration
$ErrorActionPreference = 'SilentlyContinue'
$script:Version = "3.0"
$script:StartTime = Get-Date
$script:Results = [System.Collections.Generic.List[object]]::new()

# Teams process names
$script:NewTeamsProcesses = @('ms-teams', 'Teams', 'MSTeams', 'MicrosoftTeams')
$script:ClassicTeamsProcesses = @('Teams', 'Teams.exe')

# Paths to clean
$script:NewTeamsPaths = @(
    "Microsoft\Teams",
    "Microsoft\TeamsMeetingAddin",
    "Packages\MSTeams_8wekyb3d8bbwe"
)

$script:ClassicTeamsPaths = @(
    "Microsoft\Teams",
    "Microsoft\Teams - Preview"
)
#endregion

#region Helper Functions
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Action')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"
    
    # File logging
    try {
        Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
    } catch {}
    
    # Console output
    $colors = @{
        Info    = 'Cyan'
        Success = 'Green'
        Warning = 'Yellow'
        Error   = 'Red'
        Action  = 'White'
    }
    $prefix = switch ($Level) {
        'Info'    { '[*]' }
        'Success' { '[+]' }
        'Warning' { '[!]' }
        'Error'   { '[-]' }
        'Action'  { '[-]' }
    }
    
    Write-Host "$prefix $Message" -ForegroundColor $colors[$Level]
}

function Show-Header {
    Write-Host ""
    Write-Host "=================================" -ForegroundColor Cyan
    Write-Host " Microsoft Teams Uninstaller v$script:Version" -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Log "Started: $($script:StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level Info
    Write-Log "Log: $LogPath" -Level Info
    Write-Log "KeepUserData: $KeepUserData, AllUsers: $AllUsers, RemoveClassic: $RemoveClassicTeams" -Level Info
}

function Show-Summary {
    Write-Host ""
    Write-Host "=================================" -ForegroundColor Green
    Write-Host " SUMMARY" -ForegroundColor Green
    Write-Host "=================================" -ForegroundColor Green
    Write-Host ""
    
    $total = $script:Results.Count
    $success = ($script:Results | Where-Object { $_.Success }).Count
    $failed = ($script:Results | Where-Object { -not $_.Success }).Count
    
    Write-Log "Computers processed: $total" -Level Info
    Write-Log "Successful: $success" -Level $(if ($success -gt 0) { 'Success' } else { 'Info' })
    Write-Log "Failed: $failed" -Level $(if ($failed -gt 0) { 'Error' } else { 'Success' })
    
    if ($failed -gt 0) {
        $script:Results | Where-Object { -not $_.Success } | ForEach-Object {
            Write-Log "  - $($_.ComputerName): $($_.Error)" -Level Error
        }
    }
    
    $duration = (Get-Date) - $script:StartTime
    Write-Log "Duration: $($duration.ToString('mm\:ss'))" -Level Info
    Write-Log "Log saved: $LogPath" -Level Info
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Stop-TeamsProcesses {
    param([switch]$IncludeClassic)
    
    Write-Log "Stopping Teams processes..." -Level Action
    
    $processNames = $script:NewTeamsProcesses
    if ($IncludeClassic) {
        $processNames += $script:ClassicTeamsProcesses | Select-Object -Unique
    }
    
    $stoppedCount = 0
    foreach ($procName in $processNames) {
        $processes = Get-Process -Name $procName -ErrorAction SilentlyContinue
        foreach ($proc in $processes) {
            try {
                if ($PSCmdlet.ShouldProcess($proc.Name, "Stop Process")) {
                    $proc | Stop-Process -Force
                    $stoppedCount++
                    Write-Log "Stopped: $($proc.Name) (PID: $($proc.Id))" -Level Info
                }
            }
            catch {
                Write-Log "Failed to stop $($proc.Name): $($_.Exception.Message)" -Level Warning
            }
        }
    }
    
    if ($stoppedCount -gt 0) {
        Start-Sleep -Seconds 2
        Write-Log "Stopped $stoppedCount process(es)" -Level Success
    } else {
        Write-Log "No Teams processes running" -Level Info
    }
}

function Remove-NewTeamsAppx {
    param([switch]$IsAdmin)
    
    Write-Log "Checking for new Teams Appx packages..." -Level Info
    
    try {
        # Get packages
        if ($AllUsers -and $IsAdmin) {
            $teamsPackages = Get-AppxPackage -Name "MSTeams" -AllUsers -ErrorAction SilentlyContinue
        } else {
            $teamsPackages = Get-AppxPackage -Name "MSTeams" -ErrorAction SilentlyContinue
        }
        
        if ($teamsPackages) {
            Write-Log "Found $($teamsPackages.Count) Appx package(s)" -Level Info
            
            foreach ($package in $teamsPackages) {
                if ($PSCmdlet.ShouldProcess($package.PackageFullName, "Remove AppxPackage")) {
                    try {
                        if ($AllUsers -and $IsAdmin) {
                            Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
                        } else {
                            Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
                        }
                        Write-Log "Removed: $($package.PackageFullName)" -Level Success
                    }
                    catch {
                        Write-Log "Failed to remove $($package.PackageFullName): $($_.Exception.Message)" -Level Error
                    }
                }
            }
        } else {
            Write-Log "No new Teams Appx packages found" -Level Info
        }
    }
    catch {
        Write-Log "Error checking Appx packages: $($_.Exception.Message)" -Level Warning
    }
}

function Remove-ProvisionedTeams {
    Write-Log "Checking for provisioned Teams package..." -Level Info
    
    try {
        $provisionedPackage = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -eq 'MSTeams' }
        
        if ($provisionedPackage) {
            Write-Log "Found provisioned package: $($provisionedPackage.PackageName)" -Level Info
            
            if ($PSCmdlet.ShouldProcess($provisionedPackage.PackageName, "Remove Provisioned Package")) {
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $provisionedPackage.PackageName -ErrorAction Stop
                    Write-Log "Removed provisioned package" -Level Success
                }
                catch {
                    Write-Log "Failed to remove provisioned package: $($_.Exception.Message)" -Level Error
                }
            }
        } else {
            Write-Log "No provisioned package found" -Level Info
        }
    }
    catch {
        Write-Log "Error checking provisioned packages: $($_.Exception.Message)" -Level Warning
    }
}

function Remove-MachineWideInstaller {
    Write-Log "Checking for machine-wide installer..." -Level Info
    
    $machineWidePath = "${env:ProgramFiles(x86)}\Teams Installer"
    $teamsExe = Join-Path $machineWidePath "Teams.exe"
    
    if (Test-Path $teamsExe) {
        Write-Log "Running machine-wide uninstaller..." -Level Action
        
        if ($PSCmdlet.ShouldProcess($teamsExe, "Uninstall")) {
            try {
                $proc = Start-Process $teamsExe -ArgumentList "--uninstall -s" -Wait -PassThru -WindowStyle Hidden
                Write-Log "Uninstaller exit code: $($proc.ExitCode)" -Level Info
            }
            catch {
                Write-Log "Uninstaller failed: $($_.Exception.Message)" -Level Warning
            }
        }
    } else {
        Write-Log "No machine-wide installer found" -Level Info
    }
    
    # Clean up installer folder
    if (Test-Path $machineWidePath) {
        if ($PSCmdlet.ShouldProcess($machineWidePath, "Remove Directory")) {
            try {
                Remove-Item -Path $machineWidePath -Recurse -Force
                Write-Log "Removed: $machineWidePath" -Level Success
            }
            catch {
                Write-Log "Failed to remove $machineWidePath`: $($_.Exception.Message)" -Level Warning
            }
        }
    }
}

function Remove-ClassicTeams {
    Write-Log "Checking for Classic Teams..." -Level Info
    
    # Classic Teams uninstall string from registry
    $uninstallPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    
    $classicTeams = $null
    foreach ($path in $uninstallPaths) {
        $classicTeams = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -eq 'Microsoft Teams' -or $_.DisplayName -match 'Teams Machine-Wide Installer' }
        if ($classicTeams) { break }
    }
    
    if ($classicTeams) {
        Write-Log "Found Classic Teams installer" -Level Info
        
        if ($PSCmdlet.ShouldProcess("Classic Teams", "Uninstall")) {
            try {
                if ($classicTeams.UninstallString -match 'msiexec') {
                    $guid = [regex]::Match($classicTeams.UninstallString, '\{[A-F0-9-]+\}').Value
                    if ($guid) {
                        Start-Process "msiexec.exe" -ArgumentList "/x $guid /qn /norestart" -Wait
                        Write-Log "Classic Teams uninstalled via MSI" -Level Success
                    }
                }
            }
            catch {
                Write-Log "Failed to uninstall Classic Teams: $($_.Exception.Message)" -Level Warning
            }
        }
    } else {
        Write-Log "No Classic Teams installation found" -Level Info
    }
}

function Remove-ResidualData {
    param(
        [string]$ProfilePath = $env:USERPROFILE,
        [string]$Username = $env:USERNAME,
        [switch]$IsAdmin
    )
    
    if ($KeepUserData) {
        Write-Log "Skipping user data cleanup (KeepUserData specified)" -Level Info
        return
    }
    
    Write-Log "Cleaning up residual data for $Username..." -Level Action
    
    $localAppData = Join-Path $ProfilePath "AppData\Local"
    $roamingAppData = Join-Path $ProfilePath "AppData\Roaming"
    
    # Build path list
    $pathsToRemove = @()
    
    # New Teams paths
    foreach ($relPath in $script:NewTeamsPaths) {
        $pathsToRemove += Join-Path $localAppData $relPath
    }
    
    # Classic Teams paths (if requested)
    if ($RemoveClassicTeams) {
        foreach ($relPath in $script:ClassicTeamsPaths) {
            $pathsToRemove += Join-Path $localAppData $relPath
            $pathsToRemove += Join-Path $roamingAppData $relPath
        }
    }
    
    # Add ProgramData path if admin
    if ($IsAdmin) {
        $pathsToRemove += Join-Path $env:ProgramData "Microsoft\Teams"
    }
    
    $removedCount = 0
    foreach ($path in $pathsToRemove) {
        if (Test-Path $path) {
            if ($PSCmdlet.ShouldProcess($path, "Remove Directory")) {
                try {
                    Remove-Item -Path $path -Recurse -Force
                    Write-Log "Removed: $path" -Level Info
                    $removedCount++
                }
                catch {
                    Write-Log "Failed to remove $path`: $($_.Exception.Message)" -Level Warning
                }
            }
        }
    }
    
    Write-Log "Removed $removedCount residual folder(s)" -Level Success
}

function Remove-AllUserProfiles {
    param([switch]$IsAdmin)
    
    if (-not $AllUsers -or -not $IsAdmin) { return }
    
    Write-Log "Cleaning up all user profiles..." -Level Action
    
    $userProfiles = Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -notin @('Public', 'Default', 'Default User', 'All Users', 'WDAGUtilityAccount') }
    
    foreach ($profile in $userProfiles) {
        Remove-ResidualData -ProfilePath $profile.FullName -Username $profile.Name -IsAdmin:$IsAdmin
    }
}
#endregion

#region Main Functions
function Invoke-LocalUninstall {
    $isAdmin = Test-IsAdmin
    
    if (-not $isAdmin) {
        Write-Log "Running without admin rights - some cleanup may be limited" -Level Warning
    }
    
    # Stop processes
    Stop-TeamsProcesses -IncludeClassic:$RemoveClassicTeams
    
    # Remove new Teams Appx
    Remove-NewTeamsAppx -IsAdmin:$isAdmin
    
    # Remove provisioned package (admin only)
    if ($isAdmin) {
        Remove-ProvisionedTeams
    }
    
    # Remove machine-wide installer
    Remove-MachineWideInstaller
    
    # Remove Classic Teams if requested
    if ($RemoveClassicTeams -and $isAdmin) {
        Remove-ClassicTeams
    }
    
    # Remove residual data
    Remove-ResidualData -IsAdmin:$isAdmin
    
    # Clean all profiles if requested
    Remove-AllUserProfiles -IsAdmin:$isAdmin
    
    Write-Log "Uninstall complete" -Level Success
}

function Invoke-RemoteUninstall {
    param(
        [string]$Computer,
        [PSCredential]$Cred
    )
    
    Write-Log "Connecting to $Computer..." -Level Info
    
    $result = [PSCustomObject]@{
        ComputerName = $Computer
        Success = $false
        Error = $null
    }
    
    try {
        # Test connection
        if (-not (Test-Connection -ComputerName $Computer -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
            Write-Log "Ping failed for $Computer, trying WinRM..." -Level Warning
        }
        
        # Build remote script
        $scriptBlock = {
            param($Params)
            
            $tempScript = Join-Path $env:TEMP "TeamsUninstall_$(Get-Random).ps1"
            
            $scriptContent = @'
param($KeepUserData, $AllUsers, $RemoveClassic, $WhatIf)
$ErrorActionPreference = 'SilentlyContinue'

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$isAdmin = Test-IsAdmin

# Stop processes
$procs = @('ms-teams','Teams','MSTeams')
if ($RemoveClassic) { $procs += 'Teams' }
foreach ($name in $procs | Select-Object -Unique) {
    Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force
}
Start-Sleep -Seconds 2

# Remove Appx
$packages = Get-AppxPackage -Name "MSTeams" -ErrorAction SilentlyContinue
foreach ($pkg in $packages) {
    if (-not $WhatIf) {
        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue
    }
}

# Remove provisioned (if admin)
if ($isAdmin) {
    $prov = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq 'MSTeams' }
    if ($prov -and -not $WhatIf) {
        Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName
    }
    
    # Remove machine-wide installer
    $mwPath = "${env:ProgramFiles(x86)}\Teams Installer"
    if (Test-Path $mwPath) {
        $teamsExe = Join-Path $mwPath "Teams.exe"
        if (Test-Path $teamsExe -and -not $WhatIf) {
            Start-Process $teamsExe -ArgumentList "--uninstall -s" -Wait -WindowStyle Hidden
        }
        Remove-Item $mwPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Clean residual data
if (-not $KeepUserData) {
    $paths = @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\Teams"),
        (Join-Path $env:LOCALAPPDATA "Packages\MSTeams_8wekyb3d8bbwe"),
        (Join-Path $env:APPDATA "Microsoft\Teams")
    )
    foreach ($p in $paths) {
        if (Test-Path $p -and -not $WhatIf) {
            Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

"Completed on $env:COMPUTERNAME"
'@
            
            Set-Content -Path $tempScript -Value $scriptContent
            $output = & $tempScript @Params
            Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
            return $output
        }
        
        $invokeParams = @{
            ComputerName = $Computer
            ScriptBlock = $scriptBlock
            ArgumentList = @(@{
                KeepUserData = $KeepUserData
                AllUsers = $AllUsers
                RemoveClassic = $RemoveClassicTeams
                WhatIf = $WhatIf
            })
            ErrorAction = 'Stop'
        }
        
        if ($Cred) { $invokeParams.Credential = $Cred }
        
        $remoteResult = Invoke-Command @invokeParams
        Write-Log "Remote result: $remoteResult" -Level Success
        
        $result.Success = $true
    }
    catch {
        $result.Success = $false
        $result.Error = $_.Exception.Message
        Write-Log "Remote uninstall failed on ${Computer}: $($_.Exception.Message)" -Level Error
    }
    
    $script:Results.Add($result)
}
#endregion

#region Main Execution
Show-Header

# Confirmation
if (-not $Force -and -not $WhatIf) {
    $target = if ($ComputerName) { "remote computer(s): $($ComputerName -join ', ')" } else { "local machine" }
    $confirm = Read-Host "Remove Microsoft Teams from $target? (Y/N)"
    if ($confirm -notmatch '^(y|yes)$') {
        Write-Log "Operation cancelled by user" -Level Warning
        exit 0
    }
}

# Process computers
if ($ComputerName) {
    foreach ($computer in $ComputerName) {
        $cred = if ($Credential) { $Credential } elseif (-not $UseCurrent) { 
            Get-Credential -Message "Enter credentials for $computer" 
        } else { $null }
        
        Invoke-RemoteUninstall -Computer $computer -Cred $cred
    }
} else {
    Invoke-LocalUninstall
}

# Summary
Show-Summary

# Exit code
$failedCount = ($script:Results | Where-Object { -not $_.Success }).Count
if ($failedCount -eq 0) { exit 0 } else { exit 1 }
#endregion
