<#
.SYNOPSIS
    Uninstalls Adobe Acrobat Reader DC for Intune deployment.

.DESCRIPTION
    Silently uninstalls Adobe Acrobat Reader DC using the official uninstaller
    or MSI GUID. Cleans up residual files and registry entries.

    Exit Codes:
    0 = Success
    1 = Failure

    Author: Kyle Baker
    Version: 1.0
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AdobeReader-Uninstall-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

#region Logging
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info"
    )
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"
    
    $LogDir = Split-Path -Parent $LogPath
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    Add-Content -Path $LogPath -Value $LogEntry -ErrorAction SilentlyContinue
    
    switch ($Level) {
        "Info"    { Write-Host $LogEntry }
        "Warning" { Write-Warning $Message }
        "Error"   { Write-Error $Message }
        "Success" { Write-Host $LogEntry -ForegroundColor Green }
    }
}
#endregion

try {
    Write-Log "=== Adobe Acrobat Reader DC Uninstallation Started ==="
    
    # Common Adobe Reader MSI GUIDs (may vary by version)
    $MSIGUIDs = @(
        "{AC76BA86-7AD7-1033-7B44-AC0F074E4100}",  # Common Reader DC GUID
        "{AC76BA86-0804-1033-1959-0010835504B}",  # Alternative GUID
        "{AC76BA86-0000-0000-0000-6028747ADE01}"   # Another variant
    )
    
    $Uninstalled = $false
    
    # Method 1: Try MSI uninstall
    foreach ($GUID in $MSIGUIDs) {
        $Installed = Get-WmiObject -Class Win32_Product | Where-Object { $_.IdentifyingNumber -eq $GUID }
        if ($Installed) {
            Write-Log "Found Adobe Reader installation (GUID: $GUID)"
            Write-Log "Uninstalling via MSI..."
            
            $Process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$GUID`" /qn /norestart /l*v `"$env:TEMP\AdobeReader-Uninstall.log`"" -Wait -PassThru -WindowStyle Hidden
            
            if ($Process.ExitCode -eq 0 -or $Process.ExitCode -eq 3010) {
                Write-Log "MSI uninstall completed successfully" -Level "Success"
                $Uninstalled = $true
                break
            } else {
                Write-Log "MSI uninstall failed with code: $($Process.ExitCode)" -Level "Warning"
            }
        }
    }
    
    # Method 2: Try using Adobe's uninstaller if MSI method failed
    if (-not $Uninstalled) {
        $UninstallerPaths = @(
            "${env:ProgramFiles(x86)}\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe",
            "$env:ProgramFiles\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe"
        )
        
        foreach ($Uninstaller in $UninstallerPaths) {
            if (Test-Path $Uninstaller) {
                $SetupDir = Split-Path -Parent $Uninstaller
                $Helper = Join-Path $SetupDir "Setup.exe"
                
                if (Test-Path $Helper) {
                    Write-Log "Found Adobe Setup helper, attempting uninstall..."
                    $Process = Start-Process -FilePath $Helper -ArgumentList "/sAll /rs /msi /norestart" -Wait -PassThru -WindowStyle Hidden
                    
                    if ($Process.ExitCode -eq 0 -or $Process.ExitCode -eq 3010) {
                        Write-Log "Uninstall completed via Adobe Setup" -Level "Success"
                        $Uninstalled = $true
                        break
                    }
                }
            }
        }
    }
    
    # Method 3: Force removal if still present
    if (-not $Uninstalled) {
        Write-Log "Standard uninstall methods failed, checking for remaining files..." -Level "Warning"
    }
    
    # Clean up residual files
    $ResidualPaths = @(
        "${env:ProgramFiles(x86)}\Adobe\Acrobat Reader DC",
        "$env:ProgramFiles\Adobe\Acrobat Reader DC",
        "$env:LOCALAPPDATA\Adobe\Acrobat",
        "$env:APPDATA\Adobe\Acrobat",
        "C:\ProgramData\Adobe\Acrobat"
    )
    
    foreach ($Path in $ResidualPaths) {
        if (Test-Path $Path) {
            Write-Log "Removing residual path: $Path"
            Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Clean up registry entries
    $RegistryPaths = @(
        "HKLM:\SOFTWARE\Adobe\Acrobat Reader",
        "HKLM:\SOFTWARE\WOW6432Node\Adobe\Acrobat Reader",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{AC76BA86-7AD7-1033-7B44-AC0F074E4100}",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{AC76BA86-7AD7-1033-7B44-AC0F074E4100}"
    )
    
    foreach ($RegPath in $RegistryPaths) {
        if (Test-Path $RegPath) {
            Write-Log "Removing registry key: $RegPath"
            Remove-Item -Path $RegPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Clean up shortcuts
    $Shortcuts = @(
        "$env:Public\Desktop\Adobe Acrobat Reader DC.lnk",
        "$env:USERPROFILE\Desktop\Adobe Acrobat Reader DC.lnk"
    )
    
    foreach ($Shortcut in $Shortcuts) {
        if (Test-Path $Shortcut) {
            Remove-Item $Shortcut -Force -ErrorAction SilentlyContinue
        }
    }
    
    Write-Log "=== Uninstallation Completed ===" -Level "Success"
    exit 0
}
catch {
    Write-Log "ERROR: $_" -Level "Error"
    exit 1
}
