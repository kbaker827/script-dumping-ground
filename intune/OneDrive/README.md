# Microsoft OneDrive - Intune Package

Automated installation and update of Microsoft OneDrive for Windows via Microsoft Intune.

## Overview

This package provides scripts to:
1. Install OneDrive if not present
2. Update OneDrive to the latest version if outdated
3. Configure enterprise settings (silent sign-in, KFM, etc.)
4. Support both per-user and per-machine (all users) installations

## Contents

| File | Purpose |
|------|---------|
| `Install-OneDrive.ps1` | Installs or updates OneDrive |
| `Remove-OneDrive.ps1` | Removes OneDrive |
| `Detect-OneDrive.ps1` | Detection script for Intune |

## Features

- ✅ **Auto-detect** — Checks if OneDrive is installed and current
- ✅ **Install or Update** — Installs fresh or updates to latest
- ✅ **Per-Machine Support** — Install for all users (recommended for Intune)
- ✅ **Silent Configuration** — Auto sign-in with Windows credentials
- ✅ **Known Folder Move** — Redirect Desktop/Documents/Pictures to OneDrive
- ✅ **Files On-Demand** — Enable cloud-first file access
- ✅ **Version Comparison** — Only updates when newer version available

## Quick Start

### Basic Installation (Per-Machine, Recommended)

```powershell
.\Install-OneDrive.ps1 -InstallMode PerMachine
```

### With Silent Configuration (Auto Sign-in)

```powershell
.\Install-OneDrive.ps1 -InstallMode PerMachine -EnableSilentConfig -TenantID "12345678-1234-1234-1234-123456789012"
```

### With Known Folder Move

```powershell
.\Install-OneDrive.ps1 -InstallMode PerMachine -KnownFolderMove -KFMSilentOptIn -TenantID "12345678-1234-1234-1234-123456789012"
```

### Force Update

```powershell
.\Install-OneDrive.ps1 -InstallMode PerMachine -ForceUpdate
```

## Intune Deployment

### As Win32 App (Recommended)

1. **Prepare your files:**
   ```
   OneDrive/
   ├── Install-OneDrive.ps1
   ├── Remove-OneDrive.ps1
   └── Detect-OneDrive.ps1
   ```

2. **Create .intunewin package:**
   ```powershell
   IntuneWinAppUtil.exe -c "C:\OneDrive" -s "Install-OneDrive.ps1" -o "C:\Output"
   ```

3. **Configure in Intune:**
   - **Name**: Microsoft OneDrive
   - **Description**: OneDrive for Business with enterprise configuration
   - **Publisher**: Microsoft

4. **Program Settings:**

   **Install command:**
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File "Install-OneDrive.ps1" -InstallMode PerMachine -EnableSilentConfig -TenantID "YOUR-TENANT-ID"
   ```

   **Uninstall command:**
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File "Remove-OneDrive.ps1"
   ```

5. **Detection Rules:**
   - Use custom detection script: `Detect-OneDrive.ps1`
   - Or file detection: `%ProgramFiles(x86)%\Microsoft OneDrive\OneDrive.exe`

### As PowerShell Script

Deploy directly through Intune PowerShell scripts:
```powershell
.\Install-OneDrive.ps1 -InstallMode PerMachine -EnableSilentConfig -TenantID "YOUR-TENANT-ID" -KnownFolderMove -KFMSilentOptIn
```

## Script Parameters

### Install-OneDrive.ps1

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `InstallMode` | No | `PerMachine` | `PerMachine` (all users) or `PerUser` |
| `DownloadURL` | No | Microsoft | Direct URL to OneDriveSetup.exe |
| `EnableSilentConfig` | No | `$false` | Auto sign-in with Windows account |
| `EnableFilesOnDemand` | No | `$true` | Enable Files On-Demand |
| `DisableAutoStart` | No | `$false` | Disable OneDrive startup |
| `KnownFolderMove` | No | `$false` | Enable KFM policies |
| `KFMSilentOptIn` | No | `$false` | Silent KFM opt-in (requires TenantID) |
| `TenantID` | No | - | Azure AD Tenant ID |
| `LogPath` | No | Intune logs | Log file location |
| `ForceUpdate` | No | `$false` | Force update regardless of version |

## Installation Modes

### Per-Machine (Recommended for Intune)

- Installs to `C:\Program Files (x86)\Microsoft OneDrive`
- Available to all users
- Updates apply to all users
- Requires Administrator rights
- **Recommended for enterprise deployments**

```powershell
.\Install-OneDrive.ps1 -InstallMode PerMachine
```

### Per-User

- Installs to `%LOCALAPPDATA%\Microsoft\OneDrive`
- Only for current user
- Each user manages their own updates
- No admin rights required
- **Better for personal/BYOD devices**

```powershell
.\Install-OneDrive.ps1 -InstallMode PerUser
```

## Enterprise Configuration

### Silent Account Configuration

Automatically signs users in with their Windows credentials:

```powershell
.\Install-OneDrive.ps1 `
    -InstallMode PerMachine `
    -EnableSilentConfig `
    -TenantID "12345678-1234-1234-1234-123456789012"
