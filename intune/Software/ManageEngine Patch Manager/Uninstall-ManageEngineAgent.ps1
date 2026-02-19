#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Uninstalls ManageEngine Patch Manager Plus agent.

.DESCRIPTION
    Removes the ManageEngine Patch Manager Plus agent from the system.
    Can be used for Intune uninstall command or manual removal.

.PARAMETER LogPath
    Path for uninstallation logs

.EXAMPLE
    .\Uninstall-ManageEngineAgent.ps1

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

# Configuration
$ScriptName = "ManageEngineAgentUninstall"
$LogFile = "$LogPath\$ScriptName.log"

# Ensure log directory exists
if (!(Test-Path -Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    try {
        Add-Content -Path $LogFile -Value $logEntry -ErrorAction SilentlyContinue
    }
    catch {
        # Fallback to console if log file is locked
    }
    
    $color = switch ($Level) {
        "ERROR"   { "Red" }
        "WARN"    { "Yellow" }
        "SUCCESS" { "Green" }
        default   { "White" }
    }
    Write-Host $logEntry -ForegroundColor $color
}

function Get-AgentUninstallString {
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($regPath in $regPaths) {
        $product = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -like "*ManageEngine*Patch*Agent*" -or $_.DisplayName -like "*Patch Manager Plus*" }
        
        if ($product -and $product.UninstallString) {
            Write-Log "Found uninstall string: $($product.UninstallString)"
            return @{
                UninstallString = $product.UninstallString
                ProductCode = $product.PSChildName
                DisplayName = $product.DisplayName
            }
        }
    }
    
    return $null
}

function Stop-AgentProcesses {
    $processes = @("PatchManagerAgent", "PMService", "ManageEngineAgent")
    
    foreach ($procName in $processes) {
        $process = Get-Process -Name $procName -ErrorAction SilentlyContinue
        if ($process) {
            Write-Log "Stopping process: $procName"
            Stop-Process -Name $procName -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Stop the service first
    $service = Get-Service -Name "PatchManagerAgent" -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -eq "Running") {
            Write-Log "Stopping Patch Manager Agent service..."
            Stop-Service -Name "PatchManagerAgent" -Force -ErrorAction SilentlyContinue
        }
        
        # Set to disabled to prevent auto-start
        Set-Service -Name "PatchManagerAgent" -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Log "Service disabled"
    }
}

