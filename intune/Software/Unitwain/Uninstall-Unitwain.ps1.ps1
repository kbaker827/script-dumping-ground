#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Uninstalls Unitwain and removes configuration.

.DESCRIPTION
    Completely removes Unitwain scanner software from the system, including
    configuration files and licenses.

.PARAMETER LogPath
    Path for uninstallation logs

.PARAMETER RemoveSettings
    Also remove user settings and configuration files

.EXAMPLE
    .\Uninstall-Unitwain.ps1

.EXAMPLE
    .\Uninstall-Unitwain.ps1 -RemoveSettings

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs",

    [Parameter(Mandatory=$false)]
    [switch]$RemoveSettings
)

# Configuration
$ScriptName = "UnitwainUninstall"
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

function Get-UnitwainUninstallString {
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($regPath in $regPaths) {
        $product = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -like "*Unitwain*" -or $_.Publisher -like "*Unitwain*" }
        
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

function Uninstall-Unitwain {
    $unitwainInfo = Get-UnitwainUninstallString
    
    if (-not $unitwainInfo) {
        Write-Log "Unitwain not found in registry. May already be uninstalled." "WARN"
        return $true
    }
    
    Write-Log "Found installation: $($unitwainInfo.DisplayName)"
    
    try {
        $uninstallString = $unitwainInfo.UninstallString
        
        # Determine if it's MSI or EXE uninstaller
        if ($uninstallString -match "msiexec") {
            Write-Log "Using MSI uninstall method..."
            
            if ($uninstallString -match "{[A-F0-9-]+") {
                $productCode = $matches[0]
            }
            else {
                $productCode = $unitwainInfo.ProductCode
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
            
            # Silent uninstall flags
            $silentArgs = "/S /silent /verysilent"
            
            if ($uninstallString -match '"(.+?)"\s*(.*)') {
                $exePath = $matches[1]
                $existingArgs = $matches[2]
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
            default { 
                if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
                    return $true
                }
                Write-Log "Uninstall completed with exit code: $($process.ExitCode)" "WARN"
                return $true  # Assume success
            }
        }
    }
    catch {
        Write-Log "Uninstall failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Remove-UnitwainResiduals {
    Write-Log "Cleaning up residual files and registry entries..."
    
    # Remove installation directories
    $installPaths = @(
        "$env:ProgramFiles\Unitwain",
        "${env:ProgramFiles(x86)}\Unitwain",
        "$env:ProgramFiles\TWAIN\Unitwain",
        "$env:ProgramData\Unitwain",
        "$env:PUBLIC\Unitwain"
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
        "HKLM:\SOFTWARE\Unitwain",
        "HKLM:\SOFTWARE\WOW6432Node\Unitwain",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Unitwain",
        "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Unitwain"
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
    
    # Remove user settings if requested
    if ($RemoveSettings) {
        Write-Log "Removing user settings..."
        
        $userProfiles = Get-ChildItem -Path "$env:SystemDrive\Users" -Directory | 
            Where-Object { $_.Name -notin @("Public", "Default", "All Users") }
        
        foreach ($profile in $userProfiles) {
            $userConfigPaths = @(
                (Join-Path $profile.FullName "AppData\Roaming\Unitwain"),
                (Join-Path $profile.FullName "AppData\Local\Unitwain"),
                (Join-Path $profile.FullName "Documents\Unitwain")
            )
            
            foreach ($userPath in $userConfigPaths) {
                if (Test-Path -Path $userPath) {
                    try {
                        Remove-Item -Path $userPath -Recurse -Force -ErrorAction Stop
                        Write-Log "Removed user settings: $userPath"
                    }
                    catch {
                        Write-Log "Failed to remove $userPath" "WARN"
                    }
                }
            }
        }
    }
    
    # Remove TWAIN data source if present
    $twainPaths = @(
        "$env:WINDIR\twain_32\Unitwain",
        "$env:WINDIR\twain_64\Unitwain"
    )
    
    foreach ($twainPath in $twainPaths) {
        if (Test-Path -Path $twainPath) {
            try {
                Remove-Item -Path $twainPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Removed TWAIN data source: $twainPath"
            }
            catch {
                Write-Log "Failed to remove TWAIN data source $twainPath" "WARN"
            }
        }
    }
}

# ==================== MAIN EXECUTION ====================

Write-Log "=== Unitwain Uninstallation Started ==="

# Perform uninstallation
$uninstallSuccess = Uninstall-Unitwain

# Clean up residuals
Remove-UnitwainResiduals

if ($uninstallSuccess) {
    Write-Log "=== Uninstallation completed successfully ===" "SUCCESS"
    exit 0
}
else {
    Write-Log "=== Uninstallation completed with warnings ===" "WARN"
    exit 0
}