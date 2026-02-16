# Universal Adobe Acrobat Uninstaller for Intune

A comprehensive Intune Win32 package that removes **ALL** Adobe Acrobat products from managed devices. Handles Reader, Pro, Standard, DC, and legacy versions with multiple removal methods.

## Supported Products

This uninstaller targets all Adobe Acrobat variants:

- ✅ Adobe Acrobat Reader DC (all versions)
- ✅ Adobe Acrobat Pro DC
- ✅ Adobe Acrobat Standard DC  
- ✅ Adobe Acrobat 2020/2023 (Classic Track)
- ✅ Adobe Acrobat XI (legacy)
- ✅ Adobe Genuine Service (bloatware)
- ✅ Adobe Update Services

## Files

| File | Purpose |
|------|---------|
| `Uninstall-AllAdobeAcrobat.ps1` | Main universal uninstaller script |
| `Detect-AdobeAcrobatRemaining.ps1` | Detection script - checks if any Adobe Acrobat remains |

## Features

- ✅ **Universal Detection** - Finds any installed Adobe Acrobat product
- ✅ **Multiple Uninstall Methods** - MSI GUIDs, Adobe Cleaner Tool, manual cleanup
- ✅ **Process Termination** - Kills all Adobe processes before uninstall
- ✅ **Service Cleanup** - Stops and disables Adobe services
- ✅ **Residual Removal** - Cleans files, registry, shortcuts, scheduled tasks
- ✅ **Aggressive Mode** - Optional deep cleanup for stubborn installations
- ✅ **Comprehensive Logging** - Detailed logs for troubleshooting
- ✅ **Safe Exit Codes** - Returns 0 on success for Intune

## Prerequisites

- Microsoft Intune with Win32 app deployment
- Windows 10/11 target devices
- PowerShell 5.1 or later
- Administrator rights (runs as SYSTEM in Intune)

## Quick Start

### 1. Prepare Files

All files are in `script-dumping-ground/Intune/Adobe/`:

```
script-dumping-ground/Intune/Adobe/
├── Install-AdobeReaderDC.ps1          (from previous package)
├── Detect-AdobeReaderDC.ps1           (from previous package)
├── Uninstall-AdobeReaderDC.ps1        (from previous package)
├── Uninstall-AllAdobeAcrobat.ps1      (NEW - universal uninstaller)
├── Detect-AdobeAcrobatRemaining.ps1   (NEW - detection for uninstaller)
└── README.md                          (this file)
```

### 2. Create .intunewin Package

1. Download [Microsoft Win32 Content Prep Tool](https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool)
2. Create folder:
   ```
   C:\IntunePackages\AdobeAcrobatUninstaller\
   ├── Uninstall-AllAdobeAcrobat.ps1
   └── Detect-AdobeAcrobatRemaining.ps1
   ```
3. Run prep tool:
   ```cmd
   IntuneWinAppUtil.exe
   -c C:\IntunePackages\AdobeAcrobatUninstaller
   -s Uninstall-AllAdobeAcrobat.ps1
   -o C:\IntunePackages\Output
   ```

### 3. Create Win32 App in Intune

#### App Information
| Field | Value |
|-------|-------|
| **Name** | Adobe Acrobat Universal Uninstaller |
| **Description** | Removes all Adobe Acrobat products (Reader, Pro, Standard, DC, legacy) |
| **Publisher** | Your Organization |

#### Program Settings
| Field | Value |
|-------|-------|
| **Install command** | `powershell.exe -ExecutionPolicy Bypass -File "Uninstall-AllAdobeAcrobat.ps1"` |
| **Uninstall command** | `cmd /c` (leave blank or no-op) |
| **Install behavior** | System |
| **Device restart behavior** | No specific action |

#### Return Codes
| Code | Type | Description |
|------|------|-------------|
| 0 | Success | All Adobe products removed |
| 1 | Success | Some products may remain (check logs) |

#### Detection Rules
- **Rules format**: Use a custom detection script
- **Detection script**: Upload `Detect-AdobeAcrobatRemaining.ps1`
- **Run script as 32-bit process on 64-bit clients**: No

### 4. Assignments

**Recommended**: Assign as **Required** to device groups that need Adobe removal.

**Use Cases:**
- Migrating from Adobe Reader to Foxit/Bluebeam
- Removing legacy Acrobat versions before deploying new ones
- Standardizing on a single Acrobat version
- Cleaning up non-compliant installations

## Configuration Options

### Standard Uninstall
```powershell
powershell.exe -ExecutionPolicy Bypass -File "Uninstall-AllAdobeAcrobat.ps1"
```

### With Adobe Cleaner Tool (Recommended)
```powershell
powershell.exe -ExecutionPolicy Bypass -File "Uninstall-AllAdobeAcrobat.ps1" -UseCleanerTool
```

### Aggressive Cleanup (Deep Removal)
```powershell
powershell.exe -ExecutionPolicy Bypass -File "Uninstall-AllAdobeAcrobat.ps1" -UseCleanerTool -AggressiveCleanup
```

## How It Works

### Uninstall Sequence