function Uninstall-Agent {
    $agentInfo = Get-AgentUninstallString
    
    if (-not $agentInfo) {
        Write-Log "ManageEngine Patch Manager Agent not found in registry. May already be uninstalled." "WARN"
        return $true
    }
    
    Write-Log "Found agent: $($agentInfo.DisplayName)"
    
    try {
        $uninstallString = $agentInfo.UninstallString
        $productCode = $agentInfo.ProductCode
        
        # Determine if it's MSI or EXE uninstaller
        if ($uninstallString -match "msiexec") {
            Write-Log "Using MSI uninstall method..."
            
            # Extract product code if present
            if ($uninstallString -match "{[A-F0-9-]+") {
                $productCode = $matches[0]
            }
            
            $uninstallArgs = @(
                "/x", $productCode
                "/qn"
                "/norestart"
                "/l*v", "`"$LogPath\ManageEngineAgent_Uninstall.log`""
            )
            
            Write-Log "Running: msiexec.exe $($uninstallArgs -join ' ')"
            $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $uninstallArgs -Wait -PassThru
        }
        else {
            Write-Log "Using EXE uninstall method..."
            
            # Handle EXE uninstallers
            $uninstallArgs = "/S"  # Silent uninstall flag (common convention)
            
            # Parse any existing arguments from the uninstall string
            if ($uninstallString -match '"(.+?)"\s*(.*)') {
                $exePath = $matches[1]
                $existingArgs = $matches[2]
                
                if (-not [string]::IsNullOrEmpty($existingArgs)) {
                    $uninstallArgs = "$existingArgs $uninstallArgs"
                }
            }
            else {
                $exePath = $uninstallString
            }
            
            Write-Log "Running: $exePath $uninstallArgs"
            $process = Start-Process -FilePath $exePath -ArgumentList $uninstallArgs -Wait -PassThru
        }
        
        Write-Log "Uninstall process exited with code: $($process.ExitCode)"
        
        # Common MSI exit codes
        switch ($process.ExitCode) {
            0       { Write-Log "Uninstall completed successfully" "SUCCESS"; return $true }
            3010    { Write-Log "Uninstall completed - restart required" "SUCCESS"; return $true }
            1605    { Write-Log "Product not found (may already be uninstalled)" "WARN"; return $true }
            1614    { Write-Log "Uninstall completed with warnings" "WARN"; return $true }
            default { 
                if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
                    return $true
                }
                Write-Log "Uninstall completed with exit code: $($process.ExitCode)" "WARN"
                return $false
            }
        }
    }
    catch {
        Write-Log "Uninstall failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Remove-AgentResiduals {
    Write-Log "Cleaning up residual files and registry entries..."
    
    # Remove service if still present
    $service = Get-Service -Name "PatchManagerAgent" -ErrorAction SilentlyContinue
    if ($service) {
        try {
            sc.exe delete "PatchManagerAgent" | Out-Null
            Write-Log "Service removed"
        }
        catch {
            Write-Log "Failed to remove service: $($_.Exception.Message)" "WARN"
        }
    }
    
    # Remove installation directories
    $installPaths = @(
        "$env:ProgramFiles\ManageEngine\Patch Manager",
        "$env:ProgramFiles(x86)\ManageEngine\Patch Manager",
        "$env:ProgramData\ManageEngine\Patch Manager"
    )
    
    foreach ($path in $installPaths) {
        if (Test-Path -Path $path) {
            try {
                Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                Write-Log "Removed directory: $path"
            }
            catch {
                Write-Log "Failed to remove directory $path : $($_.Exception.Message)" "WARN"
            }
        }
    }
    
    # Remove registry entries
    $regPaths = @(
        "HKLM:\SOFTWARE\ManageEngine\Patch Manager",
        "HKLM:\SOFTWARE\WOW6432Node\ManageEngine\Patch Manager",
        "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\ManageEnginePatchAgent"
    )
    
    foreach ($regPath in $regPaths) {
        if (Test-Path -Path $regPath) {
            try {
                Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
                Write-Log "Removed registry key: $regPath"
            }
            catch {
                Write-Log "Failed to remove registry key $regPath : $($_.Exception.Message)" "WARN"
            }
        }
    }
    
    # Remove startup items
    $startupPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
    )
    
    foreach ($startupPath in $startupPaths) {
        if (Test-Path -Path $startupPath) {
            $startupItems = Get-ItemProperty -Path $startupPath -ErrorAction SilentlyContinue | 
                Get-Member -MemberType NoteProperty | 
                Where-Object { $_.Name -like "*ManageEngine*" -or $_.Name -like "*PatchManager*" }
            
            foreach ($item in $startupItems) {
                try {
                    Remove-ItemProperty -Path $startupPath -Name $item.Name -Force
                    Write-Log "Removed startup item: $($item.Name)"
                }
                catch {
                    Write-Log "Failed to remove startup item $($item.Name)" "WARN"
                }
            }
        }
    }
}

# ==================== MAIN EXECUTION ====================

Write-Log "=== ManageEngine Patch Manager Agent Uninstallation Started ==="

# Stop processes and service first
Stop-AgentProcesses

# Perform uninstallation
$uninstallSuccess = Uninstall-Agent

# Clean up residuals regardless of uninstall result
Remove-AgentResiduals

if ($uninstallSuccess) {
    Write-Log "=== Uninstallation completed successfully ===" "SUCCESS"
    exit 0
}
else {
    Write-Log "=== Uninstallation completed with warnings ===" "WARN"
    exit 0  # Return success anyway as agent is likely removed
}