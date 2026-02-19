<#
.SYNOPSIS
    Detection script for computer description sync from AD.

.DESCRIPTION
    Checks if the computer description has been synced from AD.
    Returns exit code 0 if synced, 1 if not.

.EXAMPLE
    .\Detect-ComputerDescriptionFromAD.ps1

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
#>

[CmdletBinding()]
param()

$VerbosePreference = "SilentlyContinue"

function Test-RegistryMarker {
    $regPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\ComputerDescriptionAD"
    
    if (Test-Path -Path $regPath) {
        $lastRun = Get-ItemProperty -Path $regPath -Name "LastRun" -ErrorAction SilentlyContinue
        $success = Get-ItemProperty -Path $regPath -Name "Success" -ErrorAction SilentlyContinue
        $adDescription = Get-ItemProperty -Path $regPath -Name "ADDescription" -ErrorAction SilentlyContinue
        
        if ($lastRun -and $success.Success -eq "True") {
            Write-Output "Registry marker found - LastRun: $($lastRun.LastRun)"
            Write-Output "AD Description: $($adDescription.ADDescription)"
            return $true
        }
    }
    
    return $false
}

function Test-DescriptionSet {
    try {
        $computerInfo = Get-WmiObject -Class Win32_OperatingSystem
        $description = $computerInfo.Description
        
        if (-not [string]::IsNullOrEmpty($description)) {
            Write-Output "Computer description is set: $description"
            return $true
        }
        else {
            Write-Output "Computer description is empty"
            return $false
        }
    }
    catch {
        Write-Output "Failed to check computer description"
        return $false
    }
}

# ==================== MAIN EXECUTION ====================

$detected = $false
$detectionMethods = @()

# Method 1: Check registry marker
if (Test-RegistryMarker) {
    $detected = $true
    $detectionMethods += "RegistryMarker"
}

# Method 2: Check if description is set
if (Test-DescriptionSet) {
    $detected = $true
    $detectionMethods += "DescriptionSet"
}

# Output result
if ($detected) {
    Write-Output "Detection methods triggered: $($detectionMethods -join ', ')"
    exit 0  # Compliant / Completed
}
else {
    Write-Output "Computer description sync not detected"
    exit 1  # Not compliant / Not completed
}