<#
.SYNOPSIS
    Forces check-in, publish, and approval of SharePoint Online pages stuck in checked-out state.

.DESCRIPTION
    Connects to SharePoint Online and performs administrative actions on pages that are
    checked out by users who may no longer be available (departed employees, etc.).
    
    Actions performed:
    - Discards any pending checkout
    - Forces check-in (major version)
    - Publishes the page (optional)
    - Approves the page (optional)
    
    Also supports bulk operations on multiple pages and sites.

.PARAMETER SiteUrl
    The full URL of the SharePoint site.
    Example: https://contoso.sharepoint.com/sites/Marketing

.PARAMETER PageServerRelativeUrl
    The server-relative URL of the page.
    Example: /sites/Marketing/SitePages/Launch.aspx

.PARAMETER PageName
    Alternative to PageServerRelativeUrl - just the page name.
    Example: "Launch.aspx" (assumes SitePages library)

.PARAMETER AllCheckedOutPages
    Find and process all checked-out pages in the site.

.PARAMETER ListName
    Document library to search when using -AllCheckedOutPages.
    Default: "SitePages"

.PARAMETER SkipPublish
    Skip the publish step after check-in.

.PARAMETER SkipApprove
    Skip the approval step after publish.

.PARAMETER CheckInComment
    Custom comment for the check-in action.
    Default: "Admin check-in (forced)"

.PARAMETER ConnectionMethod
    Authentication method: Interactive, ManagedIdentity, or Credential.
    Default: Interactive

.PARAMETER TenantId
    Azure AD Tenant ID (required for some auth methods).

.PARAMETER ClientId
    Azure AD App Registration Client ID (for app-only auth).

.PARAMETER Thumbprint
    Certificate thumbprint for app-only authentication.

.PARAMETER LogPath
    Path to save the operation log.
    Default: %TEMP%\SharePointCheckIn_*.log

.PARAMETER WhatIf
    Show what would be done without making changes.

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    .\Force-SharePointPageCheckIn.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/Marketing" -PageServerRelativeUrl "/sites/Marketing/SitePages/Launch.aspx"
    Forces check-in of a single page.

.EXAMPLE
    .\Force-SharePointPageCheckIn.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/HR" -PageName "Policies.aspx"
    Uses page name instead of full server-relative URL.

.EXAMPLE
    .\Force-SharePointPageCheckIn.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/News" -AllCheckedOutPages
    Finds and processes all checked-out pages in the SitePages library.

.EXAMPLE
    .\Force-SharePointPageCheckIn.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/Marketing" -AllCheckedOutPages -ListName "Documents" -WhatIf
    Preview what pages would be processed in the Documents library.

.EXAMPLE
    .\Force-SharePointPageCheckIn.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/IT" -PageName "Help.aspx" -SkipPublish -CheckInComment "Emergency fix by IT"
    Checks in without publishing, with custom comment.

.NOTES
    Version:        3.0
    Author:         IT Admin
    Updated:        2026-02-12
    
    Requirements:
    - PnP.PowerShell module (auto-installed if missing)
    - SharePoint Online permissions (Site Owner or Site Collection Admin recommended)
    - For bulk operations: Full Control permissions
    
    Exit Codes:
    0   - Success
    1   - Connection failed
    2   - Page not found or access denied
    3   - Check-in failed
    4   - Partial success (some pages failed)
    5   - No pages to process
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory, ParameterSetName='SinglePage')]
    [Parameter(Mandatory, ParameterSetName='Bulk')]
    [ValidatePattern('^https://[a-zA-Z0-9][-a-zA-Z0-9]*\.sharepoint\.com')] 
    [string]$SiteUrl,
    
    [Parameter(Mandatory, ParameterSetName='SinglePage')]
    [ValidatePattern('^/')]
    [string]$PageServerRelativeUrl,
    
    [Parameter(Mandatory, ParameterSetName='ByName')]
    [string]$PageName,
    
    [Parameter(Mandatory, ParameterSetName='Bulk')]
    [switch]$AllCheckedOutPages,
    
    [Parameter(ParameterSetName='Bulk')]
    [string]$ListName = "SitePages",
    
    [switch]$SkipPublish,
    [switch]$SkipApprove,
    
    [string]$CheckInComment = "Admin check-in (forced)",
    
    [ValidateSet('Interactive', 'ManagedIdentity', 'Credential')]
    [string]$ConnectionMethod = 'Interactive',
    
    [string]$TenantId,
    [string]$ClientId,
    [string]$Thumbprint,
    
    [string]$LogPath = (Join-Path $env:TEMP "SharePointCheckIn_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"),
    
    [switch]$WhatIf,
    [switch]$Force
)

