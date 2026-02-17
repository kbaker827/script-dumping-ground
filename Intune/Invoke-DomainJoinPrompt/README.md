# Domain Join Prompt Utility

Interactive Windows Forms utility for joining Active Directory domains. Designed for first-logon scenarios, OSD task sequences, or manual domain joining.

## Overview

This PowerShell script provides a user-friendly GUI for domain joining, with validation, pre-flight checks, and optional automation support. It's particularly useful for:
- First-logon scenarios after imaging
- Self-service domain joining for users
- Task sequence steps in OSD
- Migration scenarios

## Features

- ✅ **Pre-flight Checks** - Validates admin rights and current domain status
- ✅ **Network Validation** - Tests DNS and DC connectivity before joining
- ✅ **Modern UI** - Clean Windows Forms interface with proper styling
- ✅ **Flexible Input** - Supports DOMAIN\user or user@domain.com formats
- ✅ **Computer Rename** - Optionally rename computer during join
- ✅ **OU Selection** - Target specific OUs (with picker UI)
- ✅ **Silent Mode** - Automation/scripting support without GUI
- ✅ **Detailed Logging** - Comprehensive logs to %TEMP%
- ✅ **Helpful Errors** - User-friendly error messages with guidance

## Quick Start

### Interactive Mode
```powershell
.\Invoke-DomainJoinPrompt.ps1
```

### Pre-fill Default Domain
```powershell
.\Invoke-DomainJoinPrompt.ps1 -DefaultDomain "corp.contoso.com"
```

### Force Specific Domain
```powershell
.\Invoke-DomainJoinPrompt.ps1 -RequireDomain "corp.contoso.com" -AutoRestart
```

### Silent Mode (Automation)
```powershell
.\Invoke-DomainJoinPrompt.ps1 -Silent -Domain "corp.contoso.com" -Username "admin" -Password "P@ssw0rd" -AutoRestart
```

## Parameters

### GUI Mode Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `DefaultDomain` | string | "" | Pre-populate the domain field |
| `RequireDomain` | string | "" | Force specific domain (read-only) |
| `AllowSkip` | switch | `$false` | Show "Skip" button |
| `AutoRestart` | switch | `$false` | Restart automatically after success |
| `RenameComputer` | switch | `$false` | Allow computer rename during join |
| `OUPicker` | switch | `$false` | Show OU selection dialog |
| `LogPath` | string | `%TEMP%\DomainJoin_*.log` | Custom log path |

### Silent Mode Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `Silent` | switch | `$false` | Run without GUI (automation) |
| `Domain` | string | "" | Domain to join (required for silent) |
| `Username` | string | "" | Domain admin username |
| `Password` | string | "" | Domain admin password |
| `NewName` | string | "" | New computer name |
| `OUPath` | string | "" | Target OU distinguished name |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (domain joined or skipped with -AllowSkip) |
| 1 | Already domain joined |
| 2 | User cancelled or skipped |
| 3 | Missing administrator privileges |
| 4 | Invalid parameters (silent mode) |
| 5 | Domain join failed |
| 6 | Network connectivity issues (silent mode) |

## Examples

### Basic Interactive Join
```powershell
.\Invoke-DomainJoinPrompt.ps1
```
Shows the domain join dialog with all fields empty.

### Pre-fill Domain
```powershell
.\Invoke-DomainJoinPrompt.ps1 -DefaultDomain "ad.contoso.com"
```
Domain field is pre-filled but editable.

### Force Specific Domain
```powershell
.\Invoke-DomainJoinPrompt.ps1 -RequireDomain "CORP" -AutoRestart
```
Domain field is locked to "CORP" and computer restarts automatically on success.

### Allow Computer Rename
```powershell
.\Invoke-DomainJoinPrompt.ps1 -RenameComputer -DefaultDomain "corp.contoso.com"
```
Shows additional field for new computer name.

