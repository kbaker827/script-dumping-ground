# Script Dumping Ground

A collection of PowerShell, Python, and Bash scripts for IT administration, automation, and monitoring.

## 📁 Repository Structure

### **Intune/**
Windows deployment and management scripts for Microsoft Intune.

| Category | Description |
|----------|-------------|
| **Branding/** | Corporate wallpaper, lock screen, OEM configuration |
| **Browsers/** | Chrome/Edge enterprise configuration |
| **Computer Rename/** | Autopilot computer rename with hybrid join support |
| **Copy Folder Script/** | Folder deployment with config files |
| **Inventory/** | Software inventory and auditing |
| **Maintenance/** | Disk cleanup, system maintenance |
| **Network/** | VPN profiles, certificates, WiFi profiles |
| **Printers/** | Network printer deployment |
| **Software/** | Third-party software installers (TightVNC, Trend WFBS, etc.) |
| **Wireless Profile Copy/** | WiFi profile deployment |

### **Band Tour Monitor/**
Concert tour date monitoring for 17 bands in North Carolina.

### **HomeAssistant/**
Smart home automation and control scripts.

### **Maintenance/**
Backup verification and system health checks.

### **Monitoring/**
Event and schedule monitoring:
- Hurricanes NHL games
- Comic book conventions and store events
- Local comic shop event scrapers

### **Security/**
Security auditing and hardening scripts.

### **Utils/**
Repository management and dependency checking tools.

## 🚀 Quick Start

### Band Tour Monitor
```bash
cd "Band Tour Monitor"
python3 band_tour_monitor.py --setup
python3 band_tour_monitor.py --test
```

### Intune Scripts
```powershell
# Example: Deploy WiFi profile
.\Intune\Wireless Profile Copy\Install-WirelessProfile.ps1 -ProfileXML "wifi.xml"

# Example: Install software
.\Intune\Software\Dell Command Update\Install-DellCommandUpdate.ps1 -NoReboot
```

### Home Assistant Control
```bash
python3 HomeAssistant/ha_control.py dashboard
python3 HomeAssistant/ha_control.py on light.kitchen
```

## 📊 Stats

- **105+ scripts** across multiple categories
- **17 bands** monitored for concerts
- **8 comic shops** tracked for events
- **NHL team** schedule monitoring
- **Automated documentation** generation

## 🔄 Automation

These scripts are designed to run via:
- **OpenClaw Heartbeat** - Automated periodic checks
- **Intune** - Windows device management
- **Cron** - Scheduled task execution
- **Manual execution** - One-off operations

## 📝 Recent Updates

- Added 17 bands to tour monitor
- Added Carolina Hurricanes schedule tracking
- Added comic book event monitoring
- Added local comic shop scraper
- Added security audit script
- Added backup verification
- Added dependency checker
- Added auto-documentation tool

## ⚠️ Security Note

Scripts in this repository require Administrator/root privileges in many cases. Review scripts before running in production environments.

## 📄 License

MIT License - Feel free to use and modify.

---

*Last updated: February 2026*