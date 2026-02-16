<#
.SYNOPSIS
    Detection script for Adobe Acrobat Reader DC Intune deployment.

.DESCRIPTION
    Checks if Adobe Acrobat Reader DC is installed and returns appropriate
    exit code for Intune Win32 app detection.

    Exit Codes:
    0 = Adobe Reader is installed (Intune: App detected)
    1 = Adobe Reader is NOT installed (Intune: App not detected)

    Author: Kyle Baker
    Version: 1.0
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$MinimumVersion = "23.0.0"
)

$ErrorActionPreference = "SilentlyContinue"

# Detection paths for Acrobat Reader DC
$DetectionPaths = @(
    "${env:ProgramFiles(x86)}\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe",
    "$env:ProgramFiles\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe"
)

# Registry uninstall keys
$RegistryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{AC76BA86-7AD7-1033-7B44-AC0F074E4100}",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{AC76BA86-7AD7-1033-7B44-AC0F074E4100}"
)

$Installed = $false
$Version = $null

# Check for executable
foreach ($Path in $DetectionPaths) {
    if (Test-Path $Path) {
        try {
            $FileInfo = Get-ItemProperty $Path
            $Version = $FileInfo.VersionInfo.FileVersion
            Write-Host "Adobe Reader found at: $Path"
            Write-Host "Version: $Version"
            $Installed = $true
            break
        }
        catch {
            # Continue checking other paths
        }
    }
}

# Fallback: Check registry
if (-not $Installed) {
    foreach ($RegPath in $RegistryPaths) {
        if (Test-Path $RegPath) {
            try {
                $RegProps = Get-ItemProperty $RegPath
                if ($RegProps.DisplayName -like "*Adobe Acrobat Reader*") {
                    $Version = $RegProps.DisplayVersion
                    Write-Host "Adobe Reader found in registry: $($RegProps.DisplayName)"
                    Write-Host "Version: $Version"
                    $Installed = $true
                    break
                }
            }
            catch {
                # Continue checking other paths
            }
        }
    }
}

if ($Installed) {
    # Check version if specified
    if ($MinimumVersion) {
        try {
            $InstalledVer = [System.Version]$Version
            $RequiredVer = [System.Version]$MinimumVersion
            
            if ($InstalledVer -ge $RequiredVer) {
                Write-Host "Version check passed ($Version >= $MinimumVersion)"
                exit 0  # App is installed and meets version requirement
            } else {
                Write-Host "Version too old ($Version < $MinimumVersion)"
                exit 1  # App needs upgrade
            }
        }
        catch {
            # Version comparison failed, assume installed
            Write-Host "Version check skipped (version: $Version)"
            exit 0
        }
    }
    
    Write-Host "Adobe Acrobat Reader DC is installed"
    exit 0  # Intune: App is installed
} else {
    Write-Host "Adobe Acrobat Reader DC is NOT installed"
    exit 1  # Intune: App is NOT installed
}
