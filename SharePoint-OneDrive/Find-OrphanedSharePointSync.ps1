<#
.SYNOPSIS
    Scans for orphaned SharePoint/OneDrive sync folders no longer linked to active OneDrive accounts.

.DESCRIPTION
    Identifies local folders that appear to be former SharePoint or OneDrive sync libraries
    that are no longer associated with any active OneDrive account. Helps clean up after:
    - User account changes or deletions
    - OneDrive reconfigurations
    - SharePoint library unlinks or site deletions
    - Tenant migrations
    
    The script generates a detailed CSV report with recommendations and can optionally
    move orphaned folders to an archive location or generate deletion scripts.

.PARAMETER ExtraPaths
    Additional paths to scan beyond the default locations.

.PARAMETER OutputFolder
    Folder where the CSV report will be saved. Defaults to Documents.

.PARAMETER ArchiveFolder
    Move potentially orphaned folders to this archive location instead of flagging for review.

.PARAMETER GenerateDeletionScript
    Create a PowerShell script to delete confirmed orphaned folders.

.PARAMETER MinFolderSizeMB
    Minimum folder size in MB to include in scan. Default: 1 MB.

.PARAMETER MaxDepth
    Maximum directory depth to scan. Default: 3 levels.

.PARAMETER Force
    Skip confirmation prompts.

.PARAMETER WhatIf
    Show what would be done without making changes (when using -ArchiveFolder).

.EXAMPLE
    .\Find-OrphanedSharePointSync.ps1
    Scans default locations and generates a CSV report.

.EXAMPLE
    .\Find-OrphanedSharePointSync.ps1 -ExtraPaths "D:\SharedDocs", "E:\Archive"
    Scans default locations plus specified additional paths.

.EXAMPLE
    .\Find-OrphanedSharePointSync.ps1 -ArchiveFolder "D:\OneDrive-Archive" -WhatIf
    Shows what folders would be archived without moving them.

.EXAMPLE
    .\Find-OrphanedSharePointSync.ps1 -GenerateDeletionScript -OutputFolder "C:\Reports"
    Generates a deletion script for confirmed orphaned folders.

.EXAMPLE
    .\Find-OrphanedSharePointSync.ps1 -MinFolderSizeMB 100 -MaxDepth 2
    Only report folders larger than 100 MB, scan 2 levels deep.

.NOTES
    Version:        3.0
    Author:         IT Admin
    Updated:        2026-02-12
    
    Requires:       Windows 10/11 with OneDrive
    Privileges:     User context (no admin required for most operations)
    
    Exit Codes:
    0   - Success, no orphaned folders found
    1   - Orphaned folders found (review required)
    2   - Error during scan
    3   - User cancelled operation
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(HelpMessage="Additional paths to scan")]
    [string[]]$ExtraPaths = @(),
    
    [Parameter(HelpMessage="Output folder for reports")]
    [string]$OutputFolder = [Environment]::GetFolderPath('MyDocuments'),
    
    [Parameter(HelpMessage="Archive orphaned folders to this location")]
    [string]$ArchiveFolder = "",
    
    [Parameter(HelpMessage="Generate deletion script")]
    [switch]$GenerateDeletionScript,
    
    [Parameter(HelpMessage="Minimum folder size in MB to include")]
    [ValidateRange(0, [int]::MaxValue)]
    [int]$MinFolderSizeMB = 1,
    
    [Parameter(HelpMessage="Maximum directory depth to scan")]
    [ValidateRange(1, 10)]
    [int]$MaxDepth = 3,
    
    [Parameter(HelpMessage="Skip confirmation prompts")]
    [switch]$Force,
    
    [Parameter(HelpMessage="Preview mode")]
    [switch]$WhatIf
)

#region Configuration
$ErrorActionPreference = 'SilentlyContinue'
$script:Version = "3.0"
$script:OrphanedFolders = [System.Collections.Generic.List[object]]::new()

