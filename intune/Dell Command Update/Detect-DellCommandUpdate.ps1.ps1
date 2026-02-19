<#
.SYNOPSIS
    Detection script for Dell Command Update.

.DESCRIPTION
    Checks if Dell Command Update is installed and if updates were applied.
    Returns exit code 0 if detected, 1 if not.

.EXAMPLE
    .\Detect-DellCommandUpdate.ps1

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
#>

[CmdletBinding()]
param()

$VerbosePreference = "SilentlyContinue"

function Test-DellCommandUpdateInstalled {
    $dcuPaths = @(
        "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe",
        "$env:ProgramFiles\Dell\CommandUpdate\dcu-cli.exe"
    )
    
    foreach ($path in $dcuPaths) {
        if (Test-Path -Path $path) {
            Write-Output "Dell Command Update found: $path"
            return $true
        }
    }
    
    # Check registry
    $regPaths = @(
        "HKLM:\SOFTWARE\Dell\UpdateService",
        "HKLM:\SOFTWARE\WOW6432Node\Dell\UpdateService"
    )
    
    foreach ($regPath in $regPaths) {
        if (Test-Path -Path $regPath) {
            Write-Output "Dell Command Update registry found: $regPath"
            return $true
        }
    }
    
    return $false
}

function Test-RegistryMarker {
    $regPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\DellCommandUpdate"
    
    if (Test-Path -Path $regPath) {
        $lastRun = Get-ItemProperty -Path $regPath -Name "LastRun" -ErrorAction SilentlyContinue
        $success = Get-ItemProperty -Path $regPath -Name "Success" -ErrorAction SilentlyContinue
        $updatesApplied = Get-ItemProperty -Path $regPath -Name "UpdatesApplied" -ErrorAction SilentlyContinue
        
        if ($lastRun -and $success.Success -eq "True") {
            Write-Output "Registry marker found - LastRun: $($lastRun.LastRun), UpdatesApplied: $($updatesApplied.UpdatesApplied)"
            return $true
        }
    }
    
    return $false
}

function Test-IsDellComputer {
    try {
        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem
        return ($computerSystem.Manufacturer -like "*Dell*")
    }
    catch {
        return $false
    }
}

# Main
Write-Output "Checking Dell Command Update status..."

# If not a Dell computer, don't fail but report
if (-not (Test-IsDellComputer)) {
    Write-Output "Not a Dell computer - Dell Command Update not applicable"
    # Exit 0 so Intune doesn't show as failed on non-Dell devices
    exit 0
}

$detected = $false
$detectionMethods = @()

if (Test-DellCommandUpdateInstalled) {
    $detected = $true
    $detectionMethods += "Installed"
}

if (Test-RegistryMarker) {
    $detected = $true
    $detectionMethods += "RegistryMarker"
}

if ($detected) {
    Write-Output "Detection methods: $($detectionMethods -join ', ')"
    exit 0
}
else {
    Write-Output "Dell Command Update not detected"
    exit 1
}