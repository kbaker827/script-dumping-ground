#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Uninstalls Trend Micro Worry-Free Business Security (WFBS).

.DESCRIPTION
    Completely removes Trend Micro WFBS from the system, including
    all agents, services, and residual files.

.PARAMETER LogPath
    Path for uninstallation logs

.PARAMETER Force
    Force removal even if standard uninstall fails

.EXAMPLE
    .\Uninstall-TrendWFBS.ps1

.EXAMPLE
    .\Uninstall-TrendWFBS.ps1 -Force

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
    
    WARNING: This will completely remove Trend Micro protection from the device.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs",

    [Parameter(Mandatory=$false)]
    [switch]$Force
)

# Configuration
$ScriptName = "TrendWFBSUninstall"
$LogFile = "$LogPath\$ScriptName.log"

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
        # Fallback to console
    }
    
    $color = switch ($Level) {
        "ERROR"   { "Red" }
        "WARN"    { "Yellow" }
        "SUCCESS" { "Green" }
        default   { "White" }
    }
    Write-Host $logEntry -ForegroundColor $color
}

function Get-WFBSUninstallString {
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($regPath in $regPaths) {
        $product = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -like "*Trend Micro*Worry-Free*" -or 
                          $_.DisplayName -like "*Trend Micro*Security*Agent*" -or
                          $_.DisplayName -like "*Trend Micro*Endpoint*" }
        
        if ($product -and $product.UninstallString) {
            Write-Log "Found uninstall string for: $($product.DisplayName)"
            return @{
                UninstallString = $product.UninstallString
                ProductCode = $product.PSChildName
                DisplayName = $product.DisplayName
                InstallLocation = $product.InstallLocation
            }
        }
    }
    
    return $null
}

function Stop-WFBSServices {
    Write-Log "Stopping Trend Micro services..."
    
    $trendServices = Get-Service -Name "Trend Micro*" -ErrorAction SilentlyContinue
    
    foreach ($service in $trendServices) {
        if ($service.Status -eq "Running") {
            Write-Log "Stopping service: $($service.Name)"
            try {
                Stop-Service -Name $service.Name -Force -ErrorAction Stop
                Write-Log "Service $($service.Name) stopped"
            }
            catch {
                Write-Log "Failed to stop service $($service.Name): $($_.Exception.Message)" "WARN"
            }
        }
        
        # Disable service
        try {
            Set-Service -Name $service.Name -StartupType Disabled -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to disable service $($service.Name)" "WARN"
        }
    }
    
    # Kill any running Trend processes
    $trendProcesses = @(
        "CoreServiceShell",
        "CntAoSmScan",
        "TmListen",
        "TmCCSF",
        "TmProxy",
        "TmPfw",
        "PccNtMon",
        "NTRTScan",
        "TMBMSRV",
        "TmEvtMgr",
        "TmPreFilter",
        "TmFilter",
        "TmEso",
        "TmEP Aussie",
        "Tm Noah",
        "TmSophos",
        "UIFrameWORK",
        "TmOutlookAddin"
    )
    
    foreach ($procName in $trendProcesses) {
        $process = Get-Process -Name $procName -ErrorAction SilentlyContinue
        if ($process) {
            Write-Log "Terminating process: $procName"
            Stop-Process -Name $procName -Force -ErrorAction SilentlyContinue
        }
    }
}

