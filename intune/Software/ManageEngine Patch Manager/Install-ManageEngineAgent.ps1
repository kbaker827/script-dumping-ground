#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs ManageEngine Patch Manager Plus agent for Intune deployment.

.DESCRIPTION
    Downloads and installs the latest ManageEngine Patch Manager Plus agent.
    Supports custom server configuration and silent installation.

.PARAMETER ServerURL
    The URL of your ManageEngine Patch Manager Plus server (e.g., https://patchserver.company.com)

.PARAMETER Port
    The port number for the Patch Manager server (default: 8020)

.PARAMETER Protocol
    Protocol to use - HTTP or HTTPS (default: HTTPS)

.PARAMETER AgentVersion
    Specific agent version to install (optional - downloads latest if not specified)

.PARAMETER DownloadURL
    Direct download URL for the agent MSI (optional - auto-constructs if not provided)

.PARAMETER LogPath
    Path for installation logs

.EXAMPLE
    .\Install-ManageEngineAgent.ps1 -ServerURL "https://patch.company.com" -Port 8020

.EXAMPLE
    .\Install-ManageEngineAgent.ps1 -DownloadURL "https://patch.company.com:8020/agent/Agent.msi"

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
    Requirements:   Windows 10/11, Administrator rights
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ServerURL = "",

    [Parameter(Mandatory=$false)]
    [int]$Port = 8020,

    [Parameter(Mandatory=$false)]
    [ValidateSet("HTTP", "HTTPS")]
    [string]$Protocol = "HTTPS",

    [Parameter(Mandatory=$false)]
    [string]$AgentVersion = "",

    [Parameter(Mandatory=$false)]
    [string]$DownloadURL = "",

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
)

# Configuration
$ScriptName = "ManageEngineAgentInstall"
$LogFile = "$LogPath\$ScriptName.log"
$TempPath = "$env:TEMP\ManageEngineAgent"
$InstallerFileName = "ManageEnginePatchAgent.msi"

# Product codes for detection
$ProductCode = "{YOUR-PRODUCT-CODE-HERE}"  # Update this with actual product code after first install
$DisplayName = "ManageEngine Patch Manager Plus Agent"

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
    
    # Output to console as well
    $color = switch ($Level) {
        "ERROR"   { "Red" }
        "WARN"    { "Yellow" }
        "SUCCESS" { "Green" }
        default   { "White" }
    }
    Write-Host $logEntry -ForegroundColor $color
}

function Test-AgentInstalled {
    $installed = $false
    $installPath = $null
    
    # Check registry for installed product
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($regPath in $regPaths) {
        $product = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -like "*ManageEngine*Patch*Agent*" -or $_.DisplayName -like "*Patch Manager Plus*" }
        
        if ($product) {
            $installed = $true
            $installPath = $product.InstallLocation
            Write-Log "Found installed agent: $($product.DisplayName) v$($product.DisplayVersion)" "SUCCESS"
            break
        }
    }
    
    # Also check for service
    $service = Get-Service -Name "PatchManagerAgent" -ErrorAction SilentlyContinue
    if ($service) {
        $installed = $true
        Write-Log "Patch Manager Agent service found" "INFO"
    }
    
    return $installed
}

function Get-DownloadUrl {
    if (-not [string]::IsNullOrEmpty($DownloadURL)) {
        Write-Log "Using provided download URL: $DownloadURL"
        return $DownloadURL
    }
    
    if ([string]::IsNullOrEmpty($ServerURL)) {
        throw "Either ServerURL or DownloadURL must be provided"
    }
    
    # Construct download URL from server details
    $protocolLower = $Protocol.ToLower()
    $url = "$($protocolLower)://$($ServerURL -replace '^https?://', ''):$Port/agent/Agent.msi"
    
    Write-Log "Constructed download URL: $url"
    return $url
}

