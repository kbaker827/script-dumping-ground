# Wireless (Wi-Fi) Profile Deployment - Intune Package

PowerShell scripts to deploy wireless (Wi-Fi) network profiles to Windows 10/11 devices via Microsoft Intune.

## Overview

This package provides scripts to install, remove, and detect Wi-Fi network profiles on Windows devices. Supports various security types including WPA2/WPA3 Personal and Enterprise (802.1X).

## Contents

| File | Purpose |
|------|---------|
| `Install-WirelessProfile.ps1` | Installs Wi-Fi profiles from XML or parameters |
| `Remove-WirelessProfile.ps1` | Removes Wi-Fi profiles |
| `Detect-WirelessProfile.ps1` | Detects if profile is installed (for Intune) |

## Supported Security Types

- **Open** - No authentication
- **WEP** - Wired Equivalent Privacy (legacy, not recommended)
- **WPA2Personal** - WPA2 with Pre-Shared Key (PSK)
- **WPA2Enterprise** - WPA2 with 802.1X authentication
- **WPA3Personal** - WPA3-SAE with Pre-Shared Key
- **WPA3Enterprise** - WPA3 with 802.1X authentication

## Quick Start

### Method 1: Using Exported XML Profile (Recommended)

**Export a profile from a configured Windows device:**
```cmd
netsh wlan export profile name="YourWiFi" folder=C:\WiFi folder= key=clear
```

**Deploy via Intune:**
```powershell
.\Install-WirelessProfile.ps1 -ProfileXML "C:\WiFi\YourWiFi.xml"
```

### Method 2: Using Parameters (WPA2 Personal)

```powershell
.\Install-WirelessProfile.ps1 `
    -ProfileName "CorpWiFi" `
    -SecurityType WPA2Personal `
    -PSK "YourSecurePassword123" `
    -ConnectAutomatically `
    -MakeDefault
```

### Method 3: Using Parameters (WPA2 Enterprise)

```powershell
.\Install-WirelessProfile.ps1 `
    -ProfileName "CorpWiFi" `
    -SecurityType WPA2Enterprise `
    -EAPType PEAP `
    -ServerNames "radius.company.com" `
    -TrustedRootCA "ABCDEF1234567890ABCDEF1234567890ABCDEF12"
```

## Intune Deployment

### As Win32 App

1. **Prepare your files:**
   ```
   WirelessProfile/
   ├── Install-WirelessProfile.ps1
   ├── Remove-WirelessProfile.ps1
   ├── Detect-WirelessProfile.ps1
   └── YourWiFi.xml (if using XML method)
   ```

2. **Create .intunewin package:**
   ```powershell
   IntuneWinAppUtil.exe -c "C:\WirelessProfile" -s "Install-WirelessProfile.ps1" -o "C:\Output"
   ```

3. **Configure in Intune:**
   - **Name**: Corporate Wi-Fi Profile
   - **Description**: Deploys corporate wireless network

