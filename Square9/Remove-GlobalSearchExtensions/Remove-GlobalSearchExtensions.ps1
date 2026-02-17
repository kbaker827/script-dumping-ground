<#
.SYNOPSIS
    Remotely removes Square 9 GlobalSearch Extensions from target computers.

.DESCRIPTION
    This script connects to remote computers via PowerShell Remoting and performs 
    a comprehensive cleanup of Square 9 GlobalSearch Extensions, including:
    - Stopping related processes
    - Running uninstallers (machine-wide and per-user)
    - Cleaning up ClickOnce caches
    - Removing shortcuts and residual files
    - Cleaning up lingering services and registry entries
    - Generating detailed cleanup reports
    
    All actions are logged to C:\ProgramData\Square9-Cleanup\cleanup.log on each 
    remote host, with optional central logging to the executing machine.

.PARAMETER ComputerName
    One or more computer names to clean. Can be provided via pipeline.

.PARAMETER Credential
    Optional credentials for remote connection. If not provided, current credentials are used.

.PARAMETER DryRun
    Shows what would be done without making changes.

.PARAMETER Parallel
    Process multiple computers in parallel for faster execution.

.PARAMETER ThrottleLimit
    Maximum number of concurrent parallel operations. Default: 5.

.PARAMETER Force
    Suppress confirmation prompts.

.PARAMETER IncludeServices
    Also remove Square 9 Windows services if found.

.PARAMETER LogPath
    Central log path on the executing machine for consolidated reporting.

.PARAMETER TimeoutMinutes
    Timeout for remote operations in minutes. Default: 10.

.EXAMPLE
    .\Remove-GlobalSearchExtensions.ps1 -ComputerName "PC01", "PC02"
    Cleans up GlobalSearch Extensions on the specified computers.

.EXAMPLE
    .\Remove-GlobalSearchExtensions.ps1 -ComputerName "PC01" -DryRun
    Shows what would be cleaned without making changes.

.EXAMPLE
    .\Remove-GlobalSearchExtensions.ps1 -ComputerName (Get-Content computers.txt) -Parallel -ThrottleLimit 10
    Cleans all computers in the text file in parallel.

.EXAMPLE
    Get-ADComputer -Filter {Enabled -eq $true} | Select-Object -ExpandProperty Name | .\Remove-GlobalSearchExtensions.ps1 -Force
    Pipeline input from Active Directory.

.NOTES
    Version:        3.0
    Author:         IT Admin
    Updated:        2026-02-12
    
    Requirements:
    - PowerShell Remoting (WinRM) enabled on target computers
    - Administrator rights on target computers
    - Windows Firewall allowing WinRM (port 5985/5986)
    
    Exit Codes:
    0   - Success (all computers cleaned)
    1   - Partial success (some computers failed)
    2   - All computers failed
    3   - No valid computer names provided
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, Position=0)]
    [Alias('CN', 'MachineName', 'Name')]
    [string[]]$ComputerName,
    
    [PSCredential]$Credential,
    
    [switch]$DryRun,
    [switch]$Parallel,
    
    [ValidateRange(1, 20)]
    [int]$ThrottleLimit = 5,
    
    [switch]$Force,
    [switch]$IncludeServices,
    
    [string]$LogPath = (Join-Path $env:TEMP "GlobalSearchCleanup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"),
    
    [ValidateRange(1, 60)]
    [int]$TimeoutMinutes = 10
)

#region Configuration
$ErrorActionPreference = 'Stop'
$script:Version = "3.0"
$script:StartTime = Get-Date
$script:Results = [System.Collections.Generic.List[object]]::new()

# Process names to stop
$script:ProcessNames = @(
    'Square9.ExtensionsWebHelper',
    'GlobalSearchExtensions',
    'Square9Extensions',
    'Square9.Extensions',
    'Square9.GlobalSearch',
    'SmartSearch',
    'GlobalSearch.Desktop'
)

# Service names
$script:ServiceNames = @(
    'Square9GlobalSearch',
    'S9GlobalSearch',
    'GlobalSearchExtensions'
)

