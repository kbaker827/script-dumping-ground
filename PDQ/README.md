# Intune-to-PDQ Deploy Integration

This package provides scripts to trigger PDQ Deploy packages from Microsoft Intune, allowing you to leverage PDQ's powerful deployment engine while managing assignments through Intune's cloud-based policies.

## Files

| File | Purpose |
|------|---------|
| `Invoke-PDQDeployFromIntune.ps1` | Main PowerShell script that triggers PDQ deployments |
| `Deploy-FromIntune.bat` | Batch wrapper for easy calling from Intune |
| `Detect-PDQDeployment.ps1` | Intune detection script (required for Win32 apps) |
| `Uninstall-PDQDeployment.ps1` | Intune uninstall script (required for Win32 apps) |

## Prerequisites

### Required
- PDQ Deploy installed on a server accessible to target machines
- PDQ Inventory/Deploy agents on target machines, OR PowerShell remoting enabled
- Intune license with Win32 app deployment capability

### Network Requirements
- Target machines must reach PDQ server on required ports (default: 6336 for PDQ)
- For PowerShell remoting: WinRM ports 5985 (HTTP) or 5986 (HTTPS)

## Setup Instructions

### 1. Configure the Scripts

Edit `Invoke-PDQDeployFromIntune.ps1` and update the default parameters:

```powershell
$PDQServer = "YOUR-PDQ-SERVER-NAME"  # Or IP address
$PackageName = "YOUR-PDQ-PACKAGE-NAME"
```

Or pass parameters when calling:
```powershell
.\Invoke-PDQDeployFromIntune.ps1 -PDQServer "pdq01.contoso.com" -PackageName "Chrome-Update-v120"
```

### 2. Create .intunewin Package

1. Download the [Microsoft Win32 Content Prep Tool](https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool)
2. Organize all scripts in a folder (e.g., `C:\IntunePackages\PDQ-Deployer`)
3. Run the prep tool:

```cmd
IntuneWinAppUtil.exe
-c C:\IntunePackages\PDQ-Deployer
-s Invoke-PDQDeployFromIntune.ps1
-o C:\IntunePackages\Output
```

### 3. Create Win32 App in Intune

1. Go to **Microsoft Endpoint Manager admin center**
2. Navigate to **Apps > Windows > Add**
3. Select **Windows app (Win32)**
4. Upload your `.intunewin` file

#### App Information
- **Name**: PDQ Deploy - [Your Package Name]
- **Description**: Triggers PDQ deployment for [software]
- **Publisher**: Your Organization

#### Program Settings
- **Install command**: `powershell.exe -ExecutionPolicy Bypass -File "Invoke-PDQDeployFromIntune.ps1"`
- **Uninstall command**: `powershell.exe -ExecutionPolicy Bypass -File "Uninstall-PDQDeployment.ps1"`
- **Install behavior**: System

#### Detection Rules
- **Rule format**: Use a custom detection script
- **Detection script**: Upload `Detect-PDQDeployment.ps1`
- **Run script as 32-bit process on 64-bit clients**: No

#### Dependencies (Optional)
- Add PDQ Agent as dependency if using PDQ's agent-based deployment

### 4. Update Detection Script

The detection script needs to know how to verify your specific PDQ package completed. Update these sections:

```powershell
# Option 1: Check registry (set by PDQ or your package)
$RegistryKey = "HKLM:\SOFTWARE\YourSoftware"

# Option 2: Check for installed program
$ProgramFilesPaths = @(
    "C:\Program Files\YourSoftware",
    "C:\Program Files (x86)\YourSoftware"
)
```

## Architecture Options

### Option A: PDQ Deploy Installed Locally (Not Recommended)
If PDQ Deploy console is on the target machine, the script runs locally.

### Option B: Remote PDQ Server via PowerShell Remoting (Recommended)
Target machines use PowerShell remoting to call PDQ commands on the central server.

**Enable PowerShell Remoting on targets:**
```powershell
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "pdq-server-name" -Force
```

### Option C: PDQ Agent-Based (Best for Cloud-Managed Devices)
Install PDQ Agent on Intune-managed devices, then use PDQ's built-in cloud features.

## Usage Examples

### Deploy to single machine via Intune
1. Assign the Win32 app to a device group
2. Intune downloads and executes the package
3. Package triggers PDQ deployment
4. Detection script confirms success

### Deploy specific package dynamically
```powershell
# In Intune, use dynamic parameters
.\Invoke-PDQDeployFromIntune.ps1 `
    -PDQServer "pdq01.contoso.com" `
    -PackageName "Firefox-ESR-115" `
    -TargetComputers @($env:COMPUTERNAME) `
    -WaitForCompletion
```

### Batch deployment to multiple machines
```powershell
$Computers = Get-Content "C:\computers.txt"
.\Invoke-PDQDeployFromIntune.ps1 `
    -PackageName "Adobe-Reader-Update" `
    -TargetComputers $Computers `
    -TimeoutMinutes 60
```

## Logging

All activity is logged to:
```
C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\PDQ-Deploy-[timestamp].log
```

View logs on a target machine:
```powershell
Get-Content "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\PDQ-Deploy-*.log" -Tail 50
```

## Troubleshooting

### Issue: "PDQ Deploy not found"
**Cause**: Script cannot find pdqdeploy.exe
**Solution**: Verify PDQ Deploy is installed at `C:\Program Files (x86)\Admin Arsenal\PDQ Deploy\` or update `$PDQDeployPath` in the script.

### Issue: "Access denied" when connecting to PDQ server
**Cause**: PowerShell remoting permissions
**Solution**: 
- Ensure target computer is in PDQ server's TrustedHosts
- Check firewall rules for WinRM (port 5985/5986)
- Verify account has admin rights on PDQ server

### Issue: Intune shows "Not Installed" even after successful deployment
**Cause**: Detection script not finding the right marker
**Solution**: Update `Detect-PDQDeployment.ps1` to check for the actual files/registry your PDQ package creates.

### Issue: Deployment hangs or times out
**Cause**: PDQ package is waiting for user interaction or taking too long
**Solution**: 
- Use `-TimeoutMinutes` parameter
- Ensure PDQ packages run silently (no UI)
- Check PDQ deployment settings for interactive mode

## Security Considerations

1. **PowerShell Execution Policy**: Script bypasses execution policy - ensure your security team approves this approach
2. **Credentials**: The script runs as SYSTEM (Intune default). For cross-domain or workgroup scenarios, you may need to configure CredSSP or store credentials securely
3. **Network**: Ensure WinRM/PowerShell remoting traffic is encrypted (HTTPS) when traversing untrusted networks

## Alternative: Direct PDQ Inventory Integration

If you want Intune to simply trigger PDQ Inventory scans (rather than deployments):

```powershell
# Scan this computer in PDQ Inventory
$Computer = $env:COMPUTERNAME
Invoke-Command -ComputerName $PDQServer -ScriptBlock {
    param($PC)
    & "C:\Program Files (x86)\Admin Arsenal\PDQ Inventory\pdqinventory.exe" Scan $PC
} -ArgumentList $Computer
```

## References

- [PDQ Deploy Documentation](https://www.pdq.com/pdq-deploy/)
- [Intune Win32 App Management](https://docs.microsoft.com/en-us/mem/intune/apps/apps-win32-app-management)
- [Microsoft Win32 Content Prep Tool](https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool)

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-02-16 | Initial release |
