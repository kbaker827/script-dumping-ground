<#
.SYNOPSIS
    Detection script for Unitwain.

.DESCRIPTION
    Checks if Unitwain scanner software is installed.
    Returns exit code 0 if detected, 1 if not detected.

.EXAMPLE
    .\Detect-Unitwain.ps1
    Exit code 0 = Unitwain detected
    Exit code 1 = Unitwain not detected

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
#>

[CmdletBinding()]
param()

$VerbosePreference = "SilentlyContinue"

function Test-UnitwainInstalled {
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($regPath in $regPaths) {
        $product = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -like "*Unitwain*" -or $_.Publisher -like "*Unitwain*" }
        
        if ($product) {
            Write-Output "Unitwain found: $($product.DisplayName) v$($product.DisplayVersion)"
            return $true
        }
    }
    
    return $false
}

function Test-UnitwainRegistryMarker {
    $regPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Unitwain"
    
    if (Test-Path -Path $regPath) {
        $installDate = Get-ItemProperty -Path $regPath -Name "InstallDate" -ErrorAction SilentlyContinue
        if ($installDate) {
            Write-Output "Registry marker found - InstallDate: $($installDate.InstallDate)"
            return $true
        }
    }
    
    return $false
}

function Test-UnitwainExecutable {
    $possiblePaths = @(
        "$env:ProgramFiles\Unitwain",
        "${env:ProgramFiles(x86)}\Unitwain",
        "$env:ProgramFiles\TWAIN\Unitwain"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path -Path $path) {
            $exeFiles = Get-ChildItem -Path $path -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($exeFiles) {
                Write-Output "Unitwain executable found: $($exeFiles.FullName)"
                return $true
            }
        }
    }
    
    return $false
}

function Test-UnitwainLicense {
    $licensePaths = @(
        "$env:ProgramData\Unitwain\license.dat",
        "$env:ProgramData\Unitwain\Config\license.key",
        "$env:ProgramFiles\Unitwain\license.dat"
    )
    
    foreach ($licensePath in $licensePaths) {
        if (Test-Path -Path $licensePath) {
            Write-Output "Unitwain license file found: $licensePath"
            return $true
        }
    }
    
    # Check registry for license
    $regPath = "HKLM:\SOFTWARE\Unitwain"
    if (Test-Path -Path $regPath) {
        $license = Get-ItemProperty -Path $regPath -Name "LicenseKey" -ErrorAction SilentlyContinue
        if ($license) {
            Write-Output "Unitwain license found in registry"
            return $true
        }
    }
    
    return $false
}

# ==================== MAIN EXECUTION ====================

$detected = $false
$detectionMethods = @()

# Method 1: Registry check
if (Test-UnitwainInstalled) {
    $detected = $true
    $detectionMethods += "Registry"
}

# Method 2: Registry marker
if (Test-UnitwainRegistryMarker) {
    $detected = $true
    $detectionMethods += "RegistryMarker"
}

# Method 3: Executable files
if (Test-UnitwainExecutable) {
    $detected = $true
    $detectionMethods += "Executable"
}

# Method 4: License file
if (Test-UnitwainLicense) {
    $detected = $true
    $detectionMethods += "License"
}

# Output result
if ($detected) {
    Write-Output "Detection methods triggered: $($detectionMethods -join ', ')"
    exit 0  # Compliant / Installed
}
else {
    Write-Output "Unitwain not detected"
    exit 1  # Not compliant / Not installed
}