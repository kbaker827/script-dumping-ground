#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures Chrome and Edge browser policies via Intune.

.DESCRIPTION
    Applies enterprise browser configurations including managed bookmarks,
    homepage, startup pages, and security settings via registry.

.PARAMETER Browser
    Which browser to configure: Chrome, Edge, or Both

.PARAMETER Homepage
    Homepage URL

.PARAMETER StartupPages
    Array of startup page URLs

.PARAMETER ManagedBookmarks
    Array of bookmark objects with Name and URL

.PARAMETER DisableDevTools
    Disable developer tools

.PARAMETER DisableIncognito
    Disable incognito mode

.PARAMETER ForceSafeSearch
    Enforce safe search

.PARAMETER LogPath
    Path for operation logs

.EXAMPLE
    .\Set-BrowserConfiguration.ps1 -Browser Edge -Homepage "https://company.com" -ManagedBookmarks @( @{Name="Intranet";URL="https://intranet"} )

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Chrome", "Edge", "Both")]
    [string]$Browser = "Both",

    [Parameter(Mandatory=$false)]
    [string]$Homepage = "",

    [Parameter(Mandatory=$false)]
    [string[]]$StartupPages = @(),

    [Parameter(Mandatory=$false)]
    [hashtable[]]$ManagedBookmarks = @(),

    [Parameter(Mandatory=$false)]
    [switch]$DisableDevTools,

    [Parameter(Mandatory=$false)]
    [switch]$DisableIncognito,

    [Parameter(Mandatory=$false)]
    [switch]$ForceSafeSearch,

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
)

$ScriptName = "BrowserConfig"
$LogFile = "$LogPath\$ScriptName.log"

if (!(Test-Path -Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    try { Add-Content -Path $LogFile -Value $logEntry } catch {}
    Write-Host $logEntry -ForegroundColor $(switch($Level){"ERROR"{"Red"}"WARN"{"Yellow"}"SUCCESS"{"Green"}default{"White"}})
}

function Set-ChromePolicies {
    try {
        Write-Log "Configuring Chrome policies"
        
        $chromePath = "HKLM:\SOFTWARE\Policies\Google\Chrome"
        if (!(Test-Path $chromePath)) {
            New-Item -Path $chromePath -Force | Out-Null
        }
        
        # Homepage
        if ($Homepage) {
            Set-ItemProperty -Path $chromePath -Name "HomepageLocation" -Value $Homepage
            Set-ItemProperty -Path $chromePath -Name "ShowHomeButton" -Value 1
        }
        
        # Startup pages
        if ($StartupPages.Count -gt 0) {
            Set-ItemProperty -Path $chromePath -Name "RestoreOnStartup" -Value 4
            Set-ItemProperty -Path $chromePath -Name "RestoreOnStartupURLs" -Value $StartupPages
        }
        
        # Managed bookmarks
        if ($ManagedBookmarks.Count -gt 0) {
            $bookmarksJson = $ManagedBookmarks | ConvertTo-Json -Compress
            Set-ItemProperty -Path $chromePath -Name "ManagedBookmarks" -Value $bookmarksJson
        }
        
        # Security settings
        if ($DisableDevTools) {
            Set-ItemProperty -Path $chromePath -Name "DeveloperToolsDisabled" -Value 1
        }
        if ($DisableIncognito) {
            Set-ItemProperty -Path $chromePath -Name "IncognitoModeAvailability" -Value 1
        }
        if ($ForceSafeSearch) {
            Set-ItemProperty -Path $chromePath -Name "ForceSafeSearch" -Value 1
        }
        
        Write-Log "Chrome policies configured" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Chrome config failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Set-EdgePolicies {
    try {
        Write-Log "Configuring Edge policies"
        
        $edgePath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
        if (!(Test-Path $edgePath)) {
            New-Item -Path $edgePath -Force | Out-Null
        }
        
        # Homepage
        if ($Homepage) {
            Set-ItemProperty -Path $edgePath -Name "HomepageLocation" -Value $Homepage
            Set-ItemProperty -Path $edgePath -Name "ShowHomeButton" -Value 1
        }
        
        # Startup pages
        if ($StartupPages.Count -gt 0) {
            Set-ItemProperty -Path $edgePath -Name "RestoreOnStartup" -Value 4
            Set-ItemProperty -Path $edgePath -Name "RestoreOnStartupURLs" -Value $StartupPages
        }
        
        # Managed favorites
        if ($ManagedBookmarks.Count -gt 0) {
            $favorites = @()
            foreach ($bm in $ManagedBookmarks) {
                $favorites += @{
                    name = $bm.Name
                    url = $bm.URL
                }
            }
            $favJson = $favorites | ConvertTo-Json -Compress
            Set-ItemProperty -Path $edgePath -Name "ManagedFavorites" -Value $favJson
        }
        
        # Security settings
        if ($DisableDevTools) {
            Set-ItemProperty -Path $edgePath -Name "DeveloperToolsAvailability" -Value 2
        }
        if ($DisableIncognito) {
            Set-ItemProperty -Path $edgePath -Name "InPrivateModeAvailability" -Value 1
        }
        if ($ForceSafeSearch) {
            Set-ItemProperty -Path $edgePath -Name "ForceBingSafeSearch" -Value 1
        }
        
        # Additional Edge settings
        Set-ItemProperty -Path $edgePath -Name "EdgeShoppingAssistantEnabled" -Value 0
        Set-ItemProperty -Path $edgePath -Name "PersonalizationReportingEnabled" -Value 0
        
        Write-Log "Edge policies configured" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Edge config failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Main
Write-Log "=== Browser Configuration Started ==="

$success = $true

if ($Browser -eq "Chrome" -or $Browser -eq "Both") {
    $success = $success -and (Set-ChromePolicies)
}

if ($Browser -eq "Edge" -or $Browser -eq "Both") {
    $success = $success -and (Set-EdgePolicies)
}

if ($success) {
    Write-Log "=== Configuration completed ===" "SUCCESS"
    exit 0
} else {
    exit 1
}