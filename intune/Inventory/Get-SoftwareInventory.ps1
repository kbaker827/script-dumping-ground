#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Audits installed software and exports inventory report.

.DESCRIPTION
    Scans installed applications from registry and WMI, exports to CSV/JSON.
    Can compare against approved software list and report unauthorized apps.

.PARAMETER ExportPath
    Path to save the inventory report

.PARAMETER Format
    Export format: CSV, JSON, or Both

.PARAMETER CompareToBaseline
    Path to approved software baseline file for comparison

.PARAMETER IncludeUpdates
    Include Windows Updates in inventory

.PARAMETER IncludeSystemComponents
    Include system components and drivers

.PARAMETER ReportUnauthorized
    Report only unauthorized software (requires CompareToBaseline)

.PARAMETER LogPath
    Path for operation logs

.EXAMPLE
    .\Get-SoftwareInventory.ps1 -ExportPath "C:\Reports\SoftwareInventory.csv"

.EXAMPLE
    .\Get-SoftwareInventory.ps1 -CompareToBaseline "C:\Baselines\ApprovedSoftware.json" -ReportUnauthorized

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ExportPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\SoftwareInventory.csv",

    [Parameter(Mandatory=$false)]
    [ValidateSet("CSV", "JSON", "Both")]
    [string]$Format = "CSV",

    [Parameter(Mandatory=$false)]
    [string]$CompareToBaseline = "",

    [Parameter(Mandatory=$false)]
    [switch]$IncludeUpdates,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeSystemComponents,

    [Parameter(Mandatory=$false)]
    [switch]$ReportUnauthorized,

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
)

$ScriptName = "SoftwareInventory"
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

function Get-InstalledSoftware {
    $software = @()
    
    # Registry paths for installed software
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    # Get user-installed software
    Get-ChildItem -Path "HKU:" -ErrorAction SilentlyContinue | ForEach-Object {
        $userPath = "$($_.PSPath)\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
        if (Test-Path $userPath) {
            $regPaths += $userPath
        }
    }
    
    foreach ($path in $regPaths) {
        try {
            $items = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }
            
            foreach ($item in $items) {
                # Skip updates unless requested
                if (-not $IncludeUpdates -and ($item.DisplayName -match "Update for|Security Update|KB[0-9]")) {
                    continue
                }
                
                # Skip system components unless requested
                if (-not $IncludeSystemComponents -and $item.SystemComponent -eq 1) {
                    continue
                }
                
                $software += [PSCustomObject]@{
                    Name = $item.DisplayName
                    Version = $item.DisplayVersion
                    Publisher = $item.Publisher
                    InstallDate = $item.InstallDate
                    InstallLocation = $item.InstallLocation
                    UninstallString = $item.UninstallString
                    Is64Bit = $path -like "*WOW6432Node*" -eq $false
                    Source = "Registry"
                }
            }
        }
        catch {
            Write-Log "Error reading registry path $path`: $($_.Exception.Message)" "WARN"
        }
    }
    
    # Also get from WMI
    try {
        $wmiSoftware = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name }
        foreach ($item in $wmiSoftware) {
            $software += [PSCustomObject]@{
                Name = $item.Name
                Version = $item.Version
                Publisher = $item.Vendor
                InstallDate = $item.InstallDate
                InstallLocation = $item.InstallLocation
                UninstallString = $null
                Is64Bit = $null
                Source = "WMI"
            }
        }
    }
    catch {
        Write-Log "WMI query failed: $($_.Exception.Message)" "WARN"
    }
    
    # Remove duplicates (keep registry version as it has more details)
    $software | Sort-Object Name, Version -Unique
}

function Compare-ToBaseline {
    param([array]$Software, [string]$BaselinePath)
    
    try {
        $baseline = Get-Content -Path $BaselinePath | ConvertFrom-Json
        $approvedNames = $baseline.ApprovedSoftware | ForEach-Object { $_.ToLower() }
        
        $unauthorized = $Software | Where-Object { 
            $name = $_.Name.ToLower()
            # Check if name contains or matches any approved software
            $isApproved = $approvedNames | Where-Object { $name -like "*$_*" }
            -not $isApproved
        }
        
        return $unauthorized
    }
    catch {
        Write-Log "Baseline comparison failed: $($_.Exception.Message)" "ERROR"
        return $Software
    }
}

function Export-Inventory {
    param([array]$Software, [string]$Path, [string]$ExportFormat)
    
    try {
        $directory = Split-Path -Path $Path -Parent
        if (!(Test-Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
        
        if ($ExportFormat -eq "CSV" -or $ExportFormat -eq "Both") {
            $csvPath = [System.IO.Path]::ChangeExtension($Path, "csv")
            $Software | Export-Csv -Path $csvPath -NoTypeInformation
            Write-Log "Exported to CSV: $csvPath" "SUCCESS"
        }
        
        if ($ExportFormat -eq "JSON" -or $ExportFormat -eq "Both") {
            $jsonPath = [System.IO.Path]::ChangeExtension($Path, "json")
            $Software | ConvertTo-Json -Depth 3 | Out-File -FilePath $jsonPath
            Write-Log "Exported to JSON: $jsonPath" "SUCCESS"
        }
        
        return $true
    }
    catch {
        Write-Log "Export failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Main
Write-Log "=== Software Inventory Started ==="

Write-Log "Scanning installed software..."
$inventory = Get-InstalledSoftware
Write-Log "Found $($inventory.Count) software items"

# Compare to baseline if specified
if ($CompareToBaseline) {
    Write-Log "Comparing to baseline: $CompareToBaseline"
    $inventory = Compare-ToBaseline -Software $inventory -BaselinePath $CompareToBaseline
    Write-Log "Found $($inventory.Count) unauthorized items"
}

# Export results
$success = Export-Inventory -Software $inventory -Path $ExportPath -ExportFormat $Format

if ($success) {
    Write-Log "=== Inventory completed ===" "SUCCESS"
    exit 0
} else {
    exit 1
}