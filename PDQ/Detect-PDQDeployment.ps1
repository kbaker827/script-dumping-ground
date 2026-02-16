#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Detection script for Intune to verify PDQ deployment status.

.DESCRIPTION
    This script checks if a PDQ deployment completed successfully.
    Returns exit code 0 if deployed, 1 if not (standard Intune detection logic).

    Place this in the "Detection rules" section when creating the Win32 app in Intune.
#>

param(
    [Parameter()]
    [string]$PackageName = "YOUR-PDQ-PACKAGE-NAME",
    
    [Parameter()]
    [string]$RegistryKey = "HKLM:\SOFTWARE\Intune\PDQDeployments"
)

# Check registry for deployment marker
if (Test-Path $RegistryKey) {
    $Deployment = Get-ItemProperty -Path $RegistryKey -Name $PackageName -ErrorAction SilentlyContinue
    if ($Deployment) {
        # Check if deployment was within last 30 days
        $LastRun = [datetime]$Deployment.LastRun
        if ((Get-Date) - $LastRun -lt (New-TimeSpan -Days 30)) {
            Write-Host "Package '$PackageName' deployed successfully on $($LastRun.ToString('yyyy-MM-dd'))"
            exit 0  # Intune: App is installed
        }
    }
}

# Alternative: Check for specific file/registry that PDQ package creates
# Modify this based on what your PDQ package actually installs
$ProgramFilesPaths = @(
    "C:\Program Files\$PackageName",
    "C:\Program Files (x86)\$PackageName"
)

foreach ($Path in $ProgramFilesPaths) {
    if (Test-Path $Path) {
        Write-Host "Found installation at: $Path"
        exit 0  # Intune: App is installed
    }
}

# Not found
Write-Host "Package '$PackageName' not detected"
exit 1  # Intune: App is NOT installed
