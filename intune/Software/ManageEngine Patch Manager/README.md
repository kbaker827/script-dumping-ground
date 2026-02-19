# ManageEngine Patch Manager Plus Agent - Intune Package

Complete Intune deployment package for ManageEngine Patch Manager Plus agent with install, uninstall, and detection scripts.

## Overview

This package provides automated deployment of the ManageEngine Patch Manager Plus agent through Microsoft Intune. It supports silent installation, proper detection, and clean uninstallation.

## Contents

| File | Purpose |
|------|---------|
| `Install-ManageEngineAgent.ps1` | Downloads and installs the agent |
| `Uninstall-ManageEngineAgent.ps1` | Removes the agent completely |
| `Detect-ManageEngineAgent.ps1` | Detects if agent is installed (for Intune) |

## Prerequisites

- **Server URL**: Your ManageEngine Patch Manager Plus server URL
- **Port**: Default is 8020 (adjust if your server uses different port)
- **Intune Admin Access**: To create and deploy Win32 apps

## Quick Start

### Step 1: Package the Application

1. Download the Microsoft Win32 Content Prep Tool from GitHub
2. Create a folder structure:
   ```
   ManageEngineAgent/
   ├── Install-ManageEngineAgent.ps1
   ├── Uninstall-ManageEngineAgent.ps1
   └── Detect-ManageEngineAgent.ps1
   ```

3. Run the IntuneWinAppUtil:
   ```powershell
   IntuneWinAppUtil.exe -c "C:\ManageEngineAgent" -s "Install-ManageEngineAgent.ps1" -o "C:\Output"
   ```

### Step 2: Configure in Intune

1. Go to **Intune Admin Center** → **Apps** → **Windows** → **Add**
2. Select **Windows app (Win32)**
3. Upload the `.intunewin` file

#### App Information
- **Name**: ManageEngine Patch Manager Plus Agent
- **Description**: Endpoint patch management agent
- **Publisher**: ManageEngine

#### Program Settings

**Install command:**
```powershell
powershell.exe -ExecutionPolicy Bypass -File "Install-ManageEngineAgent.ps1" -ServerURL "https://patch.yourcompany.com" -Port 8020
```

**Uninstall command:**
```powershell
powershell.exe -ExecutionPolicy Bypass -File "Uninstall-ManageEngineAgent.ps1"
```

**Install behavior:** System

**Device restart behavior:** No specific action

#### Detection Rules

**Rule type:** Use a custom detection script

Upload: `Detect-ManageEngineAgent.ps1`

**Run script as 32-bit process on 64-bit clients:** No

**Enforce script signature check:** No

### Step 3: Assignments

- **Required**: Deploy to your target device groups
- **Available**: Optional for users to install

## Script Parameters

### Install Script Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `ServerURL` | Yes* | `""` | Your Patch Manager server URL (e.g., `https://patch.company.com`) |
| `Port` | No | `8020` | Server port number |
| `Protocol` | No | `HTTPS` | Protocol (HTTP or HTTPS) |
| `DownloadURL` | Yes* | `""` | Direct MSI download URL (alternative to ServerURL) |
| `LogPath` | No | Intune logs | Path for log files |

*Either `ServerURL` or `DownloadURL` is required

### Examples

**Standard deployment:**
```powershell
.\Install-ManageEngineAgent.ps1 -ServerURL "https://patch.company.com" -Port 8020
```

**Direct download URL:**
```powershell
.\Install-ManageEngineAgent.ps1 -DownloadURL "https://patch.company.com:8020/agent/Agent.msi"
```

**Custom log location:**
```powershell
.\Install-ManageEngineAgent.ps1 -ServerURL "https://patch.company.com" -LogPath "C:\Logs"
```

## How It Works

### Installation Flow

1. **Check for existing installation** — Exits if already installed
2. **Download agent MSI** — From your Patch Manager server using BITS
3. **Silent install** — Using msiexec with `/qn` switch
4. **Start service** — Ensures PatchManagerAgent service is running
5. **Register completion** — Creates registry key for detection
6. **Cleanup** — Removes temporary download files

### Detection Methods

The detection script uses multiple methods to verify installation:
- Registry entry check (Add/Remove Programs)
- Service status check
- Custom registry marker
- Executable file presence

### Uninstallation Flow

1. **Stop processes** — Terminates agent processes and service
2. **Run uninstaller** — Uses MSI or EXE uninstall string from registry
3. **Remove residuals** — Cleans up files, registry, and service entries

## Logging

Logs are written to:
```
%ProgramData%\Microsoft\IntuneManagementExtension\Logs\
├── ManageEngineAgentInstall.log       # Install script log
├── ManageEngineAgentUninstall.log     # Uninstall script log
└── ManageEngineAgent_Install.log      # MSI verbose log (during install)
```

## Troubleshooting

### Installation Fails

**Check the logs:**
```
%ProgramData%\Microsoft\IntuneManagementExtension\Logs\ManageEngineAgentInstall.log
```

**Common issues:**
- **Exit code 1603**: Fatal error during installation
  - Check MSI verbose log for details
  - Ensure .NET Framework is installed
  - Verify sufficient disk space

- **Download fails**: 
  - Verify server URL is accessible from client
  - Check firewall rules for port 8020
  - Try using `DownloadURL` parameter directly

- **Access denied**: 
  - Ensure script runs as SYSTEM (Intune default)
  - Check execution policy: `Set-ExecutionPolicy Bypass`

### Detection Fails

Run detection script manually:
```powershell
.\Detect-ManageEngineAgent.ps1
echo $LASTEXITCODE  # 0 = detected, 1 = not detected
```

### Service Won't Start

1. Check Windows Event Viewer → Application logs
2. Verify Patch Manager server is reachable
3. Check for port conflicts

## Finding Your Server Details

### Server URL
In your ManageEngine Patch Manager Plus console:
1. Go to **Admin** → **Agent Settings**
2. Look for "Agent Communication Settings"
3. Note the **Server Name/IP** and **Port**

### Direct Download URL
The agent MSI is typically available at:
```
https://<server>:<port>/agent/Agent.msi
```

Example:
```
https://patch.company.com:8020/agent/Agent.msi
```

## Customization

### Adding Proxy Configuration

If your environment requires a proxy, modify the install script:

```powershell
# Add to Install-ManageEngineAgent.ps1 before download
[System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy("http://proxy.company.com:8080")
[System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
```

### Custom Installation Directory

Modify the MSI properties in the install script:

```powershell
$msiProperties += "INSTALLDIR=`"C:\Custom\Path`""
```

## Requirements

- Windows 10 (1809+) or Windows 11
- PowerShell 5.1 or higher
- Administrator rights (runs as SYSTEM in Intune)
- Network connectivity to Patch Manager server

## Security Considerations

- Script requires administrator privileges
- Downloads executable content from your internal server
- Creates and starts a Windows service
- Stores configuration in HKLM registry

## Support

- **ManageEngine Documentation**: https://www.manageengine.com/patch-management/
- **Intune Documentation**: https://docs.microsoft.com/en-us/mem/intune/apps/apps-win32-prepare

## License

MIT License — Feel free to modify for your environment.

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-02-19 | Initial release |
