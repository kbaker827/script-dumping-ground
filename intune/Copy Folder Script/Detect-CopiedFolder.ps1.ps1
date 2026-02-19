<#
.SYNOPSIS
    Detection script for copied folder.

.DESCRIPTION
    Checks if a folder has been copied to the target location.
    Returns exit code 0 if detected, 1 if not detected.

.PARAMETER TargetFolder
    Path to check for existence

.EXAMPLE
    .\Detect-CopiedFolder.ps1 -TargetFolder "C:\ProgramData\MyApp\Config"

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$TargetFolder
)

$VerbosePreference = "SilentlyContinue"

function Test-FolderExists {
    param([string]$Path)
    
    if (Test-Path -Path $Path) {
        $item = Get-Item -Path $Path
        if ($item.PSIsContainer) {
            $fileCount = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue).Count
            Write-Output "Folder exists: $Path ($fileCount files)"
            return $true
        }
    }
    
    return $false
}

function Test-RegistryMarker {
    param([string]$TargetPath)
    
    $regPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\FolderCopy"
    
    if (Test-Path -Path $regPath) {
        $targetValue = Get-ItemProperty -Path $regPath -Name "TargetFolder" -ErrorAction SilentlyContinue
        if ($targetValue -and $targetValue.TargetFolder -eq $TargetPath) {
            $copyDate = Get-ItemProperty -Path $regPath -Name "LastCopyDate" -ErrorAction SilentlyContinue
            $success = Get-ItemProperty -Path $regPath -Name "Success" -ErrorAction SilentlyContinue
            
            Write-Output "Registry marker found - LastCopy: $($copyDate.LastCopyDate), Success: $($success.Success)"
            return ($success.Success -eq "True")
        }
    }
    
    return $false
}

# ==================== MAIN EXECUTION ====================

$detected = $false
$detectionMethods = @()

# Method 1: Check folder exists
if (Test-FolderExists -Path $TargetFolder) {
    $detected = $true
    $detectionMethods += "FolderExists"
}

# Method 2: Check registry marker
if (Test-RegistryMarker -TargetPath $TargetFolder) {
    $detected = $true
    $detectionMethods += "RegistryMarker"
}

# Output result
if ($detected) {
    Write-Output "Detection methods triggered: $($detectionMethods -join ', ')"
    exit 0  # Compliant / Installed
}
else {
    Write-Output "Copied folder not detected at: $TargetFolder"
    exit 1  # Not compliant / Not installed
}