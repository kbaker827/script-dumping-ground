# Copy Folder with Config - Intune Script

PowerShell scripts to copy folders with configuration files to target locations via Microsoft Intune.

## Overview

This package provides scripts to copy folders containing configuration files from a source location to a target directory. Useful for deploying application configs, templates, or resource files to managed devices.

## Contents

| File | Purpose |
|------|---------|
| `Copy-FolderWithConfig.ps1` | Main script to copy folders with config files |
| `Remove-CopiedFolder.ps1` | Removes copied folders (uninstall) |
| `Detect-CopiedFolder.ps1` | Detects if folder was copied (Intune detection) |

## Features

- ✅ Copy from UNC paths, local paths, or relative paths
- ✅ File filtering with include/exclude patterns
- ✅ Backup existing folders before overwriting
- ✅ Clean target option (remove existing before copy)
- ✅ Hash validation for file integrity
- ✅ Preserves folder structure
- ✅ Detailed logging
- ✅ Registry tracking

## Quick Start

### Usage Examples

**Basic folder copy:**
```powershell
.\Copy-FolderWithConfig.ps1 -SourceFolder "C:\Source\Config" -TargetFolder "C:\ProgramData\MyApp\Config"
```

**From network share:**
```powershell
.\Copy-FolderWithConfig.ps1 -SourceFolder "\\server\share\configs" -TargetFolder "C:\AppData"
```

**With backup:**
```powershell
.\Copy-FolderWithConfig.ps1 -SourceFolder ".\ConfigFiles" -TargetFolder "C:\Program Files\App\Config" -CreateBackup
```

**Only XML files:**
```powershell
.\Copy-FolderWithConfig.ps1 -SourceFolder "C:\Configs" -TargetFolder "C:\Target" -IncludeFilter "*.xml"
```

**Clean copy (remove existing first):**
```powershell
.\Copy-FolderWithConfig.ps1 -SourceFolder "C:\NewConfig" -TargetFolder "C:\OldConfig" -CleanTarget
```

## Intune Deployment

### As Win32 App

1. Package your source folder with the scripts:
   ```
   FolderCopyPackage/
   ├── Copy-FolderWithConfig.ps1
   ├── Remove-CopiedFolder.ps1
   ├── Detect-CopiedFolder.ps1
   └── SourceConfig/          <-- Your config folder
   ```

2. Create `.intunewin` file:
   ```powershell
   IntuneWinAppUtil.exe -c "C:\FolderCopyPackage" -s "Copy-FolderWithConfig.ps1" -o "C:\Output"
   ```

3. In Intune:
   - **Install command**: 
     ```powershell
     powershell.exe -ExecutionPolicy Bypass -File "Copy-FolderWithConfig.ps1" -SourceFolder ".\SourceConfig" -TargetFolder "C:\ProgramData\MyApp\Config"
     ```
   - **Uninstall command**:
     ```powershell
     powershell.exe -ExecutionPolicy Bypass -File "Remove-CopiedFolder.ps1" -TargetFolder "C:\ProgramData\MyApp\Config"
     ```
   - **Detection**: Use custom detection script `Detect-CopiedFolder.ps1` with parameter `-TargetFolder "C:\ProgramData\MyApp\Config"`

### As PowerShell Script

Deploy directly through Intune PowerShell scripts:
```powershell
.\Copy-FolderWithConfig.ps1 -SourceFolder "\\fileserver\configs\department" -TargetFolder "C:\ProgramData\Company\Config" -CreateBackup
```

## Script Parameters

### Copy-FolderWithConfig.ps1

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `SourceFolder` | **Yes** | - | Path to source folder |
| `TargetFolder` | **Yes** | - | Destination path |
| `Overwrite` | No | `$true` | Overwrite existing files |
| `CreateBackup` | No | `$false` | Create .bak backup first |
| `CleanTarget` | No | `$false` | Remove existing target first |
| `IncludeFilter` | No | `*` | File pattern to include |
| `ExcludeFilter` | No | `*.tmp, *.log` | Patterns to exclude |
| `LogPath` | No | Intune logs | Log file location |
| `ValidateHash` | No | `$false` | Use SHA256 validation |

