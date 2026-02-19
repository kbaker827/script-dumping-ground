#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs a wireless (Wi-Fi) profile on Windows 10/11 for Intune deployment.

.DESCRIPTION
    Imports and configures a Wi-Fi profile on Windows devices. Supports both
    XML profile files and manual configuration parameters. Designed for silent
    deployment through Microsoft Intune.

.PARAMETER ProfileXML
    Path to the Wi-Fi profile XML file exported from Windows or created manually

.PARAMETER ProfileName
    Name of the Wi-Fi network (SSID) - required if not using XML file

.PARAMETER SSID
    The SSID of the wireless network (if different from ProfileName)

.PARAMETER SecurityType
    Security type: WPA2Personal, WPA2Enterprise, WPA3Personal, WPA3Enterprise, Open

.PARAMETER PSK
    Pre-shared key (password) for WPA2/WPA3 Personal networks

.PARAMETER EAPType
    EAP type for Enterprise networks: PEAP, TLS, TTLS

.PARAMETER EAPMethod
    EAP method for authentication (required for Enterprise)

.PARAMETER ServerNames
    Server names for certificate validation (comma-separated)

.PARAMETER TrustedRootCA
    Thumbprint of trusted root CA certificate

.PARAMETER ConnectAutomatically
    Automatically connect to this network when in range

.PARAMETER ConnectHidden
    Connect even if SSID is not broadcasting

.PARAMETER MakeDefault
    Set as the preferred/default network

.PARAMETER LogPath
    Path for installation logs

.EXAMPLE
    .\Install-WirelessProfile.ps1 -ProfileXML "C:\WiFi\CorpWiFi.xml"

.EXAMPLE
    .\Install-WirelessProfile.ps1 -ProfileName "CorpWiFi" -SecurityType WPA2Personal -PSK "MyPassword123"

.EXAMPLE
    .\Install-WirelessProfile.ps1 -ProfileName "CorpWiFi" -SecurityType WPA2Enterprise -EAPType PEAP -EAPMethod "Smart Card or other certificate"

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
    Requirements:   Windows 10/11, Administrator rights

    To export a profile from a configured Windows device:
    netsh wlan export profile name="YourWiFi" folder=C:\ folder= key=clear
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ProfileXML,

    [Parameter(Mandatory=$false)]
    [string]$ProfileName,

    [Parameter(Mandatory=$false)]
    [string]$SSID,

    [Parameter(Mandatory=$false)]
    [ValidateSet("WPA2Personal", "WPA2Enterprise", "WPA3Personal", "WPA3Enterprise", "Open", "WEP")]
    [string]$SecurityType = "WPA2Personal",

    [Parameter(Mandatory=$false)]
    [string]$PSK,

    [Parameter(Mandatory=$false)]
    [ValidateSet("PEAP", "TLS", "TTLS", "LEAP", "FAST")]
    [string]$EAPType,

    [Parameter(Mandatory=$false)]
    [string]$EAPMethod,

    [Parameter(Mandatory=$false)]
    [string]$ServerNames,

    [Parameter(Mandatory=$false)]
    [string]$TrustedRootCA,

    [Parameter(Mandatory=$false)]
    [switch]$ConnectAutomatically = $true,

    [Parameter(Mandatory=$false)]
    [switch]$ConnectHidden,

    [Parameter(Mandatory=$false)]
    [switch]$MakeDefault,

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
)

# Configuration
$ScriptName = "WirelessProfileInstall"
$LogFile = "$LogPath\$ScriptName.log"
$TempPath = "$env:TEMP\WirelessProfile"

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

function Test-WirelessAdapter {
    $adapter = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*Wi-Fi*" -or $_.InterfaceDescription -like "*Wireless*" }
    
    if (-not $adapter) {
        Write-Log "No wireless adapter found on this device" "WARN"
        return $false
    }
    
    Write-Log "Wireless adapter found: $($adapter.Name) - $($adapter.InterfaceDescription)" "SUCCESS"
    return $true
}

function Test-ProfileExists {
    param([string]$Name)
    
    try {
        $existing = netsh wlan show profile name="$Name" 2>&1
        if ($existing -match "Profile.*not found") {
            return $false
        }
        return $true
    }
    catch {
        return $false
    }
}

function Remove-ExistingProfile {
    param([string]$Name)
    
    try {
        if (Test-ProfileExists -Name $Name) {
            Write-Log "Removing existing profile: $Name"
            $result = netsh wlan delete profile name="$Name" 2>&1
            Write-Log "Remove result: $result"
        }
    }
    catch {
        Write-Log "Failed to remove existing profile: $($_.Exception.Message)" "WARN"
    }
}

