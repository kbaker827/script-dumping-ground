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
    
    WHATIF MODE: Use -WhatIf or -TestMode to preview changes without applying them.
    
.NOTES
    Version:        1.1
    Author:         IT Admin
    Creation Date:  2025-02-19
    Requirements:   Windows 10/11, Autopilot, Hybrid Join
#>

[CmdletBinding(SupportsShouldProcess=$true)]
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
    [switch]$RestartAfterRename,
    
    [Parameter(HelpMessage="Preview changes without applying them")]
    [Alias("TestMode")]
    [switch]$WhatIf
)

# Configuration
$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogFile = "$LogPath\AutopilotComputerRename.log"

# Track WhatIf state
$script:IsWhatIf = $WhatIf

# Ensure log directory exists
if (!(Test-Path -Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO", [switch]$WhatIfTag)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $whatIfPrefix = if ($WhatIfTag -or $script:IsWhatIf) { "[WHATIF] " } else { "" }
    $logEntry = "[$timestamp] [$Level] $whatIfPrefix$Message"
    Add-Content -Path $LogFile -Value $logEntry
    Write-Host $logEntry
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
            $serial = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
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
        $assetTag = (Get-CimInstance -ClassName Win32_SystemEnclosure).SMBIOSAssetTag
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

function Show-WhatIfSummary {
    param(
        [string]$CurrentName,
        [string]$ProposedName,
        [bool]$DomainJoined,
        [string]$Domain,
        [bool]$InESP,
        [bool]$PendingReboot
    )
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                     WHATIF MODE SUMMARY                        ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Current Computer Name: " -NoNewline
    Write-Host $CurrentName -ForegroundColor Yellow
    Write-Host "Proposed New Name:     " -NoNewline
    Write-Host $ProposedName -ForegroundColor Green
    Write-Host ""
    Write-Host "System State:" -ForegroundColor White
    Write-Host "  • Domain Joined:     $DomainJoined" -ForegroundColor $(if ($DomainJoined) { "Green" } else { "Gray" })
    if ($DomainJoined) {
        Write-Host "  • Domain:            $Domain" -ForegroundColor Gray
    }
    Write-Host "  • In Autopilot ESP:  $InESP" -ForegroundColor $(if ($InESP) { "Green" } else { "Gray" })
    Write-Host "  • Pending Reboot:    $PendingReboot" -ForegroundColor $(if ($PendingReboot) { "Yellow" } else { "Green" })
    Write-Host ""
    Write-Host "Actions that WOULD be performed:" -ForegroundColor White
    
    if ($CurrentName -eq $ProposedName) {
        Write-Host "  ✓ No action needed - names match" -ForegroundColor Green
    }
    else {
        Write-Host "  → Rename computer from '$CurrentName' to '$ProposedName'" -ForegroundColor Yellow
        if ($DomainJoined) {
            Write-Host "    (Using domain-joined rename method)" -ForegroundColor Gray
        }
        else {
            Write-Host "    (Using workgroup/Azure AD rename method)" -ForegroundColor Gray
        }
        Write-Host "  → Create marker file at: %ProgramData%\AutopilotRename\rename-completed.marker" -ForegroundColor Yellow
        
        if ($RestartAfterRename) {
            Write-Host "  → Schedule restart in 60 seconds" -ForegroundColor Yellow
        }
        else {
            Write-Host "  → Defer restart (name takes effect on next reboot)" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "Validation:" -ForegroundColor White
    
    # Validate name length
    if ($ProposedName.Length -gt 15) {
        Write-Host "  ⚠ WARNING: Name exceeds 15 chars (NetBIOS limit)" -ForegroundColor Red
    }
    else {
        Write-Host "  ✓ Name length OK (≤15 chars)" -ForegroundColor Green
    }
    
    # Check for invalid chars
    if ($ProposedName -match '[^A-Z0-9-]') {
        Write-Host "  ⚠ WARNING: Name contains invalid characters" -ForegroundColor Red
    }
    else {
        Write-Host "  ✓ Name characters OK" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "To apply these changes, run without -WhatIf:" -ForegroundColor Cyan
    Write-Host "  .\Rename-Computer-Autopilot.ps1" -ForegroundColor White -NoNewline
    if ($NamingPrefix -ne "CORP") { Write-Host " -NamingPrefix `"$NamingPrefix`"" -ForegroundColor White -NoNewline }
    if ($UseSerialNumber) { Write-Host " -UseSerialNumber" -ForegroundColor White -NoNewline }
    if ($RestartAfterRename) { Write-Host " -RestartAfterRename" -ForegroundColor White -NoNewline }
    if ($NewComputerName) { Write-Host " -NewComputerName `"$NewComputerName`"" -ForegroundColor White -NoNewline }
    Write-Host ""
    Write-Host ""
}

# ==================== MAIN EXECUTION ====================

if ($script:IsWhatIf) {
    Write-Log "=== WHATIF MODE - NO CHANGES WILL BE MADE ===" "INFO"
}

Write-Log "=== Autopilot Computer Rename Script Started ==="
Write-Log "Current computer name: $env:COMPUTERNAME"

# Gather system info early for WhatIf mode
$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
$isDomainJoined = $computerSystem.PartOfDomain
$currentDomain = $computerSystem.Domain
$inESP = Test-AutopilotESP

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

# Show WhatIf summary and exit
if ($script:IsWhatIf) {
    Show-WhatIfSummary -CurrentName $env:COMPUTERNAME -ProposedName $NewComputerName `
        -DomainJoined $isDomainJoined -Domain $currentDomain `
        -InESP $inESP -PendingReboot $pendingReboot
    exit 0
}

# Check if rename is needed
if ($env:COMPUTERNAME -eq $NewComputerName) {
    Write-Log "Computer already has correct name. No action needed." "INFO"
    exit 0
}

# Validate we're in a good state to rename
Write-Log "Checking system state..."
Write-Log "Domain joined: $isDomainJoined | Current domain: $currentDomain"

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