### Allow Skip
```powershell
.\Invoke-DomainJoinPrompt.ps1 -AllowSkip -DefaultDomain "corp.contoso.com"
```
Adds a "Skip" button for optional domain joining.

### Silent Mode with Auto-Restart
```powershell
.\Invoke-DomainJoinPrompt.ps1 -Silent -Domain "corp.contoso.com" -Username "CORP\admin" -Password "P@ssw0rd" -AutoRestart
```
Joins domain without any GUI interaction and restarts automatically.

### Silent Mode with Rename
```powershell
.\Invoke-DomainJoinPrompt.ps1 -Silent -Domain "corp.contoso.com" -Username "admin@corp.contoso.com" -Password "P@ssw0rd" -NewName "WKSTN-12345" -AutoRestart
```
Renames computer and joins domain in one operation.

### Silent Mode with OU
```powershell
.\Invoke-DomainJoinPrompt.ps1 -Silent -Domain "corp.contoso.com" -Username "admin" -Password "P@ssw0rd" -OUPath "OU=Workstations,OU=Computers,DC=corp,DC=contoso,DC=com"
```
Joins to specific OU.

## Use Cases

### First Logon After Imaging
Deploy with your imaging solution to prompt users to join domain on first logon:

```powershell
# In your SetupComplete.cmd or RunOnce registry
powershell.exe -ExecutionPolicy Bypass -File C:\Windows\Setup\Scripts\Invoke-DomainJoinPrompt.ps1 -DefaultDomain "corp.contoso.com"
```

### OSD Task Sequence (SCCM/MDT)
Add as a step in your task sequence:
- **Command:** `powershell.exe -ExecutionPolicy Bypass -File Invoke-DomainJoinPrompt.ps1 -RequireDomain "CORP"`
- **Timeout:** 10 minutes
- **Run:** After Windows Setup but before first logon

### Self-Service for Users
Place on desktop or Start Menu for users to join domain themselves:

```powershell
.\Invoke-DomainJoinPrompt.ps1 -DefaultDomain "corp.contoso.com" -AllowSkip
```

### Automation Script
For bulk operations or scripts:

```powershell
$computers = Get-Content computers.txt
foreach ($computer in $computers) {
    Invoke-Command -ComputerName $computer -ScriptBlock {
        C:\Scripts\Invoke-DomainJoinPrompt.ps1 -Silent -Domain "corp.contoso.com" -Username "admin" -Password $using:password -AutoRestart
    }
}
```

## How It Works

### GUI Mode Flow
1. **Admin Check** - Validates running as Administrator
2. **Domain Status** - Checks if already domain joined
3. **Form Display** - Shows Windows Forms dialog
4. **Input Validation** - Validates all required fields
5. **Connectivity Test** - Tests DNS and DC connectivity
6. **Domain Join** - Executes Add-Computer with provided credentials
7. **Restart Prompt** - Prompts for restart (or auto-restarts)

### Silent Mode Flow
1. **Parameter Validation** - Ensures required parameters present
2. **Admin Check** - Validates administrator rights
3. **Domain Status** - Checks if already domain joined
4. **Connectivity Test** - Tests domain connectivity
5. **Domain Join** - Executes Add-Computer
6. **Restart** - Restarts if -AutoRestart specified

## Error Handling

The script provides helpful error messages for common issues:

| Error | Message |
|-------|---------|
| Access Denied | "Authentication failed. Please check your username and password. Make sure to use DOMAIN\username or username@domain.com format." |
| Network Path | "Cannot connect to domain controller. Please check network connectivity and DNS settings." |
| Computer Exists | "A computer with this name already exists in the domain. Please choose a different name." |
| Not Admin | "This script requires Administrator privileges. Please right-click and select 'Run as administrator'." |
| Already Joined | "This computer is already joined to domain: X" |

## Logging

All actions are logged to `%TEMP%\DomainJoin_YYYYMMDD_HHmmss.log`