function Invoke-AgentDownload {
    param([string]$Url)
    
    try {
        # Create temp directory
        if (Test-Path -Path $TempPath) {
            Remove-Item -Path $TempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
        
        $outputPath = Join-Path $TempPath $InstallerFileName
        Write-Log "Downloading agent from: $Url"
        
        # Use BITS for reliable download (works better in system context)
        try {
            Start-BitsTransfer -Source $Url -Destination $outputPath -ErrorAction Stop
            Write-Log "Download completed via BITS" "SUCCESS"
        }
        catch {
            Write-Log "BITS transfer failed, trying Invoke-WebRequest..." "WARN"
            
            # Fallback to Invoke-WebRequest
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

function Install-Agent {
    param([string]$InstallerPath)
    
    try {
        Write-Log "Starting agent installation..."
        
        # Build install arguments
        $installArgs = @(
            "/i", "`"$InstallerPath`""
            "/qn"                          # Silent install
            "/norestart"                   # Don't restart (we'll handle separately)
            "/l*v", "`"$LogPath\ManageEngineAgent_Install.log`""  # Verbose logging
        )
        
        # Add server configuration properties if provided
        $msiProperties = @()
        if (-not [string]::IsNullOrEmpty($ServerURL)) {
            $msiProperties += "SERVERURL=`"$ServerURL`""
        }
        if ($Port -ne 8020) {
            $msiProperties += "SERVERPORT=$Port"
        }
        
        if ($msiProperties.Count -gt 0) {
            $installArgs += $msiProperties -join " "
        }
        
        Write-Log "Install command: msiexec.exe $($installArgs -join ' ')"
        
        # Execute installation
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
        
        Write-Log "Installation process exited with code: $($process.ExitCode)"
        
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
            1619    { 
                Write-Log "Installation failed - MSI database not opened (1619)" "ERROR"
                return $false 
            }
            default { 
                Write-Log "Installation completed with exit code: $($process.ExitCode)" "WARN"
                return ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010 -or $process.ExitCode -eq 1641)
            }
        }
    }
    catch {
        Write-Log "Installation failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Start-AgentService {
    try {
        $service = Get-Service -Name "PatchManagerAgent" -ErrorAction SilentlyContinue
        if ($service) {
            if ($service.Status -ne "Running") {
                Write-Log "Starting Patch Manager Agent service..."
                Start-Service -Name "PatchManagerAgent" -ErrorAction Stop
                Write-Log "Service started successfully" "SUCCESS"
            }
            else {
                Write-Log "Service is already running" "INFO"
            }
        }
        else {
            Write-Log "Patch Manager Agent service not found" "WARN"
        }
    }
    catch {
        Write-Log "Failed to start service: $($_.Exception.Message)" "ERROR"
    }
}

function Register-InstallCompletion {
    # Create registry key for Intune detection
    $regPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\ManageEnginePatchAgent"
    try {
        if (!(Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $regPath -Name "InstallDate" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Set-ItemProperty -Path $regPath -Name "ServerURL" -Value $ServerURL
        Set-ItemProperty -Path $regPath -Name "Port" -Value $Port
        Set-ItemProperty -Path $regPath -Name "Version" -Value (Get-Date -Format "yyyy.MM.dd")
        
        Write-Log "Installation registered in registry" "SUCCESS"
    }
    catch {
        Write-Log "Failed to register installation: $($_.Exception.Message)" "WARN"
    }
}

# ==================== MAIN EXECUTION ====================

Write-Log "=== ManageEngine Patch Manager Agent Installation Started ==="
Write-Log "Script version: 1.0"

# Check if already installed
Write-Log "Checking for existing installation..."
if (Test-AgentInstalled) {
    Write-Log "ManageEngine Patch Manager Agent is already installed" "SUCCESS"
    Register-InstallCompletion
    exit 0
}

# Get download URL
$downloadUrl = Get-DownloadUrl

# Download installer
try {
    $installerPath = Invoke-AgentDownload -Url $downloadUrl
}
catch {
    Write-Log "Failed to download installer. Exiting." "ERROR"
    exit 1
}

# Install agent
$installSuccess = Install-Agent -InstallerPath $installerPath

if ($installSuccess) {
    # Start the service
    Start-AgentService
    
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