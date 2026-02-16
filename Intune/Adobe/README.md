# Adobe Acrobat Reader DC - Intune Win32 Package

Complete Intune deployment package for Adobe Acrobat Reader DC with enterprise configuration, bloatware removal, and update suppression.

## Files

| File | Purpose |
|------|---------|
| `Install-AdobeReaderDC.ps1` | Main installation script with download, install, and configuration |
| `Detect-AdobeReaderDC.ps1` | Intune detection script - verifies installation status |
| `Uninstall-AdobeReaderDC.ps1` | Uninstallation script for Intune removal |

## Features

- ✅ **Silent Installation** - No user interaction required
- ✅ **Automatic Download** - Downloads latest installer from Adobe
- ✅ **Bloatware Removal** - Removes Adobe Genuine Service and unwanted components
- ✅ **Update Suppression** - Disables auto-updates (managed via Intune instead)
- ✅ **Desktop Shortcut Removal** - Keeps desktops clean
- ✅ **Version Detection** - Checks minimum version requirement
- ✅ **Comprehensive Logging** - All activity logged to Intune logs
- ✅ **Error Handling** - Proper exit codes for Intune

## Prerequisites

- Microsoft Intune with Win32 app deployment capability
- Target devices running Windows 10/11 (x64 recommended)
- Internet access for downloading installer (or pre-stage installer)
- PowerShell 5.1 or later

## Quick Start

### 1. Download the Package

All files are in `script-dumping-ground/Intune/Adobe/`.

### 2. Get the Latest Adobe Reader Installer URL

The script includes a default URL, but you should update it to the latest version:

1. Visit [Adobe Acrobat Reader Distribution](https://get.adobe.com/reader/enterprise/)
2. Download the "Continuous track" version for your locale
3. Get the direct download URL and update `$InstallerUrl` in `Install-AdobeReaderDC.ps1`

**Current URL in script:**
```powershell
$InstallerUrl = "https://ardownload2.adobe.com/pub/adobe/reader/win/AcrobatDC/2300620363/AcroRdrDC2300620363_en_US.exe"
```

### 3. Create .intunewin Package

1. Download [Microsoft Win32 Content Prep Tool](https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool)
2. Create folder structure:
   ```
   C:\IntunePackages\
   └── AdobeReaderDC\
       ├── Install-AdobeReaderDC.ps1
       ├── Detect-AdobeReaderDC.ps1
       └── Uninstall-AdobeReaderDC.ps1
   ```
3. Run the prep tool:
   ```cmd
   IntuneWinAppUtil.exe
   -c C:\IntunePackages\AdobeReaderDC
   -s Install-AdobeReaderDC.ps1
   -o C:\IntunePackages\Output
   ```

### 4. Create Win32 App in Intune

#### App Information
| Field | Value |
|-------|-------|
| **Name** | Adobe Acrobat Reader DC |
| **Description** | Adobe PDF reader with enterprise configuration. Updates managed via Intune. |
| **Publisher** | Adobe Inc. |
| **App Version** | 23.x (or your version) |

#### Program
| Field | Value |
|-------|-------|
| **Install command** | `powershell.exe -ExecutionPolicy Bypass -File "Install-AdobeReaderDC.ps1"` |
| **Uninstall command** | `powershell.exe -ExecutionPolicy Bypass -File "Uninstall-AdobeReaderDC.ps1"` |
| **Install behavior** | System |
| **Device restart behavior** | Determine behavior based on return codes |

#### Return Codes
| Code | Type |
|------|------|
| 0 | Success |
| 3010 | Soft reboot (continue installation) |

#### Detection Rules
- **Rules format**: Use a custom detection script
- **Detection script**: Upload `Detect-AdobeReaderDC.ps1`
- **Run script as 32-bit process on 64-bit clients**: No

#### Dependencies
None required.

#### Supersedence (Optional)
If updating from a previous Reader version, add supersedence to automatically upgrade.

### 5. Assign to Devices

- **Required**: Deploy to all company devices
- **Available**: Let users install from Company Portal

## Configuration Options

### Edit Install Script Parameters

```powershell
# In Install-AdobeReaderDC.ps1

# Change download URL to specific version
$InstallerUrl = "https://your-custom-url/AcroRdrDC.exe"

# Pre-stage installer (no download)
$InstallerUrl = "C:\Windows\Temp\AcroRdrDC.exe"  # Pre-downloaded

# Enable/disable features
$RemoveBloatware = $true   # Set to $false to keep Adobe services
$DisableUpdater = $true    # Set to $false to allow auto-updates
```

### Minimum Version Detection

Edit `Detect-AdobeReaderDC.ps1` to enforce version requirements:

```powershell
param(
    [string]$MinimumVersion = "23.6.0"  # Enforce minimum version
)
```

## Script Details

### Install-AdobeReaderDC.ps1

**What it does:**
1. Checks if Reader is already installed
2. Downloads installer from Adobe (or uses pre-staged)
3. Silently installs with enterprise flags
4. Removes bloatware (Adobe Genuine Service, desktop shortcuts)
5. Disables auto-updater (registry configuration)
6. Verifies installation
7. Cleans up temp files

**MSI Properties Used:**
| Property | Description |
|----------|-------------|
| `/sAll` | Silent install |
| `/rs` | Suppress reboot |
| `EULA_ACCEPT=YES` | Accept EULA silently |
| `DISABLE_DESKTOP_SHORTCUT=YES` | No desktop icon |
| `DISABLE_ARM_SERVICE_INSTALL=1` | No ARM service |

**Log Location:**
```
C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AdobeReader-Install-[timestamp].log
```

### Detect-AdobeReaderDC.ps1

**Detection Methods:**
1. Checks for `AcroRd32.exe` in Program Files
2. Queries registry uninstall keys
3. Compares version against minimum requirement

**Returns:**
- Exit 0: Adobe Reader is installed (meets version requirement)
- Exit 1: Adobe Reader not found or version too old

### Uninstall-AdobeReaderDC.ps1

**Uninstall Methods (in order):**
1. MSI GUID uninstall via `msiexec.exe`
2. Adobe Setup.exe with uninstall parameters
3. Force removal of residual files/registry

**Cleans up:**
- Program Files directories
- User AppData folders
- Registry entries
- Desktop shortcuts

## Troubleshooting

### Issue: Download fails
**Check:** Internet connectivity, URL validity
**Fix:** Update `$InstallerUrl` with current Adobe URL

### Issue: "Adobe Genuine Service" still appears
**Check:** Script ran with admin rights
**Fix:** Verify `Remove-AdobeBloatware` function executed. May need to reboot.

### Issue: Auto-updates not disabled
**Check:** Registry permissions
**Fix:** Script must run as SYSTEM (Intune default). Check logs for registry errors.

### Issue: Detection fails but app is installed
**Check:** Version comparison logic
**Fix:** Modify `Detect-AdobeReaderDC.ps1` to match your installed version

### Issue: Exit code 3010 (reboot required)
**Solution:** This is normal for some Reader updates. Intune will handle based on your restart settings.

## Customization Examples

### Offline Installation (No Internet)

1. Download installer manually:
   ```powershell
   Invoke-WebRequest -Uri "https://ardownload2.adobe.com/.../AcroRdrDC.exe" -OutFile "C:\Source\AcroRdrDC.exe"
   ```

2. Modify install script:
   ```powershell
   $InstallerUrl = "C:\Source\AcroRdrDC.exe"
   ```

3. Include installer in .intunewin package

### Enable Auto-Updates

Remove this line from `Install-AdobeReaderDC.ps1`:
```powershell
if ($DisableUpdater) { Disable-AdobeUpdater }
```

Or set parameter:
```powershell
$DisableUpdater = $false
```

### Custom Configuration (PDF Ownership)

Add to `Install-AdobeReaderDC.ps1` after installation:

```powershell
# Set as default PDF handler
$RegPath = "HKLM:\SOFTWARE\Classes\.pdf"
Set-ItemProperty -Path $RegPath -Name "(Default)" -Value "AcroExch.Document.DC"
```

## Security Notes

1. **Script Execution**: Script uses `-ExecutionPolicy Bypass` - ensure your security team approves
2. **Download Source**: Verify Adobe download URL is legitimate (ardownload.adobe.com domain)
3. **EULA**: Script accepts EULA silently - ensure your organization has proper licensing
4. **Updates**: Disabling auto-updates shifts responsibility to Intune admins - monitor for security updates

## Update Management

Since auto-updates are disabled, use this approach for updates:

1. **Method A**: Update the `$InstallerUrl` and redeploy as required app
2. **Method B**: Create a separate "Adobe Reader Update" Win32 app that only installs if version < X

### Version Check for Updates

Create a new detection script for updates:
```powershell
$Current = (Get-ItemProperty "${env:ProgramFiles(x86)}\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe").VersionInfo.FileVersion
$Required = "23.6.0"

if ([System.Version]$Current -lt [System.Version]$Required) {
    exit 1  # Trigger update installation
} else {
    exit 0  # Up to date
}
```

## References

- [Adobe Acrobat Reader Distribution](https://get.adobe.com/reader/enterprise/)
- [Adobe Customization Wizard](https://www.adobe.com/devnet-docs/acrobatetk/tools/Wizard/index.html) - For MST transforms
- [Intune Win32 App Management](https://docs.microsoft.com/en-us/mem/intune/apps/apps-win32-app-management)

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-02-16 | Initial release |
