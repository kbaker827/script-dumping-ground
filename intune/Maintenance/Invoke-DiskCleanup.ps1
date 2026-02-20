#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Performs system disk cleanup and maintenance.

.DESCRIPTION
    Cleans temporary files, empties recycle bin, runs Disk Cleanup tool,
    and optionally cleans Windows Update cache. Reports space saved.

.PARAMETER CleanWindowsUpdate
    Also clean Windows Update cache (requires reboot)

.PARAMETER CleanTempFiles
    Clean user and system temp files

.PARAMETER EmptyRecycleBin
    Empty recycle bin

.PARAMETER RunDiskCleanup
    Run Windows Disk Cleanup tool

.PARAMETER MaxLogAgeDays
    Delete log files older than X days (default: 30)

.PARAMETER ReportOnly
    Report what would be cleaned without deleting

.PARAMETER LogPath
    Path for operation logs

.EXAMPLE
    .\Invoke-DiskCleanup.ps1

.EXAMPLE
    .\Invoke-DiskCleanup.ps1 -CleanWindowsUpdate -CleanTempFiles -EmptyRecycleBin

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$CleanWindowsUpdate,

    [Parameter(Mandatory=$false)]
    [switch]$CleanTempFiles = $true,

    [Parameter(Mandatory=$false)]
    [switch]$EmptyRecycleBin = $true,

    [Parameter(Mandatory=$false)]
    [switch]$RunDiskCleanup = $true,

    [Parameter(Mandatory=$false)]
    [int]$MaxLogAgeDays = 30,

    [Parameter(Mandatory=$false)]
    [switch]$ReportOnly,

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
)

$ScriptName = "DiskCleanup"
$LogFile = "$LogPath\$ScriptName.log"
$SpaceSaved = 0

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

function Get-FolderSize {
    param([string]$Path)
    try {
        if (Test-Path $Path) {
            return (Get-ChildItem $Path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        }
        return 0
    }
    catch { return 0 }
}

function Remove-FilesWithReporting {
    param([string]$Path, [string]$Description)
    
    if (!(Test-Path $Path)) { return }
    
    $sizeBefore = Get-FolderSize -Path $Path
    
    if ($ReportOnly) {
        Write-Log "[REPORT] Would clean: $Description ($([math]::Round($sizeBefore / 1MB, 2)) MB)"
        $script:SpaceSaved += $sizeBefore
        return
    }
    
    try {
        Remove-Item -Path "$Path\*" -Recurse -Force -ErrorAction SilentlyContinue
        $sizeAfter = Get-FolderSize -Path $Path
        $freed = $sizeBefore - $sizeAfter
        $script:SpaceSaved += $freed
        Write-Log "Cleaned: $Description - Freed $([math]::Round($freed / 1MB, 2)) MB"
    }
    catch {
        Write-Log "Could not clean $Description`: $($_.Exception.Message)" "WARN"
    }
}

function Clear-TempFiles {
    try {
        Write-Log "Cleaning temporary files"
        
        # Windows Temp
        Remove-FilesWithReporting -Path "$env:SystemRoot\Temp" -Description "Windows Temp"
        
        # User Temps
        Get-ChildItem -Path "C:\Users" -Directory | ForEach-Object {
            $tempPath = Join-Path $_.FullName "AppData\Local\Temp"
            Remove-FilesWithReporting -Path $tempPath -Description "Temp for $($_.Name)"
        }
        
        # IIS Logs
        Remove-FilesWithReporting -Path "$env:SystemRoot\System32\LogFiles" -Description "IIS Logs"
        
        # Event Viewer logs older than threshold
        $limit = (Get-Date).AddDays(-$MaxLogAgeDays)
        Get-ChildItem "$env:SystemRoot\Logs" -File -ErrorAction SilentlyContinue | 
            Where-Object { $_.LastWriteTime -lt $limit } | 
            Remove-Item -Force -ErrorAction SilentlyContinue
        
        Write-Log "Temp files cleaned" "SUCCESS"
    }
    catch {
        Write-Log "Temp file cleanup error: $($_.Exception.Message)" "WARN"
    }
}

function Clear-RecycleBin {
    try {
        Write-Log "Emptying recycle bin"
        
        if ($ReportOnly) {
            $shell = New-Object -ComObject Shell.Application
            $recycleBin = $shell.Namespace(0xA)
            $size = 0
            foreach ($item in $recycleBin.Items()) {
                $size += $item.Size
            }
            Write-Log "[REPORT] Would empty Recycle Bin ($([math]::Round($size / 1MB, 2)) MB)"
            $script:SpaceSaved += $size
            return
        }
        
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Write-Log "Recycle bin emptied" "SUCCESS"
    }
    catch {
        Write-Log "Recycle bin error: $($_.Exception.Message)" "WARN"
    }
}

function Invoke-WindowsDiskCleanup {
    try {
        Write-Log "Running Windows Disk Cleanup"
        
        if ($ReportOnly) {
            Write-Log "[REPORT] Would run Windows Disk Cleanup"
            return
        }
        
        # Set registry values for sageset (automated cleanup)
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
        
        # Enable various cleanup options
        $items = @(
            "Temporary Files",
            "Internet Cache Files",
            "Recycle Bin",
            "Temporary Setup Files",
            "Downloaded Program Files",
            "System error memory dump files"
        )
        
        foreach ($item in $items) {
            $itemPath = Join-Path $regPath $item
            if (Test-Path $itemPath) {
                Set-ItemProperty -Path $itemPath -Name "StateFlags0001" -Value 2 -ErrorAction SilentlyContinue
            }
        }
        
        # Run cleanup
        Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:1" -Wait -WindowStyle Hidden
        
        Write-Log "Disk cleanup completed" "SUCCESS"
    }
    catch {
        Write-Log "Disk cleanup error: $($_.Exception.Message)" "WARN"
    }
}

function Clear-WindowsUpdateCache {
    try {
        Write-Log "Cleaning Windows Update cache"
        
        if ($ReportOnly) {
            $size = Get-FolderSize -Path "$env:SystemRoot\SoftwareDistribution\Download"
            Write-Log "[REPORT] Would clean Windows Update cache ($([math]::Round($size / 1MB, 2)) MB)"
            $script:SpaceSaved += $size
            return
        }
        
        # Stop Windows Update service
        Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
        
        # Clear download cache
        Remove-FilesWithReporting -Path "$env:SystemRoot\SoftwareDistribution\Download" -Description "Windows Update Cache"
        
        # Start service
        Start-Service wuauserv -ErrorAction SilentlyContinue
        
        Write-Log "Windows Update cache cleaned" "SUCCESS"
    }
    catch {
        Write-Log "WU cache error: $($_.Exception.Message)" "WARN"
    }
}

# Main
Write-Log "=== Disk Cleanup Started ==="
Write-Log "Mode: $(if($ReportOnly){'Report Only'}else{'Cleanup'})"

if ($CleanTempFiles) { Clear-TempFiles }
if ($EmptyRecycleBin) { Clear-RecycleBin }
if ($RunDiskCleanup) { Invoke-WindowsDiskCleanup }
if ($CleanWindowsUpdate) { Clear-WindowsUpdateCache }

$mbSaved = [math]::Round($SpaceSaved / 1MB, 2)
$gbSaved = [math]::Round($SpaceSaved / 1GB, 2)

Write-Log "=== Cleanup Completed ===" "SUCCESS"
Write-Log "Total space $(if($ReportOnly){'to free'}else{'freed'}): $mbSaved MB ($gbSaved GB)"

# Return space saved for Intune reporting
$gbSaved