#region Configuration
$ErrorActionPreference = 'Stop'
$script:Version = "3.0"
$script:ProcessedPages = [System.Collections.Generic.List[object]]::new()
$script:FailedPages = [System.Collections.Generic.List[object]]::new()
#endregion

#region Helper Functions
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Detail')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    
    try {
        Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
    } catch { }
    
    $colors = @{
        Info = 'Cyan'
        Success = 'Green'
        Warning = 'Yellow'
        Error = 'Red'
        Detail = 'Gray'
    }
    
    $prefix = switch ($Level) {
        'Info'    { '[*]' }
        'Success' { '[+]' }
        'Warning' { '[!]' }
        'Error'   { '[-]' }
        'Detail'  { '   ' }
    }
    
    Write-Host "$prefix $Message" -ForegroundColor $colors[$Level]
}

function Show-Header {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  SharePoint Force Check-In Tool v$Version" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Log "Site: $SiteUrl" -Level Detail
    Write-Log "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level Detail
    Write-Host ""
}

function Install-PnPModule {
    Write-Log "Checking PnP.PowerShell module..." -Level Info
    
    $module = Get-Module -ListAvailable -Name PnP.PowerShell
    
    if (-not $module) {
        Write-Log "PnP.PowerShell not found. Installing..." -Level Warning
        
        try {
            Install-Module PnP.PowerShell -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            Write-Log "PnP.PowerShell installed successfully" -Level Success
        }
        catch {
            Write-Log "Failed to install PnP.PowerShell: $($_.Exception.Message)" -Level Error
            Write-Log "Install manually: Install-Module PnP.PowerShell -Scope CurrentUser -Force" -Level Info
            exit 1
        }
    } else {
        Write-Log "PnP.PowerShell v$($module.Version) found" -Level Success
    }
    
    Import-Module PnP.PowerShell -ErrorAction Stop
}

