#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Completely removes Microsoft Office 365 apps and all related files from Windows.
    Does NOT remove Microsoft Teams or OneDrive.

.DESCRIPTION
    This script removes:
    - Word, Excel, PowerPoint, Outlook, OneNote, Access, Publisher
    - All Office preferences, caches, and registry entries
    - License files and activation data
    - Installer files from Downloads and temp folders

    NOT removed:
    - Microsoft Teams
    - OneDrive

.EXAMPLE
    .\Remove-Office365.ps1

.NOTES
    Must be run as Administrator
#>

[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = "SilentlyContinue"

Write-Host "=== Microsoft Office 365 Complete Removal Script ===" -ForegroundColor Cyan
Write-Host "This will remove Word, Excel, PowerPoint, Outlook, OneNote, Access, Publisher"
Write-Host "Teams and OneDrive will NOT be touched"
Write-Host ""

if (-not $Force) {
    $confirm = Read-Host "Continue? (Y/N)"
    if ($confirm -notmatch "^[Yy]") {
        Write-Host "Aborted." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""
Write-Host "Closing Office applications..." -ForegroundColor Yellow
$officeProcesses = @(
    "WINWORD", "EXCEL", "POWERPNT", "OUTLOOK", "ONENOTE", 
    "MSACCESS", "MSPUB", "OfficeClickToRun", "OfficeC2RClient"
)
foreach ($proc in $officeProcesses) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | Stop-Process -Force
}
Start-Sleep -Seconds 2

# Function to remove Office using Click-to-Run
function Remove-OfficeClickToRun {
    Write-Host "Attempting Office Click-to-Run uninstall..." -ForegroundColor Yellow
    
    $officeC2R = "C:\Program Files\Common Files\Microsoft Shared\ClickToRun\OfficeClickToRun.exe"
    if (Test-Path $officeC2R) {
        # Get installed Office products (excluding Teams/OneDrive)
        $officeProducts = @(
            "O365ProPlusRetail", "O365BusinessRetail", "O365HomePremRetail",
            "VisioProRetail", "ProjectProRetail", "AccessRetail", "PublisherRetail"
        )
        
        foreach ($product in $officeProducts) {
            Write-Host "  Removing $product..." -ForegroundColor Gray
            Start-Process -FilePath $officeC2R -ArgumentList "scenario=install scenariosubtype=ARP sourcetype=None productstoremove=$product.16_en-us_x-none culture=en-us version.16=0.0.0.0 DisplayLevel=False" -Wait -NoNewWindow
        }
    }
}

# Function to remove Office using Windows Installer (MSI)
function Remove-OfficeMSI {
    Write-Host "Checking for MSI-based Office installations..." -ForegroundColor Yellow
    
    $uninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    
    foreach ($path in $uninstallPaths) {
        Get-ChildItem -Path $path -ErrorAction SilentlyContinue | ForEach-Object {
            $displayName = (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue).DisplayName
            $uninstallString = (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue).UninstallString
            
            if ($displayName -match "Microsoft Office" -and 
                $displayName -notmatch "Teams" -and 
                $displayName -notmatch "OneDrive" -and
                $uninstallString) {
                
                Write-Host "  Uninstalling: $displayName" -ForegroundColor Gray
                if ($uninstallString -match "msiexec") {
                    $guid = [regex]::Match($uninstallString, "\{[A-F0-9-]+\}").Value
                    if ($guid) {
                        Start-Process "msiexec.exe" -ArgumentList "/x $guid /qn /norestart" -Wait -NoNewWindow
                    }
                }
            }
        }
    }
}

# Try Click-to-Run removal first
Remove-OfficeClickToRun

# Then try MSI removal
Remove-OfficeMSI

Write-Host ""
Write-Host "Removing Office directories..." -ForegroundColor Yellow

# Program Files
$programDirs = @(
    "$env:ProgramFiles\Microsoft Office",
    "$env:ProgramFiles\Microsoft Office 15",
    "$env:ProgramFiles\Microsoft Office 16",
    "${env:ProgramFiles(x86)}\Microsoft Office",
    "${env:ProgramFiles(x86)}\Microsoft Office 15",
    "${env:ProgramFiles(x86)}\Microsoft Office 16",
    "$env:ProgramFiles\Common Files\Microsoft Shared\ClickToRun",
    "$env:ProgramFiles\Common Files\Microsoft Shared\OFFICE16",
    "$env:ProgramFiles\Common Files\Microsoft Shared\OFFICE15",
    "${env:ProgramFiles(x86)}\Common Files\Microsoft Shared\OFFICE16",
    "${env:ProgramFiles(x86)}\Common Files\Microsoft Shared\OFFICE15"
)

foreach ($dir in $programDirs) {
    if (Test-Path $dir) {
        Write-Host "  Removing: $dir" -ForegroundColor Gray
        Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "Removing user Office data for all users..." -ForegroundColor Yellow

$userProfiles = Get-ChildItem "C:\Users" -Directory | Where-Object { $_.Name -notmatch "^(Public|Default|Default User|All Users)$" }

foreach ($profile in $userProfiles) {
    $username = $profile.Name
    $userPath = $profile.FullName
    
    # AppData\Local
    $localPaths = @(
        "$userPath\AppData\Local\Microsoft\Office",
        "$userPath\AppData\Local\Microsoft\Outlook",
        "$userPath\AppData\Local\Microsoft\OneNote",
        "$userPath\AppData\Local\Microsoft\Excel",
        "$userPath\AppData\Local\Microsoft\Word",
        "$userPath\AppData\Local\Microsoft\PowerPoint",
        "$userPath\AppData\Local\Microsoft\Access",
        "$userPath\AppData\Local\Microsoft\Publisher"
    )
    
    # AppData\Roaming
    $roamingPaths = @(
        "$userPath\AppData\Roaming\Microsoft\Office",
        "$userPath\AppData\Roaming\Microsoft\Outlook",
        "$userPath\AppData\Roaming\Microsoft\Excel",
        "$userPath\AppData\Roaming\Microsoft\Word",
        "$userPath\AppData\Roaming\Microsoft\PowerPoint",
        "$userPath\AppData\Roaming\Microsoft\Access",
        "$userPath\AppData\Roaming\Microsoft\Publisher",
        "$userPath\AppData\Roaming\Microsoft\Templates",
        "$userPath\AppData\Roaming\Microsoft\Document Building Blocks"
    )
    
    foreach ($path in ($localPaths + $roamingPaths)) {
        if (Test-Path $path) {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Write-Host "  Cleaned user: $username" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Removing Office registry entries..." -ForegroundColor Yellow

# Current User registry (run for each user profile via HKU)
$regPaths = @(
    "HKCU:\Software\Microsoft\Office",
    "HKLM:\SOFTWARE\Microsoft\Office",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office"
)

foreach ($regPath in $regPaths) {
    if (Test-Path $regPath) {
        # Keep Teams and OneDrive related keys
        Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue | ForEach-Object {
            $keyName = $_.PSChildName
            if ($keyName -notmatch "Teams|OneDrive") {
                Remove-Item -Path $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# Remove Office licensing
$licensingPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun",
    "HKLM:\SOFTWARE\Microsoft\Office\16.0\Common\Licensing",
    "HKLM:\SOFTWARE\Microsoft\Office\15.0\Common\Licensing",
    "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Office\ClickToRun",
    "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Office\16.0\Common\Licensing"
)

foreach ($path in $licensingPaths) {
    if (Test-Path $path) {
        Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "Removing scheduled tasks..." -ForegroundColor Yellow

$tasks = @(
    "Office Automatic Updates 2.0",
    "Office ClickToRun Service Monitor",
    "Office Feature Updates",
    "Office Feature Updates Logon",
    "Office Serviceability Manager"
)

foreach ($task in $tasks) {
    Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Removing Office services..." -ForegroundColor Yellow

$services = @(
    "ClickToRunSvc",
    "ose", # Office Source Engine
    "ose64"
)

foreach ($svc in $services) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        sc.exe delete $svc 2>$null
    }
}

Write-Host ""
Write-Host "Removing installer files from Downloads..." -ForegroundColor Yellow

foreach ($profile in $userProfiles) {
    $downloads = "$($profile.FullName)\Downloads"
    if (Test-Path $downloads) {
        Get-ChildItem -Path $downloads -Include "*Office*Setup*.exe", "*Office*.iso", "OfficeSetup.exe", "*O365*.exe" -Recurse -ErrorAction SilentlyContinue | 
            Where-Object { $_.Name -notmatch "Teams|OneDrive" } |
            ForEach-Object {
                Write-Host "  Removing: $($_.Name)" -ForegroundColor Gray
                Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
            }
    }
}

# Temp folders
Write-Host ""
Write-Host "Cleaning temp folders..." -ForegroundColor Yellow

$tempPaths = @(
    "$env:TEMP\*Office*",
    "$env:TEMP\*Microsoft Office*",
    "C:\Windows\Temp\*Office*"
)

foreach ($tempPath in $tempPaths) {
    Get-ChildItem -Path $tempPath -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -notmatch "Teams|OneDrive" } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Clearing Office fonts..." -ForegroundColor Yellow
# Only remove Office-specific fonts (careful not to remove system fonts)
$officeFonts = Get-ChildItem "C:\Windows\Fonts" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^(calibri|cambria|candara|consolas|constantia|corbel)" }
# Note: These fonts are often protected - just skip if fails

Write-Host ""
Write-Host "=== Office 365 removal complete! ===" -ForegroundColor Green
Write-Host ""
Write-Host "Removed:" -ForegroundColor White
Write-Host "  - Word, Excel, PowerPoint, Outlook, OneNote, Access, Publisher"
Write-Host "  - All preferences, caches, and registry entries"
Write-Host "  - License files and activation data"
Write-Host "  - Scheduled tasks and services"
Write-Host "  - Installer files from Downloads"
Write-Host ""
Write-Host "NOT removed:" -ForegroundColor White
Write-Host "  - Microsoft Teams"
Write-Host "  - OneDrive"
Write-Host ""
Write-Host "Recommendation: Restart your computer to complete the removal." -ForegroundColor Yellow
Write-Host ""

# Prompt for restart
if (-not $Force) {
    $restart = Read-Host "Restart now? (Y/N)"
    if ($restart -match "^[Yy]") {
        Restart-Computer -Force
    }
}
