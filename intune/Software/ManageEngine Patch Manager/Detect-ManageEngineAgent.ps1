<#
.SYNOPSIS
    Detection script for ManageEngine Patch Manager Plus agent.

.DESCRIPTION
    Checks if the ManageEngine Patch Manager Plus agent is installed and running.
    Returns exit code 0 if detected, 1 if not detected.
    Designed for Intune Win32 app detection or Proactive Remediation.

.EXAMPLE
    .\Detect-ManageEngineAgent.ps1
    Exit code 0 = Agent detected
    Exit code 1 = Agent not detected

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
#>

[CmdletBinding()]
param()

$VerbosePreference = "SilentlyContinue"

function Test-AgentInstalled {
    # Check registry for installed product
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($regPath in $regPaths) {
        $product = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -like "*ManageEngine*Patch*Agent*" -or $_.DisplayName -like "*Patch Manager Plus*" }
        
        if ($product) {
            Write-Output "Agent found: $($product.DisplayName) v$($product.DisplayVersion)"
            return $true
        }
    }
    
    return $false
}

function Test-AgentService {
    $service = Get-Service -Name "PatchManagerAgent" -ErrorAction SilentlyContinue
    
    if ($service) {
        if ($service.Status -eq "Running") {
            Write-Output "Agent service is running"
            return $true
        }
        else {
            Write-Output "Agent service exists but is not running (Status: $($service.Status))"
            return $false
        }
    }
    
    return $false
}

function Test-AgentRegistryMarker {
    $regPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\ManageEnginePatchAgent"
    
    if (Test-Path -Path $regPath) {
        $installDate = Get-ItemProperty -Path $regPath -Name "InstallDate" -ErrorAction SilentlyContinue
        if ($installDate) {
            Write-Output "Registry marker found - InstallDate: $($installDate.InstallDate)"
            return $true
        }
    }
    
    return $false
}

function Test-AgentExecutable {
    $possiblePaths = @(
        "$env:ProgramFiles\ManageEngine\Patch Manager\Agent\",
        "$env:ProgramFiles(x86)\ManageEngine\Patch Manager\Agent\",
        "$env:ProgramFiles\ManageEngine\Patch Manager Plus\Agent\",
        "$env:ProgramFiles(x86)\ManageEngine\Patch Manager Plus\Agent\"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path -Path $path) {
            $exeFiles = Get-ChildItem -Path $path -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($exeFiles) {
                Write-Output "Agent executables found in: $path"
                return $true
            }
        }
    }
    
    return $false
}

# ==================== MAIN EXECUTION ====================

$detected = $false
$detectionMethods = @()

# Method 1: Registry check
if (Test-AgentInstalled) {
    $detected = $true
    $detectionMethods += "Registry"
}

# Method 2: Service check
if (Test-AgentService) {
    $detected = $true
    $detectionMethods += "Service"
}

# Method 3: Registry marker
if (Test-AgentRegistryMarker) {
    $detected = $true
    $detectionMethods += "RegistryMarker"
}

# Method 4: Executable files
if (Test-AgentExecutable) {
    $detected = $true
    $detectionMethods += "Executable"
}

# Output result
if ($detected) {
    Write-Output "Detection methods triggered: $($detectionMethods -join ', ')"
    exit 0  # Compliant / Installed
}
else {
    Write-Output "ManageEngine Patch Manager Agent not detected"
    exit 1  # Not compliant / Not installed
}