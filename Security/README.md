# Security Scripts

Scripts for security auditing and hardening.

## Scripts

### `Invoke-SecurityAudit.ps1`
Performs comprehensive security audit of Windows systems.

**Features:**
- Windows Defender status check
- Firewall configuration verification
- User account security review
- BitLocker encryption status
- Windows Update status
- Software whitelist comparison
- Generates HTML security report with scoring

**Usage:**
```powershell
# Basic audit
.\Invoke-SecurityAudit.ps1

# Detailed report with all checks
.\Invoke-SecurityAudit.ps1 -DetailedReport -ExportPath "C:\Reports\SecurityAudit.html"

# Check against approved software list
.\Invoke-SecurityAudit.ps1 -CheckSoftwareWhitelist -WhitelistFile "approved.json"
```

**Output:**
- Security score (0-100)
- Critical issues list
- Warnings
- Passed checks
- Detailed HTML report

## Requirements

- Windows 10/11
- PowerShell 5.1 or higher
- Administrator rights
