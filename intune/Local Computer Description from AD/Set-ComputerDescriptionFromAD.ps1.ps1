#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Sets the local computer description from the Active Directory computer object.

.DESCRIPTION
    Queries Active Directory for the computer's description attribute and sets it
    as the local computer description. This ensures the local machine description
    matches what's documented in AD. Designed for Intune deployment on hybrid
    or domain-joined devices.

.PARAMETER DomainController
    Specific domain controller to query (optional - auto-detects if not specified)

.PARAMETER Credential
    Credentials for AD query (optional - uses computer account by default)

.PARAMETER FallbackDescription
    Description to use if AD query fails

.PARAMETER LogPath
    Path for operation logs

.PARAMETER Force
    Force update even if descriptions match

.EXAMPLE
    .\Set-ComputerDescriptionFromAD.ps1

.EXAMPLE
    .\Set-ComputerDescriptionFromAD.ps1 -DomainController "dc01.company.com"

.EXAMPLE
    .\Set-ComputerDescriptionFromAD.ps1 -FallbackDescription "Standard Workstation"

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
    Requirements:   Windows 10/11, Domain-joined, RSAT-AD-PowerShell (optional)
    
    The script works by:
    1. Determining the computer's domain and hostname
    2. Querying AD for the computer object's description attribute
    3. Setting the local computer description via WMI/CIM
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$DomainController = "",

    [Parameter(Mandatory=$false)]
    [System.Management.Automation.PSCredential]$Credential = $null,

    [Parameter(Mandatory=$false)]
    [string]$FallbackDescription = "",

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs",

    [Parameter(Mandatory=$false)]
    [switch]$Force
)

# Configuration
$ScriptName = "ComputerDescriptionFromAD"
$LogFile = "$LogPath\$ScriptName.log"
$RegistryPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\ComputerDescriptionAD"

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

