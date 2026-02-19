#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs or updates Microsoft OneDrive to the latest version.

.DESCRIPTION
    Checks for OneDrive installation, installs the latest version if missing,
    or updates the existing installation. Supports both per-user and per-machine
    (all users) installations. Designed for Microsoft Intune deployment.

.PARAMETER InstallMode
    Installation mode: "PerMachine" (all users) or "PerUser" (current user only)

.PARAMETER DownloadURL
    Direct download URL for OneDrive installer

.PARAMETER EnableSilentConfig
    Enable silent configuration (auto sign-in with Windows account)

.PARAMETER EnableFilesOnDemand
    Enable Files On-Demand feature

.PARAMETER DisableAutoStart
    Disable OneDrive auto-start with Windows

.PARAMETER KnownFolderMove
    Enable Known Folder Move (redirect Desktop/Documents/Pictures to OneDrive)

.PARAMETER KFMSilentOptIn
    Silently opt-in to Known Folder Move (requires tenant ID)

.PARAMETER TenantID
    Azure AD Tenant ID for silent configuration and KFM

.PARAMETER LogPath
    Path for installation logs

.PARAMETER ForceUpdate
    Force update even if already on latest version

.EXAMPLE
    .\Install-OneDrive.ps1

.EXAMPLE
    .\Install-OneDrive.ps1 -InstallMode PerMachine

.EXAMPLE
    .\Install-OneDrive.ps1 -InstallMode PerMachine -EnableSilentConfig -TenantID "12345678-1234-1234-1234-123456789012"

.EXAMPLE
    .\Install-OneDrive.ps1 -KnownFolderMove -KFMSilentOptIn -TenantID "12345678-1234-1234-1234-123456789012"

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
    Requirements:   Windows 10/11, Administrator rights (for PerMachine mode)
    
    OneDrive standalone installer download page:
    https://support.microsoft.com/en-us/office/onedrive-release-notes-845dcf18-f921-435e-bf28-4e24b95e5fc0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("PerMachine", "PerUser")]
    [string]$InstallMode = "PerMachine",

    [Parameter(Mandatory=$false)]
    [string]$DownloadURL = "",

    [Parameter(Mandatory=$false)]
    [switch]$EnableSilentConfig,

    [Parameter(Mandatory=$false)]
    [switch]$EnableFilesOnDemand = $true,

    [Parameter(Mandatory=$false)]
    [switch]$DisableAutoStart,

    [Parameter(Mandatory=$false)]
    [switch]$KnownFolderMove,

    [Parameter(Mandatory=$false)]
    [switch]$KFMSilentOptIn,

    [Parameter(Mandatory=$false)]
    [string]$TenantID = "",

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs",

    [Parameter(Mandatory=$false)]
    [switch]$ForceUpdate
)

# Configuration
$ScriptName = "OneDriveInstall"
$LogFile = "$LogPath\$ScriptName.log"
$TempPath = "$env:TEMP\OneDriveInstall"

# OneDrive download URLs
$OneDriveDownloadURLs = @{
    PerMachine = "https://go.microsoft.com/fwlink/?linkid=844652"  # Standalone Enterprise (all users)
    PerUser    = "https://go.microsoft.com/fwlink/?linkid=844651"  # Standalone (current user)
}

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
        Write-Host $logEntry
    }
    
    $color = switch ($Level) {
        "ERROR"   { "Red" }
        "WARN"    { "Yellow" }
        "SUCCESS" { "Green" }
        default   { "White" }
    }
    Write-Host $logEntry -ForegroundColor $color
}

function Get-OneDriveInfo {
    $oneDrivePaths = @{
        PerMachine = "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe"
        PerUser    = "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
    }
    
    $info = @{
        Installed = $false
        Version = $null
        InstallPath = $null
        InstallMode = $null
    }
    
    # Check per-machine installation
    if (Test-Path -Path $oneDrivePaths.PerMachine) {
        $info.Installed = $true
        $info.InstallPath = $oneDrivePaths.PerMachine
        $info.InstallMode = "PerMachine"
        
        try {
            $fileInfo = Get-Item $oneDrivePaths.PerMachine
            $info.Version = $fileInfo.VersionInfo.FileVersion
        }
        catch {
            Write-Log "Could not get version from per-machine install" "WARN"
        }
    }
    # Check per-user installation
    elseif (Test-Path -Path $oneDrivePaths.PerUser) {
        $info.Installed = $true
        $info.InstallPath = $oneDrivePaths.PerUser
        $info.InstallMode = "PerUser"
        
        try {
            $fileInfo = Get-Item $oneDrivePaths.PerUser
            $info.Version = $fileInfo.VersionInfo.FileVersion
        }
        catch {
            Write-Log "Could not get version from per-user install" "WARN"
        }
    }
    
    return $info
}