Example log:
```
[2026-02-12 14:30:15] [Info] Domain Join Utility v2.0 started
[2026-02-12 14:30:15] [Info] Computer: DESKTOP-ABC123
[2026-02-12 14:30:15] [Info] User: Administrator
[2026-02-12 14:30:16] [Info] Testing connectivity to corp.contoso.com...
[2026-02-12 14:30:16] [Success] DNS resolution successful: 192.168.1.10
[2026-02-12 14:30:17] [Success] Domain connectivity verified
[2026-02-12 14:30:20] [Info] Starting domain join process...
[2026-02-12 14:30:20] [Info] Domain: corp.contoso.com
[2026-02-12 14:30:20] [Info] Username: CORP\admin
[2026-02-12 14:30:20] [Info] Executing Add-Computer...
[2026-02-12 14:30:25] [Success] Domain join completed successfully!
[2026-02-12 14:30:30] [Info] User chose to restart now
```

## Requirements

- Windows 10/11 Pro, Enterprise, or Education
- PowerShell 5.1 or later
- Administrator privileges
- Network connectivity to domain controller
- .NET Framework (for Windows Forms)

## Security Considerations

⚠️ **Password Handling**
- Passwords are never logged
- Passwords are stored in SecureString during processing
- In silent mode, passwords are passed as plain text (use with caution)

⚠️ **Credential Storage**
- Never hardcode credentials in scripts
- Consider using `-RequireDomain` to prevent typosquatting
- Use service accounts with minimal required permissions

## Customization

### Change UI Colors
Edit the `$script:Theme` hashtable at the top of the script:

```powershell
$script:Theme = @{
    BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)  # Background
    ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)     # Text
    AccentColor = [System.Drawing.Color]::FromArgb(0, 112, 192)  # Button
    ErrorColor = [System.Drawing.Color]::FromArgb(192, 0, 0)     # Errors
    SuccessColor = [System.Drawing.Color]::FromArgb(0, 128, 0)   # Success
}
```

### Add Custom Validation
Add validation logic in the `Show-DomainJoinForm` function:

```powershell
# Example: Require specific username format
if (-not ($username -match "^CORP\\")) {
    Show-ErrorDialog "Username must start with CORP\"
    return Show-DomainJoinForm
}
```

## Troubleshooting

### "Add-Computer" not recognized
Ensure you're running full PowerShell (not PowerShell Core) on Windows.

### Form doesn't appear
Check if Windows Forms assembly is available:
```powershell
Add-Type -AssemblyName System.Windows.Forms
```

### Domain join fails with "RPC server unavailable"
- Check network connectivity to DC
- Verify DNS is configured to point to domain DNS
- Check Windows Firewall rules

### Silent mode returns exit code 4
Ensure all required parameters are provided:
- `-Domain`
- `-Username`
- `-Password`

## Comparison with netdom.exe

| Feature | This Script | netdom.exe |
|---------|-------------|------------|
| GUI | ✅ Yes | ❌ No |
| Pre-validation | ✅ Yes | ❌ No |
| Error Messages | ✅ Friendly | ⚠️ Technical |
| Logging | ✅ Built-in | ❌ Manual |
| Silent Mode | ✅ Yes | ✅ Yes |
| Computer Rename | ✅ Yes | ✅ Yes |
| OU Selection | ✅ Yes | ✅ Yes |

## Version History

### 2.0 (2026-02-12)
- Complete rewrite with professional structure
- Added silent mode for automation
- Added network connectivity validation
- Added computer rename support
- Added OU picker option
- Improved error handling and messages
- Added comprehensive logging
- Added theme customization

### 1.0
- Basic Windows Forms domain join dialog

## See Also

- `Check-IntuneEnrollment.ps1` - For cloud (Azure AD) joining instead of domain joining
- Microsoft Docs: [Add-Computer](https://docs.microsoft.com/powershell/module/microsoft.powershell.management/add-computer)

## License

MIT License - Use at your own risk.