```

### Known Folder Move (KFM)

Redirects Desktop, Documents, and Pictures to OneDrive:

```powershell
.\Install-OneDrive.ps1 `
    -InstallMode PerMachine `
    -TenantID "12345678-1234-1234-1234-123456789012" `
    -KnownFolderMove `
    -KFMSilentOptIn
```

**Full KFM with blocking opt-out:**
```powershell
# Combine with Intune Configuration Profile
# Device Configuration > Administrative Templates > OneDrive
# - Silently move Windows known folders to OneDrive: Enabled
# - Prevent users from redirecting their Windows known folders: Enabled
```

### Finding Your Tenant ID

**Method 1: Azure AD Portal**
1. Go to Azure AD admin center
2. Azure Active Directory > Properties
3. Copy Directory ID

**Method 2: PowerShell**
```powershell
Get-AzureADTenantDetail | Select ObjectId
```

**Method 3: Domain Lookup**
```powershell
Invoke-RestMethod -Uri "https://login.microsoftonline.com/yourdomain.com/.well-known/openid-configuration" | Select -ExpandProperty authorization_endpoint
```

## Examples

### Standard Corporate Deployment

```powershell
.\Install-OneDrive.ps1 `
    -InstallMode PerMachine `
    -EnableSilentConfig `
    -EnableFilesOnDemand `
    -TenantID "12345678-1234-1234-1234-123456789012"
```

### Full KFM Deployment

```powershell
.\Install-OneDrive.ps1 `
    -InstallMode PerMachine `
    -EnableSilentConfig `
    -KnownFolderMove `
    -KFMSilentOptIn `
    -TenantID "12345678-1234-1234-1234-123456789012"
```

### Update Only (No Config Changes)

```powershell
.\Install-OneDrive.ps1 -InstallMode PerMachine -ForceUpdate
```

### Quiet Installation (User Mode)

```powershell
.\Install-OneDrive.ps1 -InstallMode PerUser -DisableAutoStart
```

## Logging

Logs are written to:
```
%ProgramData%\Microsoft\IntuneManagementExtension\Logs\OneDriveInstall.log
```

Example log:
```
[2025-02-19 10:00:00] [INFO] === OneDrive Installation/Update Script Started ===
[2025-02-19 10:00:01] [INFO] Install mode: PerMachine
[2025-02-19 10:00:02] [INFO] OneDrive not currently installed
[2025-02-19 10:00:15] [SUCCESS] Download completed via BITS
[2025-02-19 10:00:45] [SUCCESS] OneDrive installed successfully: 24.010.0114.0003
[2025-02-19 10:00:46] [SUCCESS] Configuration completed
```

## Registry Tracking

Successful operations create:
```
HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\OneDrive
  LastRun = "2025-02-19 10:00:46"
  Installed = "True"
  Updated = "False"
  Version = "24.010.0114.0003"
  InstallMode = "PerMachine"
  Success = "True"
```

## Troubleshooting

### Installation Fails

**Check logs:**
```
%ProgramData%\Microsoft\IntuneManagementExtension\Logs\OneDriveInstall.log
```

**Manual test:**
```powershell
# Download and test install manually
$installer = "$env:TEMP\OneDriveSetup.exe"
Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=844652" -OutFile $installer
& $installer /silent /allusers
```

### Version Not Updating

OneDrive may have been installed via Microsoft Store. Remove Store version first:
```powershell
Get-AppxPackage Microsoft.OneDrive | Remove-AppxPackage
```

### Silent Sign-in Not Working

Verify Tenant ID is correct and silent config policy is enabled:
```powershell
Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive" -Name "SilentAccountConfig"
Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive" -Name "DefaultTenant"
```

### Detection Fails

Run detection manually:
```powershell
.\Detect-OneDrive.ps1
echo $LASTEXITCODE  # 0 = found, 1 = not found
```

### Conflicting Installations

If both per-user and per-machine exist:
```powershell
# Remove per-user first
& "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe" /uninstall

# Then install per-machine
.\Install-OneDrive.ps1 -InstallMode PerMachine
```

## OneDrive Standalone Installer

Download URLs:
- **Per-Machine (All Users)**: `https://go.microsoft.com/fwlink/?linkid=844652`
- **Per-User (Current User)**: `https://go.microsoft.com/fwlink/?linkid=844651`

## Requirements

- Windows 10 (1709+) or Windows 11
- PowerShell 5.1 or higher
- Administrator rights (for PerMachine mode)
- Internet connection for download
- ~150MB free space

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-02-19 | Initial release |

## References

- [OneDrive Deployment Guide](https://docs.microsoft.com/en-us/onedrive/deploy-and-configure-on-macos)
- [Known Folder Move](https://docs.microsoft.com/en-us/onedrive/redirect-known-folders)
- [Silent Account Configuration](https://docs.microsoft.com/en-us/onedrive/use-silent-account-configuration)
- [OneDrive Release Notes](https://support.microsoft.com/en-us/office/onedrive-release-notes-845dcf18-f921-435e-bf28-4e24b95e5fc0)

## License

MIT License — Modify for your environment as needed.
