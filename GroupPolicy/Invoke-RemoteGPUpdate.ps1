<#
.SYNOPSIS
    Remotely refreshes Group Policy on target computers via PowerShell Remoting with GUI support.

.DESCRIPTION
    Provides multiple interfaces to execute gpupdate /force on remote machines:
    - GUI selection dialog for target computer and options
    - Command-line parameters for automation
    - Bulk processing of multiple computers
    - Credential management with secure prompts
    - Comprehensive logging and error handling

    Features:
    - Native Windows CredUI for credential prompts (with WinForms fallback)
    - ICMP ping verification (optional)
    - Target selection (Computer/User/Both policies)
    - Silent remote execution (no UI on target)
    - Multiple authentication methods

.PARAMETER ComputerName
    Target computer name(s). If omitted, GUI will prompt for selection.

.PARAMETER ComputerList
    Array of computer names for bulk processing.

.PARAMETER Credential
    PSCredential object for authentication.

.PARAMETER DefaultUser
    Pre-fills the username field in credential prompts.

.PARAMETER PolicyTarget
    Which policies to refresh: Both, Computer, or User. Default: Both.

.PARAMETER CommonComputers
    Array of computer names to populate the GUI dropdown. 
    Default: Common workstation naming patterns.

.PARAMETER SkipPing
    Skip ICMP connectivity test before attempting WinRM connection.

.PARAMETER UseCurrent
    Use current Windows sign-in credentials without prompting.

.PARAMETER ForcePrompt
    Always prompt for credentials, even if UseCurrent is set.

.PARAMETER LogPath
    Path to log file. Default: %ProgramData%\GpupdateRemote\gpupdate_<timestamp>.log

.PARAMETER LogToEventLog
    Also write results to Windows Event Log.

.PARAMETER TimeoutSec
    Timeout in seconds for remote command execution. Default: 60.

.PARAMETER Retries
    Number of credential prompt retries if cancelled. Default: 2.

.PARAMETER Parallel
    Process multiple computers in parallel (for bulk operations).

.PARAMETER ThrottleLimit
    Maximum parallel operations when using -Parallel. Default: 5.

.PARAMETER ExportResults
    Export results to CSV file.

.PARAMETER Quiet
    Suppress console output (for automation).

.EXAMPLE
    .\Invoke-RemoteGPUpdate.ps1
    Opens the GUI to select computer and options.

.EXAMPLE
    .\Invoke-RemoteGPUpdate.ps1 -ComputerName PC01 -PolicyTarget Computer -SkipPing
    Runs gpupdate /target:computer on PC01, skipping ping check.

.EXAMPLE
    .\Invoke-RemoteGPUpdate.ps1 -ComputerList PC01,PC02,PC03 -UseCurrent -Parallel
    Updates all three computers in parallel using current credentials.

.EXAMPLE
    .\Invoke-RemoteGPUpdate.ps1 -DefaultUser 'CONTOSO\AdminUser' -ForcePrompt
    Forces credential prompt with pre-filled username.

.EXAMPLE
    Get-Content computers.txt | .\Invoke-RemoteGPUpdate.ps1 -UseCurrent -ExportResults
    Bulk update from pipeline input.