1. **Stop Processes** - Terminates all Adobe processes (AcroRd32, AcroCEF, ARM, etc.)
2. **Stop Services** - Disables Adobe services (ARM, Genuine Monitor, Update Service)
3. **Detect Products** - Scans WMI and Registry for installed Adobe Acrobat products
4. **MSI Uninstall** - Attempts removal via known MSI GUIDs
5. **Adobe Cleaner Tool** - Downloads and runs Adobe's official cleaner (optional)
6. **Residual Cleanup** - Removes:
   - Program Files directories
   - User AppData folders
   - Registry keys
   - Scheduled tasks
   - Desktop shortcuts
7. **Verification** - Confirms all products removed

### Known MSI GUIDs

The script includes GUIDs for:
- Reader DC (multiple versions)
- Acrobat Pro DC
- Acrobat Standard DC
- Acrobat XI
- Acrobat 2020/2023
- Adobe Genuine Service
- Update Service components

## Logging

All activity is logged to:
```
C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Adobe-Acrobat-Universal-Uninstall-[timestamp].log
```

Individual MSI uninstalls also create logs:
```
C:\Windows\Temp\Adobe-Uninstall-[GUID].log
```

### View Logs
```powershell
# View main log
Get-Content "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Adobe-Acrobat-Universal-Uninstall-*.log" -Tail 100

# View MSI logs
Get-ChildItem "C:\Windows\Temp\Adobe-Uninstall-*.log" | Get-Content
```

## Troubleshooting

### Issue: Products remain after uninstall
**Check:** Run with `-AggressiveCleanup` flag
**Fix:** The script will use more thorough cleanup methods

### Issue: Adobe Cleaner Tool fails to download
**Check:** Internet connectivity
**Fix:** Pre-download the cleaner tool and modify script path

### Issue: WMI scan is slow
**Cause:** Win32_Product is slow on some systems
**Fix:** Script also uses registry scan as fallback - WMI timeout is handled

### Issue: Services won't stop
**Check:** Running processes locking services
**Fix:** Script attempts process termination before service cleanup

### Issue: Registry cleanup fails
**Check:** Permissions on registry keys
**Fix:** Script runs as SYSTEM via Intune - should have permissions

## Advanced Usage

### Custom Cleaner Tool URL

Edit script to use internal-hosted cleaner tool:

```powershell
# In Uninstall-AllAdobeAcrobat.ps1
$CleanerToolUrl = "https://your-server.com/AcroCleaner.exe"
```

### Exclude Specific Versions

To skip certain products, modify the GUID list:

```powershell
# Remove specific GUID from $AcrobatGUIDs array
$AcrobatGUIDs = $AcrobatGUIDs | Where-Object { $_ -ne "GUID-TO-KEEP" }
```

### Force Reboot After Uninstall

Add to end of script:

```powershell
if ($ProductsRemoved -gt 0) {
    exit 3010  # Signal reboot needed
}
```

Then configure Intune return code 3010 = "Hard reboot"

## Integration with Other Packages

### Pre-Install Cleanup
Use this package as a dependency for a new Acrobat install:

1. Create "Adobe Acrobat Uninstaller" app (this package)
2. Create "Adobe Acrobat Reader DC" app (install package)
3. Add dependency: Install requires Uninstaller first
4. Intune will:
   - Run uninstaller (removes all versions)
   - Then run installer (fresh install)

### Migration Scenario

**Goal:** Replace Adobe Reader with Foxit Reader

1. Deploy "Adobe Acrobat Universal Uninstaller" (Required)
2. Deploy "Foxit Reader Installer" (Required, after uninstaller)
3. Users get seamless transition

## Security Considerations

1. **Script Execution Policy**: Uses `-ExecutionPolicy Bypass` - ensure security team approval
2. **Download**: Adobe Cleaner Tool downloads from Adobe - verify URL
3. **Scope**: This removes ALL Adobe Acrobat products - be careful on devices that need Pro/Standard
4. **Data**: Does NOT remove user PDF files, only application files

## Known Limitations

1. **WMI Performance**: Win32_Product scan can be slow (30-60 seconds)
2. **Reboot Required**: Some remnants may require reboot to fully remove
3. **Shared Components**: May affect other Adobe products (Photoshop, Illustrator) if they share Acrobat components
4. **Adobe ID**: Does not remove Adobe ID/account associations

## Comparison: Single vs Universal Uninstaller

| Feature | Single Uninstaller | Universal Uninstaller |
|---------|-------------------|----------------------|
| Targets | Specific version | ALL Acrobat products |
| Detection | One product | Any Acrobat product |
| Speed | Faster | Slower (more scans) |
| Use Case | Standard updates | Migrations, cleanup |

Use **Single Uninstaller** (`Uninstall-AdobeReaderDC.ps1`) for:
- Standard Reader updates
- Reinstalling same version

Use **Universal Uninstaller** (`Uninstall-AllAdobeAcrobat.ps1`) for:
- Version migrations
- Cleaning unknown installations
- Removing Pro/Standard/Reader all at once

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success - no Adobe products remain |
| 1 | Warning - some products may still be present (check logs) |

**Note:** Both codes are treated as "Success" in Intune. Use detection script to verify removal.

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-02-16 | Initial release |

## References

- [Adobe Cleaner Tool](https://helpx.adobe.com/acrobat/kb/acrobat-cleaner-tool.html)
- [Adobe Acrobat Enterprise Info](https://www.adobe.com/devnet-docs/acrobatetk/tools/ReleaseNotes/index.html)
- [Intune Win32 Apps](https://docs.microsoft.com/en-us/mem/intune/apps/apps-win32-app-management)