function Get-LatestOneDriveVersion {
    try {
        # Try to get version from the download URL
        $url = if ($InstallMode -eq "PerMachine") { $OneDriveDownloadURLs.PerMachine } else { $OneDriveDownloadURLs.PerUser }
        
        if (-not [string]::IsNullOrEmpty($DownloadURL)) {
            $url = $DownloadURL
        }
        
        Write-Log "Checking latest version from: $url"
        
        # Follow redirect to get actual file
        $request = [System.Net.WebRequest]::Create($url)
        $request.Method = "HEAD"
        $request.AllowAutoRedirect = $true
        $response = $request.GetResponse()
        $finalUrl = $response.ResponseUri.AbsoluteUri
        $response.Close()
        
        Write-Log "Resolved download URL: $finalUrl"
        
        # The version is typically in the filename or we can extract it
        # For now, return the URL - actual version comparison happens after download
        return @{
            URL = $finalUrl
            Version = "Latest"  # We'll compare file versions after download
        }
    }
    catch {
        Write-Log "Failed to check latest version: $($_.Exception.Message)" "WARN"
        return @{
            URL = $url
            Version = "Unknown"
        }
    }
}

function Invoke-OneDriveDownload {
    param([string]$Url)
    
    try {
        if (!(Test-Path -Path $TempPath)) {
            New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
        }
        
        $outputFile = Join-Path $TempPath "OneDriveSetup.exe"
        Write-Log "Downloading OneDrive from: $Url"
        
        # Use BITS for reliable download
        try {
            Start-BitsTransfer -Source $Url -Destination $outputFile -ErrorAction Stop
            Write-Log "Download completed via BITS" "SUCCESS"
        }
        catch {
            Write-Log "BITS failed, trying WebRequest..." "WARN"
            Invoke-WebRequest -Uri $Url -OutFile $outputFile -UseBasicParsing -ErrorAction Stop
        }
        
        if (Test-Path -Path $outputFile) {
            $fileSize = (Get-Item $outputFile).Length / 1MB
            $version = (Get-Item $outputFile).VersionInfo.FileVersion
            Write-Log "Downloaded: $([math]::Round($fileSize, 2)) MB, Version: $version"
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

function Install-OneDrive {
    param([string]$Installer)
    
    try {
        Write-Log "Installing OneDrive ($InstallMode mode)"
        
        $arguments = "/silent"
        
        if ($InstallMode -eq "PerMachine") {
            $arguments += " /allusers"
        }
        
        Write-Log "Running: $Installer $arguments"
        $process = Start-Process -FilePath $Installer -ArgumentList $arguments -Wait -PassThru
        
        Write-Log "Installer exited with code: $($process.ExitCode)"
        
        # Wait for installation to settle
        Start-Sleep -Seconds 10
        
        # Verify installation
        $info = Get-OneDriveInfo
        if ($info.Installed) {
            Write-Log "OneDrive installed successfully: $($info.Version)" "SUCCESS"
            return $true
        }
        else {
            Write-Log "Installation verification failed" "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Installation failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Update-OneDrive {
    param([string]$Installer)
    
    try {
        Write-Log "Updating OneDrive"
        
        # Same process as install for OneDrive - installer handles updates
        return Install-OneDrive -Installer $Installer
    }
    catch {
        Write-Log "Update failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Configure-OneDrive {
    try {
        Write-Log "Configuring OneDrive settings"
        
        $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive"
        if (!(Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        
        # Silent configuration (auto sign-in with Windows account)
        if ($EnableSilentConfig -and -not [string]::IsNullOrEmpty($TenantID)) {
            Write-Log "Enabling silent configuration"
            Set-ItemProperty -Path $regPath -Name "SilentAccountConfig" -Value 1 -Type DWord
            Set-ItemProperty -Path $regPath -Name "DefaultTenant" -Value $TenantID -Type String
        }
        
        # Files On-Demand
        if ($EnableFilesOnDemand) {
            Write-Log "Enabling Files On-Demand"
            Set-ItemProperty -Path $regPath -Name "FilesOnDemandEnabled" -Value 1 -Type DWord
        }
        
        # Disable auto-start
        if ($DisableAutoStart) {
            Write-Log "Disabling auto-start"
            $runPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
            Remove-ItemProperty -Path $runPath -Name "OneDrive" -ErrorAction SilentlyContinue
        }
        
        # Known Folder Move
        if ($KnownFolderMove) {
            Write-Log "Configuring Known Folder Move"
            
            if ($KFMSilentOptIn -and -not [string]::IsNullOrEmpty($TenantID)) {
                Set-ItemProperty -Path $regPath -Name "KFMSilentOptIn" -Value $TenantID -Type String
            }
            
            # Enable KFM policies
            Set-ItemProperty -Path $regPath -Name "KFMBlockOptOut" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        }
        
        Write-Log "Configuration completed" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Configuration failed: $($_.Exception.Message)" "WARN"
        return $false
    }
}

function Register-Operation {
    param(
        [bool]$Installed,
        [bool]$Updated,
        [string]$Version,
        [bool]$Success
    )
    
    $regPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\OneDrive"
    
    try {
        if (!(Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $regPath -Name "LastRun" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Set-ItemProperty -Path $regPath -Name "Installed" -Value ([string]$Installed)
        Set-ItemProperty -Path $regPath -Name "Updated" -Value ([string]$Updated)
        Set-ItemProperty -Path $regPath -Name "Version" -Value $Version
        Set-ItemProperty -Path $regPath -Name "InstallMode" -Value $InstallMode
        Set-ItemProperty -Path $regPath -Name "Success" -Value ([string]$Success)
        
        Write-Log "Operation registered in registry" "SUCCESS"
    }
    catch {
        Write-Log "Failed to register operation: $($_.Exception.Message)" "WARN"
    }
}

# ==================== MAIN EXECUTION ====================

Write-Log "=== OneDrive Installation/Update Script Started ==="
Write-Log "Script version: 1.0"
Write-Log "Install mode: $InstallMode"

# Check current installation
$currentInfo = Get-OneDriveInfo
if ($currentInfo.Installed) {
    Write-Log "OneDrive found: $($currentInfo.Version) ($($currentInfo.InstallMode))"
}
else {
    Write-Log "OneDrive not currently installed"
}

# Get download URL
$downloadUrl = if (-not [string]::IsNullOrEmpty($DownloadURL)) { 
    $DownloadURL 
} else { 
    $OneDriveDownloadURLs[$InstallMode] 
}

Write-Log "Download URL: $downloadUrl"

# Download installer
$installer = Invoke-OneDriveDownload -Url $downloadUrl
if (-not $installer) {
    Write-Log "Failed to download OneDrive installer" "ERROR"
    exit 1
}

# Get version of downloaded file
$downloadedVersion = (Get-Item $installer).VersionInfo.FileVersion
Write-Log "Downloaded installer version: $downloadedVersion"

# Determine if install or update needed
$needsInstall = $false
$needsUpdate = $false

if (-not $currentInfo.Installed) {
    Write-Log "Installation required"
    $needsInstall = $true
}
elseif ($currentInfo.InstallMode -ne $InstallMode) {
    Write-Log "Install mode mismatch. Current: $($currentInfo.InstallMode), Target: $InstallMode"
    Write-Log "Will reinstall in correct mode"
    $needsInstall = $true
}
elseif ($ForceUpdate) {
    Write-Log "Force update specified"
    $needsUpdate = $true
}
else {
    # Compare versions (simple string comparison for now)
    if ($downloadedVersion -ne $currentInfo.Version) {
        Write-Log "Newer version available: $downloadedVersion vs $($currentInfo.Version)"
        $needsUpdate = $true
    }
    else {
        Write-Log "Already on latest version: $($currentInfo.Version)" "SUCCESS"
    }
}

# Perform install or update
$operationSuccess = $false
$wasInstalled = $false
$wasUpdated = $false
$finalVersion = $currentInfo.Version

if ($needsInstall) {
    $wasInstalled = Install-OneDrive -Installer $installer
    $operationSuccess = $wasInstalled
    
    if ($wasInstalled) {
        $finalInfo = Get-OneDriveInfo
        $finalVersion = $finalInfo.Version
    }
}
elseif ($needsUpdate) {
    $wasUpdated = Update-OneDrive -Installer $installer
    $operationSuccess = $wasUpdated
    
    if ($wasUpdated) {
        $finalInfo = Get-OneDriveInfo
        $finalVersion = $finalInfo.Version
    }
}
else {
    Write-Log "No action required - already up to date"
    $operationSuccess = $true
    $finalVersion = $currentInfo.Version
}

# Apply configuration if install/update was successful
if ($operationSuccess) {
    Configure-OneDrive | Out-Null
}

# Cleanup
if (Test-Path -Path $TempPath) {
    Remove-Item -Path $TempPath -Recurse -Force -ErrorAction SilentlyContinue
}

# Register completion
Register-Operation -Installed $wasInstalled -Updated $wasUpdated -Version $finalVersion -Success $operationSuccess

if ($operationSuccess) {
    Write-Log "=== OneDrive installation/update completed ===" "SUCCESS"
    Write-Log "Final version: $finalVersion"
    exit 0
}
else {
    Write-Log "=== OneDrive installation/update failed ===" "ERROR"
    exit 1
}