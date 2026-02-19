# Autopilot Computer Rename Script

PowerShell script to rename computers during Windows Autopilot enrollment, with full support for Hybrid Azure AD Join scenarios.

## Overview

This script handles computer renaming during the Autopilot enrollment process, ensuring proper naming conventions are applied whether the device is:
- Hybrid Azure AD Joined (on-prem AD + Azure AD)
- Azure AD Joined only
- Workgroup (pre-domain join)

## Features

- ✅ **Autopilot ESP Aware** — Detects enrollment status page context
- ✅ **Hybrid Join Support** — Handles domain-joined machines correctly
- ✅ **Flexible Naming** — Serial number, asset tag, or custom name
- ✅ **Logging** — Detailed logs to Intune log folder
- ✅ **Detection Marker** — Creates marker file for Intune compliance
- ✅ **Safe Naming** — Validates NetBIOS naming conventions
- ✅ **Optional Restart** — Can trigger restart after rename

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `NewComputerName` | String | `""` | Specify exact computer name (bypasses auto-generation) |
| `NamingPrefix` | String | `CORP` | Prefix for auto-generated names |
| `UseSerialNumber` | Switch | `$false` | Append serial number to prefix |
| `MaxSerialLength` | Int | `12` | Max characters from serial number |
| `DomainName` | String | `""` | Domain name (for hybrid join context) |
| `RestartAfterRename` | Switch | `$false` | Automatically restart after rename |

## Usage Examples

### Example 1: Rename using serial number
```powershell
.\Rename-Computer-Autopilot.ps1 -NamingPrefix "CORP" -UseSerialNumber -RestartAfterRename
# Result: CORP-C02ABC123456
```

### Example 2: Specific computer name
```powershell
.\Rename-Computer-Autopilot.ps1 -NewComputerName "CORP-IT-001"
```

### Example 3: Asset tag based (automatic fallback)
```powershell
.\Rename-Computer-Autopilot.ps1 -NamingPrefix "LAPTOP"
# Tries asset tag first, falls back to serial if unavailable
```

## Deployment Options

### Option 1: Intune Win32 App (Recommended)

1. **Create folder structure:**
   ```
   Rename-Computer/
   ├── Rename-Computer-Autopilot.ps1
   └── Rename-Computer.intunewin
   ```

2. **Create install command:**
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File "Rename-Computer-Autopilot.ps1" -NamingPrefix "CORP" -UseSerialNumber -RestartAfterRename
   ```

3. **Detection rule:** Check for marker file:
   ```
   Path: %ProgramData%\AutopilotRename
   File: rename-completed.marker
   ```

4. **Assign** to Autopilot device group during ESP

### Option 2: Intune PowerShell Script

1. In Intune Admin Center, go to **Devices** → **PowerShell Scripts**
2. Upload `Rename-Computer-Autopilot.ps1`
3. Configure settings:
   - **Run this script using the logged on credentials:** No
   - **Enforce script signature check:** No
   - **Run script in 64 bit PowerShell:** Yes
4. Assign to Autopilot device group

### Option 3: Proactive Remediation

For post-enrollment rename scenarios:

**Detection Script:**
```powershell
$marker = "$env:ProgramData\AutopilotRename\rename-completed.marker"
if (Test-Path $marker) { exit 0 } else { exit 1 }
```

**Remediation Script:**
```powershell
& ".\Rename-Computer-Autopilot.ps1" -NamingPrefix "CORP" -UseSerialNumber
```

## Naming Logic

The script follows this priority order when auto-generating names:

1. **Explicit name** — If `NewComputerName` is provided, use it
2. **Asset tag** — Query WMI for SMBIOS asset tag
3. **Serial number** — Fall back to BIOS serial number
4. **Clean & truncate** — Remove invalid chars, ensure ≤15 chars (NetBIOS limit)

## Logging

Logs are written to:
```
%ProgramData%\Microsoft\IntuneManagementExtension\Logs\AutopilotComputerRename.log
```

Example log output:
```
[2025-02-19 14:30:15] [INFO] === Autopilot Computer Rename Script Started ===
[2025-02-19 14:30:15] [INFO] Current computer name: DESKTOP-ABC123
[2025-02-19 14:30:15] [INFO] Target computer name: CORP-C02ABC123456
[2025-02-19 14:30:16] [SUCCESS] Computer successfully renamed to: CORP-C02ABC123456
```

## Hybrid Join Considerations

When deploying in a Hybrid Azure AD Join scenario:

1. **Timing:** The script detects domain join status and handles appropriately
2. **Permissions:** Runs as SYSTEM (required for domain-joined renames during ESP)
3. **Sync:** After rename, allow time for Azure AD Connect sync
4. **Restart:** Recommended to let rename fully propagate

## Troubleshooting

### Issue: "Access denied" error
**Solution:** Ensure script runs as SYSTEM (Intune default) or with domain admin rights for domain-joined machines

### Issue: Name not changing immediately
**Solution:** Restart required. Use `-RestartAfterRename` or schedule restart separately

### Issue: Serial number not found
**Solution:** Check BIOS/firmware version. Some VMs may not expose serial numbers

### Issue: Intune detection fails
**Solution:** Verify marker file exists at `%ProgramData%\AutopilotRename\rename-completed.marker`

## Requirements

- Windows 10 (1809+) or Windows 11
- PowerShell 5.1 or higher
- Run as Administrator/SYSTEM
- Intune enrolled (for Autopilot scenarios)

## License

MIT License — Feel free to use and modify as needed.

## Author

Created for Intune/Autopilot deployments with Hybrid Azure AD Join support.
