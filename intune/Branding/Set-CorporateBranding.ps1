#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Deploys corporate wallpaper, lock screen, and OEM branding via Intune.

.DESCRIPTION
    Copies branded wallpaper images to the system and configures Windows to use them.
    Sets OEM information and lock screen branding. Designed for silent Intune deployment.

.PARAMETER WallpaperSource
    Path to the wallpaper image file (JPG/PNG/BMP)

.PARAMETER LockScreenSource
    Path to the lock screen image file (optional - uses wallpaper if not specified)

.PARAMETER WallpaperStyle
    Wallpaper style: Fill, Fit, Stretch, Tile, Center, Span (default: Fill)

.PARAMETER OEMLogo
    Path to OEM logo image (120x120 recommended)

.PARAMETER OEMManufacturer
    Company name for OEM info

.PARAMETER OEMModel
    Model info (optional)

.PARAMETER OEMSupportHours
    Support hours text (optional)

.PARAMETER OEMSupportPhone
    Support phone number (optional)

.PARAMETER OEMSupportURL
    Support website URL (optional)

.PARAMETER LogPath
    Path for operation logs

.EXAMPLE
    .\Set-CorporateBranding.ps1 -WallpaperSource "\\server\branding\wallpaper.jpg" -OEMManufacturer "Contoso Corp"

.EXAMPLE
    .\Set-CorporateBranding.ps1 -WallpaperSource "C:\Branding\wallpaper.jpg" -LockScreenSource "C:\Branding\lockscreen.jpg" -OEMManufacturer "Contoso" -OEMLogo "C:\Branding\logo.bmp"

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
    Requirements:   Windows 10/11, Administrator rights
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$WallpaperSource,

    [Parameter(Mandatory=$false)]
    [string]$LockScreenSource = "",

    [Parameter(Mandatory=$false)]
    [ValidateSet("Fill", "Fit", "Stretch", "Tile", "Center", "Span")]
    [string]$WallpaperStyle = "Fill",

    [Parameter(Mandatory=$false)]
    [string]$OEMLogo = "",

    [Parameter(Mandatory=$false)]
    [string]$OEMManufacturer = "",

    [Parameter(Mandatory=$false)]
    [string]$OEMModel = "",

    [Parameter(Mandatory=$false)]
    [string]$OEMSupportHours = "",

    [Parameter(Mandatory=$false)]
    [string]$OEMSupportPhone = "",

    [Parameter(Mandatory=$false)]
    [string]$OEMSupportURL = "",

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
)

# Configuration
$ScriptName = "CorporateBranding"
$LogFile = "$LogPath\$ScriptName.log"
$BrandingPath = "$env:SystemRoot\Web\Wallpaper\Corporate"
$OEMPath = "$env:SystemRoot\System32\OEM"

# Wallpaper styles registry values
$StyleMap = @{
    "Fill" = 10
    "Fit" = 6
    "Stretch" = 2
    "Tile" = 0
    "Center" = 0
    "Span" = 22
}

