# Unitwain - Intune Package

Complete Intune deployment package for Unitwain scanner software with site licensing and custom configuration.

## Overview

This package provides automated deployment of Unitwain TWAIN scanner driver through Microsoft Intune with:
- Silent installation
- Automatic site license activation
- Custom settings deployment
- Network scanning configuration

## Contents

| File | Purpose |
|------|---------|
| `Install-Unitwain.ps1` | Downloads, installs, and configures Unitwain with license |
| `Uninstall-Unitwain.ps1` | Removes Unitwain completely |
| `Detect-Unitwain.ps1` | Detects if Unitwain is installed (for Intune) |

## Prerequisites

- **Site License Key**: Your Unitwain site license key
- **Download URL** (optional): Direct URL to Unitwain installer
- **Custom Settings File** (optional): XML configuration file

## Quick Start

### Step 1: Package the Application

1. Download the Microsoft Win32 Content Prep Tool
2. Create folder structure:
   ```
   Unitwain/
   ├── Install-Unitwain.ps1
   ├── Uninstall-Unitwain.ps1
   ├── Detect-Unitwain.ps1
   └── unitwain-config.xml (optional - your custom settings)
   ```

3. Run IntuneWinAppUtil:
   ```powershell
   IntuneWinAppUtil.exe -c "C:\Unitwain" -s "Install-Unitwain.ps1" -o "C:\Output"
   ```

### Step 2: Configure in Intune

1. Go to **Intune Admin Center** → **Apps** → **Windows** → **Add**
2. Select **Windows app (Win32)**
3. Upload the `.intunewin` file

#### App Information
- **Name**: Unitwain Scanner Driver
- **Description**: TWAIN scanner driver with site licensing
- **Publisher**: Unitwain

#### Program Settings

**Install command:**
```powershell
powershell.exe -ExecutionPolicy Bypass -File "Install-Unitwain.ps1" -SiteLicenseKey "XXXX-XXXX-XXXX-XXXX"
```

**Uninstall command:**
```powershell
powershell.exe -ExecutionPolicy Bypass -File "Uninstall-Unitwain.ps1"
```

**Install behavior:** System

**Device restart behavior:** No specific action

#### Detection Rules

**Rule type:** Use a custom detection script

Upload: `Detect-Unitwain.ps1`

**Run script as 32-bit process on 64-bit clients:** No

**Enforce script signature check:** No

### Step 3: Assignments

- **Required**: Deploy to devices with scanners
- **Available**: Optional for users to install

## Script Parameters

### Install Script Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `SiteLicenseKey` | **Yes** | - | Site license key for activation |
| `DownloadURL` | No | Official | Direct URL to Unitwain installer |
| `SettingsFile` | No | `""` | Path to custom settings XML |
| `LicenseFile` | No | `""` | Path to license file |
| `LogPath` | No | Intune logs | Path for log files |
| `DefaultScanner` | No | `""` | Default scanner model |
| `EnableNetworkScan` | No | `$false` | Enable network scanning |

### Examples

**Basic installation with license:**
```powershell
.\Install-Unitwain.ps1 -SiteLicenseKey "ABCD-1234-EFGH-5678"
```

**With custom settings:**
```powershell
.\Install-Unitwain.ps1 -SiteLicenseKey "ABCD-1234" -SettingsFile "C:\Config\unitwain.xml"
```

**With network scanning:**
```powershell
.\Install-Unitwain.ps1 -SiteLicenseKey "ABCD-1234" -EnableNetworkScan -DefaultScanner "Canon DR-C225"
```

**Custom download URL:**
```powershell
.\Install-Unitwain.ps1 -SiteLicenseKey "ABCD-1234" -DownloadURL "https://internal.company.com/unitwain.exe"
```

## Custom Settings File

Create an XML file with your organization's scanner defaults:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<UnitwainConfiguration>
    <License>
        <Type>Site</Type>
        <Key>XXXX-XXXX-XXXX-XXXX</Key>
    </License>
    <Scanner>
        <DefaultModel>Canon DR-C225</DefaultModel>
        <AutoDetect>true</AutoDetect>
    </Scanner>
    <Network>
        <Enabled>true</Enabled>
        <Discovery>true</Discovery>
    </Network>
    <ScanDefaults>
        <ColorMode>Color</ColorMode>
        <Resolution>300</Resolution>
        <Format>PDF</Format>
        <Duplex>false</Duplex>
    </ScanDefaults>
</UnitwainConfiguration>
```

Save as `unitwain-config.xml` and include in the package.

## How It Works

### Installation Flow

1. **Validate license key** — Required parameter check
2. **Check existing install** — Updates license/settings if already installed
3. **Download installer** — From official source or custom URL
4. **Silent install** — Executes with silent flags
5. **Apply license** — Writes license to registry and files
6. **Configure settings** — Deploys custom configuration
7. **Register completion** — Creates registry marker

### License Configuration

The script applies the site license in multiple locations:
- `%ProgramData%\Unitwain\license.dat`
- `%ProgramData%\Unitwain\Config\license.key`
- `HKLM:\SOFTWARE\Unitwain\LicenseKey`

### Detection Methods

The detection script verifies:
- Add/Remove Programs registry entry
- Custom Intune registry marker
- Executable file presence
- License file existence

## Logging

Logs are written to:
```
%ProgramData%\Microsoft\IntuneManagementExtension\Logs\
├── UnitwainInstall.log       # Install script log
└── UnitwainUninstall.log     # Uninstall script log
```

## Troubleshooting

### Installation Fails

**Check the logs:**
```
%ProgramData%\Microsoft\IntuneManagementExtension\Logs\UnitwainInstall.log
```

**Common issues:**
- **Invalid license key**: Verify your site license with Unitwain
- **Download fails**: Check internet connectivity or use internal URL
- **Silent install fails**: May need to adjust install flags for your version

### License Not Applied

Check license file locations:
```powershell
Test-Path "$env:ProgramData\Unitwain\license.dat"
Test-Path "HKLM:\SOFTWARE\Unitwain"
```

### Detection Fails

Run detection script manually:
```powershell
.\Detect-Unitwain.ps1
echo $LASTEXITCODE  # 0 = detected, 1 = not detected
```

### Scanner Not Detected

1. Verify scanner is connected and powered on
2. Check USB connections
3. Ensure scanner drivers are installed
4. Test with manufacturer's utility first

## Finding Your Site License

Contact your Unitwain vendor or check your purchase documentation for the site license key. The key format is typically: `XXXX-XXXX-XXXX-XXXX`

## Network Scanning

To enable network scanner discovery:

```powershell
.\Install-Unitwain.ps1 -SiteLicenseKey "XXXX-XXXX" -EnableNetworkScan
```

Ensure network scanners are:
- On the same subnet, or
- Accessible via routing, and
- Have network scanning enabled in their configuration

## Uninstallation

### Standard Uninstall
```powershell
.\Uninstall-Unitwain.ps1
```

### Remove Including User Settings
```powershell
.\Uninstall-Unitwain.ps1 -RemoveSettings
```

## Requirements

- Windows 10 (1809+) or Windows 11
- PowerShell 5.1 or higher
- Administrator rights (runs as SYSTEM in Intune)
- TWAIN-compatible scanner
- Site license key

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-02-19 | Initial release |

## License

MIT License — Modify for your environment as needed.

## Support

- **Unitwain Support**: Contact your software vendor
- **TWAIN Documentation**: https://www.twain.org
