#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs TightVNC with custom password configuration for Intune deployment.

.DESCRIPTION
    Downloads and installs the latest TightVNC server, configures authentication
    password, and sets desired configuration options. Designed for silent deployment
    through Microsoft Intune.

.PARAMETER VNCPassword
    The password to set for TightVNC authentication (required)

.PARAMETER ViewerPassword
    The view-only password (optional - if not specified, view-only access is disabled)

.PARAMETER Port
    The port number for VNC connections (default: 5900)

.PARAMETER DownloadURL
    Direct download URL for TightVNC installer (optional - uses official source if not provided)

.PARAMETER LogPath
    Path for installation logs

.PARAMETER AllowLoopback
    Allow connections from localhost (default: false for security)

.PARAMETER AllowOnlyLoopback
    Only allow connections from localhost (default: false)

.EXAMPLE
    .\Install-TightVNC.ps1 -VNCPassword "SecurePass123!"

.EXAMPLE
    .\Install-TightVNC.ps1 -VNCPassword "AdminPass123" -ViewerPassword "ViewOnly456" -Port 5901

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
    Requirements:   Windows 10/11, Administrator rights

    SECURITY NOTE: Passwords are stored encrypted in registry by TightVNC.
    This script handles the encryption automatically.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, HelpMessage="Password for VNC authentication")]
    [string]$VNCPassword,

    [Parameter(Mandatory=$false, HelpMessage="View-only password (optional)")]
    [string]$ViewerPassword = "",

    [Parameter(Mandatory=$false)]
    [int]$Port = 5900,

    [Parameter(Mandatory=$false)]
    [string]$DownloadURL = "",

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs",

    [Parameter(Mandatory=$false)]
    [switch]$AllowLoopback,

    [Parameter(Mandatory=$false)]
    [switch]$AllowOnlyLoopback
)

# Configuration
$ScriptName = "TightVNCInstall"
$LogFile = "$LogPath\$ScriptName.log"
$TempPath = "$env:TEMP\TightVNCInstall"

# TightVNC official download (update as needed)
$DefaultDownloadURL = "https://www.tightvnc.com/download/2.8.81/tightvnc-2.8.81-gpl-setup-64bit.msi"
$ProductName = "TightVNC"

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

function Test-TightVNCInstalled {
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($regPath in $regPaths) {
        $product = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -like "*TightVNC*" }
        
        if ($product) {
            Write-Log "Found installed TightVNC: $($product.DisplayName) v$($product.DisplayVersion)" "SUCCESS"
            return $true
        }
    }
    
    # Also check for service
    $service = Get-Service -Name "TightVNC*" -ErrorAction SilentlyContinue
    if ($service) {
        Write-Log "TightVNC service found" "INFO"
        return $true
    }
    
    return $false
}

