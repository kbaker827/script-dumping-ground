#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Copies a source folder with config files to a target directory.

.DESCRIPTION
    Copies a folder containing configuration files from a source location
    to a target directory on the computer. Designed for Intune deployment
    of configuration files, templates, or resources.

.PARAMETER SourceFolder
    Path to the source folder to copy (can be UNC path, local path, or relative)

.PARAMETER TargetFolder
    Path where the folder should be copied to

.PARAMETER Overwrite
    Overwrite existing files in target (default: true)

.PARAMETER CreateBackup
    Create .bak backup of existing files before overwriting

.PARAMETER CleanTarget
    Remove existing target folder before copying (use with caution)

.PARAMETER IncludeFilter
    File pattern to include (e.g., "*.xml", "config*")

.PARAMETER ExcludeFilter
    File pattern to exclude (e.g., "*.tmp", "*.log")

.PARAMETER LogPath
    Path for operation logs

.PARAMETER ValidateHash
    Validate file integrity using SHA256 hashes

.EXAMPLE
    .\Copy-FolderWithConfig.ps1 -SourceFolder "C:\Source\Config" -TargetFolder "C:\ProgramData\MyApp\Config"

.EXAMPLE
    .\Copy-FolderWithConfig.ps1 -SourceFolder "\\server\share\config" -TargetFolder "C:\AppData" -CreateBackup

.EXAMPLE
    .\Copy-FolderWithConfig.ps1 -SourceFolder ".\Configs" -TargetFolder "$env:ProgramData\Company" -IncludeFilter "*.xml"

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
    Requirements:   Windows 10/11, Administrator rights (for system folders)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, HelpMessage="Source folder path")]
    [string]$SourceFolder,

    [Parameter(Mandatory=$true, HelpMessage="Target folder path")]
    [string]$TargetFolder,

    [Parameter(Mandatory=$false)]
    [switch]$Overwrite = $true,

    [Parameter(Mandatory=$false)]
    [switch]$CreateBackup,

    [Parameter(Mandatory=$false)]
    [switch]$CleanTarget,

    [Parameter(Mandatory=$false)]
    [string]$IncludeFilter = "*",

    [Parameter(Mandatory=$false)]
    [string[]]$ExcludeFilter = @("*.tmp", "*.log", "~$*"),

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs",

    [Parameter(Mandatory=$false)]
    [switch]$ValidateHash
)

# Configuration
$ScriptName = "CopyFolderConfig"
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

function Test-SourceFolder {
    param([string]$Path)
    
    # Resolve relative paths
    $resolvedPath = Resolve-Path -Path $Path -ErrorAction SilentlyContinue
    if (-not $resolvedPath) {
        $resolvedPath = $Path
    }
    
    if (!(Test-Path -Path $resolvedPath)) {
        Write-Log "Source folder not found: $resolvedPath" "ERROR"
        return $null
    }
    
    $item = Get-Item -Path $resolvedPath
    if (-not $item.PSIsContainer) {
        Write-Log "Source path is not a folder: $resolvedPath" "ERROR"
        return $null
    }
    
    Write-Log "Source folder validated: $resolvedPath" "SUCCESS"
    return $resolvedPath
}

function Backup-ExistingFiles {
    param([string]$TargetPath)
    
    if (!(Test-Path -Path $TargetPath)) {
        return
    }
    
    Write-Log "Creating backup of existing target folder..."
    $backupPath = "$TargetPath.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    try {
        Copy-Item -Path $TargetPath -Destination $backupPath -Recurse -Force -ErrorAction Stop
        Write-Log "Backup created at: $backupPath" "SUCCESS"
    }
    catch {
        Write-Log "Failed to create backup: $($_.Exception.Message)" "ERROR"
    }
}

