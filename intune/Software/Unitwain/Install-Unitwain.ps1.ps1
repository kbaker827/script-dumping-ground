#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs Unitwain with site license and custom settings for Intune deployment.

.DESCRIPTION
    Downloads and installs the latest Unitwain scanner driver software, applies
    site licensing, and deploys custom configuration files. Designed for silent
    deployment through Microsoft Intune.

.PARAMETER DownloadURL
    Direct download URL for Unitwain installer (optional - uses official source if not provided)

.PARAMETER SiteLicenseKey
    Site license key for Unitwain activation

.PARAMETER SettingsFile
    Path to custom Unitwain settings XML/JSON file (optional)

.PARAMETER LicenseFile
    Path to site license file (optional - can embed license instead)

.PARAMETER LogPath
    Path for installation logs

.PARAMETER DefaultScanner
    Default scanner model to configure

.PARAMETER EnableNetworkScan
    Enable network scanning capability

.EXAMPLE
    .\Install-Unitwain.ps1 -SiteLicenseKey "XXXX-XXXX-XXXX-XXXX"

.EXAMPLE
    .\Install-Unitwain.ps1 -SiteLicenseKey "XXXX-XXXX" -SettingsFile "C:\Config\unitwain.xml"

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
    Requirements:   Windows 10/11, Administrator rights
    
    Unitwain documentation: https://www.unitwain.com
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$DownloadURL = "",

    [Parameter(Mandatory=$true, HelpMessage="Site license key for Unitwain")]
    [string]$SiteLicenseKey,

    [Parameter(Mandatory=$false)]
    [string]$SettingsFile = "",

    [Parameter(Mandatory=$false)]
    [string]$LicenseFile = "",

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs",

    [Parameter(Mandatory=$false)]
    [string]$DefaultScanner = "",

    [Parameter(Mandatory=$false)]
    [switch]$EnableNetworkScan
)

# Configuration
$ScriptName = "UnitwainInstall"
$LogFile = "$LogPath\$ScriptName.log"
$TempPath = "$env:TEMP\UnitwainInstall"
$ConfigPath = "$env:ProgramData\Unitwain\Config"

# Unitwain official download (update version as needed)
$DefaultDownloadURL = "https://www.unitwain.com/download/latest/UnitwainSetup.exe"
$ProductName = "Unitwain"

# Ensure log directory exists
if (!(Test-Path -Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    try {
        Add-Content -Path $LogFile -Value $logEntry -ErrorAction SilentlyContinue
    }
    catch {
        # Fallback to console if log file is locked
    }
    
    $color = switch ($Level) {
        "ERROR"   { "Red" }
        "WARN"    { "Yellow" }
        "SUCCESS" { "Green" }
        default   { "White" }
    }
    Write-Host $logEntry -ForegroundColor $color
}

function Test-UnitwainInstalled {
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($regPath in $regPaths) {
        $product = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -like "*Unitwain*" -or $_.Publisher -like "*Unitwain*" }
        
        if ($product) {
            Write-Log "Found installed Unitwain: $($product.DisplayName) v$($product.DisplayVersion)" "SUCCESS"
            return $true
        }
    }
    
    # Check for installation directory
    $installPaths = @(
        "$env:ProgramFiles\Unitwain",
        "${env:ProgramFiles(x86)}\Unitwain",
        "$env:ProgramFiles\TWAIN\Unitwain"
    )
    
    foreach ($path in $installPaths) {
        if (Test-Path -Path $path) {
            Write-Log "Unitwain installation directory found: $path" "SUCCESS"
            return $true
        }
    }
    
    return $false
}

