#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs Dell Command Update and updates all Dell drivers/BIOS.

.DESCRIPTION
    Checks for Dell Command Update, installs it if missing, then runs updates
    for all available Dell drivers, BIOS, and Command Update itself.
    Designed for Intune deployment with optional reboot control.

.PARAMETER DownloadURL
    Direct download URL for Dell Command Update installer

.PARAMETER InstallerPath
    Local path to Dell Command Update installer (if pre-staged)

.PARAMETER NoReboot
    Suppress automatic reboot after updates

.PARAMETER ScheduleReboot
    Schedule reboot for later instead of immediate

.PARAMETER RebootDelayMinutes
    Delay before reboot (default: 60)

.PARAMETER UpdateSeverity
    Minimum severity to install: critical, recommended, optional (default: recommended)

.PARAMETER UpdateType
    Types to update: bios,firmware,driver,application,utility (default: all)

.PARAMETER LogPath
    Path for operation logs

.PARAMETER WhatIf
    Preview what would be updated without installing

.EXAMPLE
    .\Install-DellCommandUpdate.ps1

.EXAMPLE
    .\Install-DellCommandUpdate.ps1 -NoReboot

.EXAMPLE
    .\Install-DellCommandUpdate.ps1 -ScheduleReboot -RebootDelayMinutes 120

.EXAMPLE
    .\Install-DellCommandUpdate.ps1 -UpdateSeverity critical -UpdateType bios,firmware

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
    Requirements:   Dell computer, Windows 10/11, Administrator rights
    
    Dell Command Update must be run on Dell hardware.
    Downloads from Dell if not pre-staged.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$DownloadURL = "",

    [Parameter(Mandatory=$false)]
    [string]$InstallerPath = "",

    [Parameter(Mandatory=$false)]
    [switch]$NoReboot,

    [Parameter(Mandatory=$false)]
    [switch]$ScheduleReboot,

    [Parameter(Mandatory=$false)]
    [int]$RebootDelayMinutes = 60,

    [Parameter(Mandatory=$false)]
    [ValidateSet("critical", "recommended", "optional")]
    [string]$UpdateSeverity = "recommended",

    [Parameter(Mandatory=$false)]
    [string]$UpdateType = "all",

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs",

    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

# Configuration
$ScriptName = "DellCommandUpdate"
$LogFile = "$LogPath\$ScriptName.log"
$TempPath = "$env:TEMP\DellCommandUpdate"
$DCUInstallPath = "${env:ProgramFiles(x86)}\Dell\CommandUpdate"
$DCUExePath = "$DCUInstallPath\dcu-cli.exe"

# Dell Command Update download URL (Universal version)
$DefaultDownloadURL = "https://dl.dell.com/FOLDER11563481M/1/Dell-Command-Update-Windows-Universal-Application_6VFWC_WIN_5.4.0_A00.EXE"

# Ensure log directory exists
if (!(Test-Path -Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "WHATIF")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $whatIfPrefix = if ($WhatIf -and $Level -ne "WHATIF") { "[WHATIF] " } else { "" }
    $logEntry = "[$timestamp] [$Level] $whatIfPrefix$Message"
    
    try {
        Add-Content -Path $LogFile -Value $logEntry -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host $logEntry
    }
    
    $color = switch ($Level) {
        "ERROR"   { "Red" }
        "WARN"    { "Yellow" }
        "SUCCESS" { "Green" }
        "WHATIF"  { "Cyan" }
        default   { "White" }
    }
    Write-Host $logEntry -ForegroundColor $color
}

