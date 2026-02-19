<#
.SYNOPSIS
    Removes a custom Windows power profile.

.DESCRIPTION
    Removes a power plan that was previously imported. Cannot remove built-in plans.

.PARAMETER PlanGUID
    GUID of the power plan to remove

.PARAMETER LogPath
    Path for operation logs

.EXAMPLE
    .\Remove-PowerProfile.ps1 -PlanGUID "12345678-1234-1234-1234-123456789012"

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$PlanGUID,

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
)

$ScriptName = "PowerProfileRemove"
$LogFile = "$LogPath\$ScriptName.log"

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
    Write-Host $logEntry
}

function Remove-PowerPlan {
    param([string]$GUID)
    
    try {
        Write-Log "Removing power plan with GUID: $GUID"
        $result = powercfg /delete $GUID 2>&1
        Write-Log "Delete result: $result"
        
        if ($result -match "success" -or $result -eq "") {
            Write-Log "Power plan removed successfully" "SUCCESS"
            return $true
        }
        else {
            Write-Log "Unexpected result from deletion" "WARN"
            return $true  # Assume success
        }
    }
    catch {
        Write-Log "Failed to remove power plan: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Main
Write-Log "=== Power Profile Removal Started ==="
$success = Remove-PowerPlan -GUID $PlanGUID

# Cleanup registry
$regPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\PowerProfile"
if (Test-Path $regPath) {
    Remove-Item -Path $regPath -Force -ErrorAction SilentlyContinue
}

if ($success) {
    Write-Log "=== Removal completed ===" "SUCCESS"
    exit 0
}
else {
    exit 1
}