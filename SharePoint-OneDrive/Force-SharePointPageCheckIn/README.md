# SharePoint Force Check-In Tool

PowerShell utility to force check-in, publish, and approve SharePoint Online pages that are stuck in a checked-out state by users who may no longer be available.

## Overview

When SharePoint pages are left checked out by departed employees or users who are unavailable, they can block publishing workflows and prevent others from editing. This script provides administrative tools to:

- Force check-in pages checked out by any user
- Discard pending checkouts
- Publish and approve pages automatically
- Handle bulk operations across multiple pages

## Features

- ✅ **Force Check-In** - Override any user's checkout
- ✅ **Auto-Publish** - Publish after check-in (optional)
- ✅ **Auto-Approve** - Approve after publish (optional)
- ✅ **Bulk Operations** - Process all checked-out pages in a library
- ✅ **Multiple Auth Methods** - Interactive, Managed Identity, or App-only
- ✅ **PnP Module Auto-Install** - Installs required module if missing
- ✅ **Detailed Logging** - Comprehensive operation logs
- ✅ **WhatIf Support** - Preview changes before applying

## Quick Start

### Single Page
```powershell
.\Force-SharePointPageCheckIn.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/Marketing" -PageServerRelativeUrl "/sites/Marketing/SitePages/Launch.aspx"
```

### By Page Name
```powershell
.\Force-SharePointPageCheckIn.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/HR" -PageName "Policies.aspx"
```

### Bulk Operation
```powershell
.\Force-SharePointPageCheckIn.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/News" -AllCheckedOutPages
```

## Parameters

### Page Selection (Parameter Sets)

| Parameter | Set | Description |
|-----------|-----|-------------|
| `PageServerRelativeUrl` | SinglePage | Full server-relative URL |
| `PageName` | ByName | Just the filename (assumes SitePages) |
| `AllCheckedOutPages` | Bulk | Process all checked-out pages |

### Common Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `SiteUrl` | string | (required) | SharePoint site URL |
| `ListName` | string | "SitePages" | Library name for bulk ops |
| `SkipPublish` | switch | `$false` | Skip publishing |
| `SkipApprove` | switch | `$false` | Skip approval |
| `CheckInComment` | string | "Admin check-in (forced)" | Custom check-in comment |
| `ConnectionMethod` | string | "Interactive" | Auth method |
| `LogPath` | string | `%TEMP%\SharePointCheckIn_*.log` | Log file path |
| `WhatIf` | switch | `$false` | Preview mode |
| `Force` | switch | `$false` | Skip confirmations |

### Authentication Parameters

| Parameter | Description |
|-----------|-------------|
| `TenantId` | Azure AD Tenant ID |
| `ClientId` | App Registration Client ID |
| `Thumbprint` | Certificate thumbprint |

## Examples

### Force Check-In Single Page
```powershell
.\Force-SharePointPageCheckIn.ps1 `
    -SiteUrl "https://contoso.sharepoint.com/sites/Marketing" `
    -PageServerRelativeUrl "/sites/Marketing/SitePages/Launch.aspx"
```

### Check-In Without Publishing
```powershell
.\Force-SharePointPageCheckIn.ps1 `
    -SiteUrl "https://contoso.sharepoint.com/sites/IT" `
    -PageName "Help.aspx" `
    -SkipPublish `
    -CheckInComment "Emergency fix by IT"
```

### Bulk Process All Checked-Out Pages
```powershell
.\Force-SharePointPageCheckIn.ps1 `
    -SiteUrl "https://contoso.sharepoint.com/sites/News" `
    -AllCheckedOutPages
```

### Preview Mode (No Changes)
```powershell
.\Force-SharePointPageCheckIn.ps1 `
    -SiteUrl "https://contoso.sharepoint.com/sites/Marketing" `
    -AllCheckedOutPages `
    -WhatIf
```

### Process Documents Library
```powershell
.\Force-SharePointPageCheckIn.ps1 `
    -SiteUrl "https://contoso.sharepoint.com/sites/Finance" `
    -AllCheckedOutPages `
    -ListName "Documents" `
    -Force
```

### Using Managed Identity
```powershell
.\Force-SharePointPageCheckIn.ps1 `
    -SiteUrl "https://contoso.sharepoint.com/sites/HR" `
    -PageName "Policy.docx" `
    -ConnectionMethod ManagedIdentity
```

## Authentication Methods

### Interactive (Default)
Opens browser for Microsoft 365 login:
```powershell
.\Force-SharePointPageCheckIn.ps1 -SiteUrl $url -PageName "page.aspx"
```

### Managed Identity
For Azure Automation or Azure VMs:
```powershell
.\Force-SharePointPageCheckIn.ps1 -SiteUrl $url -PageName "page.aspx" -ConnectionMethod ManagedIdentity
```

### App-Only (Certificate)
For service principals:
```powershell
.\Force-SharePointPageCheckIn.ps1 `
    -SiteUrl $url `
    -PageName "page.aspx" `
    -ConnectionMethod Credential `
    -ClientId "app-id" `
    -Thumbprint "cert-thumbprint" `
    -TenantId "tenant-id"
```

## How It Works

### Single Page Processing
1. Connects to SharePoint Online using PnP.PowerShell
2. Retrieves current file status (who has it checked out)
3. Discards any pending checkout (`Undo-PnPFileCheckout`)
4. Forces check-in as major version (`Set-PnPFileCheckedIn`)
5. Optionally publishes the file (`Publish-PnPFile`)
6. Optionally approves the file (`Approve-PnPFile`)

