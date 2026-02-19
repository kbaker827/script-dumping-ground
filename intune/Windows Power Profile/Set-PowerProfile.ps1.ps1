#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Imports and sets a Windows power profile (power plan) for Intune deployment.

.DESCRIPTION
    Imports a Windows power plan from an exported .pow file and optionally sets it
    as the active plan. Can also copy an existing plan from the local computer.
    Designed for standardizing power settings across devices via Intune.

.PARAMETER PowerPlanFile
    Path to the exported power plan .pow file to import

.PARAMETER PlanName
    Name for the imported power plan (if not specified, uses filename)

.PARAMETER SetActive
    Set the imported plan as the active (current) power plan

.PARAMETER CopyExistingPlan
    Copy an existing power plan by GUID instead of importing from file

.PARAMETER SourcePlanGUID
    GUID of the source plan to copy (use with CopyExistingPlan)

.PARAMETER NewPlanName
    Name for the copied plan (use with CopyExistingPlan)

.PARAMETER ExportCurrentPlan
    Export the current active plan to a file (for capture/setup)

.PARAMETER ExportPath
    Path to export the current plan (use with ExportCurrentPlan)

.PARAMETER ListPlans
    List all available power plans and exit

.PARAMETER LogPath
    Path for operation logs

.EXAMPLE
    .\Set-PowerProfile.ps1 -PowerPlanFile "C:\PowerPlans\Corporate.pow" -SetActive

.EXAMPLE
    .\Set-PowerProfile.ps1 -CopyExistingPlan -SourcePlanGUID "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" -NewPlanName "Corporate High Performance" -SetActive

.EXAMPLE
    .\Set-PowerProfile.ps1 -ListPlans

.EXAMPLE
    .\Set-PowerProfile.ps1 -ExportCurrentPlan -ExportPath "C:\PowerPlans\Current.pow"

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
    Requirements:   Windows 10/11, Administrator rights
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$PowerPlanFile,

    [Parameter(Mandatory=$false)]
    [string]$PlanName,

    [Parameter(Mandatory=$false)]
    [switch]$SetActive,

    [Parameter(Mandatory=$false)]
    [switch]$CopyExistingPlan,

    [Parameter(Mandatory=$false)]
    [string]$SourcePlanGUID,

    [Parameter(Mandatory=$false)]
    [string]$NewPlanName,

    [Parameter(Mandatory=$false)]
    [switch]$ExportCurrentPlan,

    [Parameter(Mandatory=$false)]
    [string]$ExportPath,

    [Parameter(Mandatory=$false)]
    [switch]$ListPlans,

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
)

# Configuration
$ScriptName = "PowerProfile"
$LogFile = "$LogPath\$ScriptName.log"
$RegistryPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\PowerProfile"

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
        Write-Host $logEntry
    }
    
    $color = switch ($Level) {
        "ERROR"   { "Red" }
        "WARN"    { "Yellow" }
        "SUCCESS" { "Green" }
        default   { "White" }
    }
    Write-Host $logEntry -ForegroundColor $color
}

function Get-PowerPlans {
    try {
        $plans = powercfg /list 2>&1
        $planObjects = @()
        
        foreach ($line in $plans) {
            if ($line -match "Power Scheme GUID:\s+([\w-]+)\s+\((.+?)\)\s*(\*?)") {
                $planObjects += [PSCustomObject]@{
                    GUID = $matches[1]
                    Name = $matches[2]
                    IsActive = ($matches[3] -eq "*")
                }
            }
        }
        
        return $planObjects
    }
    catch {
        Write-Log "Failed to get power plans: $($_.Exception.Message)" "ERROR"
        return @()
    }
}

function Show-PowerPlans {
    Write-Log "Available Power Plans:"
    $plans = Get-PowerPlans
    
    foreach ($plan in $plans) {
        $status = if ($plan.IsActive) { " [ACTIVE]" } else { "" }
        Write-Log "  GUID: $($plan.GUID) - Name: $($plan.Name)$status"
    }
    
    return $plans
}

