#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Renames computer during Windows Autopilot with Hybrid Azure AD Join support.
    
.DESCRIPTION
    This script renames the computer during the Autopilot enrollment process.
    Designed for Hybrid Azure AD Join scenarios where the device is joined to
    on-premises AD and registered in Azure AD.
    
    Can be deployed as:
    - Intune Win32 app (during ESP)
    - Intune PowerShell script
    - Proactive remediation script
    
.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
    Requirements:   Windows 10/11, Autopilot, Hybrid Join
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$NewComputerName = "",
    
    [Parameter()]
    [string]$NamingPrefix = "CORP",
    
    [Parameter()]
    [switch]$UseSerialNumber,
    
    [Parameter()]
    [int]$MaxSerialLength = 12,
    
    [Parameter()]
    [string]$DomainName = "",
    
    [Parameter()]
    [switch]$RestartAfterRename
)

# Configuration
$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogFile = "$LogPath\AutopilotComputerRename.log"

# Ensure log directory exists
if (!(Test-Path -Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $logEntry
    Write-Verbose $logEntry
}

function Get-SafeComputerName {
    param(
        [string]$BaseName,
        [int]$MaxLength = 15
    )
    
    # Remove invalid characters and convert to uppercase
    $safeName = $BaseName.ToUpper() -replace '[^A-Z0-9-]', ''
    
    # Trim to max length (NetBIOS limit is 15 chars)
    if ($safeName.Length -gt $MaxLength) {
        $safeName = $safeName.Substring(0, $MaxLength)
    }
    
    return $safeName
}

function Test-AutopilotESP {
    # Check if we're in Autopilot Enrollment Status Page
    $espProcesses = @("wwahost", "EnterpriseDesktopAppMgmt", "Microsoft.Windows.SecHealthUI")
    $inESP = $espProcesses | ForEach-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
    
    $provisioning = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Provisioning\Autopilot\" -Name "AutopilotProfile" -ErrorAction SilentlyContinue
    
    return ($null -ne $inESP) -or ($null -ne $provisioning)
}

function Get-ComputerNameFromSource {
    param(
        [string]$Prefix,
        [switch]$UseSerial
    )
    
    if ($UseSerial) {
        try {
            $serial = (Get-WmiObject -Class Win32_BIOS).SerialNumber
            # Clean and truncate serial
            $serial = ($serial -replace '[^A-Z0-9]', '').Substring(0, [Math]::Min($MaxSerialLength, $serial.Length))
            return "$Prefix-$serial"
        }
        catch {
            Write-Log "Failed to get serial number: $($_.Exception.Message)" "ERROR"
            return $null
        }
    }
    
    # Generate name based on asset tag if available
    try {
        $assetTag = (Get-WmiObject -Class Win32_SystemEnclosure).SMBIOSAssetTag
        if ($assetTag -and $assetTag -notin @("No Asset Tag", "None", "")) {
            return "$Prefix-$assetTag"
        }
    }
    catch {
        Write-Log "Failed to get asset tag: $($_.Exception.Message)" "WARN"
    }
    
    # Fallback to serial if nothing else works
    return Get-ComputerNameFromSource -Prefix $Prefix -UseSerial
}

# ==================== MAIN EXECUTION ====================

Write-Log "=== Autopilot Computer Rename Script Started ==="
Write-Log "Current computer name: $env:COMPUTERNAME"

# Determine new computer name
if ([string]::IsNullOrEmpty($NewComputerName)) {
    Write-Log "No computer name specified, generating from naming convention..."
    $NewComputerName = Get-ComputerNameFromSource -Prefix $NamingPrefix -UseSerial:$UseSerialNumber
}

if ([string]::IsNullOrEmpty($NewComputerName)) {
    Write-Log "Failed to generate computer name. Exiting." "ERROR"
    exit 1
}

# Ensure name is safe for NetBIOS
$NewComputerName = Get-SafeComputerName -BaseName $NewComputerName
Write-Log "Target computer name: $NewComputerName"

# Check if rename is needed
if ($env:COMPUTERNAME -eq $NewComputerName) {
    Write-Log "Computer already has correct name. No action needed." "INFO"
    exit 0
}

# Validate we're in a good state to rename
Write-Log "Checking system state..."

# Check if domain joined (for hybrid join)
$computerSystem = Get-WmiObject -Class Win32_ComputerSystem
$isDomainJoined = $computerSystem.PartOfDomain
$currentDomain = $computerSystem.Domain

Write-Log "Domain joined: $isDomainJoined | Current domain: $currentDomain"

# Check for pending reboot
$pendingReboot = $false
try {
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
        $pendingReboot = $true
    }
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
        $pendingReboot = $true
    }
}
catch {
    Write-Log "Could not check pending reboot status" "WARN"
}

if ($pendingReboot) {
    Write-Log "Pending reboot detected. Rename should be deferred." "WARN"
}

# Perform the rename
try {
    Write-Log "Initiating computer rename..."
    
    if ($isDomainJoined -and $DomainName) {
        # For domain-joined machines, we may need domain credentials
        # In Autopilot hybrid join, this should already be handled by the join process
        Write-Log "Machine is domain joined. Using Rename-Computer for domain member..."
        Rename-Computer -NewName $NewComputerName -Force -ErrorAction Stop
    }
    else {
        # Workgroup or Azure AD joined
        Write-Log "Renaming workgroup/Azure AD joined computer..."
        Rename-Computer -NewName $NewComputerName -Force -ErrorAction Stop
    }
    
    Write-Log "Computer successfully renamed to: $NewComputerName" "SUCCESS"
    
    # Create marker file for Intune detection
    $markerPath = "$env:ProgramData\AutopilotRename"
    if (!(Test-Path -Path $markerPath)) {
        New-Item -Path $markerPath -ItemType Directory -Force | Out-Null
    }
    $markerFile = "$markerPath\rename-completed.marker"
    [PSCustomObject]@{
        OldName = $env:COMPUTERNAME
        NewName = $NewComputerName
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Method = "Autopilot Script"
    } | ConvertTo-Json | Set-Content -Path $markerFile
    
    Write-Log "Marker file created at: $markerFile"
    
    # Handle restart
    if ($RestartAfterRename) {
        Write-Log "Restart scheduled in 60 seconds..."
        shutdown /r /t 60 /c "Computer renamed to $NewComputerName. Restarting..." /f
    }
    else {
        Write-Log "Restart deferred. Name will take effect after next reboot."
    }
    
    exit 0
}
catch {
    Write-Log "Failed to rename computer: $($_.Exception.Message)" "ERROR"
    exit 1
}
finally {
    Write-Log "=== Script Completed ==="
}