function Install-ProfileFromXML {
    param([string]$XMLPath)
    
    try {
        Write-Log "Installing wireless profile from XML: $XMLPath"
        
        if (-not (Test-Path -Path $XMLPath)) {
            throw "XML file not found: $XMLPath"
        }
        
        # Get profile name from XML
        [xml]$xmlContent = Get-Content -Path $XMLPath
        $profileNameFromXML = $xmlContent.WLANProfile.name
        
        Write-Log "Profile name from XML: $profileNameFromXML"
        
        # Remove existing profile
        Remove-ExistingProfile -Name $profileNameFromXML
        
        # Install the profile
        $result = netsh wlan add profile filename="$XMLPath" 2>&1
        Write-Log "netsh result: $result"
        
        if ($result -match "successfully" -or $result -match "is added") {
            Write-Log "Profile installed successfully from XML" "SUCCESS"
            return $profileNameFromXML
        }
        else {
            throw "Failed to install profile: $result"
        }
    }
    catch {
        Write-Log "Failed to install from XML: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function New-WiFiProfileXML {
    param(
        [string]$Name,
        [string]$NetworkSSID,
        [string]$Security,
        [string]$Password,
        [string]$EAP,
        [string]$EAPAuthMethod,
        [string]$Servers,
        [string]$RootCAThumbprint,
        [bool]$AutoConnect,
        [bool]$HiddenNetwork
    )
    
    # Determine security configuration based on type
    $authEncryption = ""
    $sharedKey = ""
    $eapConfig = ""
    
    switch ($Security) {
        "Open" {
            $authEncryption = @"
            <authEncryption>
                <authentication>open</authentication>
                <encryption>none</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
"@
        }
        "WEP" {
            $authEncryption = @"
            <authEncryption>
                <authentication>open</authentication>
                <encryption>WEP</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>networkKey</keyType>
                <protected>false</protected>
                <keyMaterial>$Password</keyMaterial>
            </sharedKey>
"@
        }
        "WPA2Personal" {
            $authEncryption = @"
            <authEncryption>
                <authentication>WPA2PSK</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$Password</keyMaterial>
            </sharedKey>
"@
        }
        "WPA3Personal" {
            $authEncryption = @"
            <authEncryption>
                <authentication>WPA3SAE</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$Password</keyMaterial>
            </sharedKey>
"@
        }
        "WPA2Enterprise" {
            $eapConfig = New-EAPConfiguration -EAPType $EAP -EAPMethod $EAPAuthMethod -ServerNames $Servers -RootCAThumbprint $RootCAThumbprint
            $authEncryption = @"
            <authEncryption>
                <authentication>WPA2</authentication>
                <encryption>AES</encryption>
                <useOneX>true</useOneX>
            </authEncryption>
            <eapConfig>$eapConfig</eapConfig>
"@
        }
        "WPA3Enterprise" {
            $eapConfig = New-EAPConfiguration -EAPType $EAP -EAPMethod $EAPAuthMethod -ServerNames $Servers -RootCAThumbprint $RootCAThumbprint
            $authEncryption = @"
            <authEncryption>
                <authentication>WPA3</authentication>
                <encryption>AES</encryption>
                <useOneX>true</useOneX>
            </authEncryption>
            <eapConfig>$eapConfig</eapConfig>
"@
        }
    }
    
    $hexSSID = [System.BitConverter]::ToString([System.Text.Encoding]::UTF8.GetBytes($NetworkSSID)).Replace("-", "")
    $connectionMode = if ($AutoConnect) { "auto" } else { "manual" }
    $connectionHidden = if ($HiddenNetwork) { "true" } else { "false" }
    
    $xml = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$Name</name>
    <SSIDConfig>
        <SSID>
            <hex>$hexSSID</hex>
            <name>$NetworkSSID</name>
        </SSID>
        <nonBroadcast>$connectionHidden</nonBroadcast>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>$connectionMode</connectionMode>
    <MSM>
        <security>
            $authEncryption
        </security>
    </MSM>
</WLANProfile>
"@
    
    return $xml
}

function New-EAPConfiguration {
    param(
        [string]$EAPType,
        [string]$EAPMethod,
        [string]$ServerNames,
        [string]$RootCAThumbprint
    )
    
    # Simplified EAP configuration - full config would require more detailed XML
    # This is a basic template that would need customization for specific environments
    
    $serverValidation = ""
    if ($ServerNames) {
        $serverList = $ServerNames -split "," | ForEach-Object { "<serverName>$_</serverName>" }
        $serverValidation = $serverList -join "`n                "
    }
    
    $thumbprintXML = ""
    if ($RootCAThumbprint) {
        $thumbprintXML = "<trustedRootCA>$RootCAThumbprint</trustedRootCA>"
    }
    
    $eapXML = @"
<Config xmlns="http://www.microsoft.com/provisioning/EapHostConfig">
    <EapMethod>
        <Type xmlns="http://www.microsoft.com/provisioning/EapCommon">25</Type>
        <VendorId xmlns="http://www.microsoft.com/provisioning/EapCommon">0</VendorId>
        <VendorType xmlns="http://www.microsoft.com/provisioning/EapCommon">0</VendorType>
        <AuthorId xmlns="http://www.microsoft.com/provisioning/EapCommon">0</AuthorId>
    </EapMethod>
    <Config xmlns="http://www.microsoft.com/provisioning/EapHostConfig">
        <Eap xmlns="http://www.microsoft.com/provisioning/BaseEapConnectionPropertiesV1">
            <Type>25</Type>
            <EapType xmlns="http://www.microsoft.com/provisioning/MsPeapConnectionPropertiesV1">
                <ServerValidation>
                    <DisableServerValidation>false</DisableServerValidation>
                    <ServerNames>
                        $serverValidation
                    </ServerNames>
                    $thumbprintXML
                </ServerValidation>
            </EapType>
        </Eap>
    </Config>
</Config>
"@
    
    return [System.Security.SecurityElement]::Escape($eapXML)
}

function Install-ProfileFromParameters {
    param(
        [string]$Name,
        [string]$NetworkSSID,
        [string]$Security,
        [string]$Password,
        [string]$EAP,
        [string]$EAPAuthMethod,
        [string]$Servers,
        [string]$RootCAThumbprint,
        [bool]$AutoConnect,
        [bool]$HiddenNetwork
    )
    
    try {
        Write-Log "Creating wireless profile from parameters: $Name"
        
        # Use ProfileName as SSID if not specified
        if ([string]::IsNullOrEmpty($NetworkSSID)) {
            $NetworkSSID = $Name
        }
        
        # Generate XML
        $xmlContent = New-WiFiProfileXML -Name $Name -NetworkSSID $NetworkSSID -Security $Security `
            -Password $Password -EAP $EAP -EAPMethod $EAPAuthMethod -Servers $Servers `
            -RootCAThumbprint $RootCAThumbprint -AutoConnect $AutoConnect -HiddenNetwork $HiddenNetwork
        
        # Create temp directory
        if (!(Test-Path -Path $TempPath)) {
            New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
        }
        
        $xmlPath = Join-Path $TempPath "$Name.xml"
        Set-Content -Path $xmlPath -Value $xmlContent -Encoding UTF8
        
        Write-Log "Generated XML profile at: $xmlPath"
        
        # Install the generated profile
        return Install-ProfileFromXML -XMLPath $xmlPath
    }
    catch {
        Write-Log "Failed to create and install profile: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Set-ProfilePriority {
    param([string]$Name)
    
    try {
        Write-Log "Setting profile priority for: $Name"
        $result = netsh wlan set profileorder name="$Name" interface="Wi-Fi" priority=1 2>&1
        Write-Log "Priority set: $result" "SUCCESS"
    }
    catch {
        Write-Log "Failed to set profile priority: $($_.Exception.Message)" "WARN"
    }
}

function Register-InstallCompletion {
    param([string]$Name)
    
    $regPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\WirelessProfile"
    try {
        if (!(Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $regPath -Name "InstalledProfile" -Value $Name
        Set-ItemProperty -Path $regPath -Name "InstallDate" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Set-ItemProperty -Path $regPath -Name "ProfileType" -Value $SecurityType
        
        Write-Log "Installation registered in registry" "SUCCESS"
    }
    catch {
        Write-Log "Failed to register installation: $($_.Exception.Message)" "WARN"
    }
}

# ==================== MAIN EXECUTION ====================

Write-Log "=== Wireless Profile Installation Started ==="
Write-Log "Script version: 1.0"

# Check for wireless adapter
if (-not (Test-WirelessAdapter)) {
    Write-Log "No wireless adapter detected - profile will be installed for when adapter is available" "WARN"
}

$installedProfileName = $null

# Determine installation method
if (-not [string]::IsNullOrEmpty($ProfileXML)) {
    # Install from XML file
    $installedProfileName = Install-ProfileFromXML -XMLPath $ProfileXML
}
elseif (-not [string]::IsNullOrEmpty($ProfileName)) {
    # Install from parameters
    $installedProfileName = Install-ProfileFromParameters -Name $ProfileName -NetworkSSID $SSID `
        -Security $SecurityType -Password $PSK -EAP $EAPType -EAPMethod $EAPMethod `
        -Servers $ServerNames -RootCAThumbprint $TrustedRootCA `
        -AutoConnect $ConnectAutomatically -HiddenNetwork $ConnectHidden
}
else {
    Write-Log "Either ProfileXML or ProfileName must be specified" "ERROR"
    exit 1
}

if ($installedProfileName) {
    # Set as default if requested
    if ($MakeDefault) {
        Set-ProfilePriority -Name $installedProfileName
    }
    
    # Register completion
    Register-InstallCompletion -Name $installedProfileName
    
    # Cleanup temp files
    if (Test-Path -Path $TempPath) {
        Remove-Item -Path $TempPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    Write-Log "=== Wireless profile installation completed successfully ===" "SUCCESS"
    Write-Log "Profile: $installedProfileName"
    exit 0
}
else {
    Write-Log "=== Wireless profile installation failed ===" "ERROR"
    exit 1
}