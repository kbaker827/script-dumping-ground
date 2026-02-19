# TightVNC Server - Intune Package

Complete Intune deployment package for TightVNC Server with automated password configuration and security hardening.

## Overview

This package provides automated deployment of TightVNC Server through Microsoft Intune with:
- Silent installation
- Automatic password configuration
- Windows Firewall rule creation
- Service management
- Security hardening

## ⚠️ Security Notice

**TightVNC transmits data unencrypted by default.** For production use:
- Consider using SSH tunneling or VPN for remote access
- Restrict access using firewall rules
- Use strong passwords (max 8 characters for VNC auth)
- Enable view-only passwords for shared access

## Contents

| File | Purpose |
|------|---------|
| `Install-TightVNC.ps1` | Downloads, installs, and configures TightVNC |
| `Uninstall-TightVNC.ps1` | Removes TightVNC completely |
| `Detect-TightVNC.ps1` | Detects if TightVNC is installed (for Intune) |

## Quick Start

### Step 1: Package the Application

1. Download the Microsoft Win32 Content Prep Tool from GitHub
2. Create a folder structure:
   ```
   TightVNC/
   ├── Install-TightVNC.ps1
   ├── Uninstall-TightVNC.ps1
   └── Detect-TightVNC.ps1
   ```

3. Run the IntuneWinAppUtil:
   ```powershell
   IntuneWinAppUtil.exe -c "C:\TightVNC" -s "Install-TightVNC.ps1" -o "C:\Output"
   ```

### Step 2: Configure in Intune

1. Go to **Intune Admin Center** → **Apps** → **Windows** → **Add**
2. Select **Windows app (Win32)**
3. Upload the `.intunewin` file

#### App Information
- **Name**: TightVNC Server
- **Description**: Remote desktop access via VNC protocol
- **Publisher**: GlavSoft LLC

#### Program Settings

**Install command:**
```powershell
powershell.exe -ExecutionPolicy Bypass -File "Install-TightVNC.ps1" -VNCPassword "YourSecurePwd"
```

**Uninstall command:**
```powershell
powershell.exe -ExecutionPolicy Bypass -File "Uninstall-TightVNC.ps1"
```

**Install behavior:** System

**Device restart behavior:** No specific action

#### Detection Rules

**Rule type:** Use a custom detection script

Upload: `Detect-TightVNC.ps1`

**Run script as 32-bit process on 64-bit clients:** No

**Enforce script signature check:** No

### Step 3: Assignments

- **Required**: Deploy to your target device groups
- **Available**: Optional for users to install

## Script Parameters

### Install Script Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `VNCPassword` | **Yes** | - | Main VNC authentication password |
| `ViewerPassword` | No | `""` | View-only password (empty = disabled) |
| `Port` | No | `5900` | VNC server port |
| `DownloadURL` | No | Official | Direct URL to TightVNC MSI |
| `LogPath` | No | Intune logs | Path for log files |
| `AllowLoopback` | No | `$false` | Allow localhost connections |
| `AllowOnlyLoopback` | No | `$false` | Only allow localhost connections |

### Examples

**Basic installation:**
```powershell
.\Install-TightVNC.ps1 -VNCPassword "Admin123"
```

**With view-only access:**
```powershell
.\Install-TightVNC.ps1 -VNCPassword "Admin123" -ViewerPassword "ViewOnly456"
```

**Custom port:**
```powershell
.\Install-TightVNC.ps1 -VNCPassword "Admin123" -Port 5901
```

**Localhost only (most secure):**
```powershell
.\Install-TightVNC.ps1 -VNCPassword "Admin123" -AllowOnlyLoopback
```

## Configuration Details

### Default Security Settings

The script applies these security configurations:

| Setting | Value | Purpose |
|---------|-------|---------|
| `AcceptHttpConnections` | 0 | Disable web-based access |
| `UseVncAuthentication` | 1 | Require password authentication |
| `AllowLoopback` | Configurable | Localhost access control |
| `RemoveWallpaper` | 0 | Keep wallpaper for better UX |
| `CaptureAlphaBlending` | 1 | Better visual quality |

### Windows Firewall

The script automatically creates an inbound firewall rule:
- **Name**: `TightVNC Server - Port XXXX`
- **Protocol**: TCP
- **Port**: Configurable (default 5900)
- **Profile**: Domain, Private
- **Action**: Allow

To modify the firewall rule for additional security:
```powershell
# Restrict to specific IPs
Set-NetFirewallRule -DisplayName "TightVNC Server*" -RemoteAddress "10.0.0.0/24"
```