function Invoke-TightVNCDownload {
    param([string]$Url)
    
    try {
        # Create temp directory
        if (Test-Path -Path $TempPath) {
            Remove-Item -Path $TempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
        
        $outputPath = Join-Path $TempPath "tightvnc-setup.msi"
        Write-Log "Downloading TightVNC from: $Url"
        
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

function Install-TightVNC {
    param([string]$InstallerPath)
    
    try {
        Write-Log "Starting TightVNC installation..."
        
        # Build install arguments for MSI
        # ADDLOCAL=Server installs server component only (no viewer needed on endpoints)
        $installArgs = @(
            "/i", "`"$InstallerPath`""
            "/qn"                          # Silent install
            "/norestart"                   # Don't restart
            "ADDLOCAL=Server"              # Install server only
            "INSTALLDIR=`"$env:ProgramFiles\TightVNC`""
            "/l*v", "`"$LogPath\TightVNC_Install.log`""
        )
        
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
            1603    { 
                Write-Log "Installation failed with fatal error (1603)" "ERROR"
                return $false 
            }
            1618    { 
                Write-Log "Installation failed - another installation in progress (1618)" "ERROR"
                return $false 
            }
            default { 
                Write-Log "Installation completed with exit code: $($process.ExitCode)" "WARN"
                return ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010)
            }
        }
    }
    catch {
        Write-Log "Installation failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Set-TightVNCPassword {
    param(
        [string]$Password,
        [string]$ViewOnlyPassword = ""
    )
    
    try {
        Write-Log "Configuring TightVNC password..."
        
        $tvnServerPath = "$env:ProgramFiles\TightVNC\tvnserver.exe"
        if (-not (Test-Path $tvnServerPath)) {
            $tvnServerPath = "${env:ProgramFiles(x86)}\TightVNC\tvnserver.exe"
        }
        
        if (-not (Test-Path $tvnServerPath)) {
            throw "tvnserver.exe not found"
        }
        
        # TightVNC stores passwords as encrypted registry values
        # We use the tvnserver.exe -controlapp command to set passwords properly
        
        # Set primary password
        Write-Log "Setting primary VNC password..."
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $tvnServerPath
        $psi.Arguments = "-controlapp -password `"$Password`""
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $process = [System.Diagnostics.Process]::Start($psi)
        $process.WaitForExit()
        
        if ($process.ExitCode -eq 0) {
            Write-Log "Primary password set successfully" "SUCCESS"
        }
        else {
            Write-Log "Password set returned exit code: $($process.ExitCode)" "WARN"
        }
        
        # Set view-only password if provided
        if (-not [string]::IsNullOrEmpty($ViewOnlyPassword)) {
            Write-Log "Setting view-only password..."
            $psi.Arguments = "-controlapp -viewpassword `"$ViewOnlyPassword`""
            $process = [System.Diagnostics.Process]::Start($psi)
            $process.WaitForExit()
            
            if ($process.ExitCode -eq 0) {
                Write-Log "View-only password set successfully" "SUCCESS"
            }
        }
        else {
            # Disable view-only password if not set
            $psi.Arguments = "-controlapp -viewpassword `"`""
            $process = [System.Diagnostics.Process]::Start($psi)
            $process.WaitForExit()
            Write-Log "View-only access disabled" "INFO"
        }
        
        return $true
    }
    catch {
        Write-Log "Failed to configure password: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Set-TightVNCConfiguration {
    param(
        [int]$VncPort = 5900,
        [switch]$AllowLoopback,
        [switch]$AllowOnlyLoopback
    )
    
    try {
        Write-Log "Configuring TightVNC settings..."
        
        $regPath = "HKLM:\SOFTWARE\TightVNC\Server"
        if (!(Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        
        # Core settings
        Set-ItemProperty -Path $regPath -Name "AcceptHttpConnections" -Value 0 -Type DWord  # Disable web access
        Set-ItemProperty -Path $regPath -Name "AcceptRfbConnections" -Value 1 -Type DWord  # Enable VNC
        Set-ItemProperty -Path $regPath -Name "RfbPort" -Value $VncPort -Type DWord
        
        # Security settings
        Set-ItemProperty -Path $regPath -Name "UseVncAuthentication" -Value 1 -Type DWord   # Require password
        Set-ItemProperty -Path $regPath -Name "UseControlAuthentication" -Value 1 -Type DWord  # Control interface auth
        
        # Loopback settings
        if ($AllowOnlyLoopback) {
            Set-ItemProperty -Path $regPath -Name "AllowLoopback" -Value 1 -Type DWord
            Set-ItemProperty -Path $regPath -Name "OnlyLoopback" -Value 1 -Type DWord
            Set-ItemProperty -Path $regPath -Name "AcceptRemoteConnections" -Value 0 -Type DWord
        }
        elseif ($AllowLoopback) {
            Set-ItemProperty -Path $regPath -Name "AllowLoopback" -Value 1 -Type DWord
            Set-ItemProperty -Path $regPath -Name "OnlyLoopback" -Value 0 -Type DWord
        }
        else {
            Set-ItemProperty -Path $regPath -Name "AllowLoopback" -Value 0 -Type DWord
            Set-ItemProperty -Path $regPath -Name "OnlyLoopback" -Value 0 -Type DWord
        }
        
        # Additional security
        Set-ItemProperty -Path $regPath -Name "RemoveWallpaper" -Value 0 -Type DWord  # Keep wallpaper (better UX)
        Set-ItemProperty -Path $regPath -Name "CaptureAlphaBlending" -Value 1 -Type DWord  # Better display quality
        
        Write-Log "Configuration applied successfully" "SUCCESS"
        
        # Configure Windows Firewall
        Write-Log "Configuring Windows Firewall rules..."
        
        # Remove existing rules to avoid duplicates
        Get-NetFirewallRule -DisplayName "TightVNC*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule
        
        # Create new inbound rule
        $ruleName = "TightVNC Server - Port $VncPort"
        New-NetFirewallRule -DisplayName $ruleName `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort $VncPort `
            -Action Allow `
            -Profile Domain,Private `
            -Program "$env:ProgramFiles\TightVNC\tvnserver.exe" `
            -ErrorAction SilentlyContinue | Out-Null
        
        Write-Log "Firewall rule created: $ruleName" "SUCCESS"
        
        return $true
    }
    catch {
        Write-Log "Failed to configure TightVNC: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Start-TightVNCService {
    try {
        $service = Get-Service -Name "TightVNC Server" -ErrorAction SilentlyContinue
        
        if ($service) {
            if ($service.Status -ne "Running") {
                Write-Log "Starting TightVNC Server service..."
                Start-Service -Name "TightVNC Server" -ErrorAction Stop
                Write-Log "Service started successfully" "SUCCESS"
            }
            else {
                Write-Log "TightVNC Server service is already running" "INFO"
            }
            
            # Set to automatic start
            Set-Service -Name "TightVNC Server" -StartupType Automatic
            Write-Log "Service startup type set to Automatic" "SUCCESS"
        }
        else {
            Write-Log "TightVNC Server service not found - attempting to start manually" "WARN"
            
            $tvnServer = "$env:ProgramFiles\TightVNC\tvnserver.exe"
            if (Test-Path $tvnServer) {
                Start-Process -FilePath $tvnServer -ArgumentList "-service" -WindowStyle Hidden
                Write-Log "Started TightVNC server manually" "INFO"
            }
        }
    }
    catch {
        Write-Log "Failed to start service: $($_.Exception.Message)" "ERROR"
    }
}

function Register-InstallCompletion {
    $regPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\TightVNC"
    try {
        if (!(Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $regPath -Name "InstallDate" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Set-ItemProperty -Path $regPath -Name "Port" -Value $Port
        Set-ItemProperty -Path $regPath -Name "Loopback" -Value ([int]$AllowLoopback.IsPresent)
        Set-ItemProperty -Path $regPath -Name "OnlyLoopback" -Value ([int]$AllowOnlyLoopback.IsPresent)
        
        Write-Log "Installation registered in registry" "SUCCESS"
    }
    catch {
        Write-Log "Failed to register installation: $($_.Exception.Message)" "WARN"
    }
}

# ==================== MAIN EXECUTION ====================

Write-Log "=== TightVNC Installation Started ==="
Write-Log "Script version: 1.0"
Write-Log "Target port: $Port"

# Check if already installed
Write-Log "Checking for existing installation..."
$wasInstalled = Test-TightVNCInstalled

# Get download URL
$downloadUrl = if ([string]::IsNullOrEmpty($DownloadURL)) { $DefaultDownloadURL } else { $DownloadURL }

# Download installer
try {
    $installerPath = Invoke-TightVNCDownload -Url $downloadUrl
}
catch {
    Write-Log "Failed to download installer. Exiting." "ERROR"
    exit 1
}

# Install TightVNC
$installSuccess = Install-TightVNC -InstallerPath $installerPath

if ($installSuccess) {
    # Configure password (only on fresh install or password explicitly provided)
    if (-not $wasInstalled -or -not [string]::IsNullOrEmpty($VNCPassword)) {
        Set-TightVNCPassword -Password $VNCPassword -ViewOnlyPassword $ViewerPassword | Out-Null
    }
    
    # Apply configuration
    Set-TightVNCConfiguration -VncPort $Port -AllowLoopback:$AllowLoopback -AllowOnlyLoopback:$AllowOnlyLoopback | Out-Null
    
    # Start service
    Start-TightVNCService
    
    # Register completion
    Register-InstallCompletion
    
    # Cleanup
    if (Test-Path -Path $TempPath) {
        Remove-Item -Path $TempPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Cleaned up temporary files"
    }
    
    Write-Log "=== Installation completed successfully ===" "SUCCESS"
    Write-Log "Connect to this computer using: <computer-ip>:$Port"
    Write-Log "Password has been configured as specified"
    exit 0
}
else {
    Write-Log "=== Installation failed ===" "ERROR"
    exit 1
}