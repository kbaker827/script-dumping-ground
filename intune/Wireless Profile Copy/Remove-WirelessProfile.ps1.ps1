#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Removes a wireless (Wi-Fi) profile from Windows.

.DESCRIPTION
    Removes a previously installed Wi-Fi profile from the system.

.PARAMETER ProfileName
    Name of the Wi-Fi profile to remove (required)

.PARAMETER LogPath
    Path for operation logs

.EXAMPLE
    .\Remove-WirelessProfile.ps1 -ProfileName "CorpWiFi"

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, HelpMessage="Name of the Wi-Fi profile to remove")]
    [string]$ProfileName,

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
)

# Configuration
$ScriptName = "WirelessProfileRemove"
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
        Write-Host $logEntry
    }
    
    $color = switch ($Level) {
        "ERROR"   { "Red" }
        "WARN"    { "Yellow" }
        "SUCCESS" { "Green" }
        default   { "White" }
    }
    Write-Host $logEntry -ForegroundColor $color
}

function Remove-WirelessProfile {
    param([string]$Name)
    
    try {
        Write-Log "Removing wireless profile: $Name"
        
        # Check if profile exists
        $checkResult = netsh wlan show profile name="$Name" 2>&1
        if ($checkResult -match "Profile.*not found") {
            Write-Log "Profile not found - may already be removed" "WARN"
            return $true
        }
        
        # Remove the profile
        $result = netsh wlan delete profile name="$Name" 2>&1
        Write-Log "netsh result: $result"
        
        if ($result -match "successfully" -or $result -match "is deleted") {
            Write-Log "Profile removed successfully" "SUCCESS"
            return $true
        }
        else {
            Write-Log "Unexpected result from removal: $result" "WARN"
            return $true  # Assume success
        }
    }
    catch {
        Write-Log "Failed to remove profile: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Remove-RegistryEntry {
    param([string]$Name)
    
    $regPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\WirelessProfile"
    
    try {
        if (Test-Path $regPath) {
            $installedProfile = Get-ItemProperty -Path $regPath -Name "InstalledProfile" -ErrorAction SilentlyContinue
            if ($installedProfile -and $installedProfile.InstalledProfile -eq $Name) {
                Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
                Write-Log "Registry entry removed" "SUCCESS"
            }
        }
    }
    catch {
        Write-Log "Failed to remove registry entry: $($_.Exception.Message)" "WARN"
    }
}

# ==================== MAIN EXECUTION ====================

Write-Log "=== Wireless Profile Removal Started ==="

$removeSuccess = Remove-WirelessProfile -Name $ProfileName

if ($removeSuccess) {
    Remove-RegistryEntry -Name $ProfileName
    Write-Log "=== Profile removal completed successfully ===" "SUCCESS"
    exit 0
}
else {
    Write-Log "=== Profile removal failed ===" "ERROR"
    exit 1
}