function Import-PowerPlan {
    param(
        [string]$FilePath,
        [string]$Name
    )
    
    try {
        if (-not (Test-Path -Path $FilePath)) {
            throw "Power plan file not found: $FilePath"
        }
        
        Write-Log "Importing power plan from: $FilePath"
        
        # Import the plan
        $result = powercfg /import "$FilePath" 2>&1
        Write-Log "Import result: $result"
        
        # Extract the new GUID from result
        if ($result -match "GUID:\s+([\w-]+)") {
            $newGUID = $matches[1]
            Write-Log "Imported plan GUID: $newGUID" "SUCCESS"
            
            # Rename if name provided
            if (-not [string]::IsNullOrEmpty($Name)) {
                Write-Log "Renaming plan to: $Name"
                $renameResult = powercfg /changename $newGUID "$Name" 2>&1
                Write-Log "Rename result: $renameResult"
            }
            
            return $newGUID
        }
        else {
            throw "Could not extract GUID from import result"
        }
    }
    catch {
        Write-Log "Failed to import power plan: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Copy-PowerPlan {
    param(
        [string]$SourceGUID,
        [string]$NewName
    )
    
    try {
        Write-Log "Copying power plan with GUID: $SourceGUID"
        
        # Export the source plan
        $tempFile = "$env:TEMP\PowerPlanExport.pow"
        $exportResult = powercfg /export "$tempFile" $SourceGUID 2>&1
        Write-Log "Export result: $exportResult"
        
        if (-not (Test-Path -Path $tempFile)) {
            throw "Export failed - temp file not created"
        }
        
        # Import as new plan
        $newGUID = Import-PowerPlan -FilePath $tempFile -Name $NewName
        
        # Cleanup temp file
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
        
        return $newGUID
    }
    catch {
        Write-Log "Failed to copy power plan: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Set-ActivePowerPlan {
    param([string]$GUID)
    
    try {
        Write-Log "Setting active power plan to GUID: $GUID"
        $result = powercfg /setactive $GUID 2>&1
        Write-Log "Set active result: $result"
        
        # Verify
        $current = powercfg /getactivescheme 2>&1
        if ($current -match $GUID) {
            Write-Log "Power plan activated successfully" "SUCCESS"
            return $true
        }
        else {
            Write-Log "Power plan activation may have failed" "WARN"
            return $false
        }
    }
    catch {
        Write-Log "Failed to set active power plan: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Export-PowerPlan {
    param(
        [string]$OutputPath,
        [string]$PlanGUID = ""
    )
    
    try {
        # If no GUID specified, export current active plan
        if ([string]::IsNullOrEmpty($PlanGUID)) {
            $active = powercfg /getactivescheme 2>&1
            if ($active -match "GUID:\s+([\w-]+)") {
                $PlanGUID = $matches[1]
            }
            else {
                throw "Could not determine active power plan"
            }
        }
        
        # Ensure output directory exists
        $outputDir = Split-Path -Path $OutputPath -Parent
        if (-not (Test-Path -Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }
        
        Write-Log "Exporting power plan $PlanGUID to: $OutputPath"
        $result = powercfg /export "$OutputPath" $PlanGUID 2>&1
        Write-Log "Export result: $result" "SUCCESS"
        
        return (Test-Path -Path $OutputPath)
    }
    catch {
        Write-Log "Failed to export power plan: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Register-Operation {
    param(
        [string]$PlanGUID,
        [string]$PlanName,
        [bool]$IsActive,
        [bool]$Success
    )
    
    try {
        if (!(Test-Path $RegistryPath)) {
            New-Item -Path $RegistryPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $RegistryPath -Name "PlanGUID" -Value $PlanGUID
        Set-ItemProperty -Path $RegistryPath -Name "PlanName" -Value $PlanName
        Set-ItemProperty -Path $RegistryPath -Name "IsActive" -Value ([string]$IsActive)
        Set-ItemProperty -Path $RegistryPath -Name "LastRun" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Set-ItemProperty -Path $RegistryPath -Name "Success" -Value ([string]$Success)
        
        Write-Log "Operation registered in registry" "SUCCESS"
    }
    catch {
        Write-Log "Failed to register operation: $($_.Exception.Message)" "WARN"
    }
}

# ==================== MAIN EXECUTION ====================

Write-Log "=== Windows Power Profile Script Started ==="
Write-Log "Script version: 1.0"

# List plans and exit if requested
if ($ListPlans) {
    Show-PowerPlans
    exit 0
}

# Export current plan and exit if requested
if ($ExportCurrentPlan) {
    $exportPath = if ([string]::IsNullOrEmpty($ExportPath)) { "$env:TEMP\CurrentPowerPlan.pow" } else { $ExportPath }
    $success = Export-PowerPlan -OutputPath $exportPath
    exit ($success ? 0 : 1)
}

$importedGUID = $null
$finalPlanName = $PlanName

# Import from file or copy existing
if (-not [string]::IsNullOrEmpty($PowerPlanFile)) {
    # Import from file
    $importedGUID = Import-PowerPlan -FilePath $PowerPlanFile -Name $PlanName
    if ([string]::IsNullOrEmpty($finalPlanName)) {
        $finalPlanName = [System.IO.Path]::GetFileNameWithoutExtension($PowerPlanFile)
    }
}
elseif ($CopyExistingPlan) {
    # Copy existing plan
    if ([string]::IsNullOrEmpty($SourcePlanGUID)) {
        Write-Log "SourcePlanGUID is required when using CopyExistingPlan" "ERROR"
        exit 1
    }
    if ([string]::IsNullOrEmpty($NewPlanName)) {
        Write-Log "NewPlanName is required when using CopyExistingPlan" "ERROR"
        exit 1
    }
    
    $importedGUID = Copy-PowerPlan -SourceGUID $SourcePlanGUID -NewName $NewPlanName
    $finalPlanName = $NewPlanName
}
else {
    Write-Log "No action specified. Use -PowerPlanFile, -CopyExistingPlan, -ListPlans, or -ExportCurrentPlan" "ERROR"
    Write-Log "Run with -ListPlans to see available power plans"
    exit 1
}

if (-not $importedGUID) {
    Write-Log "Failed to import/copy power plan" "ERROR"
    exit 1
}

# Set as active if requested
$isActive = $false
if ($SetActive) {
    $isActive = Set-ActivePowerPlan -GUID $importedGUID
}

# Register completion
Register-Operation -PlanGUID $importedGUID -PlanName $finalPlanName -IsActive $isActive -Success $true

Write-Log "=== Power profile operation completed ===" "SUCCESS"
Write-Log "Plan GUID: $importedGUID"
Write-Log "Plan Name: $finalPlanName"
Write-Log "Set Active: $isActive"

exit 0