# Ensure log directory exists
if (!(Test-Path -Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    try { Add-Content -Path $LogFile -Value $logEntry } catch {}
    Write-Host $logEntry -ForegroundColor $(switch($Level){"ERROR"{"Red"}"WARN"{"Yellow"}"SUCCESS"{"Green"}default{"White"}})
}

function Set-CorporateWallpaper {
    try {
        Write-Log "Setting corporate wallpaper"
        
        # Create branding directory if needed
        if (!(Test-Path -Path $BrandingPath)) {
            New-Item -Path $BrandingPath -ItemType Directory -Force | Out-Null
        }
        
        # Copy wallpaper
        $destFile = Join-Path $BrandingPath "corporate-wallpaper.jpg"
        Copy-Item -Path $WallpaperSource -Destination $destFile -Force
        Write-Log "Wallpaper copied to: $destFile"
        
        # Set wallpaper via SystemParametersInfo
        $code = @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32;
namespace Wallpaper {
    public class Setter {
        [DllImport("user32.dll", CharSet=CharSet.Auto)]
        static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
        
        public static void SetWallpaper(string path, string style) {
            // Set registry values
            RegistryKey key = Registry.CurrentUser.OpenSubKey("Control Panel\\Desktop", true);
            key.SetValue("Wallpaper", path);
            
            switch(style) {
                case "Fill":
                    key.SetValue("WallpaperStyle", "10");
                    key.SetValue("TileWallpaper", "0");
                    break;
                case "Fit":
                    key.SetValue("WallpaperStyle", "6");
                    key.SetValue("TileWallpaper", "0");
                    break;
                case "Stretch":
                    key.SetValue("WallpaperStyle", "2");
                    key.SetValue("TileWallpaper", "0");
                    break;
                case "Tile":
                    key.SetValue("WallpaperStyle", "0");
                    key.SetValue("TileWallpaper", "1");
                    break;
                case "Center":
                    key.SetValue("WallpaperStyle", "0");
                    key.SetValue("TileWallpaper", "0");
                    break;
                case "Span":
                    key.SetValue("WallpaperStyle", "22");
                    key.SetValue("TileWallpaper", "0");
                    break;
            }
            key.Close();
            
            // Apply wallpaper
            SystemParametersInfo(20, 0, path, 0x01 | 0x02);
        }
    }
}
"@
        
        Add-Type -TypeDefinition $code -Language CSharp
        [Wallpaper.Setter]::SetWallpaper($destFile, $WallpaperStyle)
        
        Write-Log "Wallpaper applied successfully" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to set wallpaper: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Set-LockScreenWallpaper {
    try {
        $lockScreenFile = if ([string]::IsNullOrEmpty($LockScreenSource)) { $WallpaperSource } else { $LockScreenSource }
        
        Write-Log "Setting lock screen wallpaper"
        
        # Copy to Windows Web folder
        $destFile = "$env:SystemRoot\Web\Screen\lockscreen.jpg"
        Copy-Item -Path $lockScreenFile -Destination $destFile -Force
        
        # Set via registry (Windows 10/11)
        $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
        if (!(Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $regPath -Name "LockScreenImage" -Value $destFile
        Set-ItemProperty -Path $regPath -Name "LockScreenOverlaysDisabled" -Value 1
        
        Write-Log "Lock screen wallpaper set" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to set lock screen: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Set-OEMInformation {
    try {
        if ([string]::IsNullOrEmpty($OEMManufacturer) -and [string]::IsNullOrEmpty($OEMLogo)) {
            return $true
        }
        
        Write-Log "Setting OEM information"
        
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation"
        if (!(Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        
        # Copy logo if provided
        if (-not [string]::IsNullOrEmpty($OEMLogo) -and (Test-Path $OEMLogo)) {
            if (!(Test-Path $OEMPath)) {
                New-Item -Path $OEMPath -ItemType Directory -Force | Out-Null
            }
            $logoDest = Join-Path $OEMPath "logo.bmp"
            Copy-Item -Path $OEMLogo -Destination $logoDest -Force
            Set-ItemProperty -Path $regPath -Name "Logo" -Value $logoDest
        }
        
        # Set OEM properties
        if ($OEMManufacturer) { Set-ItemProperty -Path $regPath -Name "Manufacturer" -Value $OEMManufacturer }
        if ($OEMModel) { Set-ItemProperty -Path $regPath -Name "Model" -Value $OEMModel }
        if ($OEMSupportHours) { Set-ItemProperty -Path $regPath -Name "SupportHours" -Value $OEMSupportHours }
        if ($OEMSupportPhone) { Set-ItemProperty -Path $regPath -Name "SupportPhone" -Value $OEMSupportPhone }
        if ($OEMSupportURL) { Set-ItemProperty -Path $regPath -Name "SupportURL" -Value $OEMSupportURL }
        
        Write-Log "OEM information set" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to set OEM info: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Main
Write-Log "=== Corporate Branding Deployment Started ==="

$success = $true

if (Test-Path $WallpaperSource) {
    $success = $success -and (Set-CorporateWallpaper)
    $success = $success -and (Set-LockScreenWallpaper)
} else {
    Write-Log "Wallpaper source not found: $WallpaperSource" "ERROR"
    $success = $false
}

$success = $success -and (Set-OEMInformation)

if ($success) {
    Write-Log "=== Branding deployment completed ===" "SUCCESS"
    exit 0
} else {
    exit 1
}