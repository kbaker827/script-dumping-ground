<#
.SYNOPSIS
    Detection script for wireless profile installation.

.DESCRIPTION
    Checks if a wireless (Wi-Fi) profile is installed on the system.
    Returns exit code 0 if detected, 1 if not detected.

.PARAMETER ProfileName
    Name of the Wi-Fi profile to check for

.EXAMPLE
    .\Detect-WirelessProfile.ps1 -ProfileName "CorpWiFi"

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ProfileName
)

$VerbosePreference = "SilentlyContinue"

function Test-ProfileInstalled {
    param([string]$Name)
    
    try {
        $result = netsh wlan show profile name="$Name" 2>&1
        if ($result -match "Profile.*not found") {
            return $false
        }
        
        # Extract profile info
        $profileInfo = $result | Where-Object { $_ -match "Profile name|Authentication|Connection mode" }
        Write-Output "Profile found: $Name"
        Write-Output ($profileInfo -join "`n")
        return $true
    }
    catch {
        return $false
    }
}

function Test-RegistryMarker {
    param([string]$Name)
    
    $regPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\WirelessProfile"
    
    if (Test-Path -Path $regPath) {
        $installedProfile = Get-ItemProperty -Path $regPath -Name "InstalledProfile" -ErrorAction SilentlyContinue
        if ($installedProfile -and $installedProfile.InstalledProfile -eq $Name) {
            $installDate = Get-ItemProperty -Path $regPath -Name "InstallDate" -ErrorAction SilentlyContinue
            Write-Output "Registry marker found - InstallDate: $($installDate.InstallDate)"
            return $true
        }
    }
    
    return $false
}

function Get-ProfileList {
    try {
        $profiles = netsh wlan show profiles 2>&1
        $profileNames = $profiles | Select-String "All User Profile\s*:\s*(.+)$" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }
        return $profileNames
    }
    catch {
        return @()
    }
}

# ==================== MAIN EXECUTION ====================

Write-Output "Checking for wireless profile: $ProfileName"
Write-Output ""

$detected = $false
$detectionMethods = @()

# Method 1: Check if profile exists in WLAN profiles
if (Test-ProfileInstalled -Name $ProfileName) {
    $detected = $true
    $detectionMethods += "WLANProfile"
}

# Method 2: Check registry marker
if (Test-RegistryMarker -Name $ProfileName) {
    $detected = $true
    $detectionMethods += "RegistryMarker"
}

# Output result
if ($detected) {
    Write-Output ""
    Write-Output "Detection methods triggered: $($detectionMethods -join ', ')"
    exit 0  # Compliant / Installed
}
else {
    $allProfiles = Get-ProfileList
    Write-Output ""
    Write-Output "Profile not found. Available profiles: $($allProfiles -join ', ')"
    exit 1  # Not compliant / Not installed
}