function Uninstall-WFBS {
    $wfbsInfo = Get-WFBSUninstallString
    
    if (-not $wfbsInfo) {
        Write-Log "Trend WFBS not found in registry. May already be uninstalled." "WARN"
        return $true
    }
    
    Write-Log "Found installation: $($wfbsInfo.DisplayName)"
    
    try {
        $uninstallString = $wfbsInfo.UninstallString
        
        # Determine if it's MSI or EXE uninstaller
        if ($uninstallString -match "msiexec") {
            Write-Log "Using MSI uninstall method..."
            
            if ($uninstallString -match "{[A-F0-9-]+") {
                $productCode = $matches[0]
            }
            else {
                $productCode = $wfbsInfo.ProductCode
            }
            
            $uninstallArgs = @(
                "/x", $productCode
                "/qn"
                "/norestart"
            )
            
            Write-Log "Running: msiexec.exe $($uninstallArgs -join ' ')"
            $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $uninstallArgs -Wait -PassThru
        }
        else {
            Write-Log "Using EXE uninstall method..."
            
            # Parse EXE uninstall string
            $silentArgs = "/S /v/qn"
            
            if ($uninstallString -match '"(.+?)"\s*(.*)') {
                $exePath = $matches[1]
                $existingArgs = $matches[2]
                
                # Build full argument list
                $uninstallArgs = "$existingArgs $silentArgs".Trim()
            }
            else {
                $exePath = $uninstallString
                $uninstallArgs = $silentArgs
            }
            
            Write-Log "Running: $exePath $uninstallArgs"
            $process = Start-Process -FilePath $exePath -ArgumentList $uninstallArgs -Wait -PassThru
        }
        
        Write-Log "Uninstall process exited with code: $($process.ExitCode)"
        
        switch ($process.ExitCode) {
            0       { Write-Log "Uninstall completed successfully" "SUCCESS"; return $true }
            3010    { Write-Log "Uninstall completed - restart required" "SUCCESS"; return $true }
            1605    { Write-Log "Product not found (may already be uninstalled)" "WARN"; return $true }
            1614    { Write-Log "Uninstall completed with warnings" "WARN"; return $true }
            default { 
                if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
                    return $true
                }
                Write-Log "Uninstall completed with exit code: $($process.ExitCode)" "WARN"
                return $false
            }
        }
    }
    catch {
        Write-Log "Uninstall failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Remove-WFBSResiduals {
    Write-Log "Cleaning up residual files and registry entries..."
    
    # Remove services that may remain
    $servicesToRemove = @(
        "Trend Micro Deep Security Manager",
        "Trend Micro Endpoint Basecamp",
        "Trend Micro Security Agent",
        "Trend Micro Listener",
        "Trend Micro Management Agent",
        "Trend Micro Unauthorized Change Prevention Service"
    )
    
    foreach ($svcName in $servicesToRemove) {
        $service = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($service) {
            try {
                sc.exe delete "$svcName" | Out-Null
                Write-Log "Removed service: $svcName"
            }
            catch {
                Write-Log "Failed to remove service $svcName" "WARN"
            }
        }
    }
    
    # Remove installation directories
    $installPaths = @(
        "$env:ProgramFiles\Trend Micro",
        "${env:ProgramFiles(x86)}\Trend Micro",
        "$env:ProgramData\Trend Micro",
        "$env:PUBLIC\Trend Micro"
    )
    
    foreach ($path in $installPaths) {
        if (Test-Path -Path $path) {
            try {
                Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                Write-Log "Removed directory: $path"
            }
            catch {
                Write-Log "Failed to remove directory $path : $($_.Exception.Message)" "WARN"
            }
        }
    }
    
    # Remove registry entries
    $regPaths = @(
        "HKLM:\SOFTWARE\Trend Micro",
        "HKLM:\SOFTWARE\WOW6432Node\Trend Micro",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Trend Micro",
        "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\TrendWFBS"
    )
    
    foreach ($regPath in $regPaths) {
        if (Test-Path -Path $regPath) {
            try {
                Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
                Write-Log "Removed registry key: $regPath"
            }
            catch {
                Write-Log "Failed to remove registry key $regPath" "WARN"
            }
        }
    }
    
    # Remove drivers
    $trendDrivers = @(
        "Trend Micro Filter",
        "Trend Micro TDI",
        "Trend Micro MFR",
        "Trend Micro Prevent",
        "Trend Micro Filter Driver",
        "Trend Micro NDIS 6.0 Filter Driver"
    )
    
    foreach ($driver in $trendDrivers) {
        try {
            $drv = Get-WindowsDriver -Online -ErrorAction SilentlyContinue | 
                Where-Object { $_.OriginalFileName -like "*Trend*" -or $_.ProviderName -like "*Trend Micro*" }
            
            # Note: Removing drivers requires pnputil and can be risky
            # This is a best-effort cleanup
        }
        catch {
            # Continue silently
        }
    }
}

# ==================== MAIN EXECUTION ====================

Write-Log "=== Trend WFBS Uninstallation Started ==="
Write-Log "WARNING: This will completely remove Trend Micro protection from this device"

# Stop services first
Stop-WFBSServices

# Perform uninstallation
$uninstallSuccess = Uninstall-WFBS

# If force mode or uninstall failed, do aggressive cleanup
if ($Force -or -not $uninstallSuccess) {
    Write-Log "Performing forced cleanup..."
    Remove-WFBSResiduals
}
else {
    # Standard cleanup
    Remove-WFBSResiduals
}

Write-Log "=== Uninstallation completed ===" "SUCCESS"
exit 0