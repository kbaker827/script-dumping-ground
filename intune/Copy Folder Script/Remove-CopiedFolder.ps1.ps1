#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Removes a copied folder and its contents.

.DESCRIPTION
    Removes a folder that was previously copied by the Copy-FolderWithConfig script.
    Can optionally restore from backup if one exists.

.PARAMETER TargetFolder
    Path to the folder to remove

.PARAMETER RestoreFromBackup
    Restore from .bak backup if available

.PARAMETER KeepRegistryEntry
    Keep the registry tracking entry

.PARAMETER LogPath
    Path for operation logs

.EXAMPLE
    .\Remove-CopiedFolder.ps1 -TargetFolder "C:\ProgramData\MyApp\Config"

.EXAMPLE
    .\Remove-CopiedFolder.ps1 -TargetFolder "C:\ProgramData\MyApp\Config" -RestoreFromBackup

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, HelpMessage="Target folder to remove")]
    [string]$TargetFolder,

    [Parameter(Mandatory=$false)]
    [switch]$RestoreFromBackup,

    [Parameter(Mandatory=$false)]
    [switch]$KeepRegistryEntry,

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
)

# Configuration
$ScriptName = "RemoveCopiedFolder"
$LogFile = "$LogPath\$ScriptName.log"
$RegistryPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\FolderCopy"

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

function Find-BackupFolder {
    param([string]$TargetPath)
    
    $parentDir = Split-Path -Path $TargetPath -Parent
    $folderName = Split-Path -Path $TargetPath -Leaf
    
    $backups = Get-ChildItem -Path $parentDir -Filter "$folderName.bak.*" -Directory | 
        Sort-Object Name -Descending
    
    if ($backups) {
        return $backups[0].FullName
    }
    
    return $null
}

function Remove-TargetFolder {
    param(
        [string]$Path,
        [bool]$ShouldRestore
    )
    
    try {
        if (!(Test-Path -Path $Path)) {
            Write-Log "Target folder does not exist: $Path" "WARN"
            return $true
        }
        
        # Find and restore from backup if requested
        if ($ShouldRestore) {
            $backupPath = Find-BackupFolder -TargetPath $Path
            
            if ($backupPath) {
                Write-Log "Found backup: $backupPath"
                
                # Remove current folder
                Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
                Write-Log "Removed current folder: $Path"
                
                # Restore from backup
                Rename-Item -Path $backupPath -NewName (Split-Path -Path $Path -Leaf) -ErrorAction Stop
                Write-Log "Restored from backup: $backupPath → $Path" "SUCCESS"
                return $true
            }
            else {
                Write-Log "No backup found to restore from" "WARN"
            }
        }
        
        # Just remove the folder
        Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
        Write-Log "Removed folder: $Path" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to remove folder: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Remove-RegistryEntry {
    param([string]$TargetPath)
    
    try {
        if (Test-Path $RegistryPath) {
            $existingTarget = Get-ItemProperty -Path $RegistryPath -Name "TargetFolder" -ErrorAction SilentlyContinue
            if ($existingTarget -and $existingTarget.TargetFolder -eq $TargetPath) {
                Remove-Item -Path $RegistryPath -Recurse -Force -ErrorAction Stop
                Write-Log "Registry entry removed" "SUCCESS"
            }
        }
    }
    catch {
        Write-Log "Failed to remove registry entry: $($_.Exception.Message)" "WARN"
    }
}

# ==================== MAIN EXECUTION ====================

Write-Log "=== Remove Copied Folder Script Started ==="

# Remove the folder
$removeSuccess = Remove-TargetFolder -Path $TargetFolder -ShouldRestore $RestoreFromBackup

# Clean up registry entry unless requested to keep
if (-not $KeepRegistryEntry) {
    Remove-RegistryEntry -TargetPath $TargetFolder
}

if ($removeSuccess) {
    Write-Log "=== Operation completed successfully ===" "SUCCESS"
    exit 0
}
else {
    Write-Log "=== Operation completed with errors ===" "ERROR"
    exit 1
}