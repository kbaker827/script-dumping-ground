# Trend Micro Worry-Free Business Security (WFBS) Cloud - Intune Package

Complete Intune deployment package for Trend Micro WFBS Cloud agent.

## Overview

This package provides automated deployment of the Trend Micro WFBS Cloud agent through Microsoft Intune with silent installation, service validation, and proper cleanup.

## Contents

| File | Purpose |
|------|---------|
| `Install-TrendWFBS.ps1` | Downloads and installs the WFBS agent |
| `Uninstall-TrendWFBS.ps1` | Removes WFBS completely |
| `Detect-TrendWFBS.ps1` | Detects if WFBS is installed (for Intune) |

## Prerequisites

### Required: Download URL from Trend Console

You **must** obtain the agent download URL from your Trend WFBS Cloud console:

1. Log in to your **WFBS Cloud Console** (https://wfbs-svc-cloud-us.trendmicro.com)
2. Go to **Devices** → **Add Device**
3. Select **Windows**
4. Click **Download Agent**
5. Copy the download URL (right-click → Copy link address)

**Note:** The URL contains your unique deployment token and is specific to your account.

## Quick Start

### Step 1: Package the Application

1. Download the Microsoft Win32 Content Prep Tool
2. Create folder structure:
   ```
   TrendWFBS/
   ├── Install-TrendWFBS.ps1
   ├── Uninstall-TrendWFBS.ps1
   └── Detect-TrendWFBS.ps1
   ```

3. Run IntuneWinAppUtil:
   ```powershell
   IntuneWinAppUtil.exe -c "C:\TrendWFBS" -s "Install-TrendWFBS.ps1" -o "C:\Output"
   ```

### Step 2: Configure in Intune

1. Go to **Intune Admin Center** → **Apps** → **Windows** → **Add**
2. Select **Windows app (Win32)**
3. Upload the `.intunewin` file

#### App Information
- **Name**: Trend Micro WFBS Cloud Agent
- **Description**: Endpoint security and antivirus protection
- **Publisher**: Trend Micro

#### Program Settings

**Install command:**
```powershell
powershell.exe -ExecutionPolicy Bypass -File "Install-TrendWFBS.ps1" -DownloadURL "https://wfbs-svc-cloud-us.trendmicro.com/..."
```

**Uninstall command:**
```powershell
powershell.exe -ExecutionPolicy Bypass -File "Uninstall-TrendWFBS.ps1"
```

**Install behavior:** System

**Device restart behavior:** No specific action

#### Detection Rules

**Rule type:** Use a custom detection script

Upload: `Detect-TrendWFBS.ps1`

**Run script as 32-bit process on 64-bit clients:** No

**Enforce script signature check:** No

### Step 3: Assignments

- **Required**: Deploy to your target device groups
- Consider a pilot group first for testing

## Script Parameters

### Install Script Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `DownloadURL` | **Yes** | - | Download URL from Trend console |
| `AgentToken` | No | `""` | Deployment token (if not in URL) |
| `LogPath` | No | Intune logs | Path for log files |
| `WaitForService` | No | `$false` | Wait for services to start |
| `ServiceTimeout` | No | `300` | Seconds to wait for services |

### Examples

**Basic installation:**
```powershell
.\Install-TrendWFBS.ps1 -DownloadURL "https://wfbs-svc-cloud-us.trendmicro.com/agentpkg/download?token=..."
```

**Wait for services to confirm startup:**
```powershell
.\Install-TrendWFBS.ps1 -DownloadURL "https://wfbs-svc-cloud-us.trendmicro.com/..." -WaitForService
```

**Custom timeout:**
```powershell
.\Install-TrendWFBS.ps1 -DownloadURL "https://wfbs-svc-cloud-us.trendmicro.com/..." -WaitForService -ServiceTimeout 600
```

## How It Works

### Installation Flow

1. **Validate URL** — Ensures download URL is provided
2. **Check existing install** — Exits if already installed
3. **Download agent** — From Trend cloud using BITS
4. **Silent install** — Executes with `/S /v/qn` flags
5. **Wait for services** — Optionally validates services start
6. **Register completion** — Creates registry marker
7. **Cleanup** — Removes temporary files

### Detection Methods

The detection script verifies:
- Add/Remove Programs registry entry
- Trend Micro services status
- Custom Intune registry marker
- CoreServiceShell.exe presence

### Services Monitored

- Trend Micro Deep Security Manager
- Trend Micro Endpoint Basecamp
- Trend Micro Security Agent
- Trend Micro Listener
- Trend Micro Management Agent

## Logging

Logs are written to:
```
%ProgramData%\Microsoft\IntuneManagementExtension\Logs\
├── TrendWFBSInstall.log        # Install script log
└── TrendWFBSUninstall.log      # Uninstall script log
```

## Troubleshooting

### Installation Fails

**Check the logs:**
```
%ProgramData%\Microsoft\IntuneManagementExtension\Logs\TrendWFBSInstall.log
```

**Common issues:**

**Exit code 1603:**
- Conflicting antivirus software (uninstall other AV first)
- Insufficient permissions (ensure running as SYSTEM)
- Corrupted installer (re-download from Trend console)

**Download fails:**
- Verify URL is complete and not expired
- Check internet connectivity from device
- URL may be IP-restricted in Trend console

**Services don't start:**
- Check Windows Event Logs → Application
- Verify no other AV is blocking Trend
- Allow 5-10 minutes for initial sync with cloud

### Detection Fails

Run detection script manually:
```powershell
.\Detect-TrendWFBS.ps1
echo $LASTEXITCODE  # 0 = detected, 1 = not detected
```

### Device Not Appearing in Console

1. Check agent is actually installed:
   ```powershell
   Get-Service -Name "Trend Micro*"
   ```

2. Verify network connectivity to Trend:
   ```powershell
   Test-NetConnection -ComputerName wfbs-svc-cloud-us.trendmicro.com -Port 443
   ```

3. Check agent logs:
   ```
   %ProgramData%\Trend Micro\Security Agent\Logs\
   ```

4. Allow time for initial cloud sync (up to 15 minutes)

## Getting Your Download URL

### Method 1: From WFBS Cloud Console (Recommended)

1. Log in to https://wfbs-svc-cloud-us.trendmicro.com
2. Navigate to **Devices** → **Add Device**
3. Select **Windows** platform
4. Click **Download Agent** button
5. Right-click the download link → **Copy link address**
6. Use this URL in the install command

### Method 2: Download and Host Internally

1. Download the agent from Trend console
2. Host on your internal web server
3. Use internal URL:
   ```powershell
   .\Install-TrendWFBS.ps1 -DownloadURL "https://internal.company.com/trend/WFBSAgent.exe"
   ```

## Uninstallation

### Standard Uninstall
```powershell
.\Uninstall-TrendWFBS.ps1
```

### Force Uninstall (if standard fails)
```powershell
.\Uninstall-TrendWFBS.ps1 -Force
```

**⚠️ Warning:** Uninstalling removes all endpoint protection. Ensure alternative protection is in place.

## Requirements

- Windows 10 (1809+) or Windows 11
- PowerShell 5.1 or higher
- Administrator rights (runs as SYSTEM in Intune)
- Internet connectivity to Trend cloud
- No conflicting antivirus software

## Security Considerations

- Script runs with SYSTEM privileges
- Downloads executable from specified URL
- Installs kernel-level security drivers
- Creates Windows services

Verify download URL is from legitimate Trend Micro domain:
- ✅ `wfbs-svc-cloud-us.trendmicro.com`
- ✅ `wfbs-svc-cloud-eu.trendmicro.com`
- ✅ `wfbs-svc-cloud-au.trendmicro.com`

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-02-19 | Initial release |

## License

MIT License — Modify for your environment as needed.

## Support

- **Trend Micro Support**: https://success.trendmicro.com
- **WFBS Cloud Documentation**: https://docs.trendmicro.com/en-us/enterprise/worry-free-business-security-services.aspx

## Related Links

- Trend Micro WFBS Cloud: https://wfbs-svc-cloud-us.trendmicro.com
- Intune Win32 App Documentation: https://docs.microsoft.com/en-us/mem/intune/apps/apps-win32-prepare