function Test-DomainJoined {
    try {
        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem
        $isDomainJoined = $computerSystem.PartOfDomain
        $domain = $computerSystem.Domain
        
        if ($isDomainJoined) {
            Write-Log "Computer is domain joined to: $domain" "SUCCESS"
            return $domain
        }
        else {
            Write-Log "Computer is not domain joined (workgroup: $domain)" "WARN"
            return $null
        }
    }
    catch {
        Write-Log "Failed to check domain join status: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Get-ADDescriptionLDAP {
    param(
        [string]$ComputerName,
        [string]$Domain,
        [string]$Server = ""
    )
    
    try {
        Write-Log "Querying AD via LDAP for computer: $ComputerName"
        
        # Parse domain for LDAP path
        $domainParts = $Domain -split '\.'
        $ldapPath = ($domainParts | ForEach-Object { "DC=$_" }) -join ","
        
        # Build LDAP query
        $searcher = New-Object System.DirectoryServices.DirectorySearcher
        
        if (-not [string]::IsNullOrEmpty($Server)) {
            $searcher.SearchRoot = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$Server/$ldapPath")
        }
        else {
            $searcher.SearchRoot = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$ldapPath")
        }
        
        $searcher.Filter = "(&(objectClass=computer)(name=$ComputerName))"
        $searcher.PropertiesToLoad.Add("description") | Out-Null
        $searcher.PropertiesToLoad.Add("cn") | Out-Null
        $searcher.PropertiesToLoad.Add("distinguishedName") | Out-Null
        
        $result = $searcher.FindOne()
        
        if ($result) {
            $description = $result.Properties["description"]
            $computerCN = $result.Properties["cn"]
            
            if ($description) {
                $descText = $description[0]
                Write-Log "Found AD description for $computerCN`: $descText" "SUCCESS"
                return $descText
            }
            else {
                Write-Log "Computer found in AD but has no description attribute" "WARN"
                return $null
            }
        }
        else {
            Write-Log "Computer not found in AD: $ComputerName" "WARN"
            return $null
        }
    }
    catch {
        Write-Log "LDAP query failed: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Get-ADDescriptionADModule {
    param(
        [string]$ComputerName,
        [string]$Server = ""
    )
    
    try {
        Write-Log "Querying AD via ActiveDirectory module for computer: $ComputerName"
        
        # Check if module is available
        if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
            Write-Log "ActiveDirectory module not available" "WARN"
            return $null
        }
        
        Import-Module ActiveDirectory -ErrorAction Stop
        
        $params = @{
            Identity = $ComputerName
            Properties = "Description"
            ErrorAction = "Stop"
        }
        
        if (-not [string]::IsNullOrEmpty($Server)) {
            $params.Server = $Server
        }
        
        if ($Credential) {
            $params.Credential = $Credential
        }
        
        $computer = Get-ADComputer @params
        
        if ($computer -and $computer.Description) {
            Write-Log "Found AD description: $($computer.Description)" "SUCCESS"
            return $computer.Description
        }
        else {
            Write-Log "Computer found but has no description attribute" "WARN"
            return $null
        }
    }
    catch {
        Write-Log "AD module query failed: $($_.Exception.Message)" "WARN"
        return $null
    }
}

function Get-CurrentLocalDescription {
    try {
        $computerInfo = Get-WmiObject -Class Win32_OperatingSystem
        $description = $computerInfo.Description
        Write-Log "Current local description: $description" "INFO"
        return $description
    }
    catch {
        Write-Log "Failed to get local description: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Set-LocalComputerDescription {
    param([string]$Description)
    
    try {
        Write-Log "Setting local computer description to: $Description"
        
        # Method 1: WMI
        $computerSystem = Get-WmiObject -Class Win32_OperatingSystem
        $computerSystem.Description = $Description
        $computerSystem.Put() | Out-Null
        
        # Verify the change
        $verify = Get-WmiObject -Class Win32_OperatingSystem
        if ($verify.Description -eq $Description) {
            Write-Log "Local description updated successfully" "SUCCESS"
            return $true
        }
        else {
            throw "Description verification failed"
        }
    }
    catch {
        Write-Log "Failed to set local description via WMI: $($_.Exception.Message)" "ERROR"
        
        # Method 2: CIM as fallback
        try {
            Write-Log "Trying CIM method..."
            Set-CimInstance -Query "SELECT * FROM Win32_OperatingSystem" -Property @{Description = $Description} -ErrorAction Stop
            Write-Log "Local description updated via CIM" "SUCCESS"
            return $true
        }
        catch {
            Write-Log "CIM method also failed: $($_.Exception.Message)" "ERROR"
            return $false
        }
    }
}

function Register-Operation {
    param(
        [string]$ADDescription,
        [string]$LocalDescription,
        [bool]$Success
    )
    
    try {
        if (!(Test-Path $RegistryPath)) {
            New-Item -Path $RegistryPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $RegistryPath -Name "LastRun" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Set-ItemProperty -Path $RegistryPath -Name "ADDescription" -Value $ADDescription
        Set-ItemProperty -Path $RegistryPath -Name "LocalDescription" -Value $LocalDescription
        Set-ItemProperty -Path $RegistryPath -Name "Success" -Value ([string]$Success)
        
        Write-Log "Operation registered in registry" "SUCCESS"
    }
    catch {
        Write-Log "Failed to register operation: $($_.Exception.Message)" "WARN"
    }
}

# ==================== MAIN EXECUTION ====================

Write-Log "=== Computer Description from AD Sync Started ==="
Write-Log "Script version: 1.0"
Write-Log "Computer name: $env:COMPUTERNAME"

# Check if domain joined
$domain = Test-DomainJoined
if (-not $domain) {
    Write-Log "Computer is not domain joined. Using fallback if provided." "WARN"
    
    if (-not [string]::IsNullOrEmpty($FallbackDescription)) {
        $currentDesc = Get-CurrentLocalDescription
        if ($currentDesc -ne $FallbackDescription -or $Force) {
            Set-LocalComputerDescription -Description $FallbackDescription | Out-Null
            Register-Operation -ADDescription "N/A - Not domain joined" -LocalDescription $FallbackDescription -Success $true
        }
        exit 0
    }
    else {
        Write-Log "No fallback description provided. Exiting." "ERROR"
        exit 1
    }
}

# Get current local description
$currentLocalDescription = Get-CurrentLocalDescription

# Try to get description from AD
try {
    # Try ActiveDirectory module first (more reliable)
    $adDescription = Get-ADDescriptionADModule -ComputerName $env:COMPUTERNAME -Server $DomainController
    
    # Fall back to LDAP if AD module not available
    if (-not $adDescription) {
        $adDescription = Get-ADDescriptionLDAP -ComputerName $env:COMPUTERNAME -Domain $domain -Server $DomainController
    }
}
catch {
    Write-Log "AD query failed: $($_.Exception.Message)" "ERROR"
    $adDescription = $null
}

# Determine final description to use
if ($adDescription) {
    $targetDescription = $adDescription
    Write-Log "Using description from AD: $targetDescription"
}
elseif (-not [string]::IsNullOrEmpty($FallbackDescription)) {
    $targetDescription = $FallbackDescription
    Write-Log "Using fallback description: $targetDescription" "WARN"
}
else {
    Write-Log "No AD description found and no fallback provided. Nothing to do." "WARN"
    exit 0
}

# Check if update is needed
if (-not $Force -and $currentLocalDescription -eq $targetDescription) {
    Write-Log "Local description already matches target. No update needed." "SUCCESS"
    Register-Operation -ADDescription $adDescription -LocalDescription $targetDescription -Success $true
    exit 0
}

# Set the local description
$success = Set-LocalComputerDescription -Description $targetDescription

# Register completion
Register-Operation -ADDescription $adDescription -LocalDescription $targetDescription -Success $success

if ($success) {
    Write-Log "=== Computer description sync completed successfully ===" "SUCCESS"
    exit 0
}
else {
    Write-Log "=== Computer description sync failed ===" "ERROR"
    exit 1
}