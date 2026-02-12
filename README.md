# Microsoft Office 365 Removal Scripts

Cross-platform scripts to completely remove Microsoft Office 365 from macOS and Windows systems.

## Overview

These scripts provide IT administrators with a clean, automated way to remove Microsoft Office 365 applications and all related files from end-user devices. They handle multiple installation types (Click-to-Run, MSI, standalone apps) and clean up all traces including preferences, caches, licenses, and registry entries.

### Key Features

- **Cross-platform:** Separate scripts for macOS and Windows
- **Comprehensive removal:** Apps, settings, caches, licenses, and installer files
- **Selective cleanup:** Preserves Microsoft Teams and OneDrive
- **Safe execution:** Confirmation prompts and graceful error handling
- **Administrator-ready:** Suitable for deployment tools (SCCM, Intune, Jamf)

## What's Included

| Script | Platform | File |
|--------|----------|------|
| macOS Removal | macOS | `macos/remove-office365.sh` |
| Windows Removal | Windows | `windows/Remove-Office365.ps1` |

## What Gets Removed

- **Office Applications:**
  - Microsoft Word
  - Microsoft Excel
  - Microsoft PowerPoint
  - Microsoft Outlook
  - Microsoft OneNote
  - Microsoft Access (Windows)
  - Microsoft Publisher (Windows)

- **Data & Settings:**
  - User preferences and caches
  - Application containers/sandboxes
  - Registry entries (Windows)
  - License and activation data
  - Saved application states

- **System Components:**
  - Program files and folders
  - Scheduled tasks and services
  - Installer receipts (macOS)
  - Downloaded installer files

## What's Preserved

- **Microsoft Teams** - Intentionally not removed
- **OneDrive** - Intentionally not removed
- **User documents** - Your files stay in Documents

## Quick Start

### macOS
```bash
sudo ./macos/remove-office365.sh
```

### Windows
```powershell
.\windows\Remove-Office365.ps1
```

## Detailed Documentation

- [macOS README](macos/README.md) - macOS-specific details
- [Windows README](windows/README.md) - Windows-specific details

## Use Cases

- **Migrating to web-based Office** - Remove desktop apps when moving to Office Online
- **License compliance** - Clean removal for license reclamation
- **Troubleshooting** - Complete fresh install prep when Office is corrupted
- **Device decommissioning** - Sanitize machines before reassignment
- **Standardization** - Enforce specific Office versions across org

## Safety Notes

⚠️ **These scripts permanently delete data.**

- Office will need to be reinstalled if needed later
- All Office preferences and settings will be lost
- Document files in your Documents folder are NOT deleted
- Run with appropriate privileges (sudo on macOS, Administrator on Windows)

## License

MIT License - Use, modify, and distribute freely.

## Contributing

This is a utility repository for IT scripts. Feel free to fork and adapt to your organization's needs.

## Support

These scripts are provided as-is. Test in your environment before production deployment. See individual README files for troubleshooting tips.
