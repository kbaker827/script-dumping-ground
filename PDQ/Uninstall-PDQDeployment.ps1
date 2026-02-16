#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Uninstall script for Intune PDQ deployment package.

.DESCRIPTION
    Cleans up registry markers and logs for the PDQ deployment.
    This does NOT uninstall the software that PDQ deployed - 
    that should be handled by PDQ's own uninstall package.
#>

param(
    [Parameter()]
    [string]$PackageName = "YOUR-PDQ-PACKAGE-NAME",
    
    [Parameter()]
    [string]$RegistryKey = "HKLM:\SOFTWARE\Intune\PDQDeployments"
)

$ErrorActionPreference = "SilentlyContinue"

# Remove registry marker
if (Test-Path $RegistryKey) {
    Remove-ItemProperty -Path $RegistryKey -Name $PackageName -Force
    Write-Host "Removed registry marker for $PackageName"
}

# Clean up old logs older than 30 days
$LogDir = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
if (Test-Path $LogDir) {
    Get-ChildItem -Path $LogDir -Filter "PDQ-Deploy-*.log" | 
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
        Remove-Item -Force
    Write-Host "Cleaned up old log files"
}

Write-Host "Uninstall completed"
exit 0
