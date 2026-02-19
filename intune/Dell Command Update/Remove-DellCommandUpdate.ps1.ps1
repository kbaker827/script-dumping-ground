#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Removes Dell Command Update from the system.

.DESCRIPTION
    Uninstalls Dell Command Update and removes associated files.

.PARAMETER LogPath
    Path for operation logs

.EXAMPLE
    .\Remove-DellCommandUpdate.ps1

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
)

$ScriptName = "DellCommandUpdateRemove"
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

function Get-UninstallString {
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($regPath in $regPaths) {
        $app = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -like "*Dell Command*Update*" }
        
        if ($app -and $app.UninstallString) {
            return $app.UninstallString
        }
    }
    
    return $null
}

function Remove-DellCommandUpdate {
    try {
        $uninstallString = Get-UninstallString
        
        if ($uninstallString) {
            Write-Log "Found uninstall string: $uninstallString"
            
            if ($uninstallString -match '"(.+?)"') {
                $exe = $matches[1]
                $args = "/S"  # Silent uninstall
                
                Write-Log "Running: $exe $args"
                $process = Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru
                Write-Log "Uninstaller exited with code: $($process.ExitCode)"
            }
        }
        else {
            Write-Log "No uninstall string found - may already be removed" "WARN"
        }
        
        # Remove remaining files
        $paths = @(
            "${env:ProgramFiles(x86)}\Dell\CommandUpdate",
            "$env:ProgramFiles\Dell\CommandUpdate",
            "$env:ProgramData\Dell\CommandUpdate"
        )
        
        foreach ($path in $paths) {
            if (Test-Path -Path $path) {
                Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Removed: $path"
            }
        }
        
        # Remove registry
        $regPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\DellCommandUpdate"
        if (Test-Path $regPath) {
            Remove-Item -Path $regPath -Force -ErrorAction SilentlyContinue
        }
        
        Write-Log "Removal completed" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Removal failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Main
Write-Log "=== Dell Command Update Removal Started ==="
$success = Remove-DellCommandUpdate

if ($success) {
    Write-Log "=== Removal completed ===" "SUCCESS"
    exit 0
}
else {
    exit 1
}