<#
.SYNOPSIS
    Interactive domain join utility for Windows devices - runs at first logon.

.DESCRIPTION
    This script displays a Windows Forms dialog prompting users to join an Active Directory domain.
    Designed for first-logon scenarios, OSD task sequences, or manual domain joining.
    
    Features:
    - Pre-flight checks (domain join status, network connectivity, admin rights)
    - Clean Windows Forms UI with validation
    - OU selection support (optional)
    - Computer rename option
    - Secure credential handling
    - Detailed logging
    - Silent/automated mode support

.PARAMETER DefaultDomain
    Pre-populate the domain field with a default value.

.PARAMETER RequireDomain
    Domain name that must be used (disables editing).

.PARAMETER AllowSkip
    Allow users to skip the domain join (shows skip button).

.PARAMETER AutoRestart
    Automatically restart after successful domain join without prompting.

.PARAMETER RenameComputer
    Allow users to specify a new computer name before joining.

.PARAMETER OUPicker
    Show OU picker dialog for selecting target OU.

.PARAMETER LogPath
    Path to save the domain join log.

.PARAMETER Silent
    Silent mode - no GUI, use parameters only (for automation).

.PARAMETER Domain
    Domain name (required for -Silent).

.PARAMETER Username
    Domain admin username (required for -Silent).

.PARAMETER Password
    Domain admin password (required for -Silent).

.PARAMETER NewName
    New computer name (used with -Silent -RenameComputer).

.PARAMETER OUPath
    Target OU distinguished name (optional, for -Silent).

.EXAMPLE
    .\Invoke-DomainJoinPrompt.ps1
    Show interactive domain join dialog.

.EXAMPLE
    .\Invoke-DomainJoinPrompt.ps1 -DefaultDomain "corp.contoso.com"
    Pre-fill the domain field.

.EXAMPLE
    .\Invoke-DomainJoinPrompt.ps1 -RequireDomain "corp.contoso.com" -AutoRestart
    Force specific domain and auto-restart on success.

.EXAMPLE
    .\Invoke-DomainJoinPrompt.ps1 -RenameComputer -OUPicker
    Allow computer rename and OU selection.

.EXAMPLE
    .\Invoke-DomainJoinPrompt.ps1 -Silent -Domain "corp.contoso.com" -Username "admin" -Password "P@ssw0rd" -AutoRestart
    Silent domain join (automation/scripting).

.NOTES
    Version:        2.0
    Author:         IT Admin
    Updated:        2026-02-12
    
    Requirements:
    - Windows 10/11 Pro, Enterprise, or Education
    - Administrator privileges
    - Network connectivity to domain controller
    - .NET Framework (for Windows Forms)
    
    Exit Codes:
    0   - Success (domain joined or skipped with -AllowSkip)
    1   - Already domain joined
    2   - User cancelled/skipped
    3   - Missing admin privileges
    4   - Invalid parameters
    5   - Domain join failed
    6   - Network connectivity issues
#>

[CmdletBinding()]
param(
    [string]$DefaultDomain = "",
    [string]$RequireDomain = "",
    [switch]$AllowSkip,
    [switch]$AutoRestart,
    [switch]$RenameComputer,
    [switch]$OUPicker,
    [string]$LogPath = (Join-Path $env:TEMP "DomainJoin_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"),
    
    # Silent mode parameters
    [switch]$Silent,
    [string]$Domain = "",
    [string]$Username = "",
    [string]$Password = "",
    [string]$NewName = "",
    [string]$OUPath = ""
)

#region Configuration
$ErrorActionPreference = 'Stop'
$script:Version = "2.0"

# Form colors and styling
$script:Theme = @{
    BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
    ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
    AccentColor = [System.Drawing.Color]::FromArgb(0, 112, 192)
    ErrorColor = [System.Drawing.Color]::FromArgb(192, 0, 0)
    SuccessColor = [System.Drawing.Color]::FromArgb(0, 128, 0)
}
#endregion