### Bulk Processing
1. Connects to SharePoint
2. Queries specified list for all items with `CheckoutUser` populated
3. Lists all checked-out files with user names
4. Prompts for confirmation (unless `-Force`)
5. Processes each file individually
6. Reports success/failure for each

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (all pages processed) |
| 1 | Connection failed |
| 2 | Page not found or access denied |
| 3 | Check-in failed (all pages) |
| 4 | Partial success (some pages failed) |
| 5 | No pages to process |

## Use Cases

### Departed Employee Cleanup
```powershell
# Find and fix all pages checked out by any user
.\Force-SharePointPageCheckIn.ps1 `
    -SiteUrl "https://contoso.sharepoint.com/sites/Team" `
    -AllCheckedOutPages
```

### Emergency Content Update
When a critical page needs immediate updating but is checked out:
```powershell
.\Force-SharePointPageCheckIn.ps1 `
    -SiteUrl "https://contoso.sharepoint.com/sites/Intranet" `
    -PageName "Emergency-Notice.aspx" `
    -SkipApprove
```

### Publishing Workflow Recovery
When approval workflows are stuck:
```powershell
.\Force-SharePointPageCheckIn.ps1 `
    -SiteUrl "https://contoso.sharepoint.com/sites/Comms" `
    -AllCheckedOutPages `
    -ListName "SitePages" `
    -Force
```

## Requirements

- PowerShell 5.1 or PowerShell 7+
- PnP.PowerShell module (auto-installed if missing)
- SharePoint Online permissions:
  - Site Owner or Site Collection Admin (recommended)
  - At minimum: Full Control on target library

## Required Permissions

### For Interactive Authentication
- SharePoint Site Owner or Site Collection Administrator
- Or: Full Control permissions on the target document library

### For App-Only Authentication
- Azure AD App Registration with SharePoint API permissions:
  - `Sites.FullControl.All` (Application permission)
  - Admin consent required

## Output Example

```
========================================
  SharePoint Force Check-In Tool v3.0
========================================

[*] Site: https://contoso.sharepoint.com/sites/Marketing
[*] PnP.PowerShell v2.0.0 found
[*] Connecting to SharePoint Online...
    Site: https://contoso.sharepoint.com/sites/Marketing
    Method: Interactive
[+] Connected as: Admin User (admin@contoso.com)

[*] Finding all checked-out files in 'SitePages'...
[+] Found 3 checked-out item(s)

[*] Found 3 checked-out file(s):
    - Launch.aspx (by jsmith@contoso.com)
    - Campaign.docx (by departe@contoso.com)
    - Budget.xlsx (by mgarcia@contoso.com)

Process all 3 files? (Y/N): Y

[*] Processing: Launch.aspx
    URL: /sites/Marketing/SitePages/Launch.aspx
[!]   Currently checked out to: jsmith@contoso.com
[*]   Discarding checkout...
[+]   ✓ Checkout discarded
[*]   Checking in file...
[+]   ✓ Checked in (major version)
[*]   Publishing file...
[+]   ✓ Published
[*]   Approving file...
[+]   ✓ Approved

... (additional pages)

========================================
  SUMMARY
========================================

[+] Successfully processed: 3
[+] Failed: 0

[*] Log saved to: C:\Users\admin\AppData\Local\Temp\SharePointCheckIn_20260212_155030.log
```

## Safety Features

- **Confirmation Prompts**: Asks before bulk operations (unless `-Force`)
- **WhatIf Mode**: Preview all actions without making changes
- **Detailed Logging**: Every action logged with timestamps
- **Error Handling**: Graceful handling of "already checked in" etc.
- **PnP Auto-Install**: Installs required module if missing

## Troubleshooting

### "Failed to connect"
- Verify SiteUrl is correct
- Check you have permissions to the site
- Try interactive authentication first

### "Access denied"
- You need Full Control on the document library
- Site Owner or Site Collection Admin recommended
- For bulk operations, need Site Collection Admin

### "PnP.PowerShell module not found"
The script auto-installs, but if it fails:
```powershell
Install-Module PnP.PowerShell -Scope CurrentUser -Force
```

### "Page not found"
- Verify the server-relative URL is correct
- Use `-PageName` instead if unsure of full path
- Check that page exists in the SitePages library

### "Check-in failed: The file is checked out"
Some files may be locked. Try:
```powershell
# Run with higher permissions
# Or wait and retry
```

### Managed Identity not working
Ensure the managed identity has SharePoint permissions:
1. Azure Portal → Managed Identity
2. Azure role assignments → Add → SharePoint permissions

## Version History

### 3.0 (2026-02-12)
- Complete rewrite with improved error handling
- Added bulk operation support (`-AllCheckedOutPages`)
- Added multiple authentication methods
- Added WhatIf support
- Added detailed logging
- Better parameter validation
- Improved summary reporting

### 2.0 (2026-02-04)
- Basic force check-in functionality
- Single page support
- PnP.PowerShell integration

### 1.0
- Initial release with CSOM

## Related Scripts

- `Find-OrphanedSharePointSync.ps1` - Find orphaned local sync folders
- `Check-IntuneEnrollment.ps1` - Device management

## License

MIT License - Use responsibly. Always verify permissions before forcefully modifying content checked out by other users.

## Disclaimer

This tool provides administrative override capabilities. Use only when:
- The checked-out user is unavailable (departed, on leave)
- The content needs urgent updating
- You have proper authorization

Audit logs in SharePoint will show these administrative actions.