# Uninstall patterns
$script:UninstallPatterns = @(
    'GlobalSearch Extension',
    'GlobalSearch Extensions',
    'Square ?9.*Extension',
    'GlobalSearch Desktop Extensions',
    'GlobalSearch Browser Extension',
    'SmartSearch',
    'Square9 SmartSearch'
)

# File/folder patterns to remove
$script:PathPatterns = @(
    'Square_9_Softworks',
    'Square9',
    'GlobalSearch',
    'SmartSearch'
)
#endregion

#region Helper Functions
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Detail')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"
    
    try {
        Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
    } catch {}
    
    $colors = @{
        Info    = 'Cyan'
        Success = 'Green'
        Warning = 'Yellow'
        Error   = 'Red'
        Detail  = 'Gray'
    }
    
    $prefix = switch ($Level) {
        'Info'    { '[*]' }
        'Success' { '[+]' }
        'Warning' { '[!]' }
        'Error'   { '[-]' }
        'Detail'  { '   ' }
    }
    
    Write-Host "$prefix $Message" -ForegroundColor $colors[$Level]
}

function Show-Header {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  GlobalSearch Extension Cleanup v$script:Version" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Log "Started: $($script:StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level Detail
    Write-Log "Central log: $LogPath" -Level Detail
    Write-Log "DryRun: $DryRun, Parallel: $Parallel" -Level Detail
}

function Show-Summary {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  SUMMARY" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    
    $total = $script:Results.Count
    $success = ($script:Results | Where-Object { $_.Success }).Count
    $failed = ($script:Results | Where-Object { -not $_.Success }).Count
    
    Write-Log "Total computers: $total" -Level Info
    Write-Log "Successful: $success" -Level $(if ($success -gt 0) { 'Success' } else { 'Info' })
    Write-Log "Failed: $failed" -Level $(if ($failed -gt 0) { 'Error' } else { 'Success' })
    
    if ($failed -gt 0) {
        Write-Host ""
        Write-Log "Failed computers:" -Level Error
        $script:Results | Where-Object { -not $_.Success } | ForEach-Object {
            Write-Log "  - $($_.ComputerName): $($_.ErrorMessage)" -Level Error
        }
    }
    
    $duration = (Get-Date) - $script:StartTime
    Write-Host ""
    Write-Log "Duration: $($duration.ToString('mm\:ss'))" -Level Info
    Write-Log "Central log: $LogPath" -Level Detail
}

function Get-ComputerList {
    if (-not $ComputerName) {
        $inputText = Read-Host "Enter computer name(s) (comma-separated, or pipe from AD/Get-Content)"
        $list = $inputText -split '[,\s]+' | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() } | Select-Object -Unique
        return $list
    }
    return $ComputerName | Select-Object -Unique
}
#endregion

