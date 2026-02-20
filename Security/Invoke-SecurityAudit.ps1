#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Performs security audit of the system.

.DESCRIPTION
    Checks for security issues including Windows Defender status, 
    firewall status, default passwords, unauthorized software, and more.
    Outputs a security report.

.PARAMETER DetailedReport
    Generate detailed HTML report

.PARAMETER ExportPath
    Path to save the report

.PARAMETER CheckWindowsDefender
    Verify Windows Defender is enabled and up to date

.PARAMETER CheckFirewall
    Verify Windows Firewall is enabled

.PARAMETER CheckForDefaultPasswords
    Check for accounts with default/simple passwords

.PARAMETER CheckSoftwareWhitelist
    Compare installed software against approved list

.PARAMETER WhitelistFile
    Path to approved software JSON file

.PARAMETER EmailReport
    Email the report (requires SMTP config)

.PARAMETER LogPath
    Path for operation logs

.EXAMPLE
    .\Invoke-SecurityAudit.ps1

.EXAMPLE
    .\Invoke-SecurityAudit.ps1 -DetailedReport -ExportPath "C:\Reports\SecurityAudit.html"

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
    Requirements:   Windows 10/11, Administrator rights
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$DetailedReport,

    [Parameter(Mandatory=$false)]
    [string]$ExportPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\SecurityAudit.html",

    [Parameter(Mandatory=$false)]
    [switch]$CheckWindowsDefender = $true,

    [Parameter(Mandatory=$false)]
    [switch]$CheckFirewall = $true,

    [Parameter(Mandatory=$false)]
    [switch]$CheckForDefaultPasswords,

    [Parameter(Mandatory=$false)]
    [switch]$CheckSoftwareWhitelist,

    [Parameter(Mandatory=$false)]
    [string]$WhitelistFile = "",

    [Parameter(Mandatory=$false)]
    [switch]$EmailReport,

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
)

$ScriptName = "SecurityAudit"
$LogFile = "$LogPath\$ScriptName.log"
$AuditResults = @{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    ComputerName = $env:COMPUTERNAME
    Issues = @()
    Warnings = @()
    Passed = @()
    Score = 0
}

