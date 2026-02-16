#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs Adobe Acrobat Reader DC for Intune deployment.

.DESCRIPTION
    Downloads and installs Adobe Acrobat Reader DC (continuous track) silently.
    Configures common enterprise settings and removes bloatware (Adobe Genuine Service, etc.)

    Exit Codes:
    0 = Success
    1 = General failure
    3010 = Success, reboot required

    Author: Kyle Baker
    Version: 1.0
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$InstallerUrl = "https://ardownload2.adobe.com/pub/adobe/reader/win/AcrobatDC/2300620363/AcroRdrDC2300620363_en_US.exe",
    
    [Parameter()]
    [string]$InstallPath = "$env:TEMP\AdobeReaderSetup.exe",
    
    [Parameter()]
    [switch]$RemoveBloatware = $true,
    
    [Parameter()]
    [switch]$DisableUpdater = $true
)

#region Configuration
$ErrorActionPreference = "Stop"
$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AdobeReader-Install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$MaxDownloadAttempts = 3
$DownloadTimeout = 300 # seconds

# MSI properties for silent install
$MSIProperties = @(
    "/sAll",                    # Silent install
    "/rs",                      # Suppress reboot
    "/rps",                     # Suppress reboot
    "/msi",                     # MSI options follow
    "EULA_ACCEPT=YES",          # Accept EULA
    "DISABLE_DESKTOP_SHORTCUT=YES",
    "DISABLE_ARM_SERVICE_INSTALL=1"
)
#endregion

#region Logging
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info"
    )
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"
    
    $LogDir = Split-Path -Parent $LogPath
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    Add-Content -Path $LogPath -Value $LogEntry -ErrorAction SilentlyContinue
    
    switch ($Level) {
        "Info"    { Write-Host $LogEntry }
        "Warning" { Write-Warning $Message }
        "Error"   { Write-Error $Message }
        "Success" { Write-Host $LogEntry -ForegroundColor Green }
    }
}
#endregion

#region Functions
function Test-AdobeReaderInstalled {
    $Paths = @(
        "${env:ProgramFiles(x86)}\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe",
        "$env:ProgramFiles\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe"
    )
    
    foreach ($Path in $Paths) {
        if (Test-Path $Path) {
            return $true
        }
    }
    return $false
}

function Get-AdobeReaderVersion {
    $Paths = @(
        "${env:ProgramFiles(x86)}\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe",
        "$env:ProgramFiles\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe"
    )
    
    foreach ($Path in $Paths) {
        if (Test-Path $Path) {
            return (Get-ItemProperty $Path).VersionInfo.FileVersion
        }
    }
    return $null
}