### Remove-CopiedFolder.ps1

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `TargetFolder` | **Yes** | - | Folder to remove |
| `RestoreFromBackup` | No | `$false` | Restore from .bak |
| `KeepRegistryEntry` | No | `$false` | Keep tracking entry |

### Detect-CopiedFolder.ps1

| Parameter | Required | Description |
|-----------|----------|-------------|
| `TargetFolder` | **Yes** | Path to verify |

## Advanced Examples

### Copy with Hash Validation

```powershell
.\Copy-FolderWithConfig.ps1 `
    -SourceFolder "\\server\secure\configs" `
    -TargetFolder "C:\ProgramData\App" `
    -ValidateHash `
    -CreateBackup
```

### Exclude Temporary Files

```powershell
.\Copy-FolderWithConfig.ps1 `
    -SourceFolder "C:\Configs" `
    -TargetFolder "C:\Target" `
    -ExcludeFilter @("*.tmp", "*.log", "~$*", "*.bak")
```

### Multiple File Types

```powershell
.\Copy-FolderWithConfig.ps1 `
    -SourceFolder "C:\Source" `
    -TargetFolder "C:\Dest" `
    -IncludeFilter "*.xml" `
    -ExcludeFilter @("*_test.xml", "*_old.xml")
```

### Restore from Backup

```powershell
.\Remove-CopiedFolder.ps1 -TargetFolder "C:\ProgramData\App\Config" -RestoreFromBackup
```

## Logging

Logs are written to:
```
%ProgramData%\Microsoft\IntuneManagementExtension\Logs\
├── CopyFolderConfig.log
└── RemoveCopiedFolder.log
```

Log entries include:
- Timestamp
- Source and target paths
- Files copied/skipped/failed
- Operation results

## Registry Tracking

Successful operations are tracked in:
```
HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\FolderCopy
```

Values:
- `SourceFolder` - Original source path
- `TargetFolder` - Destination path
- `LastCopyDate` - When copy occurred
- `Success` - Whether operation succeeded

## Common Use Cases

### Application Configuration Deployment

Deploy app configs to ProgramData:
```powershell
.\Copy-FolderWithConfig.ps1 `
    -SourceFolder ".\AppConfig" `
    -TargetFolder "$env:ProgramData\MyApp\Config" `
    -CreateBackup
```

### Department-Specific Files

Copy department configs based on group:
```powershell
$dept = "Sales"  # Could come from AD attribute
.\Copy-FolderWithConfig.ps1 `
    -SourceFolder "\\server\depts\$dept" `
    -TargetFolder "C:\Company\Config"
```

### User Profile Deployment

Deploy to all user profiles:
```powershell
$users = Get-ChildItem -Path "C:\Users" -Directory
foreach ($user in $users) {
    $target = Join-Path $user.FullName "AppData\Roaming\MyApp"
    .\Copy-FolderWithConfig.ps1 -SourceFolder ".\Config" -TargetFolder $target
}
```

## Troubleshooting

### Access Denied

Run as Administrator for system folders:
```powershell
#Requires -RunAsAdministrator
```

### Network Path Issues

Ensure SYSTEM account has access:
```powershell
# Grant access to computer account
# \\server\share → Properties → Security → Add → DOMAIN\COMPUTERNAME$
```

### Detection Fails

Run detection manually:
```powershell
.\Detect-CopiedFolder.ps1 -TargetFolder "C:\Target"
echo $LASTEXITCODE  # 0 = found, 1 = not found
```

### Files Not Copying

Check logs for excluded files:
```
[2025-02-19 10:00:00] [INFO] Found 15 files to copy
[2025-02-19 10:00:01] [INFO] Skipping existing file: config.tmp
```

## Requirements

- Windows 10 (1809+) or Windows 11
- PowerShell 5.1 or higher
- Administrator rights (for system folders)
- Read access to source
- Write access to target

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-02-19 | Initial release |

## License

MIT License — Modify for your environment as needed.