function Test-IsDellComputer {
    try {
        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem
        $manufacturer = $computerSystem.Manufacturer
        
        if ($manufacturer -like "*Dell*") {
            Write-Log "Confirmed Dell computer: $($computerSystem.Model)" "SUCCESS"
            return $true
        }
        else {
            Write-Log "Not a Dell computer (Manufacturer: $manufacturer)" "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Failed to check manufacturer: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Test-DellCommandUpdateInstalled {
    try {
        # Check for installation directory
        if (Test-Path -Path $DCUExePath) {
            Write-Log "Dell Command Update found at: $DCUExePath" "SUCCESS"
            
            # Get version
            $versionInfo = (Get-Item $DCUExePath).VersionInfo
            Write-Log "Version: $($versionInfo.FileVersion)" "INFO"
            
            return $true
        }
        
        # Check registry
        $regPaths = @(
            "HKLM:\SOFTWARE\Dell\UpdateService",
            "HKLM:\SOFTWARE\WOW6432Node\Dell\UpdateService",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        
        foreach ($regPath in $regPaths) {
            if ($regPath -like "*\Uninstall\*") {
                $app = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | 
                    Where-Object { $_.DisplayName -like "*Dell Command*Update*" }
                if ($app) {
                    Write-Log "Dell Command Update found in registry: $($app.DisplayName) v$($app.DisplayVersion)" "SUCCESS"
                    return $true
                }
            }
            elseif (Test-Path -Path $regPath) {
                Write-Log "Dell Command Update registry found: $regPath" "SUCCESS"
                return $true
            }
        }
        
        Write-Log "Dell Command Update not found" "INFO"
        return $false
    }
    catch {
        Write-Log "Failed to check installation status: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Invoke-DellCommandUpdateDownload {
    param([string]$Url)
    
    try {
        if (!(Test-Path -Path $TempPath)) {
            New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
        }
        
        $outputFile = Join-Path $TempPath "DellCommandUpdate.exe"
        Write-Log "Downloading Dell Command Update from: $Url"
        
        if ($WhatIf) {
            Write-Log "Would download to: $outputFile" "WHATIF"
            return $outputFile
        }
        
        # Use BITS for reliable download
        try {
            Start-BitsTransfer -Source $Url -Destination $outputFile -ErrorAction Stop
            Write-Log "Download completed successfully" "SUCCESS"
        }
        catch {
            Write-Log "BITS failed, trying WebRequest..." "WARN"
            Invoke-WebRequest -Uri $Url -OutFile $outputFile -UseBasicParsing -ErrorAction Stop
        }
        
        if (Test-Path -Path $outputFile) {
            $fileSize = (Get-Item $outputFile).Length / 1MB
            Write-Log "Downloaded file size: $([math]::Round($fileSize, 2)) MB"
            return $outputFile
        }
        else {
            throw "Download file not found"
        }
    }
    catch {
        Write-Log "Download failed: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Install-DellCommandUpdate {
    param([string]$Installer)
    
    try {
        Write-Log "Installing Dell Command Update from: $Installer"
        
        if ($WhatIf) {
            Write-Log "Would install using: $Installer /S" "WHATIF"
            return $true
        }
        
        # Silent install
        $process = Start-Process -FilePath $Installer -ArgumentList "/S" -Wait -PassThru
        
        Write-Log "Installer exited with code: $($process.ExitCode)"
        
        # Wait a moment for installation to complete
        Start-Sleep -Seconds 5
        
        # Verify installation
        if (Test-Path -Path $DCUExePath) {
            Write-Log "Dell Command Update installed successfully" "SUCCESS"
            return $true
        }
        else {
            # Check alternate location
            $altPath = "$env:ProgramFiles\Dell\CommandUpdate\dcu-cli.exe"
            if (Test-Path -Path $altPath) {
                $script:DCUExePath = $altPath
                $script:DCUInstallPath = "$env:ProgramFiles\Dell\CommandUpdate"
                Write-Log "Dell Command Update found at alternate location: $altPath" "SUCCESS"
                return $true
            }
            
            Write-Log "Installation verification failed - executable not found" "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Installation failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Get-DellCommandUpdateStatus {
    try {
        Write-Log "Checking for available updates..."
        
        if (-not (Test-Path -Path $DCUExePath)) {
            Write-Log "Dell Command Update CLI not found" "ERROR"
            return $null
        }
        
        # Scan for updates
        $scanResult = & $DCUExePath /scan 2>&1
        Write-Log "Scan result: $scanResult"
        
        return $scanResult
    }
    catch {
        Write-Log "Failed to check update status: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Invoke-DellUpdates {
    try {
        Write-Log "Starting Dell updates (Severity: $UpdateSeverity, Types: $UpdateType)"
        
        if (-not (Test-Path -Path $DCUExePath)) {
            Write-Log "Dell Command Update CLI not found" "ERROR"
            return $false
        }
        
        if ($WhatIf) {
            Write-Log "Would run: $DCUExePath /applyUpdates -updateSeverity=$UpdateSeverity -updateType=$UpdateType" "WHATIF"
            return $true
        }
        
        # Build update arguments
        $updateArgs = @(
            "/applyUpdates",
            "-updateSeverity=$UpdateSeverity"
        )
        
        if ($UpdateType -ne "all") {
            $updateArgs += "-updateType=$UpdateType"
        }
        
        # Handle reboot options
        if ($NoReboot) {
            $updateArgs += "-reboot=disable"
            Write-Log "Reboot disabled - updates requiring restart will be pending"
        }
        elseif ($ScheduleReboot) {
            # DCU doesn't support scheduled reboot directly, we'll handle it separately
            Write-Log "Reboot will be scheduled for $RebootDelayMinutes minutes"
        }
        
        Write-Log "Running: $DCUExePath $($updateArgs -join ' ')"
        $updateResult = & $DCUExePath @updateArgs 2>&1
        
        Write-Log "Update result: $updateResult"
        
        # Check result
        if ($updateResult -match "completed successfully" -or 
            $updateResult -match "Update successful" -or
            $LASTEXITCODE -eq 0 -or
            $LASTEXITCODE -eq 1) {  # Exit code 1 often means success with pending reboot
            
            Write-Log "Updates completed successfully" "SUCCESS"
            
            # Check if reboot is needed
            if ($updateResult -match "reboot required" -or $updateResult -match "restart") {
                Write-Log "Reboot is required to complete updates" "WARN"
                return "REBOOT_REQUIRED"
            }
            
            return $true
        }
        else {
            Write-Log "Updates may have failed or partial success" "WARN"
            return $false
        }
    }
    catch {
        Write-Log "Update process failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Invoke-ScheduledReboot {
    try {
        Write-Log "Scheduling reboot in $RebootDelayMinutes minutes"
        
        if ($WhatIf) {
            Write-Log "Would schedule: shutdown /r /t $($RebootDelayMinutes * 60) /c 'Dell updates installed - restart scheduled'" "WHATIF"
            return
        }
        
        # Schedule reboot
        $seconds = $RebootDelayMinutes * 60
        $result = shutdown /r /t $seconds /c "Dell updates installed - restart scheduled" /f 2>&1
        Write-Log "Reboot scheduled: $result" "SUCCESS"
        
        # Notify user (optional - Windows will show default restart warning)
        Write-Log "System will restart in $RebootDelayMinutes minutes"
    }
    catch {
        Write-Log "Failed to schedule reboot: $($_.Exception.Message)" "ERROR"
    }
}

function Register-Operation {
    param(
        [bool]$Installed,
        [bool]$Updated,
        [bool]$RebootRequired,
        [bool]$Success
    )
    
    $regPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\DellCommandUpdate"
    
    try {
        if (!(Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $regPath -Name "LastRun" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Set-ItemProperty -Path $regPath -Name "DCUInstalled" -Value ([string]$Installed)
        Set-ItemProperty -Path $regPath -Name "UpdatesApplied" -Value ([string]$Updated)
        Set-ItemProperty -Path $regPath -Name "RebootRequired" -Value ([string]$RebootRequired)
        Set-ItemProperty -Path $regPath -Name "Success" -Value ([string]$Success)
        Set-ItemProperty -Path $regPath -Name "NoRebootFlag" -Value ([string]$NoReboot)
        
        Write-Log "Operation registered in registry" "SUCCESS"
    }
    catch {
        Write-Log "Failed to register operation: $($_.Exception.Message)" "WARN"
    }
}

# ==================== MAIN EXECUTION ====================

Write-Log "=== Dell Command Update Script Started ==="
Write-Log "Script version: 1.0"
Write-Log "Computer: $env:COMPUTERNAME"

if ($WhatIf) {
    Write-Log "RUNNING IN WHATIF MODE - NO CHANGES WILL BE MADE" "WHATIF"
}

# Check if Dell computer
if (-not (Test-IsDellComputer)) {
    Write-Log "This script is designed for Dell computers only" "ERROR"
    exit 1
}

$dcuWasInstalled = $false
$updatesApplied = $false
$rebootRequired = $false

# Check/Install Dell Command Update
$dcuInstalled = Test-DellCommandUpdateInstalled

if (-not $dcuInstalled) {
    Write-Log "Dell Command Update not found - installation required"
    
    # Determine installer source
    $installer = if (-not [string]::IsNullOrEmpty($InstallerPath) -and (Test-Path -Path $InstallerPath)) {
        $InstallerPath
    }
    elseif (-not [string]::IsNullOrEmpty($DownloadURL)) {
        Invoke-DellCommandUpdateDownload -Url $DownloadURL
    }
    else {
        Invoke-DellCommandUpdateDownload -Url $DefaultDownloadURL
    }
    
    if (-not $installer) {
        Write-Log "Failed to obtain installer" "ERROR"
        exit 1
    }
    
    # Install
    $installSuccess = Install-DellCommandUpdate -Installer $installer
    
    if (-not $installSuccess) {
        Write-Log "Dell Command Update installation failed" "ERROR"
        exit 1
    }
    
    $dcuWasInstalled = $true
    
    # Cleanup installer
    if (Test-Path -Path $TempPath) {
        Remove-Item -Path $TempPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
else {
    Write-Log "Dell Command Update already installed"
}

# Check for updates and apply
$updateResult = Invoke-DellUpdates

if ($updateResult -eq "REBOOT_REQUIRED") {
    $rebootRequired = $true
    $updatesApplied = $true
}
elseif ($updateResult -eq $true) {
    $updatesApplied = $true
}

# Handle reboot
if ($rebootRequired -and -not $NoReboot) {
    if ($ScheduleReboot) {
        Invoke-ScheduledReboot
    }
    else {
        Write-Log "Reboot is required to complete updates" "WARN"
        Write-Log "System will restart after script completes" "WARN"
        # Set flag for reboot
        $global:RebootNeeded = $true
    }
}
elseif ($rebootRequired -and $NoReboot) {
    Write-Log "Updates installed but reboot deferred (NoReboot specified)" "WARN"
    Write-Log "System must be restarted manually to complete updates" "WARN"
}

# Register completion
Register-Operation -Installed $dcuWasInstalled -Updated $updatesApplied -RebootRequired $rebootRequired -Success $true

Write-Log "=== Dell Command Update Script Completed ===" "SUCCESS"

# Trigger reboot if needed (and not scheduled)
if ($global:RebootNeeded -and -not $WhatIf) {
    Write-Log "Initiating immediate restart..."
    Start-Sleep -Seconds 5
    Restart-Computer -Force
}

exit 0