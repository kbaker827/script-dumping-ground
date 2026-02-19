<#
.SYNOPSIS
    Detection script for Trend Micro Worry-Free Business Security (WFBS).

.DESCRIPTION
    Checks if Trend Micro WFBS agent is installed and services are present.
    Returns exit code 0 if detected, 1 if not detected.

.EXAMPLE
    .\Detect-TrendWFBS.ps1
    Exit code 0 = WFBS detected
    Exit code 1 = WFBS not detected

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
#>

[CmdletBinding()]
param()

$VerbosePreference = "SilentlyContinue"

function Test-WFBSInstalled {
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($regPath in $regPaths) {
        $product = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -like "*Trend Micro*Worry-Free*" -or 
                          $_.DisplayName -like "*Trend Micro*Security*Agent*" }
        
        if ($product) {
            Write-Output "Trend WFBS found: $($product.DisplayName) v$($product.DisplayVersion)"
            return $true
        }
    }
    
    return $false
}

function Test-WFBSServices {
    $trendServices = Get-Service -Name "Trend Micro*" -ErrorAction SilentlyContinue
    
    if ($trendServices) {
        $runningCount = ($trendServices | Where-Object { $_.Status -eq "Running" }).Count
        Write-Output "Trend services found: $($trendServices.Count) total, $runningCount running"
        return ($runningCount -gt 0)
    }
    
    return $false
}

function Test-WFBSRegistryMarker {
    $regPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\TrendWFBS"
    
    if (Test-Path -Path $regPath) {
        $installDate = Get-ItemProperty -Path $regPath -Name "InstallDate" -ErrorAction SilentlyContinue
        if ($installDate) {
            Write-Output "Registry marker found - InstallDate: $($installDate.InstallDate)"
            return $true
        }
    }
    
    return $false
}

function Test-WFBSExecutable {
    $possiblePaths = @(
        "$env:ProgramFiles\Trend Micro\Security Agent",
        "${env:ProgramFiles(x86)}\Trend Micro\Security Agent",
        "$env:ProgramFiles\Trend Micro\Worry-Free Business Security"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path -Path $path) {
            $coreService = Get-ChildItem -Path $path -Recurse -Filter "CoreServiceShell.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($coreService) {
                Write-Output "Trend WFBS executable found: $($coreService.FullName)"
                return $true
            }
        }
    }
    
    return $false
}

# ==================== MAIN EXECUTION ====================

$detected = $false
$detectionMethods = @()

# Method 1: Registry check
if (Test-WFBSInstalled) {
    $detected = $true
    $detectionMethods += "Registry"
}

# Method 2: Service check
if (Test-WFBSServices) {
    $detected = $true
    $detectionMethods += "Service"
}

# Method 3: Registry marker
if (Test-WFBSRegistryMarker) {
    $detected = $true
    $detectionMethods += "RegistryMarker"
}

# Method 4: Executable files
if (Test-WFBSExecutable) {
    $detected = $true
    $detectionMethods += "Executable"
}

# Output result
if ($detected) {
    Write-Output "Detection methods triggered: $($detectionMethods -join ', ')"
    exit 0  # Compliant / Installed
}
else {
    Write-Output "Trend WFBS not detected"
    exit 1  # Not compliant / Not installed
}