# Known system folders to skip
$script:SkipFolders = @(
    'AppData', '$Recycle.Bin', 'Windows', 'Program Files', 'Program Files (x86)',
    'ProgramData', 'Temp', 'Tmp', 'inetpub', 'PerfLogs', 'Recovery', 'System Volume Information',
    'Config.Msi', 'MSOCache', '$WINDOWS.~BT', '$WinREAgent', 'Documents and Settings'
)

# Regex patterns for SharePoint/OneDrive naming conventions
$script:SharePointPatterns = @(
    'Documents?\s*-\s*\w+',           # "Documents - Company"
    '.*\s+-\s+SharePoint',            # anything ending in " - SharePoint"
    'SharePoint\s+-\s+.*',             # anything starting with "SharePoint - "
    '.*\s+-\s+.*\s+\d{4}',             # "Name - Something 2023"
    '^Site\s*-\s*\w+',                 # "Site - Name"
    '.*Library.*',                     # anything with "Library"
    'OneDrive\s+-\s*.*',               # "OneDrive - Company"
    'Synced\s+.*',                     # "Synced Something"
    'Archive\s+-\s*.*',                # "Archive - Something"
    '.*\s+\(\d+\)$'                    # folders ending in " (1)", " (2)" etc.
)

# File patterns indicating cloud sync
$script:CloudFilePatterns = @(
    '*.odt', '*.odg', '*.odm', '*.tmp'  # OneDrive temp files
)
#endregion

#region Helper Functions
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Detail')]
        [string]$Level = 'Info'
    )
    
    $colors = @{
        Info = 'Cyan'
        Success = 'Green'
        Warning = 'Yellow'
        Error = 'Red'
        Detail = 'Gray'
    }
    
    $prefix = switch ($Level) {
        'Info'    { '[*]' }
        'Success' { '[+]' }
        'Warning' { '[!]' }
        'Error'   { '[-]' }
        'Detail'  { '   ' }
    }
    
    Write-Host "$prefix $Message" -ForegroundColor $colors[$Level]
}

function Show-Header {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Orphaned SharePoint Sync Scanner v$Version" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Log "Computer: $env:COMPUTERNAME" -Level Detail
    Write-Log "User: $env:USERNAME" -Level Detail
    Write-Log "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level Detail
    Write-Host ""
}