function Copy-ConfigFolder {
    param(
        [string]$Source,
        [string]$Target,
        [string]$Include,
        [string[]]$Exclude,
        [bool]$ShouldOverwrite,
        [bool]$ShouldCleanTarget
    )
    
    try {
        # Clean target if requested
        if ($ShouldCleanTarget -and (Test-Path -Path $Target)) {
            Write-Log "Cleaning target folder: $Target"
            Remove-Item -Path $Target -Recurse -Force -ErrorAction Stop
            Write-Log "Target folder removed" "SUCCESS"
        }
        
        # Create target folder if it doesn't exist
        if (!(Test-Path -Path $Target)) {
            Write-Log "Creating target folder: $Target"
            New-Item -Path $Target -ItemType Directory -Force | Out-Null
            Write-Log "Target folder created" "SUCCESS"
        }
        
        # Get files to copy
        $files = Get-ChildItem -Path $Source -Recurse -File -Filter $Include | Where-Object {
            $file = $_
            $shouldInclude = $true
            foreach ($pattern in $Exclude) {
                if ($file.Name -like $pattern) {
                    $shouldInclude = $false
                    break
                }
            }
            $shouldInclude
        }
        
        Write-Log "Found $($files.Count) files to copy"
        
        $copiedCount = 0
        $skippedCount = 0
        $errorCount = 0
        
        foreach ($file in $files) {
            # Calculate relative path
            $relativePath = $file.FullName.Substring($Source.Length).TrimStart('\', '/')
            $targetFilePath = Join-Path -Path $Target -ChildPath $relativePath
            $targetFileDir = Split-Path -Path $targetFilePath -Parent
            
            # Create subdirectory structure
            if (!(Test-Path -Path $targetFileDir)) {
                New-Item -Path $targetFileDir -ItemType Directory -Force | Out-Null
            }
            
            # Check if file exists
            $shouldCopy = $true
            if (Test-Path -Path $targetFilePath) {
                if (-not $ShouldOverwrite) {
                    Write-Log "Skipping existing file: $relativePath"
                    $skippedCount++
                    continue
                }
                
                # Validate hash if requested
                if ($ValidateHash) {
                    $sourceHash = Get-FileHash -Path $file.FullName -Algorithm SHA256
                    $targetHash = Get-FileHash -Path $targetFilePath -Algorithm SHA256
                    
                    if ($sourceHash.Hash -eq $targetHash.Hash) {
                        Write-Log "File unchanged (hash match): $relativePath"
                        $skippedCount++
                        continue
                    }
                }
            }
            
            # Copy the file
            try {
                Copy-Item -Path $file.FullName -Destination $targetFilePath -Force -ErrorAction Stop
                $copiedCount++
                Write-Log "Copied: $relativePath"
            }
            catch {
                $errorCount++
                Write-Log "Failed to copy $relativePath : $($_.Exception.Message)" "ERROR"
            }
        }
        
        Write-Log "Copy operation completed: $copiedCount copied, $skippedCount skipped, $errorCount errors" "SUCCESS"
        return ($errorCount -eq 0)
    }
    catch {
        Write-Log "Copy operation failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Register-CopyOperation {
    param(
        [string]$Source,
        [string]$Target,
        [bool]$Success
    )
    
    try {
        if (!(Test-Path $RegistryPath)) {
            New-Item -Path $RegistryPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $RegistryPath -Name "SourceFolder" -Value $Source
        Set-ItemProperty -Path $RegistryPath -Name "TargetFolder" -Value $Target
        Set-ItemProperty -Path $RegistryPath -Name "LastCopyDate" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Set-ItemProperty -Path $RegistryPath -Name "Success" -Value ([string]$Success)
        
        Write-Log "Operation registered in registry" "SUCCESS"
    }
    catch {
        Write-Log "Failed to register operation: $($_.Exception.Message)" "WARN"
    }
}

# ==================== MAIN EXECUTION ====================

Write-Log "=== Folder Copy Script Started ==="
Write-Log "Script version: 1.0"

# Validate source folder
$validatedSource = Test-SourceFolder -Path $SourceFolder
if (-not $validatedSource) {
    exit 1
}

# Create backup if requested
if ($CreateBackup -and (Test-Path -Path $TargetFolder)) {
    Backup-ExistingFiles -TargetPath $TargetFolder
}

# Perform copy
$copySuccess = Copy-ConfigFolder -Source $validatedSource -Target $TargetFolder `
    -Include $IncludeFilter -Exclude $ExcludeFilter `
    -ShouldOverwrite $Overwrite -ShouldCleanTarget $CleanTarget

# Register completion
Register-CopyOperation -Source $validatedSource -Target $TargetFolder -Success $copySuccess

if ($copySuccess) {
    Write-Log "=== Folder copy completed successfully ===" "SUCCESS"
    Write-Log "Source: $validatedSource"
    Write-Log "Target: $TargetFolder"
    exit 0
}
else {
    Write-Log "=== Folder copy completed with errors ===" "ERROR"
    exit 1
}