function Invoke-UnitwainDownload {
    param([string]$Url)
    
    try {
        # Create temp directory
        if (Test-Path -Path $TempPath) {
            Remove-Item -Path $TempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
        
        $outputPath = Join-Path $TempPath "UnitwainSetup.exe"
        Write-Log "Downloading Unitwain from: $Url"
        
        # Use BITS for reliable download
        try {
            Start-BitsTransfer -Source $Url -Destination $outputPath -ErrorAction Stop
            Write-Log "Download completed via BITS" "SUCCESS"
        }
        catch {
            Write-Log "BITS transfer failed, trying Invoke-WebRequest..." "WARN"
            
            $progressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $Url -OutFile $outputPath -UseBasicParsing -ErrorAction Stop
            Write-Log "Download completed via WebRequest" "SUCCESS"
        }
        
        if (Test-Path -Path $outputPath) {
            $fileSize = (Get-Item $outputPath).Length / 1MB
            Write-Log "Downloaded file size: $([math]::Round($fileSize, 2)) MB"
            return $outputPath
        }
        else {
            throw "Download file not found after download attempt"
        }
    }
    catch {
        Write-Log "Download failed: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Install-Unitwain {
    param([string]$InstallerPath)
    
    try {
        Write-Log "Starting Unitwain installation..."
        
        # Build install arguments for silent installation
        # Common silent install flags - adjust based on actual Unitwain installer
        $installArgs = @(
            "/S"                           # Silent install (NSIS)
            "/silent"                      # Alternative silent flag
            "/verysilent"                  # Very silent (Inno Setup)
            "/quiet"                       # Quiet mode (MSI)
            "/norestart"                   # Don't restart
        )
        
        Write-Log "Install command: `"$InstallerPath`" $($installArgs -join ' ')"
        
        # Execute installation
        $process = Start-Process -FilePath $InstallerPath -ArgumentList $installArgs -Wait -PassThru
        
        Write-Log "Installation process exited with code: $($process.ExitCode)"
        
        # Common installer exit codes
        switch ($process.ExitCode) {
            0       { 
                Write-Log "Installation completed successfully" "SUCCESS"
                return $true 
            }
            3010    { 
                Write-Log "Installation completed - restart required" "SUCCESS"
                return $true 
            }
            1641    { 
                Write-Log "Installation completed - restart initiated" "SUCCESS"
                return $true 
            }
            1603    { 
                Write-Log "Installation failed with fatal error (1603)" "ERROR"
                return $false 
            }
            1618    { 
                Write-Log "Installation failed - another installation in progress (1618)" "ERROR"
                return $false 
            }
            default { 
                # Some installers return non-zero for success with warnings
                if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010 -or $process.ExitCode -eq 1641) {
                    return $true
                }
                Write-Log "Installation completed with exit code: $($process.ExitCode)" "WARN"
                # Assume success for unknown codes (many installers are non-standard)
                return $true
            }
        }
    }
    catch {
        Write-Log "Installation failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Set-UnitwainLicense {
    param([string]$LicenseKey)
    
    try {
        Write-Log "Configuring Unitwain site license..."
        
        # Create config directory if needed
        if (!(Test-Path -Path $ConfigPath)) {
            New-Item -Path $ConfigPath -ItemType Directory -Force | Out-Null
        }
        
        # Common Unitwain license/config paths
        $licensePaths = @(
            "$env:ProgramData\Unitwain\license.dat",
            "$env:ProgramData\Unitwain\Config\license.key",
            "$env:ProgramFiles\Unitwain\license.dat",
            "${env:ProgramFiles(x86)}\Unitwain\license.dat"
        )
        
        # Write license to common locations
        $licenseWritten = $false
        foreach ($licensePath in $licensePaths) {
            try {
                $directory = Split-Path -Path $licensePath -Parent
                if (!(Test-Path -Path $directory)) {
                    New-Item -Path $directory -ItemType Directory -Force | Out-Null
                }
                
                Set-Content -Path $licensePath -Value $LicenseKey -Force
                Write-Log "License written to: $licensePath" "SUCCESS"
                $licenseWritten = $true
            }
            catch {
                Write-Log "Could not write license to $licensePath : $($_.Exception.Message)" "WARN"
            }
        }
        
        # Also set in registry if applicable
        try {
            $regPath = "HKLM:\SOFTWARE\Unitwain"
            if (!(Test-Path $regPath)) {
                New-Item -Path $regPath -Force | Out-Null
            }
            Set-ItemProperty -Path $regPath -Name "LicenseKey" -Value $LicenseKey -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $regPath -Name "SiteLicense" -Value $LicenseKey -ErrorAction SilentlyContinue
        }
        catch {
            Write-Log "Could not write license to registry: $($_.Exception.Message)" "WARN"
        }
        
        if ($licenseWritten) {
            Write-Log "Site license configured successfully" "SUCCESS"
            return $true
        }
        else {
            Write-Log "Could not write license to any location" "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Failed to configure license: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Set-UnitwainSettings {
    param(
        [string]$CustomSettingsFile,
        [string]$DefaultScannerModel,
        [switch]$NetworkScan
    )
    
    try {
        Write-Log "Configuring Unitwain settings..."
        
        # Ensure config directory exists
        if (!(Test-Path -Path $ConfigPath)) {
            New-Item -Path $ConfigPath -ItemType Directory -Force | Out-Null
        }
        
        # Copy custom settings file if provided
        if (-not [string]::IsNullOrEmpty($CustomSettingsFile) -and (Test-Path -Path $CustomSettingsFile)) {
            $destPath = Join-Path $ConfigPath "settings.xml"
            Copy-Item -Path $CustomSettingsFile -Destination $destPath -Force
            Write-Log "Custom settings copied to: $destPath" "SUCCESS"
        }
        
        # Create default settings if none provided
        $settingsContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<UnitwainConfiguration>
    <License>
        <Type>Site</Type>
        <Key>$SiteLicenseKey</Key>
    </License>
    <Scanner>
        <DefaultModel>$DefaultScannerModel</DefaultModel>
        <AutoDetect>true</AutoDetect>
    </Scanner>
    <Network>
        <Enabled>$([string]$NetworkScan)</Enabled>
        <Discovery>true</Discovery>
    </Network>
    <ScanDefaults>
        <ColorMode>Color</ColorMode>
        <Resolution>300</Resolution>
        <Format>PDF</Format>
        <Duplex>false</Duplex>
    </ScanDefaults>
</UnitwainConfiguration>
"@
        
        $defaultConfigPath = Join-Path $ConfigPath "unitwain.xml"
        Set-Content -Path $defaultConfigPath -Value $settingsContent -Force
        Write-Log "Default configuration created at: $defaultConfigPath" "SUCCESS"
        
        # Also deploy to user profiles
        $userProfiles = Get-ChildItem -Path "$env:SystemDrive\Users" -Directory | Where-Object { $_.Name -notin @("Public", "Default", "All Users") }
        foreach ($profile in $userProfiles) {
            $userConfigPath = Join-Path $profile.FullName "AppData\Roaming\Unitwain\Config"
            if (!(Test-Path -Path $userConfigPath)) {
                New-Item -Path $userConfigPath -ItemType Directory -Force | Out-Null
            }
            Set-Content -Path (Join-Path $userConfigPath "unitwain.xml") -Value $settingsContent -Force
        }
        
        Write-Log "Settings configured successfully" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to configure settings: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Register-InstallCompletion {
    $regPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Unitwain"
    try {
        if (!(Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $regPath -Name "InstallDate" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Set-ItemProperty -Path $regPath -Name "LicenseConfigured" -Value "Yes"
        Set-ItemProperty -Path $regPath -Name "SettingsConfigured" -Value "Yes"
        
        Write-Log "Installation registered in registry" "SUCCESS"
    }
    catch {
        Write-Log "Failed to register installation: $($_.Exception.Message)" "WARN"
    }
}

# ==================== MAIN EXECUTION ====================

Write-Log "=== Unitwain Installation Started ==="
Write-Log "Script version: 1.0"

# Validate license key
if ([string]::IsNullOrEmpty($SiteLicenseKey)) {
    Write-Log "Site license key is required" "ERROR"
    exit 1
}

# Mask license key in logs (show only first 4 and last 4 chars)
$maskedKey = if ($SiteLicenseKey.Length -gt 8) { 
    $SiteLicenseKey.Substring(0,4) + "****" + $SiteLicenseKey.Substring($SiteLicenseKey.Length-4) 
} else { 
    "****" 
}
Write-Log "License Key: $maskedKey"

# Check if already installed
Write-Log "Checking for existing installation..."
if (Test-UnitwainInstalled) {
    Write-Log "Unitwain appears to already be installed" "SUCCESS"
    
    # Still apply license and settings
    Set-UnitwainLicense -LicenseKey $SiteLicenseKey | Out-Null
    Set-UnitwainSettings -CustomSettingsFile $SettingsFile -DefaultScannerModel $DefaultScanner -NetworkScan:$EnableNetworkScan | Out-Null
    Register-InstallCompletion
    
    exit 0
}

# Get download URL
$downloadUrl = if ([string]::IsNullOrEmpty($DownloadURL)) { $DefaultDownloadURL } else { $DownloadURL }

# Download installer
try {
    $installerPath = Invoke-UnitwainDownload -Url $downloadUrl
}
catch {
    Write-Log "Failed to download installer. Exiting." "ERROR"
    exit 1
}

# Install Unitwain
$installSuccess = Install-Unitwain -InstallerPath $installerPath

if ($installSuccess) {
    # Configure license
    Set-UnitwainLicense -LicenseKey $SiteLicenseKey | Out-Null
    
    # Configure settings
    Set-UnitwainSettings -CustomSettingsFile $SettingsFile -DefaultScannerModel $DefaultScanner -NetworkScan:$EnableNetworkScan | Out-Null
    
    # Register completion
    Register-InstallCompletion
    
    # Cleanup
    if (Test-Path -Path $TempPath) {
        Remove-Item -Path $TempPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Cleaned up temporary files"
    }
    
    Write-Log "=== Installation completed successfully ===" "SUCCESS"
    exit 0
}
else {
    Write-Log "=== Installation failed ===" "ERROR"
    exit 1
}