<#
.SYNOPSIS
    Detection script for Microsoft OneDrive.

.DESCRIPTION
    Checks if OneDrive is installed and at the expected version.
    Returns exit code 0 if detected, 1 if not.

.PARAMETER MinVersion
    Minimum acceptable version

.EXAMPLE
    .\Detect-OneDrive.ps1

.EXAMPLE
    .\Detect-OneDrive.ps1 -MinVersion "24.000"

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$MinVersion = ""
)

$VerbosePreference = "SilentlyContinue"

function Get-OneDriveInfo {
    $paths = @(
        "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe",
        "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
    )
    
    foreach ($path in $paths) {
        if (Test-Path -Path $path) {
            try {
                $version = (Get-Item $path).VersionInfo.FileVersion
                return @{
                    Installed = $true
                    Version = $version
                    Path = $path
                }
            }
            catch {
                return @{ Installed = $true; Version = "Unknown"; Path = $path }
            }
        }
    }
    
    return @{ Installed = $false }
}

function Test-RegistryMarker {
    $regPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\OneDrive"
    
    if (Test-Path -Path $regPath) {
        $success = Get-ItemProperty -Path $regPath -Name "Success" -ErrorAction SilentlyContinue
        $version = Get-ItemProperty -Path $regPath -Name "Version" -ErrorAction SilentlyContinue
        
        if ($success.Success -eq "True") {
            Write-Output "Registry marker found - Version: $($version.Version)"
            return $true
        }
    }
    return $false
}

# Main
$info = Get-OneDriveInfo

if ($info.Installed) {
    Write-Output "OneDrive installed: $($info.Version) at $($info.Path)"
    
    # Check minimum version if specified
    if (-not [string]::IsNullOrEmpty($MinVersion)) {
        if ($info.Version -lt $MinVersion) {
            Write-Output "Version below minimum: $($info.Version) < $MinVersion"
            exit 1
        }
    }
    
    exit 0
}
else {
    # Check registry as fallback
    if (Test-RegistryMarker) {
        exit 0
    }
    
    Write-Output "OneDrive not detected"
    exit 1
}