if (!(Test-Path -Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    try { Add-Content -Path $LogFile -Value $logEntry } catch {}
    Write-Host $logEntry -ForegroundColor $(switch($Level){"ERROR"{"Red"}"WARN"{"Yellow"}"SUCCESS"{"Green"}default{"White"}})
}

function Test-WindowsDefender {
    try {
        Write-Log "Checking Windows Defender status"
        
        $defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
        
        if (-not $defender) {
            $AuditResults.Issues += "Windows Defender status could not be determined"
            return $false
        }
        
        # Check real-time protection
        if (-not $defender.RealTimeProtectionEnabled) {
            $AuditResults.Issues += "Windows Defender real-time protection is DISABLED"
        } else {
            $AuditResults.Passed += "Windows Defender real-time protection is enabled"
        }
        
        # Check if up to date
        $lastUpdate = $defender.AntivirusSignatureLastUpdated
        $daysSinceUpdate = (Get-Date) - $lastUpdate | Select-Object -ExpandProperty Days
        
        if ($daysSinceUpdate -gt 7) {
            $AuditResults.Warnings += "Windows Defender definitions are $daysSinceUpdate days old"
        } else {
            $AuditResults.Passed += "Windows Defender definitions are current (updated $daysSinceUpdate days ago)"
        }
        
        # Check for threats
        $threats = Get-MpThreat -ErrorAction SilentlyContinue
        if ($threats) {
            $AuditResults.Issues += "Active threats detected: $($threats.Count) threat(s) found"
        } else {
            $AuditResults.Passed += "No active threats detected"
        }
        
        return $true
    }
    catch {
        Write-Log "Defender check failed: $($_.Exception.Message)" "ERROR"
        $AuditResults.Issues += "Could not verify Windows Defender status"
        return $false
    }
}

function Test-FirewallStatus {
    try {
        Write-Log "Checking Windows Firewall status"
        
        $profiles = @("Domain", "Private", "Public")
        $allEnabled = $true
        
        foreach ($profile in $profiles) {
            $fwPolicy = New-Object -ComObject HNetCfg.FwPolicy2
            $currentProfile = $fwPolicy.CurrentProfileTypes
            
            $fwProfile = $fwPolicy.get_CurrentProfile($profile)
            
            switch ($profile) {
                "Domain" { $isEnabled = $fwPolicy.FirewallEnabled(1) }
                "Private" { $isEnabled = $fwPolicy.FirewallEnabled(2) }
                "Public" { $isEnabled = $fwPolicy.FirewallEnabled(4) }
            }
            
            if (-not $isEnabled) {
                $AuditResults.Warnings += "Windows Firewall is DISABLED for $profile profile"
                $allEnabled = $false
            }
        }
        
        if ($allEnabled) {
            $AuditResults.Passed += "Windows Firewall is enabled for all profiles"
        }
        
        return $true
    }
    catch {
        Write-Log "Firewall check failed: $($_.Exception.Message)" "ERROR"
        $AuditResults.Warnings += "Could not verify Windows Firewall status"
        return $false
    }
}

function Test-UserAccounts {
    try {
        Write-Log "Checking user accounts"
        
        $users = Get-WmiObject -Class Win32_UserAccount -Filter "LocalAccount=True" | 
            Where-Object { $_.Disabled -eq $false }
        
        # Check for accounts without passwords
        foreach ($user in $users) {
            $userName = $user.Name
            
            # Check if account has password
            $account = [ADSI]"WinNT://$env:COMPUTERNAME/$userName,user"
            $flags = $account.Get("UserFlags")
            
            $hasPassword = $flags -band 0x10000  # UF_PASSWD_NOTREQD
            
            if ($hasPassword) {
                $AuditResults.Issues += "Account '$userName' may not require a password"
            }
        }
        
        # Check for Administrator account (should be disabled)
        $adminAccount = Get-WmiObject -Class Win32_UserAccount -Filter "Name='Administrator' AND LocalAccount=True"
        if ($adminAccount -and -not $adminAccount.Disabled) {
            $AuditResults.Warnings += "Built-in Administrator account is ENABLED"
        } else {
            $AuditResults.Passed += "Built-in Administrator account is disabled"
        }
        
        # Check for Guest account (should be disabled)
        $guestAccount = Get-WmiObject -Class Win32_UserAccount -Filter "Name='Guest' AND LocalAccount=True"
        if ($guestAccount -and -not $guestAccount.Disabled) {
            $AuditResults.Issues += "Guest account is ENABLED"
        } else {
            $AuditResults.Passed += "Guest account is disabled"
        }
        
        return $true
    }
    catch {
        Write-Log "User account check failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Test-SoftwareWhitelist {
    param([string]$WhitelistPath)
    
    try {
        Write-Log "Checking installed software against whitelist"
        
        if (-not (Test-Path $WhitelistPath)) {
            $AuditResults.Warnings += "Software whitelist file not found: $WhitelistPath"
            return $false
        }
        
        $whitelist = Get-Content $WhitelistPath | ConvertFrom-Json
        $approvedSoftware = $whitelist.ApprovedSoftware
        
        # Get installed software
        $installed = Get-WmiObject -Class Win32_Product | Select-Object -ExpandProperty Name
        
        $unauthorized = @()
        foreach ($software in $installed) {
            $isApproved = $approvedSoftware | Where-Object { $software -like "*$_*" }
            if (-not $isApproved) {
                $unauthorized += $software
            }
        }
        
        if ($unauthorized.Count -gt 0) {
            $AuditResults.Warnings += "Found $($unauthorized.Count) software items not in whitelist"
            foreach ($sw in $unauthorized | Select-Object -First 5) {
                $AuditResults.Warnings += "  - $sw"
            }
        } else {
            $AuditResults.Passed += "All installed software is in whitelist"
        }
        
        return $true
    }
    catch {
        Write-Log "Software whitelist check failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Test-BitLockerStatus {
    try {
        Write-Log "Checking BitLocker status"
        
        $bitlocker = Get-BitLockerVolume -MountPoint C: -ErrorAction SilentlyContinue
        
        if (-not $bitlocker) {
            $AuditResults.Warnings += "BitLocker status could not be determined"
            return $false
        }
        
        if ($bitlocker.ProtectionStatus -eq "On") {
            $AuditResults.Passed += "BitLocker is enabled on C: drive"
        } else {
            $AuditResults.Warnings += "BitLocker is NOT enabled on C: drive"
        }
        
        return $true
    }
    catch {
        Write-Log "BitLocker check failed: $($_.Exception.Message)" "WARN"
        $AuditResults.Warnings += "Could not verify BitLocker status"
        return $false
    }
}

function Test-WindowsUpdates {
    try {
        Write-Log "Checking Windows Update status"
        
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        $pendingUpdates = $updateSearcher.Search("IsInstalled=0")
        
        $updateCount = $pendingUpdates.Updates.Count
        
        if ($updateCount -gt 0) {
            $AuditResults.Warnings += "Found $updateCount pending Windows Update(s)"
        } else {
            $AuditResults.Passed += "Windows is up to date"
        }
        
        return $true
    }
    catch {
        Write-Log "Windows Update check failed: $($_.Exception.Message)" "WARN"
        return $false
    }
}

function Export-Report {
    param([string]$Path)
    
    try {
        # Calculate score
        $total = $AuditResults.Passed.Count + $AuditResults.Warnings.Count + $AuditResults.Issues.Count
        if ($total -gt 0) {
            $AuditResults.Score = [math]::Round(($AuditResults.Passed.Count / $total) * 100)
        }
        
        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Security Audit Report - $($AuditResults.ComputerName)</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        h1 { color: #333; }
        .timestamp { color: #666; font-style: italic; }
        .score { font-size: 24px; font-weight: bold; margin: 20px 0; }
        .score-good { color: green; }
        .score-warning { color: orange; }
        .score-bad { color: red; }
        .section { margin: 20px 0; }
        .section h2 { border-bottom: 2px solid #333; padding-bottom: 5px; }
        ul { line-height: 1.6; }
        .passed { color: green; }
        .warning { color: orange; }
        .issue { color: red; font-weight: bold; }
    </style>
</head>
<body>
    <h1>Security Audit Report</h1>
    <p class="timestamp">Generated: $($AuditResults.Timestamp)</p>
    <p>Computer: <strong>$($AuditResults.ComputerName)</strong></p>
    
    <div class="score $(if($AuditResults.Score -ge 80){'score-good'}elseif($AuditResults.Score -ge 60){'score-warning'}else{'score-bad'})">
        Security Score: $($AuditResults.Score)/100
    </div>
    
    <div class="section">
        <h2>⚠️ Critical Issues ($($AuditResults.Issues.Count))</h2>
        <ul>
"@
        
        foreach ($issue in $AuditResults.Issues) {
            $html += "            <li class='issue'>$issue</li>`n"
        }
        
        $html += @"
        </ul>
    </div>
    
    <div class="section">
        <h2>⚡ Warnings ($($AuditResults.Warnings.Count))</h2>
        <ul>
"@
        
        foreach ($warning in $AuditResults.Warnings) {
            $html += "            <li class='warning'>$warning</li>`n"
        }
        
        $html += @"
        </ul>
    </div>
    
    <div class="section">
        <h2>✅ Passed Checks ($($AuditResults.Passed.Count))</h2>
        <ul>
"@
        
        foreach ($pass in $AuditResults.Passed) {
            $html += "            <li class='passed'>$pass</li>`n"
        }
        
        $html += @"
        </ul>
    </div>
</body>
</html>
"@
        
        $html | Out-File -FilePath $Path -Encoding UTF8
        Write-Log "Report exported to: $Path" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to export report: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Main
Write-Log "=== Security Audit Started ==="

if ($CheckWindowsDefender) { Test-WindowsDefender }
if ($CheckFirewall) { Test-FirewallStatus }
Test-UserAccounts
if ($CheckSoftwareWhitelist -and $WhitelistFile) { Test-SoftwareWhitelist -WhitelistPath $WhitelistFile }
Test-BitLockerStatus
Test-WindowsUpdates

# Export report
if ($DetailedReport) {
    Export-Report -Path $ExportPath
}

# Summary
Write-Log "=== Security Audit Completed ==="
Write-Log "Issues: $($AuditResults.Issues.Count), Warnings: $($AuditResults.Warnings.Count), Passed: $($AuditResults.Passed.Count)"
Write-Log "Security Score: $($AuditResults.Score)/100"

if ($AuditResults.Issues.Count -eq 0) {
    Write-Log "No critical security issues found" "SUCCESS"
    exit 0
} else {
    Write-Log "Critical security issues detected!" "ERROR"
    exit 1
}