#region Remote Cleanup Script Block
$RemoteCleanupScript = {
    param(
        [switch]$DryRun,
        [switch]$IncludeServices,
        [string[]]$ProcessNames,
        [string[]]$ServiceNames,
        [string[]]$UninstallPatterns,
        [string[]]$PathPatterns
    )
    
    $ErrorActionPreference = 'Stop'
    $result = @{
        ComputerName = $env:COMPUTERNAME
        Success = $true
        ErrorMessage = $null
        Actions = [System.Collections.Generic.List[string]]::new()
        ProcessesStopped = 0
        UninstallersRun = 0
        FoldersRemoved = 0
        ShortcutsRemoved = 0
        ServicesRemoved = 0
    }
    
    # Setup logging
    $logRoot = 'C:\ProgramData\Square9-Cleanup'
    try {
        New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
    } catch {}
    $logFile = Join-Path $logRoot "cleanup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    
    function Write-LocalLog {
        param([string]$Message, [string]$Level = 'INFO')
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        "$timestamp [$Level] $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
    }
    
    function Invoke-SafeAction {
        param(
            [scriptblock]$Action,
            [string]$Description,
            [switch]$CountAction
        )
        try {
            if ($DryRun) {
                Write-LocalLog "DRYRUN: $Description"
                $result.Actions.Add("[DRYRUN] $Description")
                return
            }
            
            Write-LocalLog $Description
            & $Action
            $result.Actions.Add("[OK] $Description")
            
            if ($CountAction) {
                switch -Regex ($Description) {
                    'process' { $result.ProcessesStopped++ }
                    'Uninstall' { $result.UninstallersRun++ }
                    'folder|cache' { $result.FoldersRemoved++ }
                    'shortcut' { $result.ShortcutsRemoved++ }
                    'service' { $result.ServicesRemoved++ }
                }
            }
        }
        catch {
            Write-LocalLog "ERROR: $Description :: $($_.Exception.Message)" 'ERROR'
            $result.Actions.Add("[ERROR] $Description : $($_.Exception.Message)")
        }
    }
    
    Write-LocalLog "=== GlobalSearch Extensions cleanup started (DryRun=$DryRun) ==="
    
    # Stop processes
    foreach ($procName in $ProcessNames) {
        $processes = Get-Process -Name $procName -ErrorAction SilentlyContinue
        if ($processes) {
            Invoke-SafeAction -Action {
                $processes | Stop-Process -Force
            } -Description "Stopping process: $procName ($(($processes | Measure-Object).Count) instance(s))" -CountAction
        }
    }
    
    # Stop services if requested
    if ($IncludeServices) {
        foreach ($svcName in $ServiceNames) {
            $service = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($service) {
                Invoke-SafeAction -Action {
                    Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 1
                    sc.exe delete $svcName 2>&1 | Out-Null
                } -Description "Removing service: $svcName" -CountAction
            }
        }
    }
    
    # Find and run uninstallers
    function Get-UninstallEntries {
        $registryPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        $entries = @()
        foreach ($regPath in $registryPaths) {
            $items = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                if ($item.DisplayName) {
                    foreach ($pattern in $UninstallPatterns) {
                        if ($item.DisplayName -match $pattern) {
                            $entries += $item
                            break
                        }
                    }
                }
            }
        }
        return $entries | Sort-Object DisplayName -Unique
    }
    
    function Uninstall-Entry {
        param($Entry)
        $name = $Entry.DisplayName
        $uninstallCmd = $Entry.UninstallString
        if (-not $uninstallCmd) {
            Write-LocalLog "No UninstallString for: $name"
            return
        }
        
        # Parse command
        if ($uninstallCmd.StartsWith('"')) {
            $closingQuote = $uninstallCmd.IndexOf('"', 1)
            $exe = $uninstallCmd.Substring(1, $closingQuote - 1)
            $args = $uninstallCmd.Substring($closingQuote + 1).Trim()
        } else {
            $parts = $uninstallCmd.Split(' ', 2)
            $exe = $parts[0]
            $args = if ($parts.Count -gt 1) { $parts[1] } else { '' }
        }
        
        # Add silent flags
        if ($exe -match 'msiexec(\.exe)?$') {
            if ($args -notmatch '/x') { $args = "/x $args" }
            if ($args -notmatch '/qn') { $args += ' /qn' }
            if ($args -notmatch '/norestart') { $args += ' /norestart' }
        } else {
            if ($args -notmatch '/(?i:quiet|silent|S)\b') { $args += ' /S' }
        }
        
        Invoke-SafeAction -Action {
            $proc = Start-Process -FilePath $exe -ArgumentList $args -Wait -WindowStyle Hidden -PassThru
            Write-LocalLog "Uninstall exit code for $name`: $($proc.ExitCode)"
        } -Description "Uninstalling: $name" -CountAction
    }
    
    $entries = Get-UninstallEntries
    if ($entries) {
        foreach ($entry in $entries) {
            Uninstall-Entry -Entry $entry
        }
    } else {
        Write-LocalLog "No machine-wide GlobalSearch Extension uninstall entries found"
    }
    
    # Profile cleanup
    $profileRoot = 'C:\Users'
    $skipProfiles = @('All Users', 'Default', 'Default User', 'Public', 'WDAGUtilityAccount')
    $profiles = Get-ChildItem -Path $profileRoot -Directory -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -notin $skipProfiles }
    
    foreach ($profile in $profiles) {
        $basePath = $profile.FullName
        
        # Target folders
        $targetFolders = @(
            (Join-Path $basePath 'AppData\Local\Square_9_Softworks\GlobalSearch_Extensions'),
            (Join-Path $basePath 'AppData\Local\Apps\Square9_Apps'),
            (Join-Path $basePath 'AppData\Local\Square9\GlobalSearch_Extensions'),
            (Join-Path $basePath 'AppData\Local\Square9'),
            (Join-Path $basePath 'AppData\Roaming\Square9'),
            (Join-Path $basePath 'AppData\Roaming\Square_9_Softworks')
        )
        
        foreach ($folder in $targetFolders) {
            if (Test-Path $folder) {
                Invoke-SafeAction -Action {
                    Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
                } -Description "Removing folder: $folder" -CountAction
            }
        }
        
        # ClickOnce cache cleanup
        $clickOncePath = Join-Path $basePath 'AppData\Local\Apps\2.0'
        if (Test-Path $clickOncePath) {
            $subdirs = Get-ChildItem -Path $clickOncePath -Recurse -Directory -ErrorAction SilentlyContinue | 
                Where-Object { $_.FullName -match 'square9|globalsearch|smartsearch' }
            
            foreach ($subdir in $subdirs) {
                Invoke-SafeAction -Action {
                    Remove-Item -Path $subdir.FullName -Recurse -Force -ErrorAction SilentlyContinue
                } -Description "Removing ClickOnce cache: $($subdir.FullName)" -CountAction
            }
            
            # Remove lock files
            Get-ChildItem -Path (Join-Path $clickOncePath '*\square9.loginclient-update.lock') -ErrorAction SilentlyContinue | 
                ForEach-Object {
                    Invoke-SafeAction -Action {
                        Remove-Item -Path $_.FullName -Force
                    } -Description "Removing lock file: $($_.FullName)"
                }
        }
        
        # Local app data cleanup
        $localAppData = Join-Path $basePath 'AppData\Local'
        foreach ($pattern in $PathPatterns) {
            Get-ChildItem -Path $localAppData -Filter "*$pattern*" -Directory -ErrorAction SilentlyContinue | 
                ForEach-Object {
                    Invoke-SafeAction -Action {
                        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    } -Description "Removing local app data: $($_.FullName)" -CountAction
                }
        }
    }
    
    # Shortcut cleanup
    $shortcutRoots = @(
        'C:\ProgramData\Microsoft\Windows\Start Menu\Programs',
        'C:\Users\Public\Desktop',
        'C:\ProgramData\Desktop'
    )
    
    foreach ($root in $shortcutRoots) {
        if (Test-Path $root) {
            Get-ChildItem -Path $root -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue | 
                Where-Object { $_.Name -match 'GlobalSearch|Square ?9|Extensions|SmartSearch' } | 
                ForEach-Object {
                    Invoke-SafeAction -Action {
                        Remove-Item -Path $_.FullName -Force
                    } -Description "Removing shortcut: $($_.FullName)" -CountAction
                }
        }
    }
    
    # Registry cleanup (selected keys)
    $registryKeys = @(
        'HKLM:\SOFTWARE\Square9Softworks',
        'HKLM:\SOFTWARE\Square_9_Softworks',
        'HKLM:\SOFTWARE\WOW6432Node\Square9Softworks',
        'HKLM:\SOFTWARE\WOW6432Node\Square_9_Softworks'
    )
    
    foreach ($key in $registryKeys) {
        if (Test-Path $key) {
            Invoke-SafeAction -Action {
                Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue
            } -Description "Removing registry key: $key"
        }
    }
    
    # Final process sweep
    Start-Sleep -Seconds 2
    foreach ($procName in $ProcessNames) {
        $processes = Get-Process -Name $procName -ErrorAction SilentlyContinue
        if ($processes) {
            Invoke-SafeAction -Action {
                $processes | Stop-Process -Force
            } -Description "Stopping lingering process: $procName" -CountAction
        }
    }
    
    Write-LocalLog "=== Cleanup completed. Reboot recommended. ==="
    
    return $result
}
#endregion

