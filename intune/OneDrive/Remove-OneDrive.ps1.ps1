#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Removes Microsoft OneDrive from the system.

.DESCRIPTION
    Uninstalls OneDrive and removes residual files and registry entries.

.PARAMETER RemoveUserData
    Also remove user data folders

.PARAMETER LogPath
    Path for operation logs

.EXAMPLE
    .\Remove-OneDrive.ps1

.EXAMPLE
    .\Remove-OneDrive.ps1 -RemoveUserData

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$RemoveUserData,

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
)

$ScriptName = "OneDriveRemove"
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

function Stop-OneDriveProcess {
    $processes = Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue
    foreach ($proc in $processes) {
        Write-Log "Stopping OneDrive process (PID: $($proc.Id))"
        Stop-Process -Id $proc.Id -Force
    }
}

function Uninstall-OneDrive {
    try {
        # Try per-machine uninstall first
        $perMachinePath = "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDriveSetup.exe"
        if (Test-Path -Path $perMachinePath) {
            Write-Log "Uninstalling per-machine installation"
            $process = Start-Process -FilePath $perMachinePath -ArgumentList "/uninstall /allusers" -Wait -PassThru
            Write-Log "Uninstaller exited: $($process.ExitCode)"
        }
        
        # Try per-user uninstall
        $perUserPath = "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe"
        if (Test-Path -Path $perUserPath) {
            Write-Log "Uninstalling per-user installation"
            $process = Start-Process -FilePath $perUserPath -ArgumentList "/uninstall" -Wait -PassThru
            Write-Log "Uninstaller exited: $($process.ExitCode)"
        }
        
        return $true
    }
    catch {
        Write-Log "Uninstall failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Remove-OneDriveResiduals {
    param([bool]$RemoveData)
    
    try {
        # Remove installation directories
        $paths = @(
            "${env:ProgramFiles(x86)}\Microsoft OneDrive",
            "$env:LOCALAPPDATA\Microsoft\OneDrive",
            "$env:ProgramData\Microsoft OneDrive"
        )
        
        foreach ($path in $paths) {
            if (Test-Path -Path $path) {
                Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Removed: $path"
            }
        }
        
        # Remove user data if requested
        if ($RemoveData) {
            $userPaths = @(
                "$env:USERPROFILE\OneDrive",
                "$env:USERPROFILE\Documents\OneDrive"
            )
            
            foreach ($path in $userPaths) {
                if (Test-Path -Path $path) {
                    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Log "Removed user data: $path"
                }
            }
        }
        
        # Remove registry entries
        $regPaths = @(
            "HKLM:\SOFTWARE\Microsoft\OneDrive",
            "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive",
            "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\OneDrive"
        )
        
        foreach ($regPath in $regPaths) {
            if (Test-Path -Path $regPath) {
                Remove-Item -Path $regPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Removed registry: $regPath"
            }
        }
        
        # Remove from startup
        $runPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        Remove-ItemProperty -Path $runPath -Name "OneDrive" -ErrorAction SilentlyContinue
        
        return $true
    }
    catch {
        Write-Log "Cleanup failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Main
Write-Log "=== OneDrive Removal Started ==="

Stop-OneDriveProcess
$uninstall = Uninstall-OneDrive
$cleanup = Remove-OneDriveResiduals -RemoveData $RemoveUserData

if ($uninstall -or $cleanup) {
    Write-Log "=== Removal completed ===" "SUCCESS"
    exit 0
}
else {
    exit 1
}