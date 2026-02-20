#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Deploys network printer via Intune.

.DESCRIPTION
    Adds network printers by IP address or print server shared queue.
    Can set default printer and install specific drivers if needed.

.PARAMETER PrinterName
    Display name for the printer

.PARAMETER PrinterIP
    IP address of the printer (for TCP/IP printers)

.PARAMETER PrintServer
    Print server name (for shared printers)

.PARAMETER ShareName
    Shared printer name on print server

.PARAMETER PortName
    Custom port name (optional)

.PARAMETER DriverName
    Printer driver name (must be installed or available)

.PARAMETER MakeDefault
    Set as the default printer

.PARAMETER RemoveIfExists
    Remove and recreate if printer already exists

.PARAMETER LogPath
    Path for operation logs

.EXAMPLE
    .\Add-NetworkPrinter.ps1 -PrinterName "Floor3-HP" -PrinterIP "192.168.1.50" -DriverName "HP Universal PCL6"

.EXAMPLE
    .\Add-NetworkPrinter.ps1 -PrinterName "MainPrinter" -PrintServer "printserver.company.com" -ShareName "HP-LaserJet" -MakeDefault

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
    Requirements:   Windows 10/11, Administrator rights
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$PrinterName,

    [Parameter(Mandatory=$false)]
    [string]$PrinterIP = "",

    [Parameter(Mandatory=$false)]
    [string]$PrintServer = "",

    [Parameter(Mandatory=$false)]
    [string]$ShareName = "",

    [Parameter(Mandatory=$false)]
    [string]$PortName = "",

    [Parameter(Mandatory=$true)]
    [string]$DriverName,

    [Parameter(Mandatory=$false)]
    [switch]$MakeDefault,

    [Parameter(Mandatory=$false)]
    [switch]$RemoveIfExists,

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
)

$ScriptName = "NetworkPrinter"
$LogFile = "$LogPath\$ScriptName.log"

if (!(Test-Path -Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    try { Add-Content -Path $LogFile -Value $logEntry } catch {}
    Write-Host $logEntry -ForegroundColor $(switch($Level){"ERROR"{"Red"}"WARN"{"Yellow"}"SUCCESS"{"Green"}default{"White"}})
}

function Test-PrinterDriver {
    param([string]$Driver)
    $drivers = Get-PrinterDriver | Where-Object { $_.Name -like "*$Driver*" }
    return $null -ne $drivers
}

function Add-TCPPrinter {
    try {
        Write-Log "Adding TCP/IP printer: $PrinterName"
        
        # Generate port name if not provided
        $port = if ([string]::IsNullOrEmpty($PortName)) { "IP_$PrinterIP" } else { $PortName }
        
        # Remove existing port if needed
        $existingPort = Get-PrinterPort -Name $port -ErrorAction SilentlyContinue
        if ($existingPort) {
            Remove-PrinterPort -Name $port -ErrorAction SilentlyContinue
        }
        
        # Create TCP port
        Add-PrinterPort -Name $port -PrinterHostAddress $PrinterIP -PortNumber 9100 -ErrorAction Stop
        Write-Log "Created printer port: $port"
        
        # Remove existing printer if requested
        if ($RemoveIfExists) {
            $existing = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
            if ($existing) {
                Remove-Printer -Name $PrinterName -ErrorAction SilentlyContinue
                Write-Log "Removed existing printer"
            }
        }
        
        # Add printer
        Add-Printer -Name $PrinterName -PortName $port -DriverName $DriverName -ErrorAction Stop
        Write-Log "Printer added successfully" "SUCCESS"
        
        return $true
    }
    catch {
        Write-Log "Failed to add TCP printer: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Add-SharedPrinter {
    try {
        Write-Log "Adding shared printer: \\$PrintServer\$ShareName"
        
        $uncPath = "\\$PrintServer\$ShareName"
        
        # Remove existing if requested
        if ($RemoveIfExists) {
            $existing = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
            if ($existing) {
                Remove-Printer -Name $PrinterName -ErrorAction SilentlyContinue
            }
        }
        
        # Add printer using rundll32 (most reliable method)
        $result = rundll32 printui.dll,PrintUIEntry /ga /n$uncPath /q 2>&1
        Write-Log "Shared printer added" "SUCCESS"
        
        return $true
    }
    catch {
        Write-Log "Failed to add shared printer: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Set-DefaultPrinter {
    try {
        Write-Log "Setting $PrinterName as default"
        $printer = Get-Printer -Name $PrinterName -ErrorAction Stop
        $printer | Set-Printer -IsDefault $true
        Write-Log "Default printer set" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to set default: $($_.Exception.Message)" "WARN"
        return $false
    }
}

# Main
Write-Log "=== Network Printer Deployment Started ==="

# Validate parameters
if ([string]::IsNullOrEmpty($PrinterIP) -and [string]::IsNullOrEmpty($PrintServer)) {
    Write-Log "Either PrinterIP or PrintServer must be specified" "ERROR"
    exit 1
}

if (-not [string]::IsNullOrEmpty($PrintServer) -and [string]::IsNullOrEmpty($ShareName)) {
    Write-Log "ShareName is required when using PrintServer" "ERROR"
    exit 1
}

$success = $false

# Add printer based on type
if (-not [string]::IsNullOrEmpty($PrinterIP)) {
    $success = Add-TCPPrinter
} else {
    $success = Add-SharedPrinter
}

# Set default if requested
if ($success -and $MakeDefault) {
    Set-DefaultPrinter | Out-Null
}

if ($success) {
    Write-Log "=== Printer deployment completed ===" "SUCCESS"
    exit 0
} else {
    exit 1
}