function Connect-SharePoint {
    Write-Log "Connecting to SharePoint Online..." -Level Info
    Write-Log "Site: $SiteUrl" -Level Detail
    Write-Log "Method: $ConnectionMethod" -Level Detail
    
    try {
        switch ($ConnectionMethod) {
            'Interactive' {
                Connect-PnPOnline -Url $SiteUrl -Interactive -ErrorAction Stop
            }
            'ManagedIdentity' {
                Connect-PnPOnline -Url $SiteUrl -ManagedIdentity -ErrorAction Stop
            }
            'Credential' {
                if (-not $ClientId -or -not $Thumbprint) {
                    throw "ClientId and Thumbprint required for Credential authentication"
                }
                Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId -Thumbprint $Thumbprint -Tenant $TenantId -ErrorAction Stop
            }
        }
        
        $context = Get-PnPContext
        Write-Log "Connected as: $($context.Web.CurrentUser.Title) ($($context.Web.CurrentUser.Email))" -Level Success
        return $true
    }
    catch {
        Write-Log "Connection failed: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Get-PageServerRelativeUrl {
    if ($PageServerRelativeUrl) {
        return $PageServerRelativeUrl
    }
    
    if ($PageName) {
        # Assume SitePages library if not specified
        $listUrl = "/SitePages/$PageName"
        $web = Get-PnPWeb
        return "$($web.ServerRelativeUrl)$listUrl".Replace('//', '/')
    }
    
    return $null
}

function Get-AllCheckedOutFiles {
    param([string]$LibraryName)
    
    Write-Log "Finding all checked-out files in '$LibraryName'..." -Level Info
    
    try {
        $list = Get-PnPList -Identity $LibraryName -ErrorAction Stop
        
        # Get items with checkout user
        $checkedOutItems = Get-PnPListItem -List $list -PageSize 500 | 
            Where-Object { $_.FieldValues.CheckoutUser -ne $null }
        
        Write-Log "Found $($checkedOutItems.Count) checked-out item(s)" -Level Success
        
        return $checkedOutItems | ForEach-Object {
            [PSCustomObject]@{
                FileName = $_.FieldValues.FileLeafRef
                ServerRelativeUrl = $_.FieldValues.FileRef
                CheckedOutTo = $_.FieldValues.CheckoutUser.LookupValue
                Modified = $_.FieldValues.Modified
                Id = $_.Id
            }
        }
    }
    catch {
        Write-Log "Failed to retrieve checked-out files: $($_.Exception.Message)" -Level Error
        return @()
    }
}

function Invoke-PageCheckIn {
    param(
        [string]$Url,
        [string]$Name = $Url
    )
    
    Write-Log "Processing: $Name" -Level Info
    Write-Log "URL: $Url" -Level Detail
    
    $result = @{
        Name = $Name
        Url = $Url
        Success = $false
        Actions = @()
        Error = $null
    }
    
    try {
        # Get current file status
        try {
            $fileItem = Get-PnPFile -Url $Url -AsListItem -ErrorAction Stop
            $checkedOutTo = $fileItem["CheckoutUser"]
            
            if ($checkedOutTo) {
                Write-Log "  Currently checked out to: $($checkedOutTo.LookupValue)" -Level Warning
            } else {
                Write-Log "  File is not currently checked out" -Level Detail
            }
        }
        catch {
            Write-Log "  Could not retrieve file status: $($_.Exception.Message)" -Level Warning
        }
        
        # Step 1: Discard checkout
        Write-Log "  Discarding checkout..." -Level Detail
        try {
            if ($PSCmdlet.ShouldProcess($Url, "Discard Checkout")) {
                Undo-PnPFileCheckout -Url $Url -Force -ErrorAction Stop
                Write-Log "  ✓ Checkout discarded" -Level Success
                $result.Actions += "CheckoutDiscarded"
            } else {
                Write-Log "  [WHATIF] Would discard checkout" -Level Warning
                $result.Actions += "CheckoutDiscarded(WHATIF)"
            }
        }
        catch {
            if ($_.Exception.Message -match 'not checked out') {
                Write-Log "  Not checked out - continuing" -Level Detail
            } else {
                Write-Log "  Checkout discard warning: $($_.Exception.Message)" -Level Warning
            }
        }
        
        # Step 2: Check in
        Write-Log "  Checking in file..." -Level Detail
        try {
            if ($PSCmdlet.ShouldProcess($Url, "Check In")) {
                Set-PnPFileCheckedIn -Url $Url -CheckinType MajorCheckIn -Comment $CheckInComment -ErrorAction Stop
                Write-Log "  ✓ Checked in (major version)" -Level Success
                $result.Actions += "CheckedIn"
            } else {
                Write-Log "  [WHATIF] Would check in" -Level Warning
                $result.Actions += "CheckedIn(WHATIF)"
            }
        }
        catch {
            if ($_.Exception.Message -match 'already checked in|not checked out') {
                Write-Log "  Already checked in" -Level Detail
                $result.Actions += "AlreadyCheckedIn"
            } else {
                throw "Check-in failed: $($_.Exception.Message)"
            }
        }
        
        # Step 3: Publish
        if (-not $SkipPublish) {
            Write-Log "  Publishing file..." -Level Detail
            try {
                if ($PSCmdlet.ShouldProcess($Url, "Publish")) {
                    Publish-PnPFile -Url $Url -Comment "Published after admin check-in" -ErrorAction Stop
                    Write-Log "  ✓ Published" -Level Success
                    $result.Actions += "Published"
                } else {
                    Write-Log "  [WHATIF] Would publish" -Level Warning
                    $result.Actions += "Published(WHATIF)"
                }
            }
            catch {
                if ($_.Exception.Message -match 'not required|already published|minor version') {
                    Write-Log "  Publishing not required or already published" -Level Detail
                    $result.Actions += "PublishNotRequired"
                } else {
                    Write-Log "  Publish warning: $($_.Exception.Message)" -Level Warning
                }
            }
        }
        
        # Step 4: Approve
        if (-not $SkipApprove) {
            Write-Log "  Approving file..." -Level Detail
            try {
                if ($PSCmdlet.ShouldProcess($Url, "Approve")) {
                    Approve-PnPFile -Url $Url -Comment "Approved after admin check-in" -ErrorAction Stop
                    Write-Log "  ✓ Approved" -Level Success
                    $result.Actions += "Approved"
                } else {
                    Write-Log "  [WHATIF] Would approve" -Level Warning
                    $result.Actions += "Approved(WHATIF)"
                }
            }
            catch {
                if ($_.Exception.Message -match 'not required|does not require|already approved') {
                    Write-Log "  Approval not required or already approved" -Level Detail
                    $result.Actions += "ApprovalNotRequired"
                } else {
                    Write-Log "  Approve warning: $($_.Exception.Message)" -Level Warning
                }
            }
        }
        
        $result.Success = $true
        $script:ProcessedPages.Add($result)
        return $true
    }
    catch {
        $result.Error = $_.Exception.Message
        $script:FailedPages.Add($result)
        Write-Log "  Failed: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Show-Summary {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    $successCount = ($script:ProcessedPages | Where-Object { $_.Success }).Count
    $failCount = $script:FailedPages.Count
    
    Write-Log "Successfully processed: $successCount" -Level Success
    Write-Log "Failed: $failCount" -Level $(if ($failCount -gt 0) { 'Error' } else { 'Success' })
    
    if ($script:FailedPages.Count -gt 0) {
        Write-Host ""
        Write-Log "Failed pages:" -Level Error
        $script:FailedPages | ForEach-Object {
            Write-Log "  - $($_.Name): $($_.Error)" -Level Error
        }
    }
    
    Write-Host ""
    Write-Log "Log saved to: $LogPath" -Level Info
}
#endregion

#region Main Execution
Show-Header

# Install/check PnP module
Install-PnPModule

# Connect to SharePoint
if (-not (Connect-SharePoint)) {
    exit 1
}

# Determine pages to process
$pagesToProcess = [System.Collections.Generic.List[object]]::new()

if ($AllCheckedOutPages) {
    Write-Log "Bulk mode: Finding all checked-out pages..." -Level Info
    $checkedOutFiles = Get-AllCheckedOutFiles -LibraryName $ListName
    
    if ($checkedOutFiles.Count -eq 0) {
        Write-Log "No checked-out pages found in '$ListName'" -Level Warning
        exit 5
    }
    
    Write-Host ""
    Write-Log "Found $($checkedOutFiles.Count) checked-out file(s):" -Level Info
    $checkedOutFiles | ForEach-Object {
        Write-Log "  - $($_.FileName) (by $($_.CheckedOutTo))" -Level Detail
    }
    
    if (-not $Force -and -not $WhatIf) {
        Write-Host ""
        $confirm = Read-Host "Process all $($checkedOutFiles.Count) files? (Y/N)"
        if ($confirm -ne 'Y') {
            Write-Log "Operation cancelled by user" -Level Warning
            exit 3
        }
    }
    
    $pagesToProcess = $checkedOutFiles
}
else {
    # Single page mode
    $url = Get-PageServerRelativeUrl
    $displayName = if ($PageName) { $PageName } else { Split-Path $url -Leaf }
    
    $pagesToProcess.Add([PSCustomObject]@{
        FileName = $displayName
        ServerRelativeUrl = $url
        CheckedOutTo = "Unknown"
    })
}

# Process pages
Write-Host ""
Write-Log "Processing $($pagesToProcess.Count) page(s)..." -Level Info
Write-Host ""

foreach ($page in $pagesToProcess) {
    Invoke-PageCheckIn -Url $page.ServerRelativeUrl -Name $page.FileName
    Write-Host ""
}

# Show summary
Show-Summary

# Exit code
if ($script:FailedPages.Count -eq 0) {
    exit 0
} elseif ($script:ProcessedPages.Count -gt 0) {
    exit 4  # Partial success
} else {
    exit 3  # Complete failure
}
#endregion