function Get-OneDriveMountPoints {
    <#
    .SYNOPSIS
    Retrieves all active OneDrive mount points from the registry and current session.
    #>
    $mounts = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    
    # Method 1: Registry (OneDrive settings)
    $regPaths = @(
        'HKCU:\Software\Microsoft\OneDrive\Accounts',
        'HKCU:\Software\Microsoft\OneDrive\Accounts\Business1',
        'HKCU:\Software\Microsoft\OneDrive\Accounts\Personal'
    )
    
    $propertiesToCheck = @(
        'UserFolder', 'MountPoint', 'MountPointPath', 'LibraryFolder',
        'LibraryRoot', 'SharePointMountPoint', 'SyncedFolderPath'
    )
    
    foreach ($regRoot in $regPaths) {
        if (Test-Path $regRoot) {
            Get-ChildItem $regRoot -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $props = Get-ItemProperty $_.PSPath -ErrorAction Stop
                    
                    foreach ($prop in $propertiesToCheck) {
                        $value = $props.$prop
                        if ($value -and (Test-Path $value -ErrorAction SilentlyContinue)) {
                            $resolved = (Resolve-Path $value -ErrorAction SilentlyContinue).Path
                            if ($resolved) {
                                [void]$mounts.Add($resolved.TrimEnd('\'))
                            }
                        }
                    }
                    
                    # Check all string properties for paths
                    foreach ($propName in $props.PSObject.Properties.Name) {
                        $value = $props.$propName
                        if ($value -is [string] -and $value -match '^[A-Za-z]:\\') {
                            if (Test-Path $value -ErrorAction SilentlyContinue) {
                                $resolved = (Resolve-Path $value -ErrorAction SilentlyContinue).Path
                                if ($resolved) {
                                    [void]$mounts.Add($resolved.TrimEnd('\'))
                                }
                            }
                        }
                    }
                }
                catch {
                    # Ignore registry read errors
                }
            }
        }
    }
    
    # Method 2: Environment variables
    $envPaths = @(
        $env:OneDrive,
        $env:OneDriveCommercial,
        $env:OneDriveConsumer
    )
    
    foreach ($path in $envPaths) {
        if ($path -and (Test-Path $path -ErrorAction SilentlyContinue)) {
            $resolved = (Resolve-Path $path -ErrorAction SilentlyContinue).Path
            if ($resolved) {
                [void]$mounts.Add($resolved.TrimEnd('\'))
            }
        }
    }
    
    # Method 3: Process command lines
    Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)" -ErrorAction SilentlyContinue).CommandLine
            if ($cmdLine) {
                # Extract /client= or similar paths
                if ($cmdLine -match '\/client[=:]"?([^"]+)') {
                    $clientPath = $matches[1] -replace '\\\\', '\'
                    if (Test-Path $clientPath -ErrorAction SilentlyContinue) {
                        [void]$mounts.Add($clientPath.TrimEnd('\'))
                    }
                }
            }
        }
        catch {
            # Ignore
        }
    }
    
    return $mounts
}

function Test-IsOneDriveFolder {
    <#
    .SYNOPSIS
    Checks if a folder has OneDrive-related indicators.
    #>
    param([string]$Path)
    
    $indicators = @{
        HasDesktopIni = $false
        HasOneDriveIcon = $false
        HasCloudFiles = $false
        HasSyncFile = $false
        HasOneDriveFiles = $false
    }
    
    try {
        # Check for desktop.ini with OneDrive references
        $iniPath = Join-Path $Path 'desktop.ini'
        if (Test-Path $iniPath -PathType Leaf) {
            $indicators.HasDesktopIni = $true
            $content = Get-Content -LiteralPath $iniPath -ErrorAction Stop -Raw
            $indicators.HasOneDriveIcon = $content -match 'OneDrive|SharePoint|IconFile.*\.ico'
        }
        
        # Check for OneDrive temp/sync files
        foreach ($pattern in $script:CloudFilePatterns) {
            if (Get-ChildItem -LiteralPath $Path -Filter $pattern -File -ErrorAction SilentlyContinue | Select-Object -First 1) {
                $indicators.HasCloudFiles = $true
                break
            }
        }
        
        # Check for .one or .odt files
        if (Get-ChildItem -LiteralPath $Path -Filter '*.one' -ErrorAction SilentlyContinue | Select-Object -First 1) {
            $indicators.HasOneDriveFiles = $true
        }
        
        # Check for OneDrive sync conflict files
        if (Get-ChildItem -LiteralPath $Path -Filter "* - Copy (*).*" -ErrorAction SilentlyContinue | Select-Object -First 1) {
            $indicators.HasSyncFile = $true
        }
    }
    catch {
        # Ignore errors
    }
    
    return $indicators
}

function Get-FolderSizeInfo {
    <#
    .SYNOPSIS
    Calculates folder size with detailed breakdown.
    #>
    param([string]$Path)
    
    try {
        $files = Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue
        $totalSize = ($files | Measure-Object -Property Length -Sum).Sum
        $fileCount = $files.Count
        $cloudFiles = ($files | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint }).Count
        $localFiles = $fileCount - $cloudFiles
        
        return [PSCustomObject]@{
            SizeBytes = $totalSize
            SizeGB = [math]::Round($totalSize / 1GB, 3)
            SizeMB = [math]::Round($totalSize / 1MB, 2)
            FileCount = $fileCount
            CloudFiles = $cloudFiles
            LocalFiles = $localFiles
        }
    }
    catch {
        return [PSCustomObject]@{
            SizeBytes = 0
            SizeGB = 0
            SizeMB = 0
            FileCount = 0
            CloudFiles = 0
            LocalFiles = 0
        }
    }
}

function Test-LooksLikeSharePoint {
    <#
    .SYNOPSIS
    Checks if folder name matches SharePoint/OneDrive naming patterns.
    #>
    param([string]$FolderName)
    
    foreach ($pattern in $script:SharePointPatterns) {
        if ($FolderName -match $pattern) {
            return $true
        }
    }
    
    # Check for common SharePoint library names
    $commonNames = @(
        'Documents', 'Shared Documents', 'Shared', 'Site Assets',
        'Site Pages', 'Form Templates', 'Style Library'
    )
    
    if ($commonNames -contains $FolderName) {
        return $true
    }
    
    return $false
}

function Get-SubdirectoriesRecursive {
    <#
    .SYNOPSIS
    Gets subdirectories up to a specified depth.
    #>
    param(
        [string]$Path,
        [int]$CurrentDepth = 0,
        [int]$MaxDepth = 3
    )
    
    if ($CurrentDepth -ge $MaxDepth) {
        return @()
    }
    
    $results = [System.Collections.Generic.List[System.IO.DirectoryInfo]]::new()
    
    try {
        $children = Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin $script:SkipFolders -and -not $_.Name.StartsWith('.') }
        
        $results.AddRange($children)
        
        foreach ($child in $children) {
            $grandchildren = Get-SubdirectoriesRecursive -Path $child.FullName -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth
            $results.AddRange($grandchildren)
        }
    }
    catch {
        # Ignore access denied errors
    }
    
    return $results
}

function Find-CandidateFolders {
    <#
    .SYNOPSIS
    Finds folders that may be orphaned SharePoint/OneDrive sync roots.
    #>
    param([string[]]$ScanRoots)
    
    $candidates = [System.Collections.Generic.List[System.IO.DirectoryInfo]]::new()
    $scanned = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    
    foreach ($root in $ScanRoots) {
        if (-not (Test-Path $root)) {
            Write-Log "Skipping inaccessible path: $root" -Level Warning
            continue
        }
        
        $resolvedRoot = (Resolve-Path $root -ErrorAction SilentlyContinue).Path
        if (-not $resolvedRoot -or $scanned.Contains($resolvedRoot)) {
            continue
        }
        
        [void]$scanned.Add($resolvedRoot)
        Write-Log "Scanning: $resolvedRoot" -Level Detail
        
        # Get subdirectories
        $directories = Get-SubdirectoriesRecursive -Path $resolvedRoot -MaxDepth $MaxDepth
        
        foreach ($dir in $directories) {
            # Skip system folders
            if ($dir.Name -in $script:SkipFolders) { continue }
            
            # Check if it looks like a SharePoint/OneDrive folder
            $looksLikeSP = Test-LooksLikeSharePoint -FolderName $dir.Name
            $oneDriveIndicators = Test-IsOneDriveFolder -Path $dir.FullName
            
            # Determine if it's a candidate
            $isCandidate = $false
            $reason = @()
            
            if ($looksLikeSP) {
                $isCandidate = $true
                $reason += "Naming pattern match"
            }
            
            if ($oneDriveIndicators.HasOneDriveIcon) {
                $isCandidate = $true
                $reason += "OneDrive desktop.ini"
            }
            
            if ($oneDriveIndicators.HasCloudFiles -or $oneDriveIndicators.HasSyncFile) {
                $isCandidate = $true
                $reason += "Cloud sync files present"
            }
            
            if ($oneDriveIndicators.HasOneDriveFiles) {
                $isCandidate = $true
                $reason += "OneDrive-specific files"
            }
            
            if ($isCandidate) {
                $dir | Add-Member -NotePropertyName 'DetectReason' -NotePropertyValue ($reason -join '; ') -Force
                $candidates.Add($dir)
            }
        }
    }
    
    return $candidates | Sort-Object FullName -Unique
}

function Get-FolderStatus {
    <#
    .SYNOPSIS
    Determines the status and recommendation for a folder.
    #>
    param(
        [System.IO.DirectoryInfo]$Directory,
        [System.Collections.Generic.HashSet[string]]$ActiveMounts
    )
    
    $fullPath = $Directory.FullName.TrimEnd('\')
    $oneDriveIndicators = Test-IsOneDriveFolder -Path $fullPath
    $sizeInfo = Get-FolderSizeInfo -Path $fullPath
    
    # Check if inside active OneDrive
    $isInsideActive = $false
    $activeMountParent = $null
    
    foreach ($mount in $ActiveMounts) {
        if ($fullPath -like "$mount*") {
            $isInsideActive = $true
            $activeMountParent = $mount
            break
        }
    }
    
    # Determine status and recommendation
    if ($isInsideActive) {
        $status = 'Active'
        $confidence = 'High'
        $recommendation = 'Keep - Part of active OneDrive sync'
        $riskLevel = 'None'
    }
    elseif ($oneDriveIndicators.HasOneDriveIcon -and $oneDriveIndicators.HasCloudFiles) {
        $status = 'Likely Orphaned'
        $confidence = 'High'
        $recommendation = 'Review - Strong indicators of orphaned sync folder'
        $riskLevel = 'Medium'
    }
    elseif ($oneDriveIndicators.HasOneDriveIcon -or $oneDriveIndicators.HasSyncFile) {
        $status = 'Possibly Orphaned'
        $confidence = 'Medium'
        $recommendation = 'Review - Some indicators present, verify before action'
        $riskLevel = 'Low'
    }
    else {
        $status = 'Unknown'
        $confidence = 'Low'
        $recommendation = 'Manual Review - Inspect folder contents'
        $riskLevel = 'Unknown'
    }
    
    return [PSCustomObject]@{
        Name = $Directory.Name
        FullPath = $fullPath
        ParentPath = $Directory.Parent.FullName
        Status = $status
        Confidence = $confidence
        RiskLevel = $riskLevel
        InsideActiveOneDrive = $isInsideActive
        ActiveMountParent = $activeMountParent
        HasDesktopIni = $oneDriveIndicators.HasDesktopIni
        HasOneDriveIcon = $oneDriveIndicators.HasOneDriveIcon
        HasCloudFiles = $oneDriveIndicators.HasCloudFiles
        HasSyncFiles = $oneDriveIndicators.HasSyncFile
        HasOneDriveFiles = $oneDriveIndicators.HasOneDriveFiles
        DetectionReason = $Directory.DetectReason
        Created = $Directory.CreationTime
        Modified = $Directory.LastWriteTime
        SizeGB = $sizeInfo.SizeGB
        SizeMB = $sizeInfo.SizeMB
        FileCount = $sizeInfo.FileCount
        CloudFiles = $sizeInfo.CloudFiles
        LocalFiles = $sizeInfo.LocalFiles
        Recommendation = $recommendation
    }
}

function Move-FolderToArchive {
    <#
    .SYNOPSIS
    Moves orphaned folders to archive location.
    #>
    param(
        [array]$Folders,
        [string]$ArchivePath
    )
    
    if (-not (Test-Path $ArchivePath)) {
        try {
            New-Item -ItemType Directory -Path $ArchivePath -Force | Out-Null
            Write-Log "Created archive folder: $ArchivePath" -Level Success
        }
        catch {
            Write-Log "Failed to create archive folder: $($_.Exception.Message)" -Level Error
            return
        }
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $archiveSubfolder = Join-Path $ArchivePath "OneDriveArchive_$timestamp"
    New-Item -ItemType Directory -Path $archiveSubfolder -Force | Out-Null
    
    foreach ($folder in $Folders) {
        $destination = Join-Path $archiveSubfolder $folder.Name
        
        if ($PSCmdlet.ShouldProcess($folder.FullPath, "Move to archive")) {
            try {
                Move-Item -LiteralPath $folder.FullPath -Destination $destination -Force
                Write-Log "Archived: $($folder.Name)" -Level Success
            }
            catch {
                Write-Log "Failed to archive $($folder.Name): $($_.Exception.Message)" -Level Error
            }
        }
    }
}

function Export-DeletionScript {
    <#
    .SYNOPSIS
    Generates a PowerShell script to delete confirmed orphaned folders.
    #>
    param(
        [array]$Folders,
        [string]$ExportPath
    )
    
    $scriptContent = @"
# Generated Orphaned SharePoint/OneDrive Folder Deletion Script
# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Computer: $env:COMPUTERNAME
# User: $env:USERNAME
# WARNING: Review carefully before running!

`$foldersToDelete = @(
"@

    foreach ($folder in $Folders) {
        $escapedPath = $folder.FullPath -replace '"', '`""'
        $scriptContent += "    # $($folder.Name) - Size: $($folder.SizeGB) GB - $([string]::IsNullOrEmpty($folder.DetectionReason) ? 'N/A' : $folder.DetectionReason)`n"
        $scriptContent += "    # Recommendation: $($folder.Recommendation)`n"
        $scriptContent += "    `"$escapedPath`"`n"
    }

    $scriptContent += @"
)

Write-Host "This script will delete the following folders:" -ForegroundColor Yellow
foreach (`$path in `$foldersToDelete) {
    Write-Host "  - `$path" -ForegroundColor Red
}

`$confirm = Read-Host "`nType 'DELETE' to confirm deletion"
if (`$confirm -eq 'DELETE') {
    foreach (`$path in `$foldersToDelete) {
        try {
            Remove-Item -LiteralPath `$path -Recurse -Force
            Write-Host "Deleted: `$path" -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to delete `$path : `$(`$_.Exception.Message)" -ForegroundColor Red
        }
    }
}
else {
    Write-Host "Deletion cancelled." -ForegroundColor Yellow
}
"@

    $scriptContent | Set-Content -Path $ExportPath -Encoding UTF8
    Write-Log "Deletion script saved to: $ExportPath" -Level Success
}
#endregion

#region Main Execution
Show-Header

# Validate output folder
if (-not (Test-Path $OutputFolder)) {
    try {
        New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    }
    catch {
        Write-Log "Failed to create output folder: $OutputFolder" -Level Error
        exit 2
    }
}

# Gather active OneDrive mount points
Write-Log "Discovering active OneDrive mount points..." -Level Info
$activeMounts = Get-OneDriveMountPoints
Write-Log "Found $($activeMounts.Count) active OneDrive location(s)" -Level Success

foreach ($mount in $activeMounts) {
    Write-Log "  Active: $mount" -Level Detail
}

# Build scan roots
$defaultRoots = @($env:UserProfile)

# Add common OneDrive parent paths
$oneDriveParent = Split-Path $env:UserProfile -Parent
if ($oneDriveParent -and (Test-Path $oneDriveParent)) {
    # Look for OneDrive folders in parent of user profile
    $oneDriveFolders = Get-ChildItem -Path $oneDriveParent -Directory -Filter "*OneDrive*" -ErrorAction SilentlyContinue
    $defaultRoots += $oneDriveFolders.FullName | Where-Object { $_ }
}

# Merge all scan roots
$scanRoots = ($defaultRoots + $activeMounts + $ExtraPaths) | 
    Where-Object { $_ -and (Test-Path $_) } | 
    Sort-Object -Unique

Write-Host ""
Write-Log "Scan paths:" -Level Info
$scanRoots | ForEach-Object { Write-Log "  $_" -Level Detail }

Write-Host ""
Write-Log "Scanning for candidate folders (depth: $MaxDepth, min size: ${MinFolderSizeMB}MB)..." -Level Info

# Find candidates
$candidates = Find-CandidateFolders -ScanRoots $scanRoots

# Filter by size
$candidates = $candidates | Where-Object {
    $size = (Get-FolderSizeInfo -Path $_.FullName).SizeMB
    $size -ge $MinFolderSizeMB
}

Write-Log "Found $($candidates.Count) candidate folder(s) meeting criteria" -Level Success
Write-Host ""

if ($candidates.Count -eq 0) {
    Write-Log "No orphaned SharePoint/OneDrive sync folders detected." -Level Success
    Write-Host ""
    Write-Log "Scan complete. No action required." -Level Success
    exit 0
}

# Analyze folders
Write-Log "Analyzing folders..." -Level Info
$results = foreach ($candidate in $candidates) {
    Get-FolderStatus -Directory $candidate -ActiveMounts $activeMounts
}

# Display results
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SCAN RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$orphaned = $results | Where-Object { -not $_.InsideActiveOneDrive }
$active = $results | Where-Object { $_.InsideActiveOneDrive }

if ($active) {
    Write-Host "Active OneDrive Folders (Safe):" -ForegroundColor Green
    $active | Format-Table Name, SizeGB, InsideActiveOneDrive -AutoSize
}

if ($orphaned) {
    Write-Host "Potentially Orphaned Folders (Review Required):" -ForegroundColor Yellow
    $orphaned | Sort-Object Confidence -Descending | 
        Select-Object Name, Status, Confidence, SizeGB, FileCount, Recommendation |
        Format-Table -AutoSize
    
    $script:OrphanedFolders.AddRange($orphaned)
}

# Export to CSV
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$csvPath = Join-Path $OutputFolder "OrphanedSharePointScan_$timestamp.csv"

try {
    $results | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csvPath
    Write-Log "Detailed report saved to: $csvPath" -Level Success
}
catch {
    Write-Log "Failed to save CSV report: $($_.Exception.Message)" -Level Error
}

# Handle archive if specified
if ($ArchiveFolder -and $orphaned) {
    Write-Host ""
    $highConfidence = $orphaned | Where-Object { $_.Confidence -eq 'High' }
    
    if ($highConfidence) {
        Write-Log "Found $($highConfidence.Count) high-confidence orphaned folders" -Level Warning
        
        if ($Force -or (-not $WhatIf)) {
            $confirm = Read-Host "Move $($highConfidence.Count) folders to archive? (Y/N)"
            if ($confirm -eq 'Y') {
                Move-FolderToArchive -Folders $highConfidence -ArchivePath $ArchiveFolder
            }
        }
        elseif ($WhatIf) {
            Write-Log "WHATIF: Would archive $($highConfidence.Count) folders to: $ArchiveFolder" -Level Warning
            $highConfidence | ForEach-Object { Write-Log "  - $($_.Name) ($($_.SizeGB) GB)" -Level Detail }
        }
    }
}

# Generate deletion script if requested
if ($GenerateDeletionScript -and $orphaned) {
    $scriptPath = Join-Path $OutputFolder "DeleteOrphanedFolders_$timestamp.ps1"
    Export-DeletionScript -Folders $orphaned -ExportPath $scriptPath
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$totalOrphaned = ($orphaned | Measure-Object).Count
$totalSize = ($orphaned | Measure-Object -Property SizeGB -Sum).Sum

Write-Log "Total candidates found: $($candidates.Count)" -Level Info
Write-Log "Active OneDrive folders: $(($active | Measure-Object).Count)" -Level Success
Write-Log "Potentially orphaned folders: $totalOrphaned" -Level $(if ($totalOrphaned -gt 0) { 'Warning' } else { 'Success' })

if ($totalOrphaned -gt 0) {
    Write-Log "Total orphaned data: $([math]::Round($totalSize, 2)) GB" -Level Warning
    Write-Log "" -Level Info
    Write-Log "Next steps:" -Level Info
    Write-Log "  1. Review the CSV report: $csvPath" -Level Info
    Write-Log "  2. Verify folders are truly orphaned by checking contents" -Level Info
    Write-Log "  3. Archive or delete as appropriate" -Level Info
    Write-Log "  4. Use -ArchiveFolder parameter to move folders automatically" -Level Info
    Write-Log "  5. Use -GenerateDeletionScript to create deletion script" -Level Info
    exit 1
}
else {
    Write-Log "No orphaned folders found. No action required." -Level Success
    exit 0
}
#endregion
