<#
.SYNOPSIS
    Universal uninstaller for all Adobe Acrobat products via Intune.

.DESCRIPTION
    Detects and removes ALL Adobe Acrobat variants including:
    - Adobe Acrobat Reader DC (all versions)
    - Adobe Acrobat Pro DC
    - Adobe Acrobat Standard DC
    - Adobe Acrobat XI (legacy)
    - Adobe Acrobat 2020/2023 (Classic Track)

    Uses multiple methods: MSI GUIDs, Adobe Cleaner Tool, manual cleanup.
    Designed for Intune Win32 app deployment.

    Exit Codes:
    0 = Success (all products removed or none found)
    1 = Partial failure (some products may remain)

    Author: Kyle Baker
    Version: 1.0
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$UseCleanerTool = $true,
    
    [Parameter()]
    [switch]$AggressiveCleanup = $false,
    
    [Parameter()]
    [string]$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Adobe-Acrobat-Universal-Uninstall-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
)

#region Configuration
$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

# Known Adobe Acrobat MSI GUIDs (Reader and Pro variants)
$AcrobatGUIDs = @(
    # Adobe Acrobat Reader DC
    "{AC76BA86-7AD7-1033-7B44-AC0F074E4100}",
    "{AC76BA86-7AD7-1033-7B44-AC0F074E4100}",
    "{AC76BA86-0804-1033-1959-0010835504B}",
    "{AC76BA86-0000-0000-0000-6028747ADE01}",
    "{AC76BA86-7AD7-0000-0000-6028747ADE01}",
    "{AC76BA86-1033-0000-0000-6028747ADE01}",
    "{AC76BA86-7AD7-FFFF-9E44-AC0F074E4100}",
    # Adobe Acrobat Pro DC
    "{AC76BA86-1033-FFFF-7760-0E1450C5A17A}",
    "{AC76BA86-1033-FFFF-7760-0E2950C5A17A}",
    "{AC76BA86-1033-FFFF-7760-0E3950C5A17A}",
    "{AC76BA86-1033-FFFF-7760-0E4950C5A17A}",
    # Adobe Acrobat Standard DC
    "{AC76BA86-1033-0000-7760-0E1450C5A17A}",
    "{AC76BA86-1033-0000-7760-0E2950C5A17A}",
    # Adobe Acrobat XI
    "{AC76BA86-1033-F400-7760-000000000006}",
    "{AC76BA86-1033-F400-7760-000000000005}",
    # Adobe Acrobat 2020
    "{AC76BA86-1033-0000-BA7E-000000000006}",
    "{AC76BA86-1033-0000-BA7E-000000000005}",
    # Adobe Acrobat 2023
    "{AC76BA86-1033-0000-9E44-AC0F074E4100}",
    "{AC76BA86-1033-FFFF-9E44-AC0F074E4100}",
    # Adobe Genuine Service (often installed with Acrobat)
    "{AC76BA86-0804-1033-1959-0010835504B}",
    "{AC76BA86-0000-0000-0000-AC76BA86FFFF}",
    # Adobe Acrobat Update Service
    "{AC76BA86-0000-0000-0000-6028747ADE01}",
    "{AC76BA86-7AD7-0000-0000-6028747ADE01}"
)

# Adobe Acrobat related services
$AdobeServices = @(
    "Adobe Acrobat Update Service",
    "Adobe Genuine Monitor Service",
    "Adobe Genuine Software Integrity Service",
    "AdobeARMservice",
    "AGSService",
    "AdobeUpdateService"
)

# Adobe Acrobat related processes
$AdobeProcesses = @(
    "AcroRd32",
    "AcroCEF",
    "AcroTray",
    "AdobeARM",
    "AdobeARMHelper",
    "acrodist",
    "Acrobat",
    "AdobeCollabSync",
    "CoreSync",
    "AdobeIPCBroker",
    "LogTransport2",
    "CCXProcess",
    "CCLibrary",
    "node"
)
#endregion

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
        "Error"   { Write-Error $Message -ErrorAction Continue }
        "Success" { Write-Host $LogEntry -ForegroundColor Green }
    }
}
#endregion

