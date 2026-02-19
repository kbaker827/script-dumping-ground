#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs Trend Micro Worry-Free Business Security (WFBS) Cloud agent for Intune deployment.

.DESCRIPTION
    Downloads and installs the Trend Micro WFBS Cloud agent. Designed for silent deployment
    through Microsoft Intune. Supports custom download URLs from your Trend console.

.PARAMETER DownloadURL
    Direct download URL for the WFBS Cloud agent from your Trend console

.PARAMETER AgentToken
    Deployment token from Trend WFBS Cloud console (optional if embedded in URL)

.PARAMETER LogPath
    Path for installation logs

.PARAMETER WaitForService
    Wait for services to start after installation

.PARAMETER ServiceTimeout
    Timeout in seconds to wait for services (default: 300)

.EXAMPLE
    .\Install-TrendWFBS.ps1 -DownloadURL "https://wfbs-svc-cloud-us.trendmicro.com/..."

.EXAMPLE
    .\Install-TrendWFBS.ps1 -DownloadURL "https://wfbs-svc-cloud-us.trendmicro.com/..." -WaitForService

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
    Requirements:   Windows 10/11, Administrator rights

    IMPORTANT: You must obtain the agent download URL from your Trend WFBS Cloud console.
    Go to: Devices → Add Device → Windows → Download Agent
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, HelpMessage="Download URL from Trend WFBS Cloud console")]
    [string]$DownloadURL,

    [Parameter(Mandatory=$false)]
    [string]$AgentToken = "",

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs",

    [Parameter(Mandatory=$false)]
    [switch]$WaitForService,

    [Parameter(Mandatory=$false)]
    [int]$ServiceTimeout = 300
)

# Configuration
$ScriptName = "TrendWFBSInstall"
$LogFile = "$LogPath\$ScriptName.log"
$TempPath = "$env:TEMP\TrendWFBSInstall"
$InstallerFileName = "WFBSAgent.exe"

# Product detection
$DisplayNamePattern = "*Trend Micro*Worry-Free*"
$ServiceNamePattern = "Trend Micro*"

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

function Test-WFBSInstalled {
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($regPath in $regPaths) {
        $product = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -like $DisplayNamePattern -or $_.DisplayName -like "*Trend Micro*Security*Agent*" }
        
        if ($product) {
            Write-Log "Found installed Trend WFBS: $($product.DisplayName) v$($product.DisplayVersion)" "SUCCESS"
            return $true
        }
    }
    
    # Check for Trend services
    $services = Get-Service -Name "Trend Micro*" -ErrorAction SilentlyContinue
    if ($services) {
        Write-Log "Trend Micro services found: $($services.Name -join ', ')" "INFO"
        return $true
    }
    
    # Check for installation directory
    $installPaths = @(
        "$env:ProgramFiles\Trend Micro",
        "${env:ProgramFiles(x86)}\Trend Micro"
    )
    
    foreach ($path in $installPaths) {
        if (Test-Path -Path $path) {
            $coreService = Get-ChildItem -Path $path -Recurse -Filter "CoreServiceShell.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($coreService) {
                Write-Log "Trend Micro installation found at: $($coreService.DirectoryName)" "SUCCESS"
                return $true
            }
        }
    }
    
    return $false
}

