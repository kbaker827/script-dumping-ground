<#
.SYNOPSIS
    Detection script for Adobe Acrobat universal uninstaller.

.DESCRIPTION
    Checks if ANY Adobe Acrobat product is still installed.
    Returns exit code 0 if products remain (trigger uninstall),
    exit code 1 if no products found (uninstall not needed/successful).

    Use this for Intune detection to ensure complete removal.

    Author: Kyle Baker
    Version: 1.0
#>

$ErrorActionPreference = "SilentlyContinue"

Write-Host "Scanning for Adobe Acrobat products..."

# Product names to detect
$AdobePatterns = @(
    "Adobe Acrobat Reader",
    "Adobe Acrobat Pro",
    "Adobe Acrobat Standard",
    "Adobe Acrobat DC",
    "Adobe Acrobat 2020",
    "Adobe Acrobat 2023",
    "Adobe Acrobat XI"
)

$FoundProducts = @()

# Method 1: WMI
$WMIProducts = Get-WmiObject -Class Win32_Product | Where-Object { 
    $ProductName = $_.Name
    foreach ($Pattern in $AdobePatterns) {
        if ($ProductName -like "*$Pattern*") {
            return $true
        }
    }
    return $false
}

foreach ($Product in $WMIProducts) {
    $FoundProducts += $Product.Name
}

# Method 2: Registry
$RegistryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

foreach ($RegPath in $RegistryPaths) {
    $RegProducts = Get-ItemProperty $RegPath | Where-Object { 
        $DisplayName = $_.DisplayName
        foreach ($Pattern in $AdobePatterns) {
            if ($DisplayName -like "*$Pattern*") {
                return $true
            }
        }
        return $false
    }
    
    foreach ($Product in $RegProducts) {
        if ($FoundProducts -notcontains $Product.DisplayName) {
            $FoundProducts += $Product.DisplayName
        }
    }
}

# Method 3: Check for executables
$ExecutablePaths = @(
    "${env:ProgramFiles(x86)}\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe",
    "${env:ProgramFiles}\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe",
    "${env:ProgramFiles(x86)}\Adobe\Acrobat 2020\Acrobat\Acrobat.exe",
    "${env:ProgramFiles}\Adobe\Acrobat 2020\Acrobat\Acrobat.exe",
    "${env:ProgramFiles(x86)}\Adobe\Acrobat DC\Acrobat\Acrobat.exe",
    "${env:ProgramFiles}\Adobe\Acrobat DC\Acrobat\Acrobat.exe"
)

$ExecutablesFound = $false
foreach ($ExePath in $ExecutablePaths) {
    if (Test-Path $ExePath) {
        $ExecutablesFound = $true
        break
    }
}

# Results
if ($FoundProducts.Count -gt 0 -or $ExecutablesFound) {
    Write-Host "Adobe Acrobat products detected:"
    foreach ($Product in $FoundProducts) {
        Write-Host "  - $Product"
    }
    if ($ExecutablesFound) {
        Write-Host "  - Executable files present"
    }
    Write-Host "Uninstall required."
    exit 0  # Products found - uninstall needed
} else {
    Write-Host "No Adobe Acrobat products detected."
    exit 1  # No products - uninstall not needed
}
