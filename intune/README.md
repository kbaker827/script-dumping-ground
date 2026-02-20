# Intune Scripts Collection

Complete collection of Intune deployment scripts for Windows device management.

## Categories

### Branding
- `Set-CorporateBranding.ps1` — Deploy wallpapers, lock screens, OEM info

### Printers  
- `Add-NetworkPrinter.ps1` — Deploy network printers by IP or print server

### Browsers
- `Set-BrowserConfiguration.ps1` — Configure Chrome/Edge enterprise policies

### Network
- `Add-VPNProfile.ps1` — Deploy VPN connections (IKEv2, SSTP, L2TP)
- `Install-Certificate.ps1` — Install certificates for WiFi/VPN auth

### Maintenance
- `Invoke-DiskCleanup.ps1` — Disk cleanup, temp files, cache clearing

### Inventory
- `Get-SoftwareInventory.ps1` — Audit installed software, export reports

## Monitoring
- `hurricanes_monitor.py` — Carolina Hurricanes schedule alerts
- `comic_events_monitor.py` — NC comic book events and conventions

## Home Assistant
- `ha_control.py` — Control smart home devices from command line

## Usage

Each script includes detailed help:
```powershell
Get-Help .\ScriptName.ps1 -Full
```

All scripts support Intune deployment via Win32 apps or PowerShell scripts.