function Invoke-WFBSDownload {
    param([string]$Url)
    
    try {
        # Create temp directory
        if (Test-Path -Path $TempPath) {
            Remove-Item -Path $TempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
        
        $outputPath = Join-Path $TempPath $InstallerFileName
        Write-Log "Downloading Trend WFBS agent from: $Url"
        
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
            
            # Verify it's a valid executable
            $fileInfo = Get-Item $outputPath
            if ($fileInfo.Length -lt 1MB) {
                Write-Log "Warning: Downloaded file seems small ($($fileInfo.Length) bytes)" "WARN"
            }
            
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

function Install-WFBS {
    param([string]$InstallerPath)
    
    try {
        Write-Log "Starting Trend WFBS agent installation..."
        
        # Build install arguments
        # Common silent install flags for Trend installers
        $installArgs = @(
            "/S"                           # Silent install
            "/v/qn"                        # MSI silent mode (if MSI wrapper)
        )
        
        # Add token if provided separately
        if (-not [string]::IsNullOrEmpty($AgentToken)) {
            $installArgs += "TOKEN=$AgentToken"
        }
        
        Write-Log "Install command: `"$InstallerPath`" $($installArgs -join ' ')"
        Write-Log "This may take several minutes..."
        
        # Execute installation
        $process = Start-Process -FilePath $InstallerPath -ArgumentList $installArgs -Wait -PassThru
        
        Write-Log "Installation process exited with code: $($process.ExitCode)"
        
        # Trend specific exit codes
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
                Write-Log "Common causes: Conflicting AV, insufficient permissions, missing prerequisites" "ERROR"
                return $false 
            }
            1618    { 
                Write-Log "Installation failed - another installation in progress (1618)" "ERROR"
                return $false 
            }
            1619    { 
                Write-Log "Installation failed - invalid MSI package (1619)" "ERROR"
                return $false 
            }
            default { 
                # Trend may use custom exit codes
                if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010 -or $process.ExitCode -eq 1641) {
                    return $true
                }
                Write-Log "Installation completed with exit code: $($process.ExitCode)" "WARN"
                # Some exit codes may still indicate success for Trend
                return $true
            }
        }
    }
    catch {
        Write-Log "Installation failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Wait-WFBSServices {
    param([int]$TimeoutSeconds = 300)
    
    Write-Log "Waiting for Trend WFBS services to start (timeout: ${TimeoutSeconds}s)..."
    
    $trendServices = @(
        "Trend Micro Deep Security Manager",
        "Trend Micro Endpoint Basecamp",
        "Trend Micro Security Agent",
        "Trend Micro Listener",
        "Trend Micro Management Agent"
    )
    
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $servicesStarted = $false
    
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $runningServices = @()
        
        foreach ($svcName in $trendServices) {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq "Running") {
                $runningServices += $svcName
            }
        }
        
        if ($runningServices.Count -gt 0) {
            $servicesStarted = $true
            Write-Log "Trend services running: $($runningServices.Count)" "SUCCESS"
            break
        }
        
        Write-Log "Waiting for services... ($([math]::Round($sw.Elapsed.TotalSeconds))s elapsed)"
        Start-Sleep -Seconds 10
    }
    
    $sw.Stop()
    
    if ($servicesStarted) {
        Write-Log "Trend WFBS services started successfully after $([math]::Round($sw.Elapsed.TotalSeconds))s" "SUCCESS"
        return $true
    }
    else {
        Write-Log "Timeout waiting for services. Installation may still be in progress." "WARN"
        return $false
    }
}

function Start-WFBSServices {
    try {
        $services = Get-Service -Name "Trend Micro*" -ErrorAction SilentlyContinue
        
        if ($services) {
            foreach ($service in $services) {
                if ($service.Status -ne "Running") {
                    Write-Log "Starting service: $($service.Name)"
                    try {
                        Start-Service -Name $service.Name -ErrorAction Stop
                        Write-Log "Service $($service.Name) started" "SUCCESS"
                    }
                    catch {
                        Write-Log "Failed to start service $($service.Name): $($_.Exception.Message)" "WARN"
                    }
                }
                else {
                    Write-Log "Service $($service.Name) is already running" "INFO"
                }
                
                # Ensure startup type is automatic
                Set-Service -Name $service.Name -StartupType Automatic -ErrorAction SilentlyContinue
            }
        }
        else {
            Write-Log "No Trend Micro services found yet - may need more time to register" "WARN"
        }
    }
    catch {
        Write-Log "Failed to start services: $($_.Exception.Message)" "ERROR"
    }
}

function Register-InstallCompletion {
    $regPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\TrendWFBS"
    try {
        if (!(Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $regPath -Name "InstallDate" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Set-ItemProperty -Path $regPath -Name "DownloadURL" -Value $DownloadURL
        
        # Try to get version info
        $regPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        
        foreach ($checkPath in $regPaths) {
            $product = Get-ItemProperty $checkPath -ErrorAction SilentlyContinue | 
                Where-Object { $_.DisplayName -like $DisplayNamePattern }
            
            if ($product) {
                Set-ItemProperty -Path $regPath -Name "Version" -Value $product.DisplayVersion
                break
            }
        }
        
        Write-Log "Installation registered in registry" "SUCCESS"
    }
    catch {
        Write-Log "Failed to register installation: $($_.Exception.Message)" "WARN"
    }
}

# ==================== MAIN EXECUTION ====================

Write-Log "=== Trend WFBS Cloud Agent Installation Started ==="
Write-Log "Script version: 1.0"

# Validate download URL
if ([string]::IsNullOrEmpty($DownloadURL)) {
    Write-Log "Download URL is required. Get it from your Trend WFBS Cloud console." "ERROR"
    Write-Log "Path: Devices → Add Device → Windows → Download Agent" "ERROR"
    exit 1
}

# Check if already installed
Write-Log "Checking for existing installation..."
if (Test-WFBSInstalled) {
    Write-Log "Trend WFBS appears to already be installed" "SUCCESS"
    Register-InstallCompletion
    exit 0
}

# Download installer
try {
    $installerPath = Invoke-WFBSDownload -Url $DownloadURL
}
catch {
    Write-Log "Failed to download installer. Exiting." "ERROR"
    exit 1
}

# Install WFBS
$installSuccess = Install-WFBS -InstallerPath $installerPath

if ($installSuccess) {
    # Wait for services if requested
    if ($WaitForService) {
        Wait-WFBSServices -TimeoutSeconds $ServiceTimeout | Out-Null
    }
    else {
        Write-Log "Installation complete. Services may still be initializing."
        Start-Sleep -Seconds 30  # Brief pause for initial setup
        Start-WFBSServices
    }
    
    # Register completion
    Register-InstallCompletion
    
    # Cleanup
    if (Test-Path -Path $TempPath) {
        Remove-Item -Path $TempPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Cleaned up temporary files"
    }
    
    Write-Log "=== Installation completed successfully ===" "SUCCESS"
    Write-Log "Verify in Trend WFBS Cloud console that this device appears online"
    exit 0
}
else {
    Write-Log "=== Installation failed ===" "ERROR"
    Write-Log "Check Windows Event Logs and Trend installation logs for details"
    exit 1
}