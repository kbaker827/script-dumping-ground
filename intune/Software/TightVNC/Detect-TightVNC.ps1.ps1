<#
.SYNOPSIS
    Detection script for TightVNC.

.DESCRIPTION
    Checks if TightVNC server is installed and configured.
    Returns exit code 0 if detected, 1 if not detected.

.EXAMPLE
    .\Detect-TightVNC.ps1
    Exit code 0 = TightVNC detected
    Exit code 1 = TightVNC not detected

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
#>

[CmdletBinding()]
param()

$VerbosePreference = "SilentlyContinue"

function Test-TightVNCInstalled {
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($regPath in $regPaths) {
        $product = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -like "*TightVNC*" }
        
        if ($product) {
            Write-Output "TightVNC found: $($product.DisplayName) v$($product.DisplayVersion)"
            return $true
        }
    }
    
    return $false
}

function Test-TightVNCService {
    $service = Get-Service -Name "TightVNC Server" -ErrorAction SilentlyContinue
    
    if ($service) {
        if ($service.Status -eq "Running") {
            Write-Output "TightVNC Server service is running"
            return $true
        }
        else {
            Write-Output "TightVNC Server service exists but is not running"
            return $false
        }
    }
    
    return $false
}

function Test-TightVNCRegistryMarker {
    $regPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\TightVNC"
    
    if (Test-Path -Path $regPath) {
        $installDate = Get-ItemProperty -Path $regPath -Name "InstallDate" -ErrorAction SilentlyContinue
        if ($installDate) {
            Write-Output "Registry marker found - InstallDate: $($installDate.InstallDate)"
            return $true
        }
    }
    
    return $false
}

function Test-TightVNCExecutable {
    $possiblePaths = @(
        "$env:ProgramFiles\TightVNC\tvnserver.exe",
        "${env:ProgramFiles(x86)}\TightVNC\tvnserver.exe"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path -Path $path) {
            Write-Output "TightVNC executable found: $path"
            return $true
        }
    }
    
    return $false
}

# ==================== MAIN EXECUTION ====================

$detected = $false
$detectionMethods = @()

# Method 1: Registry check
if (Test-TightVNCInstalled) {
    $detected = $true
    $detectionMethods += "Registry"
}

# Method 2: Service check
if (Test-TightVNCService) {
    $detected = $true
    $detectionMethods += "Service"
}

# Method 3: Registry marker
if (Test-TightVNCRegistryMarker) {
    $detected = $true
    $detectionMethods += "RegistryMarker"
}

# Method 4: Executable files
if (Test-TightVNCExecutable) {
    $detected = $true
    $detectionMethods += "Executable"
}

# Output result
if ($detected) {
    Write-Output "Detection methods triggered: $($detectionMethods -join ', ')"
    exit 0  # Compliant / Installed
}
else {
    Write-Output "TightVNC not detected"
    exit 1  # Not compliant / Not installed
}