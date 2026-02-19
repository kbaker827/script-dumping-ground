<#
.SYNOPSIS
    Detection script for power profile.

.DESCRIPTION
    Checks if the specified power plan is active.
    Returns exit code 0 if detected/active, 1 if not.

.PARAMETER PlanGUID
    GUID of the power plan to check (optional)

.PARAMETER PlanName
    Name of the power plan to check (optional)

.EXAMPLE
    .\Detect-PowerProfile.ps1 -PlanGUID "12345678-1234-1234-1234-123456789012"

.EXAMPLE
    .\Detect-PowerProfile.ps1 -PlanName "Corporate Power Plan"

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$PlanGUID,

    [Parameter(Mandatory=$false)]
    [string]$PlanName
)

$VerbosePreference = "SilentlyContinue"

function Get-ActivePlan {
    try {
        $active = powercfg /getactivescheme 2>&1
        if ($active -match "GUID:\s+([\w-]+)\s+\((.+?)\)") {
            return @{
                GUID = $matches[1]
                Name = $matches[2]
            }
        }
        return $null
    }
    catch {
        return $null
    }
}

function Test-PlanExists {
    param([string]$GUID)
    
    $plans = powercfg /list 2>&1
    foreach ($line in $plans) {
        if ($line -match $GUID) {
            return $true
        }
    }
    return $false
}

function Test-RegistryMarker {
    $regPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\PowerProfile"
    
    if (Test-Path -Path $regPath) {
        $guid = Get-ItemProperty -Path $regPath -Name "PlanGUID" -ErrorAction SilentlyContinue
        $success = Get-ItemProperty -Path $regPath -Name "Success" -ErrorAction SilentlyContinue
        
        if ($guid -and $success.Success -eq "True") {
            Write-Output "Registry marker found - Plan: $($guid.PlanGUID)"
            return $true
        }
    }
    return $false
}

# Main
$activePlan = Get-ActivePlan
if ($activePlan) {
    Write-Output "Active power plan: $($activePlan.Name) ($($activePlan.GUID))"
}

# Check by GUID
if (-not [string]::IsNullOrEmpty($PlanGUID)) {
    if (Test-PlanExists -GUID $PlanGUID) {
        $isActive = ($activePlan -and $activePlan.GUID -eq $PlanGUID)
        Write-Output "Specified plan found. Active: $isActive"
        exit 0
    }
}

# Check by Name
if (-not [string]::IsNullOrEmpty($PlanName)) {
    if ($activePlan -and $activePlan.Name -eq $PlanName) {
        Write-Output "Specified plan is active"
        exit 0
    }
}

# Check registry
if (Test-RegistryMarker) {
    exit 0
}

Write-Output "Specified power plan not found or not active"
exit 1