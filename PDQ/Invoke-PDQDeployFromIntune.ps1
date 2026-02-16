#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Intune Win32 App Package - Triggers PDQ Deploy packages remotely.

.DESCRIPTION
    This script is designed to be packaged as an Intune Win32 app (.intunewin).
    It triggers PDQ Deploy packages to run on target machines by calling the
    PDQ Deploy console remotely.

    Requirements:
    - PDQ Deploy must be installed on a server accessible from target machines
    - Target machines must have PDQ Inventory/Deploy agents or be reachable
    - PowerShell remoting must be enabled (or use PDQ's built-in methods)

    Author: Kyle Baker
    Version: 1.0
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$PDQServer = "YOUR-PDQ-SERVER",
    
    [Parameter()]
    [string]$PackageName = "YOUR-PDQ-PACKAGE-NAME",
    
    [Parameter()]
    [string[]]$TargetComputers = @($env:COMPUTERNAME),
    
    [Parameter()]
    [int]$TimeoutMinutes = 30,
    
    [Parameter()]
    [switch]$WaitForCompletion
)

#region Configuration
$ErrorActionPreference = "Stop"
$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\PDQ-Deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$PDQDeployPath = "C:\Program Files (x86)\Admin Arsenal\PDQ Deploy\pdqdeploy.exe"
#endregion

#region Logging Function
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
    
    # Ensure log directory exists
    $LogDir = Split-Path -Parent $LogPath
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    
    Add-Content -Path $LogPath -Value $LogEntry
    
    switch ($Level) {
        "Info"    { Write-Host $LogEntry }
        "Warning" { Write-Warning $Message }
        "Error"   { Write-Error $Message }
        "Success" { Write-Host $LogEntry -ForegroundColor Green }
    }
}
#endregion

#region Main Script
try {
    Write-Log "Starting PDQ Deploy trigger for package: $PackageName"
    Write-Log "Target computer(s): $($TargetComputers -join ', ')"
    
    # Check if running as admin
    $IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $IsAdmin) {
        throw "This script must be run as Administrator"
    }
    
    # Method 1: If PDQ Deploy is installed locally (PDQ Console on this machine)
    if (Test-Path $PDQDeployPath) {
        Write-Log "Found local PDQ Deploy installation"
        
        foreach ($Computer in $TargetComputers) {
            Write-Log "Deploying '$PackageName' to $Computer"
            
            $Arguments = @(
                "deploy",
                "-package", "`"$PackageName`"",
                "-targets", $Computer
            )
            
            if ($WaitForCompletion) {
                $Arguments += "-wait"
            }
            
            $Process = Start-Process -FilePath $PDQDeployPath -ArgumentList $Arguments -Wait:$WaitForCompletion -PassThru -WindowStyle Hidden
            
            if ($WaitForCompletion) {
                if ($Process.ExitCode -eq 0) {
                    Write-Log "Deployment to $Computer completed successfully" -Level "Success"
                } else {
                    Write-Log "Deployment to $Computer failed with exit code: $($Process.ExitCode)" -Level "Error"
                }
            } else {
                Write-Log "Deployment to $Computer initiated (PID: $($Process.Id))" -Level "Success"
            }
        }
    }
    # Method 2: Remote PDQ Server via PowerShell Remoting
    elseif ($PDQServer -ne "YOUR-PDQ-SERVER") {
        Write-Log "Connecting to remote PDQ server: $PDQServer"
        
        # Create session to PDQ server
        $Session = New-PSSession -ComputerName $PDQServer -ErrorAction Stop
        
        try {
            Invoke-Command -Session $Session -ScriptBlock {
                param($PkgName, $Targets, $Timeout)
                
                $PDQPath = "C:\Program Files (x86)\Admin Arsenal\PDQ Deploy\pdqdeploy.exe"
                
                if (-not (Test-Path $PDQPath)) {
                    throw "PDQ Deploy not found on server"
                }
                
                foreach ($Target in $Targets) {
                    $Args = @(
                        "deploy",
                        "-package", "`"$PkgName`"",
                        "-targets", $Target,
                        "-timeout", $Timeout
                    )
                    
                    & $PDQPath @Args
                }
            } -ArgumentList $PackageName, $TargetComputers, $TimeoutMinutes
            
            Write-Log "Remote deployment initiated successfully" -Level "Success"
        }
        finally {
            Remove-PSSession -Session $Session
        }
    }
    else {
        throw "PDQ Deploy not found locally and no remote server configured. Please update PDQServer parameter."
    }
    
    Write-Log "PDQ Deploy trigger completed successfully" -Level "Success"
    exit 0
}
catch {
    Write-Log "Error: $_" -Level "Error"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level "Error"
    exit 1
}
#endregion