function Remove-AdobeBloatware {
    Write-Log "Removing Adobe bloatware components..."
    
    $Bloatware = @(
        @{ Name = "Adobe Genuine Service"; GUID = "{AC76BA86-0804-1033-1959-0010835504B}" },
        @{ Name = "Adobe Acrobat Update Service"; GUID = "{AC76BA86-0000-0000-0000-6028747ADE01}" }
    )
    
    foreach ($App in $Bloatware) {
        try {
            $Installed = Get-WmiObject -Class Win32_Product | Where-Object { $_.IdentifyingNumber -eq $App.GUID }
            if ($Installed) {
                Write-Log "Removing: $($App.Name)"
                Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$($App.GUID)`" /qn /norestart" -Wait -WindowStyle Hidden
                Write-Log "Removed: $($App.Name)" -Level "Success"
            }
        }
        catch {
            Write-Log "Failed to remove $($App.Name): $_" -Level "Warning"
        }
    }
    
    # Remove desktop shortcuts
    $Shortcuts = @(
        "$env:Public\Desktop\Adobe Acrobat.lnk",
        "$env:Public\Desktop\Adobe Acrobat Reader.lnk"
    )
    foreach ($Shortcut in $Shortcuts) {
        if (Test-Path $Shortcut) {
            Remove-Item $Shortcut -Force
            Write-Log "Removed shortcut: $Shortcut"
        }
    }
}

function Disable-AdobeUpdater {
    Write-Log "Disabling Adobe Acrobat automatic updates..."
    
    # Registry keys to disable updater
    $RegistryPaths = @(
        "HKLM:\SOFTWARE\Policies\Adobe\Acrobat Reader\DC\FeatureLockDown",
        "HKLM:\SOFTWARE\Adobe\Acrobat Reader\DC\Installer",
        "HKLM:\SOFTWARE\Wow6432Node\Adobe\Acrobat Reader\DC\Installer"
    )
    
    foreach ($Path in $RegistryPaths) {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
    }
    
    # Disable auto-update
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Adobe\Acrobat Reader\DC\FeatureLockDown" -Name "bUpdater" -Value 0 -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Adobe\Acrobat Reader\DC\Installer" -Name "DisableMaintenance" -Value 1 -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Wow6432Node\Adobe\Acrobat Reader\DC\Installer" -Name "DisableMaintenance" -Value 1 -Force -ErrorAction SilentlyContinue
    
    Write-Log "Adobe updater disabled" -Level "Success"
}
#endregion

#region Main Script
try {
    Write-Log "=== Adobe Acrobat Reader DC Installation Started ==="
    Write-Log "PowerShell Version: $($PSVersionTable.PSVersion)"
    Write-Log "OS: $((Get-CimInstance Win32_OperatingSystem).Caption)"
    
    # Check if already installed
    if (Test-AdobeReaderInstalled) {
        $CurrentVersion = Get-AdobeReaderVersion
        Write-Log "Adobe Reader already installed (Version: $CurrentVersion)"
        Write-Log "Checking for updates..."
    }
    
    # Clean up any existing installer
    if (Test-Path $InstallPath) {
        Remove-Item $InstallPath -Force
        Write-Log "Cleaned up existing installer"
    }
    
    # Download installer
    Write-Log "Downloading Adobe Reader from: $InstallerUrl"
    $Attempt = 0
    $Downloaded = $false
    
    while ($Attempt -lt $MaxDownloadAttempts -and -not $Downloaded) {
        $Attempt++
        try {
            Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallPath -UseBasicParsing -TimeoutSec $DownloadTimeout
            $Downloaded = $true
            Write-Log "Download completed successfully (Attempt $Attempt)" -Level "Success"
        }
        catch {
            Write-Log "Download attempt $Attempt failed: $_" -Level "Warning"
            Start-Sleep -Seconds 5
        }
    }
    
    if (-not $Downloaded) {
        throw "Failed to download installer after $MaxDownloadAttempts attempts"
    }
    
    # Verify download
    if (-not (Test-Path $InstallPath)) {
        throw "Installer file not found after download"
    }
    
    $FileSize = (Get-Item $InstallPath).Length / 1MB
    Write-Log "Installer size: $([math]::Round($FileSize, 2)) MB"
    
    # Install Adobe Reader
    Write-Log "Installing Adobe Acrobat Reader DC..."
    Write-Log "Install arguments: $($MSIProperties -join ' ')"
    
    $Process = Start-Process -FilePath $InstallPath -ArgumentList $MSIProperties -Wait -PassThru -WindowStyle Hidden
    
    switch ($Process.ExitCode) {
        0 { 
            Write-Log "Installation completed successfully" -Level "Success"
        }
        3010 { 
            Write-Log "Installation completed - reboot required" -Level "Warning"
        }
        default { 
            throw "Installation failed with exit code: $($Process.ExitCode)"
        }
    }
    
    # Post-installation tasks
    if ($RemoveBloatware) {
        Remove-AdobeBloatware
    }
    
    if ($DisableUpdater) {
        Disable-AdobeUpdater
    }
    
    # Verify installation
    if (Test-AdobeReaderInstalled) {
        $InstalledVersion = Get-AdobeReaderVersion
        Write-Log "Adobe Reader installed successfully (Version: $InstalledVersion)" -Level "Success"
    } else {
        throw "Installation verification failed - Acrobat not found"
    }
    
    # Clean up
    Remove-Item $InstallPath -Force -ErrorAction SilentlyContinue
    Write-Log "Cleaned up installer files"
    
    Write-Log "=== Installation Completed ===" -Level "Success"
    
    # Return appropriate exit code
    if ($Process.ExitCode -eq 3010) {
        exit 3010  # Reboot required
    }
    exit 0
}
catch {
    Write-Log "ERROR: $_" -Level "Error"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level "Error"
    
    # Clean up on failure
    if (Test-Path $InstallPath) {
        Remove-Item $InstallPath -Force -ErrorAction SilentlyContinue
    }
    
    exit 1
}
#endregion