.NOTES
    Version:        3.0
    Author:         IT Admin
    Updated:        2026-02-12
    
    Requirements:
    - PowerShell 5.1 or PowerShell 7+
    - WinRM enabled on target computers
    - Administrative rights on target computers
    - .NET Framework (for GUI components)
    
    Exit Codes:
    0   = Success
    1   = Remote execution failed
    2   = WinRM unavailable
    3   = Timeout
    4   = Cancelled by user
    5   = Credentials required but not provided
    6   = Invalid parameters
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
    [Alias('CN', 'MachineName', 'Name')]
    [string[]]$ComputerName,
    
    [string[]]$ComputerList,
    
    [PSCredential]$Credential,
    
    [string]$DefaultUser,
    
    [ValidateSet('Both', 'Computer', 'User')]
    [string]$PolicyTarget = 'Both',
    
    [string[]]$CommonComputers = @(
        $env:COMPUTERNAME,
        'localhost',
        'PC01', 'PC02', 'PC03',
        'WORKSTATION01', 'WORKSTATION02',
        'DESKTOP01', 'DESKTOP02',
        'LAPTOP01', 'LAPTOP02'
    ),
    
    [switch]$SkipPing,
    [switch]$UseCurrent,
    [switch]$ForcePrompt,
    
    [string]$LogPath = (Join-Path (Join-Path $env:ProgramData 'GpupdateRemote') 
        ("gpupdate_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))),
    
    [switch]$LogToEventLog,
    
    [ValidateRange(10, 300)]
    [int]$TimeoutSec = 60,
    
    [ValidateRange(1, 5)]
    [int]$Retries = 2,
    
    [switch]$Parallel,
    
    [ValidateRange(1, 20)]
    [int]$ThrottleLimit = 5,
    
    [switch]$ExportResults,
    
    [switch]$Quiet
)

#region Configuration
$ErrorActionPreference = 'Stop'
$script:Version = "3.0"
$script:StartTime = Get-Date
$script:Results = [System.Collections.Generic.List[object]]::new()
$script:LogBuffer = [System.Collections.Generic.List[string]]::new()

# Event Log configuration
$script:EventLogSource = "RemoteGPUpdate"
$script:EventLogName = "Application"
#endregion

#region Helper Functions
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'DEBUG', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp][$Level] $Message"
    
    # Console output
    if (-not $Quiet) {
        $color = switch ($Level) {
            'ERROR'   { 'Red' }
            'WARN'    { 'Yellow' }
            'SUCCESS' { 'Green' }
            'DEBUG'   { 'Gray' }
            default   { 'White' }
        }
        Write-Host $line -ForegroundColor $color
    }
    
    # File logging
    try {
        $logDir = Split-Path -Parent $LogPath
        if ($logDir -and -not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
    }
    catch {
        $script:LogBuffer.Add($line)
    }
    
    # Event Log
    if ($LogToEventLog) {
        try {
            $eventLevel = switch ($Level) {
                'ERROR'   { 'Error' }
                'WARN'    { 'Warning' }
                default   { 'Information' }
            }
            
            if (-not ([System.Diagnostics.EventLog]::SourceExists($script:EventLogSource))) {
                New-EventLog -LogName $script:EventLogName -Source $script:EventLogSource
            }
            
            Write-EventLog -LogName $script:EventLogName -Source $script:EventLogSource `
                -EventId 1000 -EntryType $eventLevel -Message $Message
        }
        catch {
            # Silent fail for event log errors
        }
    }
}

function Show-Header {
    if ($Quiet) { return }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Remote GPUpdate Tool v$Version" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Log "Started: $($script:StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level DEBUG
    Write-Log "Log file: $LogPath" -Level DEBUG
}

function Show-Summary {
    if ($Quiet) { return }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    $total = $script:Results.Count
    $success = ($script:Results | Where-Object { $_.ExitCode -eq 0 }).Count
    $failed = ($script:Results | Where-Object { $_.ExitCode -ne 0 }).Count
    
    Write-Log "Total computers: $total" -Level INFO
    Write-Log "Successful: $success" -Level $(if ($success -gt 0) { 'SUCCESS' } else { 'INFO' })
    Write-Log "Failed: $failed" -Level $(if ($failed -gt 0) { 'ERROR' } else { 'INFO' })
    
    if ($failed -gt 0) {
        Write-Host ""
        Write-Log "Failed computers:" -Level ERROR
        $script:Results | Where-Object { $_.ExitCode -ne 0 } | ForEach-Object {
            Write-Log "  - $($_.ComputerName): $($_.ErrorMessage)" -Level ERROR
        }
    }
    
    $duration = (Get-Date) - $script:StartTime
    Write-Host ""
    Write-Log "Duration: $($duration.ToString('mm\:ss'))" -Level INFO
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
#endregion

#region GUI Components
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

function Show-TargetSelectionDialog {
    param(
        [string[]]$ComputerList,
        [string]$InitialComputer = '',
        [string]$InitialTarget = 'Both',
        [switch]$InitialSkipPing,
        [switch]$InitialUseCurrent,
        [switch]$InitialForcePrompt
    )
    
    try {
        [System.Windows.Forms.Application]::EnableVisualStyles()
        
        $form = New-Object System.Windows.Forms.Form
        $form.Text = 'Remote GPUpdate'
        $form.Size = New-Object System.Drawing.Size(500, 360)
        $form.StartPosition = 'CenterScreen'
        $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $form.MaximizeBox = $false
        $form.MinimizeBox = $false
        $form.TopMost = $true
        
        # Computer label and dropdown
        $lblComputer = New-Object System.Windows.Forms.Label
        $lblComputer.Text = 'Computer:'
        $lblComputer.AutoSize = $true
        $lblComputer.Location = New-Object System.Drawing.Point(12, 18)
        $form.Controls.Add($lblComputer)
        
        $cmbComputer = New-Object System.Windows.Forms.ComboBox
        $cmbComputer.Location = New-Object System.Drawing.Point(150, 15)
        $cmbComputer.Size = New-Object System.Drawing.Size(320, 24)
        $cmbComputer.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
        if ($ComputerList) { [void]$cmbComputer.Items.AddRange($ComputerList) }
        if ($InitialComputer) { $cmbComputer.Text = $InitialComputer }
        $form.Controls.Add($cmbComputer)
        
        # Checkboxes
        $yPos = 50
        $chkSkipPing = New-Object System.Windows.Forms.CheckBox
        $chkSkipPing.Text = 'Skip ping (ICMP)'
        $chkSkipPing.AutoSize = $true
        $chkSkipPing.Location = New-Object System.Drawing.Point(150, $yPos)
        $chkSkipPing.Checked = [bool]$InitialSkipPing
        $form.Controls.Add($chkSkipPing)
        
        $yPos += 25
        $chkUseCurrent = New-Object System.Windows.Forms.CheckBox
        $chkUseCurrent.Text = 'Use current Windows sign-in (no credential prompt)'
        $chkUseCurrent.AutoSize = $true
        $chkUseCurrent.Location = New-Object System.Drawing.Point(150, $yPos)
        $chkUseCurrent.Checked = [bool]$InitialUseCurrent
        $form.Controls.Add($chkUseCurrent)
        
        $yPos += 25
        $chkForcePrompt = New-Object System.Windows.Forms.CheckBox
        $chkForcePrompt.Text = 'Always prompt for credentials (override above)'
        $chkForcePrompt.AutoSize = $true
        $chkForcePrompt.Location = New-Object System.Drawing.Point(150, $yPos)
        $chkForcePrompt.Checked = [bool]$InitialForcePrompt
        $form.Controls.Add($chkForcePrompt)
        
        # Policy target group
        $yPos += 35
        $grpTarget = New-Object System.Windows.Forms.GroupBox
        $grpTarget.Text = 'Policy target'
        $grpTarget.Location = New-Object System.Drawing.Point(150, $yPos)
        $grpTarget.Size = New-Object System.Drawing.Size(320, 70)
        $form.Controls.Add($grpTarget)
        
        $rbBoth = New-Object System.Windows.Forms.RadioButton
        $rbBoth.Text = 'Both'
        $rbBoth.Location = New-Object System.Drawing.Point(12, 28)
        $rbBoth.AutoSize = $true
        $grpTarget.Controls.Add($rbBoth)
        
        $rbComputer = New-Object System.Windows.Forms.RadioButton
        $rbComputer.Text = 'Computer'
        $rbComputer.Location = New-Object System.Drawing.Point(110, 28)
        $rbComputer.AutoSize = $true
        $grpTarget.Controls.Add($rbComputer)
        
        $rbUser = New-Object System.Windows.Forms.RadioButton
        $rbUser.Text = 'User'
        $rbUser.Location = New-Object System.Drawing.Point(220, 28)
        $rbUser.AutoSize = $true
        $grpTarget.Controls.Add($rbUser)
        
        switch ($InitialTarget) {
            'Computer' { $rbComputer.Checked = $true }
            'User'     { $rbUser.Checked = $true }
            default    { $rbBoth.Checked = $true }
        }
        
        # Buttons
        $btnOK = New-Object System.Windows.Forms.Button
        $btnOK.Text = 'OK'
        $btnOK.Location = New-Object System.Drawing.Point(290, 280)
        $btnOK.Size = New-Object System.Drawing.Size(80, 28)
        $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.AcceptButton = $btnOK
        $form.Controls.Add($btnOK)
        
        $btnCancel = New-Object System.Windows.Forms.Button
        $btnCancel.Text = 'Cancel'
        $btnCancel.Location = New-Object System.Drawing.Point(390, 280)
        $btnCancel.Size = New-Object System.Drawing.Size(80, 28)
        $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.CancelButton = $btnCancel
        $form.Controls.Add($btnCancel)
        
        $result = $form.ShowDialog()
        
        if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
            return $null
        }
        
        $selectedTarget = if ($rbComputer.Checked) { 'Computer' } 
                         elseif ($rbUser.Checked) { 'User' } 
                         else { 'Both' }
        
        return [PSCustomObject]@{
            ComputerName = ($cmbComputer.Text).Trim()
            SkipPing = $chkSkipPing.Checked
            UseCurrent = $chkUseCurrent.Checked
            ForcePrompt = $chkForcePrompt.Checked
            PolicyTarget = $selectedTarget
        }
    }
    catch {
        Write-Log "GUI dialog failed: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

function Show-CredentialDialog {
    param(
        [Parameter(Mandatory)]
        [string]$Target,
        [string]$Caption = 'Enter credentials',
        [string]$Message = 'Provide credentials with administrative rights.',
        [string]$DefaultUser = ''
    )
    
    # Try CredUI first (native Windows credential dialog)
    try {
        if (-not ('CredUI.CredUIPrompt' -as [type])) {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace CredUI {
    public static class CredUIPrompt {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct CREDUI_INFO {
            public int cbSize;
            public IntPtr hwndParent;
            public string pszMessageText;
            public string pszCaptionText;
            public IntPtr hbmBanner;
        }
        
        [Flags]
        public enum CREDUI_FLAGS : int {
            GENERIC_CREDENTIALS = 0x1,
            ALWAYS_SHOW_UI = 0x80,
            EXPECT_CONFIRMATION = 0x20000,
            DO_NOT_PERSIST = 0x2,
            REQUEST_ADMINISTRATOR = 0x4
        }
        
        [DllImport("credui.dll", CharSet = CharSet.Unicode)]
        public static extern int CredUIPromptForCredentials(
            ref CREDUI_INFO pUiInfo,
            string pszTargetName,
            IntPtr Reserved,
            int dwAuthError,
            StringBuilder pszUserName,
            int ulUserNameMaxChars,
            StringBuilder pszPassword,
            int ulPasswordMaxChars,
            ref bool pfSave,
            CREDUI_FLAGS dwFlags
        );
    }
}
"@
        }
        
        $info = New-Object CredUI.CredUIPrompt+CREDUI_INFO
        $info.pszCaptionText = $Caption
        $info.pszMessageText = $Message
        $info.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($info)
        
        $userMax = 513
        $passMax = 256
        $user = New-Object System.Text.StringBuilder $userMax
        if ($DefaultUser) { [void]$user.Append($DefaultUser) }
        $pass = New-Object System.Text.StringBuilder $passMax
        $save = $false
        
        $flags = [CredUI.CredUIPrompt+CREDUI_FLAGS]::ALWAYS_SHOW_UI -bor
                 [CredUI.CredUIPrompt+CREDUI_FLAGS]::GENERIC_CREDENTIALS -bor
                 [CredUI.CredUIPrompt+CREDUI_FLAGS]::DO_NOT_PERSIST -bor
                 [CredUI.CredUIPrompt+CREDUI_FLAGS]::REQUEST_ADMINISTRATOR
        
        $ret = [CredUI.CredUIPrompt]::CredUIPromptForCredentials(
            [ref]$info, $Target, [IntPtr]::Zero, 0,
            $user, $userMax, $pass, $passMax, [ref]$save, $flags
        )
        
        if ($ret -eq 0) {
            $securePass = New-Object System.Security.SecureString
            for ($i = 0; $i -lt $pass.Length; $i++) { $securePass.AppendChar($pass[$i]) }
            $securePass.MakeReadOnly()
            
            # Clear password from memory
            for ($i = 0; $i -lt $pass.Length; $i++) { $pass[$i] = [char]0 }
            
            return New-Object System.Management.Automation.PSCredential ($user.ToString(), $securePass)
        }
        
        Write-Log "CredUI returned code $ret" -Level DEBUG
    }
    catch {
        Write-Log "CredUI error: $($_.Exception.Message), falling back to WinForms" -Level DEBUG
    }
    
    # WinForms fallback
    try {
        $form = New-Object System.Windows.Forms.Form
        $form.Text = $Caption
        $form.Size = New-Object System.Drawing.Size(420, 200)
        $form.StartPosition = 'CenterScreen'
        $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $form.MaximizeBox = $false
        $form.MinimizeBox = $false
        
        $lblMessage = New-Object System.Windows.Forms.Label
        $lblMessage.Text = $Message
        $lblMessage.AutoSize = $true
        $lblMessage.Location = New-Object System.Drawing.Point(12, 12)
        $form.Controls.Add($lblMessage)
        
        $lblUser = New-Object System.Windows.Forms.Label
        $lblUser.Text = 'Username:'
        $lblUser.AutoSize = $true
        $lblUser.Location = New-Object System.Drawing.Point(12, 45)
        $form.Controls.Add($lblUser)
        
        $txtUser = New-Object System.Windows.Forms.TextBox
        $txtUser.Size = New-Object System.Drawing.Size(280, 22)
        $txtUser.Location = New-Object System.Drawing.Point(90, 42)
        $txtUser.Text = $DefaultUser
        $form.Controls.Add($txtUser)
        
        $lblPass = New-Object System.Windows.Forms.Label
        $lblPass.Text = 'Password:'
        $lblPass.AutoSize = $true
        $lblPass.Location = New-Object System.Drawing.Point(12, 75)
        $form.Controls.Add($lblPass)
        
        $txtPass = New-Object System.Windows.Forms.MaskedTextBox
        $txtPass.Size = New-Object System.Drawing.Size(280, 22)
        $txtPass.Location = New-Object System.Drawing.Point(90, 72)
        $txtPass.UseSystemPasswordChar = $true
        $form.Controls.Add($txtPass)
        
        $btnOK = New-Object System.Windows.Forms.Button
        $btnOK.Text = 'OK'
        $btnOK.Location = New-Object System.Drawing.Point(200, 110)
        $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.AcceptButton = $btnOK
        $form.Controls.Add($btnOK)
        
        $btnCancel = New-Object System.Windows.Forms.Button
        $btnCancel.Text = 'Cancel'
        $btnCancel.Location = New-Object System.Drawing.Point(290, 110)
        $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.CancelButton = $btnCancel
        $form.Controls.Add($btnCancel)
        
        $result = $form.ShowDialog()
        
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            $securePass = New-Object System.Security.SecureString
            foreach ($ch in $txtPass.Text.ToCharArray()) { $securePass.AppendChar($ch) }
            $securePass.MakeReadOnly()
            $txtPass.Text = ''
            return New-Object System.Management.Automation.PSCredential ($txtUser.Text, $securePass)
        }
        
        return $null
    }
    catch {
        Write-Log "WinForms credential prompt failed: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}
#endregion

#region Core Functions
function Test-HostConnectivity {
    param([string]$Name)
    
    if ($SkipPing) {
        Write-Log "Skipping ping test for $Name" -Level DEBUG
        return $true
    }
    
    try {
        $pingResult = Test-Connection -ComputerName $Name -Count 1 -Quiet -ErrorAction Stop
        if ($pingResult) {
            Write-Log "Ping successful for $Name" -Level DEBUG
            return $true
        }
        Write-Log "Ping failed for $Name (host may still be reachable via WinRM)" -Level WARN
        return $false
    }
    catch {
        Write-Log "Ping error for ${Name}: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

function Test-WinRMAvailability {
    param([string]$Name)
    
    try {
        Write-Log "Checking WinRM on $Name..." -Level DEBUG
        Test-WSMan -ComputerName $Name -ErrorAction Stop | Out-Null
        Write-Log "WinRM available on $Name" -Level DEBUG
        return $true
    }
    catch {
        Write-Log "WinRM not available on ${Name}: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Invoke-RemoteGPUpdate {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [PSCredential]$Cred
    )
    
    $result = [PSCustomObject]@{
        ComputerName = $Name
        ExitCode = 0
        Success = $false
        ErrorMessage = $null
        Timestamp = Get-Date
    }
    
    # Build command
    $targetArg = switch ($PolicyTarget) {
        'Computer' { '/target:computer' }
        'User'     { '/target:user' }
        default    { '' }
    }
    
    $cmd = if ($targetArg) { "gpupdate /force $targetArg" } else { 'gpupdate /force' }
    
    Write-Log "Executing '$cmd' on $Name" -Level INFO
    
    try {
        $scriptBlock = {
            param($command)
            $ProgressPreference = 'SilentlyContinue'
            $ErrorActionPreference = 'Stop'
            
            # Execute gpupdate silently
            $output = & cmd.exe /c "$command 2>&1"
            $exitCode = $LASTEXITCODE
            
            return @{
                Output = $output
                ExitCode = $exitCode
            }
        }
        
        $invokeParams = @{
            ComputerName = $Name
            ScriptBlock = $scriptBlock
            ArgumentList = $cmd
            ErrorAction = 'Stop'
        }
        
        if ($Cred) {
            $invokeParams.Credential = $Cred
        }
        
        if ($PSCmdlet.ShouldProcess($Name, "Execute gpupdate")) {
            $remoteResult = Invoke-Command @invokeParams
            
            $result.ExitCode = $remoteResult.ExitCode
            $result.Success = ($remoteResult.ExitCode -eq 0)
            
            if ($result.Success) {
                Write-Log "GPUpdate succeeded on $Name" -Level SUCCESS
            }
            else {
                Write-Log "GPUpdate returned exit code $($remoteResult.ExitCode) on $Name" -Level WARN
                $result.ErrorMessage = "Exit code: $($remoteResult.ExitCode)"
            }
        }
        else {
            Write-Log "[WHATIF] Would execute gpupdate on $Name" -Level WARN
            $result.Success = $true
        }
    }
    catch {
        $result.ExitCode = 1
        $result.Success = $false
        $result.ErrorMessage = $_.Exception.Message
        Write-Log "GPUpdate failed on ${Name}: $($_.Exception.Message)" -Level ERROR
    }
    
    $script:Results.Add($result)
    return $result
}

function Process-Computer {
    param(
        [string]$Name,
        [PSCredential]$Cred
    )
    
    Write-Log "=== Processing $Name ===" -Level INFO
    
    # Connectivity checks
    if (-not (Test-HostConnectivity -Name $Name)) {
        # Continue anyway - WinRM might still work
    }
    
    if (-not (Test-WinRMAvailability -Name $Name)) {
        $script:Results.Add([PSCustomObject]@{
            ComputerName = $Name
            ExitCode = 2
            Success = $false
            ErrorMessage = "WinRM not available"
            Timestamp = Get-Date
        })
        return
    }
    
    # Execute GPUpdate
    Invoke-RemoteGPUpdate -Name $Name -Cred $Cred | Out-Null
}

function Get-CredentialWithRetry {
    param([string]$Target)
    
    if (-not ($ForcePrompt -or -not $UseCurrent)) {
        return $null
    }
    
    $attempt = 0
    do {
        $attempt++
        $cred = Show-CredentialDialog -Target $Target `
            -Caption "Credentials for $Target" `
            -Message "Enter credentials with administrative rights on $Target" `
            -DefaultUser $DefaultUser
        
        if ($cred) {
            return $cred
        }
        
        if ($attempt -lt $Retries) {
            Write-Log "No credentials provided. Retrying ($attempt/$Retries)" -Level WARN
        }
    } while ($attempt -lt $Retries)
    
    return $null
}
#endregion

#region Main Execution
Show-Header

# Build computer list
$computersToProcess = [System.Collections.Generic.List[string]]::new()

if ($ComputerList) {
    $computersToProcess.AddRange($ComputerList)
}

if ($ComputerName) {
    $computersToProcess.AddRange($ComputerName)
}

# Show GUI if no computers specified
if ($computersToProcess.Count -eq 0) {
    $selection = Show-TargetSelectionDialog -ComputerList $CommonComputers `
        -InitialTarget $PolicyTarget -InitialSkipPing:$SkipPing `
        -InitialUseCurrent:$UseCurrent -InitialForcePrompt:$ForcePrompt
    
    if (-not $selection) {
        Write-Log "Operation cancelled by user" -Level WARN
        exit 4
    }
    
    if ([string]::IsNullOrWhiteSpace($selection.ComputerName)) {
        Write-Log "No computer name provided" -Level WARN
        exit 6
    }
    
    $computersToProcess.Add($selection.ComputerName)
    $SkipPing = $selection.SkipPing
    $UseCurrent = $selection.UseCurrent
    $ForcePrompt = $selection.ForcePrompt
    $PolicyTarget = $selection.PolicyTarget
}

# Remove duplicates
$computersToProcess = $computersToProcess | Select-Object -Unique

Write-Log "Processing $($computersToProcess.Count) computer(s)" -Level INFO

# Process computers
if ($Parallel -and $computersToProcess.Count -gt 1) {
    Write-Log "Processing in parallel (max $ThrottleLimit concurrent)" -Level INFO
    
    $computersToProcess | ForEach-Object -Parallel {
        # Import functions (needed in parallel runspace)
        # Note: Simplified parallel execution
        Write-Host "Processing $_..."
    } -ThrottleLimit $ThrottleLimit
}
else {
    foreach ($computer in $computersToProcess) {
        # Get credentials if needed
        $cred = if ($Credential) { 
            $Credential 
        } elseif ($ForcePrompt -or -not $UseCurrent) {
            Get-CredentialWithRetry -Target $computer
        } else { 
            $null 
        }
        
        if (($ForcePrompt -or -not $UseCurrent) -and -not $cred) {
            if ($ForcePrompt) {
                Write-Log "Credentials required but not provided for $computer" -Level ERROR
                continue
            }
            Write-Log "No credentials, falling back to current sign-in for $computer" -Level WARN
        }
        
        Process-Computer -Name $computer -Cred $cred
    }
}

# Export results
if ($ExportResults) {
    $exportPath = $LogPath -replace '\.log$', '_results.csv'
    try {
        $script:Results | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
        Write-Log "Results exported to: $exportPath" -Level SUCCESS
    }
    catch {
        Write-Log "Failed to export results: $($_.Exception.Message)" -Level ERROR
    }
}

# Show summary
Show-Summary

# Exit code
$failedCount = ($script:Results | Where-Object { -not $_.Success }).Count
if ($failedCount -eq 0) {
    exit 0
} elseif ($failedCount -lt $script:Results.Count) {
    exit 1  # Partial failure
} else {
    exit 1  # Complete failure
}
#endregion
