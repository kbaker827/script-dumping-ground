# Orphaned SharePoint/OneDrive Sync Scanner

PowerShell utility to identify local folders that were once synced with SharePoint or OneDrive but are no longer associated with any active account. Helps recover disk space and clean up after tenant migrations, account changes, or reconfigurations.

## Overview

When OneDrive sync relationships are broken (user leaves, tenant changes, manual unlinking), the local folders often remain consuming significant disk space. This script:

- Discovers all active OneDrive sync locations
- Scans for folders that look like former SharePoint/OneDrive sync roots
- Identifies orphan indicators (desktop.ini, cloud files, naming patterns)
- Generates detailed reports with recommendations
- Optionally archives or prepares folders for deletion

## Features

- ✅ **Active OneDrive Discovery** - Finds all registered OneDrive locations via registry, env vars, and processes
- ✅ **Heuristic Detection** - Multiple indicators for accurate orphan detection
- ✅ **Size Reporting** - Detailed folder size and file count information
- ✅ **Risk Assessment** - Confidence levels and recommendations for each folder
- ✅ **Archive Support** - Move orphaned folders to archive location
- ✅ **Deletion Script** - Generate safe deletion scripts for review
- ✅ **Configurable Scanning** - Adjustable depth and minimum size thresholds

## Quick Start

### Basic Scan
```powershell
.\Find-OrphanedSharePointSync.ps1
```
Scans default locations and generates a CSV report.

### Scan with Archive Option
```powershell
.\Find-OrphanedSharePointSync.ps1 -ArchiveFolder "D:\OneDrive-Archive" -WhatIf
```
Shows what would be archived without moving files.

### Generate Deletion Script
```powershell
.\Find-OrphanedSharePointSync.ps1 -GenerateDeletionScript -OutputFolder "C:\Reports"
```
Creates a PowerShell script to delete confirmed orphans after review.

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ExtraPaths` | string[] | `@()` | Additional paths to scan |
| `OutputFolder` | string | `Documents` | Where to save CSV reports |
| `ArchiveFolder` | string | `""` | Move orphans here (optional) |
| `GenerateDeletionScript` | switch | `$false` | Create deletion script |
| `MinFolderSizeMB` | int | `1` | Minimum folder size to include |
| `MaxDepth` | int | `3` | Directory scan depth |
| `Force` | switch | `$false` | Skip confirmations |
| `WhatIf` | switch | `$false` | Preview mode (no changes) |

## How It Works

### 1. Active OneDrive Discovery
The script finds currently active OneDrive locations via:
- Registry (`HKCU:\Software\Microsoft\OneDrive\Accounts`)
- Environment variables (`$env:OneDrive`, `$env:OneDriveCommercial`)
- Running OneDrive processes

### 2. Scanning
Scans specified paths up to `MaxDepth` levels deep, looking for:

**Naming Patterns:**
- `Documents - Company`
- `SharePoint - Site Name`
- `OneDrive - Contoso`
- Folders ending in ` (1)`, ` (2)` etc.
- Common SharePoint library names

**Indicators:**
- `desktop.ini` with OneDrive/SharePoint references
- Cloud placeholder files (reparse points)
- OneNote files (`.one`)
- Sync conflict files (`* - Copy (*).*`)
- OneDrive temp files (`.odt`, `.odg`)

### 3. Status Determination

| Status | Confidence | Description |
|--------|------------|-------------|
| **Active** | High | Inside current OneDrive sync path |
| **Likely Orphaned** | High | Strong indicators (desktop.ini + cloud files) |
| **Possibly Orphaned** | Medium | Some indicators present |
| **Unknown** | Low | Requires manual review |

### 4. Reporting
Generates CSV with columns:
- Name, FullPath, ParentPath
- Status, Confidence, RiskLevel
- InsideActiveOneDrive, ActiveMountParent
- HasDesktopIni, HasOneDriveIcon, HasCloudFiles
- SizeGB, FileCount, CloudFiles, LocalFiles
- Created, Modified, DetectionReason
- Recommendation

## Examples

### Basic Scan
```powershell
.\Find-OrphanedSharePointSync.ps1
```
Generates report in Documents folder.

### Scan Additional Locations
```powershell
.\Find-OrphanedSharePointSync.ps1 -ExtraPaths "D:\SharedDocs", "E:\Backup"
```

### Large Folders Only
```powershell
.\Find-OrphanedSharePointSync.ps1 -MinFolderSizeMB 100
```
Only reports folders larger than 100 MB.

### Shallow Scan
```powershell
.\Find-OrphanedSharePointSync.ps1 -MaxDepth 2
```
Only scan 2 levels deep (faster).

### Archive High-Confidence Orphans
```powershell
.\Find-OrphanedSharePointSync.ps1 -ArchiveFolder "D:\Archive\OneDrive" -Force
```
Moves high-confidence orphaned folders to archive.

### Preview Archive
```powershell
.\Find-OrphanedSharePointSync.ps1 -ArchiveFolder "D:\Archive" -WhatIf
```
Shows what would be archived without moving.

### Complete Cleanup Workflow
```powershell
# Step 1: Scan and generate deletion script
.\Find-OrphanedSharePointSync.ps1 -GenerateDeletionScript -OutputFolder "C:\Reports"

# Step 2: Review the CSV report
# Step 3: Run the generated deletion script after review
```

## Sample Output

### Console Output
```
========================================
  Orphaned SharePoint Sync Scanner v3.0
========================================

[*] Discovering active OneDrive mount points...
[+] Found 2 active OneDrive location(s)
    D:\OneDrive - Contoso
    C:\Users\jdoe\OneDrive