#region Functions
function Stop-AdobeProcesses {
    Write-Log "Stopping Adobe processes..."
    
    foreach ($ProcessName in $AdobeProcesses) {
        $Processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        if ($Processes) {
            Write-Log "Stopping process: $ProcessName"
            $Processes | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }
    
    Start-Sleep -Seconds 2
    Write-Log "Process termination completed" -Level "Success"
}

function Stop-AdobeServices {
    Write-Log "Stopping Adobe services..."
    
    foreach ($ServiceName in $AdobeServices) {
        $Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($Service) {
            if ($Service.Status -eq "Running") {
                Write-Log "Stopping service: $ServiceName"
                Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
            }
            Write-Log "Disabling service: $ServiceName"
            Set-Service -Name $ServiceName -StartupType Disabled -ErrorAction SilentlyContinue
        }
    }
    
    Write-Log "Service cleanup completed" -Level "Success"
}

function Uninstall-AdobeMSI {
    param(
        [string]$GUID,
        [string]$ProductName = "Unknown Adobe Product"
    )
    
    try {
        Write-Log "Attempting MSI uninstall: $ProductName ($GUID)"
        
        $Process = Start-Process -FilePath "msiexec.exe" `
            -ArgumentList "/x `"$GUID`" /qn /norestart /l*v `"$env:TEMP\Adobe-Uninstall-$GUID.log`"" `
            -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
        
        if ($Process.ExitCode -eq 0 -or $Process.ExitCode -eq 3010) {
            Write-Log "Successfully uninstalled: $ProductName" -Level "Success"
            return $true
        } else {
            Write-Log "MSI uninstall failed for $ProductName with code: $($Process.ExitCode)" -Level "Warning"
            return $false
        }
    }
    catch {
        Write-Log "Error uninstalling $ProductName`: $_" -Level "Warning"
        return $false
    }
}

function Get-InstalledAdobeProducts {
    Write-Log "Scanning for installed Adobe Acrobat products..."
    
    $InstalledProducts = @()
    
    # Method 1: WMI Win32_Product (slow but thorough)
    try {
        $WMIProducts = Get-WmiObject -Class Win32_Product | Where-Object { 
            $_.Name -like "*Adobe Acrobat*" -or 
            $_.Name -like "*Adobe Reader*" -or
            $_.Publisher -like "*Adobe*"
        }
        
        foreach ($Product in $WMIProducts) {
            $InstalledProducts += [PSCustomObject]@{
                Name = $Product.Name
                GUID = $Product.IdentifyingNumber
                Version = $Product.Version
                Source = "WMI"
            }
        }
    }
    catch {
        Write-Log "WMI scan failed: $_" -Level "Warning"
    }
    
    # Method 2: Registry scan
    $RegistryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($RegPath in $RegistryPaths) {
        try {
            $RegProducts = Get-ItemProperty $RegPath -ErrorAction SilentlyContinue | Where-Object { 
                $_.DisplayName -like "*Adobe Acrobat*" -or 
                $_.DisplayName -like "*Adobe Reader*"
            }
            
            foreach ($Product in $RegProducts) {
                # Check if already found via WMI
                $Exists = $InstalledProducts | Where-Object { $_.GUID -eq $Product.PSChildName }
                if (-not $Exists) {
                    $InstalledProducts += [PSCustomObject]@{
                        Name = $Product.DisplayName
                        GUID = $Product.PSChildName
                        Version = $Product.DisplayVersion
                        Source = "Registry"
                    }
                }
            }
        }
        catch {
            # Continue to next path
        }
    }
    
    return $InstalledProducts
}

function Invoke-AdobeCleanerTool {
    param(
        [string]$CleanerToolUrl = "https://helpx.adobe.com/content/dam/help/en/acrobat/kb/acrobat-cleaner-tool/AcroCleaner_DC2022.exe"
    )
    
    Write-Log "Downloading and running Adobe Cleaner Tool..."
    
    $CleanerPath = "$env:TEMP\AcroCleaner.exe"
    $Success = $false
    
    try {
        # Download cleaner tool
        Invoke-WebRequest -Uri $CleanerToolUrl -OutFile $CleanerPath -UseBasicParsing -TimeoutSec 120
        Write-Log "Adobe Cleaner Tool downloaded"
        
        # Run cleaner tool silently
        # /silent = silent mode, /product=10 = Acrobat/Reader
        $Process = Start-Process -FilePath $CleanerPath `
            -ArgumentList "/silent /product=10" `
            -Wait -PassThru -WindowStyle Hidden
        
        if ($Process.ExitCode -eq 0) {
            Write-Log "Adobe Cleaner Tool completed successfully" -Level "Success"
            $Success = $true
        } else {
            Write-Log "Adobe Cleaner Tool exit code: $($Process.ExitCode)" -Level "Warning"
        }
    }
    catch {
        Write-Log "Adobe Cleaner Tool failed: $_" -Level "Warning"
    }
    finally {
        if (Test-Path $CleanerPath) {
            Remove-Item $CleanerPath -Force -ErrorAction SilentlyContinue
        }
    }
    
    return $Success
}

function Remove-AdobeResiduals {
    Write-Log "Removing Adobe Acrobat residual files and registry entries..."
    
    # Program Files directories
    $ProgramPaths = @(
        "${env:ProgramFiles(x86)}\Adobe\Acrobat Reader DC",
        "${env:ProgramFiles(x86)}\Adobe\Acrobat 2020",
        "${env:ProgramFiles(x86)}\Adobe\Acrobat 2023",
        "${env:ProgramFiles(x86)}\Adobe\Acrobat XI",
        "${env:ProgramFiles}\Adobe\Acrobat Reader DC",
        "${env:ProgramFiles}\Adobe\Acrobat 2020",
        "${env:ProgramFiles}\Adobe\Acrobat 2023",
        "${env:ProgramFiles}\Adobe\Acrobat XI",
        "${env:ProgramFiles}\Adobe\Acrobat DC"
    )
    
    foreach ($Path in $ProgramPaths) {
        if (Test-Path $Path) {
            Write-Log "Removing directory: $Path"
            Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    # User profile data
    $UserProfiles = Get-WmiObject -Class Win32_UserProfile | Where-Object { 
        -not $_.Special -and $_.LocalPath -notlike "*service*" 
    }
    
    foreach ($Profile in $UserProfiles) {
        $UserPath = $Profile.LocalPath
        $AdobePaths = @(
            "$UserPath\AppData\Local\Adobe\Acrobat",
            "$UserPath\AppData\Roaming\Adobe\Acrobat",
            "$UserPath\AppData\LocalLow\Adobe\Acrobat"
        )
        
        foreach ($Path in $AdobePaths) {
            if (Test-Path $Path) {
                Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    # Common AppData
    $CommonPaths = @(
        "C:\ProgramData\Adobe\Acrobat",
        "C:\ProgramData\Adobe\ARM",
        "C:\ProgramData\Adobe\SLStore"
    )
    
    foreach ($Path in $CommonPaths) {
        if (Test-Path $Path) {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Registry cleanup
    $RegistryKeys = @(
        "HKLM:\SOFTWARE\Adobe\Acrobat Reader",
        "HKLM:\SOFTWARE\Adobe\Adobe Acrobat",
        "HKLM:\SOFTWARE\WOW6432Node\Adobe\Acrobat Reader",
        "HKLM:\SOFTWARE\WOW6432Node\Adobe\Adobe Acrobat",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\AcroRd32.exe",
        "HKLM:\SOFTWARE\Classes\AcroExch.Document"
    )
    
    foreach ($Key in $RegistryKeys) {
        if (Test-Path $Key) {
            Write-Log "Removing registry key: $Key"
            Remove-Item -Path $Key -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Shortcuts
    $ShortcutPaths = @(
        "$env:Public\Desktop\Adobe Acrobat*.lnk",
        "$env:Public\Desktop\Adobe Reader*.lnk",
        "C:\Users\*\Desktop\Adobe Acrobat*.lnk",
        "C:\Users\*\Desktop\Adobe Reader*.lnk"
    )
    
    foreach ($Shortcut in $ShortcutPaths) {
        Get-Item -Path $Shortcut -ErrorAction SilentlyContinue | Remove-Item -Force
    }
    
    Write-Log "Residual cleanup completed" -Level "Success"
}

function Remove-ScheduledTasks {
    Write-Log "Removing Adobe scheduled tasks..."
    
    $AdobeTasks = Get-ScheduledTask | Where-Object { 
        $_.TaskName -like "*Adobe*" -or 
        $_.TaskPath -like "*Adobe*" 
    }
    
    foreach ($Task in $AdobeTasks) {
        try {
            Unregister-ScheduledTask -TaskName $Task.TaskName -Confirm:$false -ErrorAction Stop
            Write-Log "Removed scheduled task: $($Task.TaskName)"
        }
        catch {
            Write-Log "Failed to remove task $($Task.TaskName): $_" -Level "Warning"
        }
    }
}
#endregion

#region Main Script
Write-Log "=== Adobe Acrobat Universal Uninstaller Started ==="
Write-Log "Parameters: UseCleanerTool=$UseCleanerTool, AggressiveCleanup=$AggressiveCleanup"

$ExitCode = 0
$ProductsRemoved = 0
$ProductsFailed = 0

try {
    # Step 1: Stop running processes
    Stop-AdobeProcesses
    
    # Step 2: Stop and disable services
    Stop-AdobeServices
    
    # Step 3: Detect installed products
    $InstalledProducts = Get-InstalledAdobeProducts
    
    if ($InstalledProducts.Count -eq 0) {
        Write-Log "No Adobe Acrobat products detected" -Level "Success"
    } else {
        Write-Log "Found $($InstalledProducts.Count) Adobe product(s) to remove:"
        foreach ($Product in $InstalledProducts) {
            Write-Log "  - $($Product.Name) (v$($Product.Version)) [$($Product.Source)]"
        }
        
        # Step 4: Uninstall detected products
        foreach ($Product in $InstalledProducts) {
            $Success = Uninstall-AdobeMSI -GUID $Product.GUID -ProductName $Product.Name
            if ($Success) {
                $ProductsRemoved++
            } else {
                $ProductsFailed++
            }
        }
    }
    
    # Step 5: Try known GUIDs (in case WMI/Registry missed them)
    Write-Log "Checking additional known GUIDs..."
    foreach ($GUID in $AcrobatGUIDs) {
        $Installed = Get-WmiObject -Class Win32_Product -Filter "IdentifyingNumber='$GUID'" -ErrorAction SilentlyContinue
        if ($Installed) {
            Write-Log "Found additional product via GUID: $($Installed.Name)"
            $Success = Uninstall-AdobeMSI -GUID $GUID -ProductName $Installed.Name
            if ($Success) { $ProductsRemoved++ } else { $ProductsFailed++ }
        }
    }
    
    # Step 6: Adobe Cleaner Tool (if enabled and products remain)
    if ($UseCleanerTool -and ($ProductsFailed -gt 0 -or $AggressiveCleanup)) {
        $CleanerSuccess = Invoke-AdobeCleanerTool
        if ($CleanerSuccess) {
            $ProductsFailed = 0  # Assume cleaner handled it
        }
    }
    
    # Step 7: Aggressive cleanup of residuals
    Remove-AdobeResiduals
    Remove-ScheduledTasks
    
    # Step 8: Final verification
    Write-Log "Performing final verification scan..."
    $RemainingProducts = Get-InstalledAdobeProducts
    
    if ($RemainingProducts.Count -eq 0) {
        Write-Log "=== All Adobe Acrobat products successfully removed ===" -Level "Success"
        $ExitCode = 0
    } else {
        Write-Log "WARNING: $($RemainingProducts.Count) product(s) may still be present:" -Level "Warning"
        foreach ($Product in $RemainingProducts) {
            Write-Log "  - $($Product.Name)" -Level "Warning"
        }
        $ExitCode = 1
    }
    
    Write-Log "Summary: Removed=$ProductsRemoved, Failed=$ProductsFailed"
}
catch {
    Write-Log "CRITICAL ERROR: $_" -Level "Error"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level "Error"
    $ExitCode = 1
}

Write-Log "=== Uninstaller completed with exit code $ExitCode ==="
exit $ExitCode
#endregion
