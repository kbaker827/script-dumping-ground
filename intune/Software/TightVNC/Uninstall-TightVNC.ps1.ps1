#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Uninstalls TightVNC and removes configuration.

.DESCRIPTION
    Completely removes TightVNC server from the system, including
    registry settings and firewall rules.

.PARAMETER LogPath
    Path for uninstallation logs

.EXAMPLE
    .\Uninstall-TightVNC.ps1

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
)

# Configuration
$ScriptName = "TightVNCUninstall"
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

function Get-TightVNCUninstallString {
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($regPath in $regPaths) {
        $product = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -like "*TightVNC*" }
        
        if ($product -and $product.UninstallString) {
            Write-Log "Found uninstall string: $($product.UninstallString)"
            return @{
                UninstallString = $product.UninstallString
                ProductCode = $product.PSChildName
                DisplayName = $product.DisplayName
            }
        }
    }
    
    return $null
}

function Stop-TightVNCProcesses {
    $processes = @("tvnserver", "tvnviewer", "tvncontrol")
    
    foreach ($procName in $processes) {
        $process = Get-Process -Name $procName -ErrorAction SilentlyContinue
        if ($process) {
            Write-Log "Stopping process: $procName"
            Stop-Process -Name $procName -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Stop the service
    $service = Get-Service -Name "TightVNC Server" -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -eq "Running") {
            Write-Log "Stopping TightVNC Server service..."
            Stop-Service -Name "TightVNC Server" -Force -ErrorAction SilentlyContinue
        }
        
        Set-Service -Name "TightVNC Server" -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Log "Service disabled"
    }
}

function Uninstall-TightVNC {
    $tvncInfo = Get-TightVNCUninstallString
    
    if (-not $tvncInfo) {
        Write-Log "TightVNC not found in registry. May already be uninstalled." "WARN"
        return $true
    }
    
    Write-Log "Found TightVNC: $($tvncInfo.DisplayName)"
    
    try {
        $uninstallString = $tvncInfo.UninstallString
        $productCode = $tvncInfo.ProductCode
        
        if ($uninstallString -match "msiexec") {
            Write-Log "Using MSI uninstall method..."
            
            if ($uninstallString -match "{[A-F0-9-]+") {
                $productCode = $matches[0]
            }
            
            $uninstallArgs = @(
                "/x", $productCode
                "/qn"
                "/norestart"
                "/l*v", "`"$LogPath\TightVNC_Uninstall.log`""
            )
            
            Write-Log "Running: msiexec.exe $($uninstallArgs -join ' ')"
            $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $uninstallArgs -Wait -PassThru
        }
        else {
            Write-Log "Using EXE uninstall method..."
            $uninstallArgs = "/S"
            
            if ($uninstallString -match '"(.+?)"\s*(.*)') {
                $exePath = $matches[1]
                $existingArgs = $matches[2]
                if (-not [string]::IsNullOrEmpty($existingArgs)) {
                    $uninstallArgs = "$existingArgs $uninstallArgs"
                }
            }
            else {
                $exePath = $uninstallString
            }
            
            Write-Log "Running: $exePath $uninstallArgs"
            $process = Start-Process -FilePath $exePath -ArgumentList $uninstallArgs -Wait -PassThru
        }
        
        Write-Log "Uninstall process exited with code: $($process.ExitCode)"
        
        switch ($process.ExitCode) {
            0       { Write-Log "Uninstall completed successfully" "SUCCESS"; return $true }
            3010    { Write-Log "Uninstall completed - restart required" "SUCCESS"; return $true }
            1605    { Write-Log "Product not found (may already be uninstalled)" "WARN"; return $true }
            default { return ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) }
        }
    }
    catch {
        Write-Log "Uninstall failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Remove-TightVNCResiduals {
    Write-Log "Cleaning up residual files and registry entries..."
    
    # Remove service if still present
    $service = Get-Service -Name "TightVNC Server" -ErrorAction SilentlyContinue
    if ($service) {
        try {
            sc.exe delete "TightVNC Server" | Out-Null
            Write-Log "Service removed"
        }
        catch {
            Write-Log "Failed to remove service: $($_.Exception.Message)" "WARN"
        }
    }
    
    # Remove installation directories
    $installPaths = @(
        "$env:ProgramFiles\TightVNC",
        "${env:ProgramFiles(x86)}\TightVNC",
        "$env:ProgramData\TightVNC"
    )
    
    foreach ($path in $installPaths) {
        if (Test-Path -Path $path) {
            try {
                Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                Write-Log "Removed directory: $path"
            }
            catch {
                Write-Log "Failed to remove directory $path" "WARN"
            }
        }
    }
    
    # Remove registry entries
    $regPaths = @(
        "HKLM:\SOFTWARE\TightVNC",
        "HKLM:\SOFTWARE\WOW6432Node\TightVNC",
        "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\TightVNC"
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
    
    # Remove firewall rules
    Get-NetFirewallRule -DisplayName "TightVNC*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Write-Log "Removed TightVNC firewall rules"
}

# ==================== MAIN EXECUTION ====================

Write-Log "=== TightVNC Uninstallation Started ==="

# Stop processes and service first
Stop-TightVNCProcesses

# Perform uninstallation
$uninstallSuccess = Uninstall-TightVNC

# Clean up residuals
Remove-TightVNCResiduals

if ($uninstallSuccess) {
    Write-Log "=== Uninstallation completed successfully ===" "SUCCESS"
    exit 0
}
else {
    Write-Log "=== Uninstallation completed with warnings ===" "WARN"
    exit 0
}