[*] Scanning for candidate folders (depth: 3, min size: 1MB)...
[+] Found 5 candidate folder(s) meeting criteria

========================================
  SCAN RESULTS
========================================

Potentially Orphaned Folders (Review Required):

Name                Status           Confidence SizeGB FileCount Recommendation
----                ------           ---------- ------ --------- --------------
Documents - OldCo   Likely Orphaned  High       12.5   342       Review - Strong indicators of orphaned sync folder
SharePoint - Site   Likely Orphaned  High       8.2    156       Review - Strong indicators of orphaned sync folder
OneDrive (1)        Possibly Orphaned Medium    2.1    89        Review - Some indicators present, verify before action

[+] Detailed report saved to: C:\Users\jdoe\Documents\OrphanedSharePointScan_20260212_144530.csv

========================================
  SUMMARY
========================================

[*] Total candidates found: 5
[+] Active OneDrive folders: 2
[!] Potentially orphaned folders: 3
[!] Total orphaned data: 22.8 GB
```

### CSV Report Columns
| Column | Description |
|--------|-------------|
| `Name` | Folder name |
| `FullPath` | Absolute path |
| `ParentPath` | Parent directory |
| `Status` | Active / Likely Orphaned / Possibly Orphaned / Unknown |
| `Confidence` | High / Medium / Low |
| `RiskLevel` | Assessment of deletion risk |
| `InsideActiveOneDrive` | True if inside current sync path |
| `ActiveMountParent` | Which active mount contains this (if any) |
| `HasDesktopIni` | Has desktop.ini file |
| `HasOneDriveIcon` | desktop.ini references OneDrive |
| `HasCloudFiles` | Contains cloud placeholder files |
| `HasSyncFiles` | Contains sync conflict files |
| `HasOneDriveFiles` | Contains OneNote files |
| `DetectionReason` | Why this folder was flagged |
| `SizeGB` / `SizeMB` | Folder size |
| `FileCount` / `CloudFiles` / `LocalFiles` | File counts |
| `Created` / `Modified` | Timestamps |
| `Recommendation` | Suggested action |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success, no orphaned folders found |
| 1 | Orphaned folders found (review required) |
| 2 | Error during scan |
| 3 | User cancelled operation |

## Use Cases

### Post-Tenant Migration
After migrating to a new Microsoft 365 tenant:
```powershell
.\Find-OrphanedSharePointSync.ps1 -ArchiveFolder "D:\OldTenant-Archive"
```

### User Account Cleanup
When a user account is removed:
```powershell
.\Find-OrphanedSharePointSync.ps1 -ExtraPaths "C:\Users" -GenerateDeletionScript
```

### Disk Space Recovery
Find what's consuming space:
```powershell
.\Find-OrphanedSharePointSync.ps1 -MinFolderSizeMB 500 | Sort-Object SizeGB -Descending
```

### Regular Maintenance
Schedule weekly scans:
```powershell
# Task Scheduler Action:
powershell.exe -File "C:\Scripts\Find-OrphanedSharePointSync.ps1" -OutputFolder "C:\Reports"
```

## Safety Features

- **Preview Mode** (`-WhatIf`): See what would be archived without making changes
- **Confidence Levels**: Only High-confidence orphans are auto-archived
- **CSV Review**: Always generates report for manual review first
- **Active Mount Protection**: Never flags folders inside active OneDrive paths
- **System Folder Exclusion**: Skips Windows, Program Files, etc.
- **Deletion Script**: Generated scripts require typing "DELETE" to confirm

## Requirements

- Windows 10/11
- PowerShell 5.1 or later
- No admin rights required for scanning
- Admin rights recommended for archive/deletion operations

## Limitations

- Cannot detect "ghost" sync relationships (fully deleted with no traces)
- Some cloud files may have been fully downloaded (lost reparse point)
- Very old sync folders may lack desktop.ini
- Requires manual review for Medium/Low confidence items

## Troubleshooting

### "No active OneDrive locations found"
OneDrive may not be installed or configured. Check:
```powershell
$env:OneDrive
Test-Path "HKCU:\Software\Microsoft\OneDrive"
```

### "Access denied" errors
Some folders may require elevated permissions. Run as Administrator if needed.

### Scan takes too long
Reduce scan depth:
```powershell
.\Find-OrphanedSharePointSync.ps1 -MaxDepth 2
```

### Too many false positives
Increase minimum size threshold:
```powershell
.\Find-OrphanedSharePointSync.ps1 -MinFolderSizeMB 50
```

## Version History

### 3.0 (2026-02-12)
- Complete rewrite with improved detection heuristics
- Added confidence levels and risk assessment
- Added archive functionality
- Added deletion script generation
- Added size breakdown (cloud vs local files)
- Improved OneDrive discovery (multiple methods)
- Better reporting with actionable recommendations

### 2.0 (2026-02-04)
- Basic orphaned sync folder detection
- CSV export
- Active mount point checking

### 1.0
- Initial release

## See Also

- `Check-IntuneEnrollment.ps1` - For cloud-managed device enrollment
- Microsoft Docs: [OneDrive Known Folder Move](https://docs.microsoft.com/onedrive/redirect-known-folders)

## License

MIT License - Use at your own risk. Always review scan results before deleting data.

---

## Related Scripts

### Force-SharePointPageCheckIn.ps1
Administrative tool to force check-in, publish, and approve SharePoint Online pages stuck in checked-out state.
- Single page or bulk operations
- Force override any user's checkout
- Auto-publish and auto-approve options
- Multiple authentication methods (Interactive, Managed Identity, App-only)
- See [README-ForceCheckIn.md](README-ForceCheckIn.md) for details