#region Helper Functions
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    
    try {
        Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
    } catch {
        # Silent fail if log write fails
    }
    
    if (-not $Silent) {
        switch ($Level) {
            'Info'    { Write-Host "[*] $Message" -ForegroundColor Cyan }
            'Success' { Write-Host "[+] $Message" -ForegroundColor Green }
            'Warning' { Write-Host "[!] $Message" -ForegroundColor Yellow }
            'Error'   { Write-Host "[-] $Message" -ForegroundColor Red }
        }
    }
}

function Test-AdminRights {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DomainJoinStatus {
    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        return @{
            PartOfDomain = $computerSystem.PartOfDomain
            Domain = $computerSystem.Domain
            Workgroup = $computerSystem.Workgroup
            ComputerName = $computerSystem.Name
        }
    } catch {
        Write-Log "Failed to get domain join status: $($_.Exception.Message)" -Level Error
        return $null
    }
}

function Test-DomainConnectivity {
    param([string]$DomainName)
    
    try {
        # Test DNS resolution
        $dnsResult = Resolve-DnsName -Name $DomainName -Type A -ErrorAction Stop
        Write-Log "DNS resolution successful: $($dnsResult[0].IPAddress)" -Level Success
        
        # Test port 445 (SMB) and 389 (LDAP)
        $smbTest = Test-NetConnection -ComputerName $DomainName -Port 445 -WarningAction SilentlyContinue
        $ldapTest = Test-NetConnection -ComputerName $DomainName -Port 389 -WarningAction SilentlyContinue
        
        if ($smbTest.TcpTestSucceeded -or $ldapTest.TcpTestSucceeded) {
            Write-Log "Domain connectivity verified" -Level Success
            return $true
        } else {
            Write-Log "Cannot connect to domain controller ports" -Level Warning
            return $false
        }
    } catch {
        Write-Log "Domain connectivity test failed: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

function Show-ErrorDialog {
    param([string]$Message, [string]$Title = "Error")
    
    if ($Silent) {
        Write-Log $Message -Level Error
        return
    }
    
    [System.Windows.Forms.MessageBox]::Show(
        $Message, 
        $Title, 
        [System.Windows.Forms.MessageBoxButtons]::OK, 
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

function Show-InfoDialog {
    param([string]$Message, [string]$Title = "Information")
    
    if ($Silent) {
        Write-Log $Message -Level Info
        return
    }
    
    [System.Windows.Forms.MessageBox]::Show(
        $Message, 
        $Title, 
        [System.Windows.Forms.MessageBoxButtons]::OK, 
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Show-ConfirmationDialog {
    param([string]$Message, [string]$Title = "Confirm")
    
    if ($Silent) { return $true }
    
    $result = [System.Windows.Forms.MessageBox]::Show(
        $Message, 
        $Title, 
        [System.Windows.Forms.MessageBoxButtons]::YesNo, 
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    return $result -eq [System.Windows.Forms.DialogResult]::Yes
}
#endregion

#region GUI Functions
function New-Label {
    param($Text, $X, $Y, $Width = 360, $Height = 20)
    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($Width, $Height)
    $label.Text = $Text
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $label.ForeColor = $script:Theme.ForeColor
    return $label
}

function New-TextBox {
    param($X, $Y, $Width = 360, $Height = 25, [switch]$Password)
    
    if ($Password) {
        $textbox = New-Object System.Windows.Forms.MaskedTextBox
        $textbox.PasswordChar = '●'
    } else {
        $textbox = New-Object System.Windows.Forms.TextBox
    }
    
    $textbox.Location = New-Object System.Drawing.Point($X, $Y)
    $textbox.Size = New-Object System.Drawing.Size($Width, $Height)
    $textbox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    return $textbox
}

function New-Button {
    param($Text, $X, $Y, $Width = 90, $Height = 30, [switch]$IsDefault)
    
    $button = New-Object System.Windows.Forms.Button
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size($Width, $Height)
    $button.Text = $Text
    $button.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $button.BackColor = if ($IsDefault) { $script:Theme.AccentColor } else { [System.Drawing.Color]::White }
    $button.ForeColor = if ($IsDefault) { [System.Drawing.Color]::White } else { $script:Theme.ForeColor }
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 1
    
    return $button
}

function Show-DomainJoinForm {
    $formHeight = 280
    if ($RenameComputer) { $formHeight += 60 }
    
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Join Active Directory Domain'
    $form.Size = New-Object System.Drawing.Size(420, $formHeight)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    $form.BackColor = $script:Theme.BackColor
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    
    $currentY = 20
    
    # Computer name info (if rename enabled)
    if ($RenameComputer) {
        $form.Controls.Add((New-Label -Text "Current Computer Name: $env:COMPUTERNAME" -X 10 -Y $currentY))
        $currentY += 25
        
        $form.Controls.Add((New-Label -Text "New Computer Name (optional):" -X 10 -Y $currentY))
        $currentY += 25
        
        $textboxNewName = New-TextBox -X 10 -Y $currentY
        $form.Controls.Add($textboxNewName)
        $currentY += 45
    }
    
    # Domain
    $form.Controls.Add((New-Label -Text "Domain Name:" -X 10 -Y $currentY))
    $currentY += 25
    
    $textboxDomain = New-TextBox -X 10 -Y $currentY
    if ($RequireDomain) {
        $textboxDomain.Text = $RequireDomain
        $textboxDomain.ReadOnly = $true
        $textboxDomain.BackColor = [System.Drawing.Color]::LightGray
    } elseif ($DefaultDomain) {
        $textboxDomain.Text = $DefaultDomain
    }
    $form.Controls.Add($textboxDomain)
    $currentY += 45
    
    # Username
    $form.Controls.Add((New-Label -Text "Domain Username (DOMAIN\user or user@domain.com):" -X 10 -Y $currentY))
    $currentY += 25
    
    $textboxUser = New-TextBox -X 10 -Y $currentY
    $form.Controls.Add($textboxUser)
    $currentY += 45
    
    # Password
    $form.Controls.Add((New-Label -Text "Password:" -X 10 -Y $currentY))
    $currentY += 25
    
    $textboxPassword = New-TextBox -X 10 -Y $currentY -Password
    $form.Controls.Add($textboxPassword)
    $currentY += 50
    
    # Buttons
    $buttonJoin = New-Button -Text "Join Domain" -X 130 -Y $currentY -IsDefault
    $buttonJoin.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $buttonJoin
    $form.Controls.Add($buttonJoin)
    
    $buttonCancel = New-Button -Text "Cancel" -X 230 -Y $currentY
    $buttonCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.CancelButton = $buttonCancel
    $form.Controls.Add($buttonCancel)
    
    if ($AllowSkip) {
        $buttonSkip = New-Button -Text "Skip" -X 330 -Y $currentY
        $buttonSkip.DialogResult = [System.Windows.Forms.DialogResult]::Ignore
        $form.Controls.Add($buttonSkip)
    }
    
    # Show form
    $result = $form.ShowDialog()
    
    if ($result -eq [System.Windows.Forms.DialogResult]::Ignore) {
        return @{ Action = "Skip" }
    }
    
    if ($result -eq [System.Windows.Forms.DialogResult]::Cancel) {
        return @{ Action = "Cancel" }
    }
    
    # Validate inputs
    $domain = $textboxDomain.Text.Trim()
    $username = $textboxUser.Text.Trim()
    $password = $textboxPassword.Text
    $newName = if ($RenameComputer) { $textboxNewName.Text.Trim() } else { "" }
    
    if ([string]::IsNullOrWhiteSpace($domain)) {
        Show-ErrorDialog "Domain name is required."
        return Show-DomainJoinForm
    }
    
    if ([string]::IsNullOrWhiteSpace($username)) {
        Show-ErrorDialog "Username is required."
        return Show-DomainJoinForm
    }
    
    if ([string]::IsNullOrWhiteSpace($password)) {
        Show-ErrorDialog "Password is required."
        return Show-DomainJoinForm
    }
    
    return @{
        Action = "Join"
        Domain = $domain
        Username = $username
        Password = $password
        NewName = $newName
    }
}

function Show-OUPickerForm {
    param([string]$Domain)
    
    # This is a simplified OU picker - in production you might want to query AD for actual OUs
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Select Organizational Unit"
    $form.Size = New-Object System.Drawing.Size(500, 400)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    
    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point(10, 10)
    $label.Size = New-Object System.Drawing.Size(460, 20)
    $label.Text = "Select OU (or leave default for Computers container):"
    $form.Controls.Add($label)
    
    $textboxOU = New-Object System.Windows.Forms.TextBox
    $textboxOU.Location = New-Object System.Drawing.Point(10, 35)
    $textboxOU.Size = New-Object System.Drawing.Size(460, 20)
    $textboxOU.Text = "OU=Computers,DC=$($Domain.Split('.')[0]),DC=$($Domain.Split('.')[1])"
    $form.Controls.Add($textboxOU)
    
    $buttonOK = New-Object System.Windows.Forms.Button
    $buttonOK.Location = New-Object System.Drawing.Point(300, 320)
    $buttonOK.Size = New-Object System.Drawing.Size(80, 25)
    $buttonOK.Text = "OK"
    $buttonOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($buttonOK)
    
    $buttonCancel = New-Object System.Windows.Forms.Button
    $buttonCancel.Location = New-Object System.Drawing.Point(390, 320)
    $buttonCancel.Size = New-Object System.Drawing.Size(80, 25)
    $buttonCancel.Text = "Default"
    $buttonCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($buttonCancel)
    
    $result = $form.ShowDialog()
    
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $textboxOU.Text.Trim()
    }
    return $null
}
#endregion

#region Domain Join Logic
function Invoke-DomainJoin {
    param(
        [string]$Domain,
        [string]$Username,
        [string]$Password,
        [string]$NewName,
        [string]$OU
    )
    
    Write-Log "Starting domain join process..." -Level Info
    Write-Log "Domain: $Domain" -Level Info
    Write-Log "Username: $Username" -Level Info
    if ($NewName) { Write-Log "New computer name: $NewName" -Level Info }
    if ($OU) { Write-Log "Target OU: $OU" -Level Info }
    
    try {
        # Create credential
        $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($Username, $securePassword)
        
        # Build splat for Add-Computer
        $joinParams = @{
            DomainName = $Domain
            Credential = $credential
            Force = $true
            ErrorAction = 'Stop'
        }
        
        if ($NewName) {
            $joinParams['NewName'] = $NewName
        }
        
        if ($OU) {
            $joinParams['OUPath'] = $OU
        }
        
        # Perform domain join
        Write-Log "Executing Add-Computer..." -Level Info
        Add-Computer @joinParams
        
        Write-Log "Domain join completed successfully!" -Level Success
        return $true
    }
    catch {
        Write-Log "Domain join failed: $($_.Exception.Message)" -Level Error
        
        # Provide helpful error messages
        $errorMsg = $_.Exception.Message
        
        if ($errorMsg -match "access denied|logon failure") {
            Show-ErrorDialog "Authentication failed. Please check your username and password.`n`nMake sure to use DOMAIN\username or username@domain.com format."
        } elseif ($errorMsg -match "network path|RPC server") {
            Show-ErrorDialog "Cannot connect to domain controller. Please check network connectivity and DNS settings."
        } elseif ($errorMsg -match "already exists") {
            Show-ErrorDialog "A computer with this name already exists in the domain. Please choose a different name."
        } else {
            Show-ErrorDialog "Failed to join domain: $errorMsg"
        }
        
        return $false
    }
}

function Invoke-RestartPrompt {
    if ($AutoRestart) {
        Write-Log "Auto-restarting computer..." -Level Info
        Restart-Computer -Force
        return
    }
    
    $result = Show-ConfirmationDialog -Message "Successfully joined the domain!`n`nThe computer must restart to complete the domain join.`n`nRestart now?" -Title "Restart Required"
    
    if ($result) {
        Write-Log "User chose to restart now" -Level Info
        Restart-Computer -Force
    } else {
        Write-Log "User chose to restart later" -Level Warning
        Show-InfoDialog "Please restart the computer manually to complete the domain join." -Title "Restart Required"
    }
}
#endregion

#region Silent Mode
function Invoke-SilentDomainJoin {
    # Validate required parameters
    if ([string]::IsNullOrWhiteSpace($Domain)) {
        Write-Log "Silent mode requires -Domain parameter" -Level Error
        exit 4
    }
    
    if ([string]::IsNullOrWhiteSpace($Username)) {
        Write-Log "Silent mode requires -Username parameter" -Level Error
        exit 4
    }
    
    if ([string]::IsNullOrWhiteSpace($Password)) {
        Write-Log "Silent mode requires -Password parameter" -Level Error
        exit 4
    }
    
    # Check connectivity
    if (-not (Test-DomainConnectivity -DomainName $Domain)) {
        Write-Log "Domain connectivity check failed" -Level Error
        exit 6
    }
    
    # Perform join
    $success = Invoke-DomainJoin -Domain $Domain -Username $Username -Password $Password -NewName $NewName -OU $OUPath
    
    if ($success) {
        if ($AutoRestart) {
            Restart-Computer -Force
        }
        exit 0
    } else {
        exit 5
    }
}
#endregion

#region Main Execution
Write-Log "Domain Join Utility v$Version started" -Level Info
Write-Log "Computer: $env:COMPUTERNAME" -Level Info
Write-Log "User: $env:USERNAME" -Level Info

# Check admin rights
if (-not (Test-AdminRights)) {
    Write-Log "Administrator privileges required" -Level Error
    if (-not $Silent) {
        Show-ErrorDialog "This script requires Administrator privileges.`n`nPlease right-click and select 'Run as administrator'."
    }
    exit 3
}

# Check if already domain joined
$joinStatus = Get-DomainJoinStatus
if ($joinStatus -and $joinStatus.PartOfDomain) {
    Write-Log "Computer is already joined to domain: $($joinStatus.Domain)" -Level Success
    if (-not $Silent) {
        Show-InfoDialog "This computer is already joined to domain:`n`n$($joinStatus.Domain)"
    }
    exit 1
}

# Silent mode
if ($Silent) {
    Invoke-SilentDomainJoin
    return
}

# GUI Mode Loop
do {
    # Show domain join form
    $formResult = Show-DomainJoinForm
    
    if ($formResult.Action -eq "Cancel") {
        Write-Log "User cancelled" -Level Warning
        exit 2
    }
    
    if ($formResult.Action -eq "Skip") {
        Write-Log "User skipped domain join" -Level Warning
        if (Show-ConfirmationDialog -Message "Are you sure you want to skip joining a domain?`n`nThe computer will remain in workgroup mode." -Title "Confirm Skip") {
            exit 2
        }
        continue
    }
    
    # Validate domain connectivity
    Write-Log "Testing connectivity to $($formResult.Domain)..." -Level Info
    if (-not (Test-DomainConnectivity -DomainName $formResult.Domain)) {
        $continue = Show-ConfirmationDialog -Message "Cannot verify connectivity to domain.`n`nDo you want to try joining anyway?" -Title "Connectivity Warning"
        if (-not $continue) { continue }
    }
    
    # OU Picker (if enabled)
    $selectedOU = $null
    if ($OUPicker) {
        $selectedOU = Show-OUPickerForm -Domain $formResult.Domain
    }
    
    # Perform domain join
    $success = Invoke-DomainJoin -Domain $formResult.Domain -Username $formResult.Username -Password $formResult.Password -NewName $formResult.NewName -OU $selectedOU
    
    if ($success) {
        Invoke-RestartPrompt
        exit 0
    }
    
    # Join failed - ask if user wants to retry
    $retry = Show-ConfirmationDialog -Message "Domain join failed. Would you like to try again?" -Title "Retry?"
    
} while ($retry)

Write-Log "Domain join utility exiting" -Level Info
exit 5
#endregion