4. **Program Settings:**

   **Install command (XML method):**
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File "Install-WirelessProfile.ps1" -ProfileXML ".\YourWiFi.xml" -MakeDefault
   ```

   **Install command (Parameter method):**
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File "Install-WirelessProfile.ps1" -ProfileName "CorpWiFi" -SecurityType WPA2Personal -PSK "Password123" -ConnectAutomatically
   ```

   **Uninstall command:**
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File "Remove-WirelessProfile.ps1" -ProfileName "CorpWiFi"
   ```

5. **Detection Rules:**
   - Use custom detection script: `Detect-WirelessProfile.ps1`
   - Detection script parameter: `-ProfileName "CorpWiFi"`

### As PowerShell Script

Deploy directly through Intune PowerShell scripts:
```powershell
.\Install-WirelessProfile.ps1 -ProfileXML "C:\CorpWiFi.xml" -ConnectAutomatically
```

## Script Parameters

### Install-WirelessProfile.ps1

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `ProfileXML` | No* | - | Path to exported XML profile |
| `ProfileName` | No* | - | Wi-Fi profile name (if not using XML) |
| `SSID` | No | ProfileName | Network SSID (if different from ProfileName) |
| `SecurityType` | No | WPA2Personal | Security type (see supported types) |
| `PSK` | No | - | Pre-shared key (password) |
| `EAPType` | No | - | EAP type for Enterprise (PEAP, TLS, TTLS) |
| `EAPMethod` | No | - | EAP authentication method |
| `ServerNames` | No | - | RADIUS server names (comma-separated) |
| `TrustedRootCA` | No | - | Root CA certificate thumbprint |
| `ConnectAutomatically` | No | `$true` | Auto-connect when in range |
| `ConnectHidden` | No | `$false` | Connect to hidden SSID |
| `MakeDefault` | No | `$false` | Set as preferred network |

*Either `ProfileXML` or `ProfileName` is required

### Remove-WirelessProfile.ps1

| Parameter | Required | Description |
|-----------|----------|-------------|
| `ProfileName` | **Yes** | Name of profile to remove |

### Detect-WirelessProfile.ps1

| Parameter | Required | Description |
|-----------|----------|-------------|
| `ProfileName` | **Yes** | Name of profile to detect |

## Exporting Wi-Fi Profiles

### From Windows GUI

1. Connect to the Wi-Fi network
2. Open Command Prompt as Administrator
3. Run:
   ```cmd
   netsh wlan export profile name="YourNetworkName" folder=C:\WiFiProfiles key=clear
   ```

### Export All Profiles

```cmd
netsh wlan export profile folder=C:\WiFiProfiles key=clear
```

### Export Without Password (safer for sharing)

```cmd
netsh wlan export profile name="YourNetworkName" folder=C:\WiFiProfiles
```

## Security Considerations

### Password Handling

- Passwords in XML files should be protected
- Consider using certificates for Enterprise networks
- Don't commit passwords to version control
- Use Intune's encrypted script parameters when possible

### Enterprise (802.1X) Configuration

For WPA2/WPA3 Enterprise, additional configuration is required:

1. **Certificate Deployment**: Deploy client certificates via Intune
2. **Server Validation**: Configure RADIUS server names and trusted root CA
3. **EAP Type**: Choose appropriate EAP type (PEAP is most common)

### Certificate Thumbprint

Get root CA thumbprint:
```powershell
Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object { $_.Subject -like "*Your CA*" } | Select-Object Thumbprint, Subject
```

## Logging

Logs are written to:
```
%ProgramData%\Microsoft\IntuneManagementExtension\Logs\
├── WirelessProfileInstall.log
└── WirelessProfileRemove.log
```

## Troubleshooting

### Profile Not Installing

**Check logs:**
```
%ProgramData%\Microsoft\IntuneManagementExtension\Logs\WirelessProfileInstall.log
```

**Test manually:**
```powershell
# Check if profile already exists
netsh wlan show profile name="YourProfile"

# List all profiles
netsh wlan show profiles

# Import manually for testing
netsh wlan add profile filename="C:\WiFi\YourProfile.xml"
```

### No Wireless Adapter

Script will log a warning but continue. Profile will be available when adapter is present.

### Detection Fails

Run detection manually:
```powershell
.\Detect-WirelessProfile.ps1 -ProfileName "CorpWiFi"
echo $LASTEXITCODE  # 0 = found, 1 = not found
```

### Enterprise Authentication Issues

1. Verify certificates are installed
2. Check RADIUS server accessibility
3. Validate EAP configuration
4. Check Windows Event Logs → Microsoft-Windows-WLAN-AutoConfig

### XML Profile Issues

**Validate XML format:**
```powershell
[xml]$xml = Get-Content "C:\WiFi\profile.xml"
$xml.WLANProfile.name
```

**Common issues:**
- XML encoding must be UTF-8
- Profile name in XML must match target
- Special characters in SSID need proper escaping

## Examples

### Basic Home Network (WPA2)

```powershell
.\Install-WirelessProfile.ps1 `
    -ProfileName "HomeWiFi" `
    -SecurityType WPA2Personal `
    -PSK "MyHomePassword" `
    -ConnectAutomatically
```

### Corporate Network (WPA2 Enterprise with PEAP)

```powershell
.\Install-WirelessProfile.ps1 `
    -ProfileName "CorpWiFi" `
    -SecurityType WPA2Enterprise `
    -EAPType PEAP `
    -ServerNames "radius1.company.com,radius2.company.com" `
    -TrustedRootCA "A1B2C3D4E5F6..." `
    -ConnectAutomatically
```

### Hidden Network

```powershell
.\Install-WirelessProfile.ps1 `
    -ProfileName "HiddenCorp" `
    -SSID "HiddenCorp" `
    -SecurityType WPA2Personal `
    -PSK "Password123" `
    -ConnectHidden `
    -ConnectAutomatically
```

### Guest Network (Open)

```powershell
.\Install-WirelessProfile.ps1 `
    -ProfileName "GuestWiFi" `
    -SecurityType Open `
    -ConnectAutomatically:$false
```

## Requirements

- Windows 10 (1809+) or Windows 11
- PowerShell 5.1 or higher
- Administrator rights (for profile management)
- Wireless adapter (optional - profile will install regardless)

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-02-19 | Initial release |

## References

- [Netsh WLAN Commands](https://docs.microsoft.com/en-us/windows-server/networking/technologies/netsh/netsh-wlan)
- [WLAN Profile Schema](https://docs.microsoft.com/en-us/windows/win32/nativewifi/wlan-profileschema-elements)
- [Intune Wi-Fi Settings](https://docs.microsoft.com/en-us/mem/intune/configuration/wi-fi-settings-configure)

## License

MIT License — Modify for your environment as needed.