## Password Encryption

TightVNC stores passwords using its internal encryption. This script:
1. Uses `tvnserver.exe -controlapp -password` to set passwords properly
2. Never stores plaintext passwords in registry or logs
3. Automatically encrypts using TightVNC's DES-based encryption

**Note:** VNC authentication uses maximum 8 characters. Longer passwords are truncated.

## How It Works

### Installation Flow

1. **Check existing installation** — Skips if already installed (unless password provided)
2. **Download MSI** — From official TightVNC source or your URL
3. **Silent install** — MSI with `/qn` and `ADDLOCAL=Server`
4. **Configure password** — Uses tvnserver control interface
5. **Apply settings** — Registry configuration for security
6. **Create firewall rule** — Windows Firewall inbound allow
7. **Start service** — Automatic start, set to Automatic startup
8. **Register completion** — Registry marker for detection

### Detection Methods

The detection script verifies:
- Add/Remove Programs registry entry
- TightVNC Server service status
- Custom Intune registry marker
- Executable file presence

## Logging

Logs are written to:
```
%ProgramData%\Microsoft\IntuneManagementExtension\Logs\
├── TightVNCInstall.log              # Install script log
├── TightVNCUninstall.log            # Uninstall script log
└── TightVNC_Install.log             # MSI verbose log
```

## Troubleshooting

### Installation Fails

**Check the logs:**
```
%ProgramData%\Microsoft\IntuneManagementExtension\Logs\TightVNCInstall.log
```

**Common issues:**
- **Exit code 1603**: Check if Visual C++ Redistributables are installed
- **Password not set**: Ensure running as SYSTEM with access to TightVNC installation
- **Service won't start**: Check for port conflicts (another VNC or remote desktop tool)

### Cannot Connect

1. **Check firewall rule:**
   ```powershell
   Get-NetFirewallRule -DisplayName "TightVNC*"
   ```

2. **Verify service is running:**
   ```powershell
   Get-Service -Name "TightVNC Server"
   ```

3. **Check port is listening:**
   ```powershell
   netstat -an | findstr 5900
   ```

4. **Verify password is set:**
   ```powershell
   & "C:\Program Files\TightVNC\tvnserver.exe" -controlapp -testauth
   ```

### Detection Fails

Run detection script manually:
```powershell
.\Detect-TightVNC.ps1
echo $LASTEXITCODE  # 0 = detected, 1 = not detected
```

## Network Access

### Port Numbers

| Display | Port Number | Description |
|---------|-------------|-------------|
| 0 | 5900 | Default VNC port |
| 1 | 5901 | Display :1 |
| 2 | 5902 | Display :2 |

To connect: `<computer-ip>:5900` or `<computer-ip>::5900` depending on viewer

### Securing Access

**Option 1: Restrict by IP (recommended)**
```powershell
# After installation, modify firewall rule
Set-NetFirewallRule -DisplayName "TightVNC Server*" `
    -RemoteAddress "10.0.0.0/8", "192.168.1.0/24"
```

**Option 2: SSH Tunneling**
```bash
# From client machine
ssh -L 5900:localhost:5900 user@remote-computer
# Then connect VNC viewer to localhost:5900
```

**Option 3: VPN Only**
```powershell
# Modify firewall to only allow VPN adapter
Set-NetFirewallRule -DisplayName "TightVNC Server*" `
    -InterfaceType RAS
```

## Customization

### Using Internal Mirror

If you host TightVNC internally:

```powershell
.\Install-TightVNC.ps1 `
    -VNCPassword "Secure123" `
    -DownloadURL "https://internal.company.com/software/tightvnc.msi"
```

### Different TightVNC Version

Update the `$DefaultDownloadURL` variable in the install script or use `-DownloadURL` parameter.

Latest versions available at: https://www.tightvnc.com/download.php

## Requirements

- Windows 10 (1809+) or Windows 11
- PowerShell 5.1 or higher
- Administrator rights (runs as SYSTEM in Intune)
- Network access to download installer (or internal mirror)
- Visual C++ Redistributables (usually already installed)

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-02-19 | Initial release |

## License

MIT License — Modify for your environment as needed.

## Disclaimer

This script automates TightVNC deployment but does not modify TightVNC's underlying security model. TightVNC uses the RFV protocol which does not encrypt traffic. Use appropriate network-level security (VPN, SSH tunneling, etc.) for sensitive environments.