#region Main Execution
Show-Header

# Get computer list
$computers = Get-ComputerList

if (-not $computers) {
    Write-Log "No valid computer names provided." -Level Error
    exit 3
}

Write-Log "Target computers: $($computers -join ', ')" -Level Info
Write-Log "Total: $($computers.Count) computer(s)" -Level Info

# Confirmation
if (-not $Force -and -not $DryRun) {
    Write-Host ""
    $confirm = Read-Host "Proceed with cleanup on $($computers.Count) computer(s)? (Y/N)"
    if ($confirm -notmatch '^(y|yes)$') {
        Write-Log "Operation cancelled by user." -Level Warning
        exit 4
    }
}

# Process computers
if ($Parallel -and $computers.Count -gt 1) {
    Write-Log "Processing in parallel (max $ThrottleLimit concurrent)..." -Level Info
    
    $computers | ForEach-Object -Parallel {
        $computer = $_
        $result = [PSCustomObject]@{
            ComputerName = $computer
            Success = $false
            ErrorMessage = $null
        }
        
        try {
            $invokeParams = @{
                ComputerName = $computer
                ScriptBlock = $using:RemoteCleanupScript
                ArgumentList = @(
                    $using:DryRun,
                    $using:IncludeServices,
                    $using:ProcessNames,
                    $using:ServiceNames,
                    $using:UninstallPatterns,
                    $using:PathPatterns
                )
                ErrorAction = 'Stop'
            }
            
            if ($using:Credential) {
                $invokeParams.Credential = $using:Credential
            }
            
            $remoteResult = Invoke-Command @invokeParams
            $result.Success = $remoteResult.Success
            $result.ErrorMessage = $remoteResult.ErrorMessage
            
            Write-Host "[$computer] Processes: $($remoteResult.ProcessesStopped), Uninstallers: $($remoteResult.UninstallersRun), Folders: $($remoteResult.FoldersRemoved)" -ForegroundColor $(if ($result.Success) { 'Green' } else { 'Red' })
        }
        catch {
            $result.Success = $false
            $result.ErrorMessage = $_.Exception.Message
            Write-Host "[$computer] FAILED: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        $result
    } -ThrottleLimit $ThrottleLimit | ForEach-Object {
        $script:Results.Add($_)
    }
}
else {
    # Sequential processing
    foreach ($computer in $computers) {
        Write-Host ""
        Write-Log "Processing: $computer" -Level Info
        
        $result = [PSCustomObject]@{
            ComputerName = $computer
            Success = $false
            ErrorMessage = $null
        }
        
        try {
            # Test connection
            if (-not (Test-Connection -ComputerName $computer -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
                Write-Log "Ping failed for $computer, trying WinRM anyway..." -Level Warning
            }
            
            # Execute cleanup
            $invokeParams = @{
                ComputerName = $computer
                ScriptBlock = $RemoteCleanupScript
                ArgumentList = @(
                    $DryRun,
                    $IncludeServices,
                    $ProcessNames,
                    $ServiceNames,
                    $UninstallPatterns,
                    $PathPatterns
                )
                ErrorAction = 'Stop'
            }
            
            if ($Credential) {
                $invokeParams.Credential = $Credential
            }
            
            $remoteResult = Invoke-Command @invokeParams
            $result.Success = $remoteResult.Success
            $result.ErrorMessage = $remoteResult.ErrorMessage
            
            $status = if ($DryRun) { "DRY RUN" } else { "COMPLETED" }
            Write-Log "$status on $computer" -Level $(if ($result.Success) { 'Success' } else { 'Error' })
            Write-Log "  Log: \\$computer\C$\ProgramData\Square9-Cleanup\" -Level Detail
            Write-Log "  Processes: $($remoteResult.ProcessesStopped), Uninstallers: $($remoteResult.UninstallersRun), Folders: $($remoteResult.FoldersRemoved)" -Level Detail
        }
        catch {
            $result.Success = $false
            $result.ErrorMessage = $_.Exception.Message
            Write-Log "FAILED on $computer`: $($_.Exception.Message)" -Level Error
        }
        
        $script:Results.Add($result)
    }
}

# Show summary
Show-Summary

# Determine exit code
$failedCount = ($script:Results | Where-Object { -not $_.Success }).Count
if ($failedCount -eq 0) {
    exit 0
} elseif ($failedCount -lt $script:Results.Count) {
    exit 1
} else {
    exit 2
}
#endregion
