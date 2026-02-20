#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Deploys VPN profile via Intune.

.DESCRIPTION
    Creates Windows VPN connection with various protocol support including
    IKEv2, SSTP, and L2TP. Can deploy with certificate or credentials.

.PARAMETER ConnectionName
    Display name for the VPN connection

.PARAMETER ServerAddress
    VPN server address (FQDN or IP)

.PARAMETER TunnelType
    VPN protocol: IKEv2, SSTP, L2TP, PPTP, Automatic

.PARAMETER AuthenticationMethod
    Auth method: EAP, MSChapv2, PAP, Certificate

.PARAMETER CertCommonName
    Certificate common name for EAP-TLS

.PARAMETER CertThumbprint
    Certificate thumbprint for client auth

.PARAMETER SplitTunneling
    Enable split tunneling

.PARAMETER RememberCredential
    Remember user credentials

.PARAMETER RegisterDNS
    Register in DNS

.PARAMETER DisableIKEv2Fragmentation
    Disable IKEv2 fragmentation (workaround for some VPNs)

.PARAMETER LogPath
    Path for operation logs

.EXAMPLE
    .\Add-VPNProfile.ps1 -ConnectionName "CorpVPN" -ServerAddress "vpn.company.com" -TunnelType IKEv2 -AuthenticationMethod EAP

.EXAMPLE
    .\Add-VPNProfile.ps1 -ConnectionName "RemoteVPN" -ServerAddress "203.0.113.1" -TunnelType SSTP -AuthenticationMethod MSChapv2 -SplitTunneling

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ConnectionName,

    [Parameter(Mandatory=$true)]
    [string]$ServerAddress,

    [Parameter(Mandatory=$false)]
    [ValidateSet("IKEv2", "SSTP", "L2TP", "PPTP", "Automatic")]
    [string]$TunnelType = "IKEv2",

    [Parameter(Mandatory=$false)]
    [ValidateSet("EAP", "MSChapv2", "PAP", "Certificate")]
    [string]$AuthenticationMethod = "EAP",

    [Parameter(Mandatory=$false)]
    [string]$CertCommonName = "",

    [Parameter(Mandatory=$false)]
    [string]$CertThumbprint = "",

    [Parameter(Mandatory=$false)]
    [switch]$SplitTunneling,

    [Parameter(Mandatory=$false)]
    [switch]$RememberCredential,

    [Parameter(Mandatory=$false)]
    [switch]$RegisterDNS,

    [Parameter(Mandatory=$false)]
    [switch]$DisableIKEv2Fragmentation,

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
)

$ScriptName = "VPNProfile"
$LogFile = "$LogPath\$ScriptName.log"

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

function Remove-ExistingVPN {
    try {
        $existing = Get-VpnConnection -Name $ConnectionName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Log "Removing existing VPN connection"
            Remove-VpnConnection -Name $ConnectionName -Force -ErrorAction Stop
        }
    }
    catch {
        Write-Log "Could not remove existing VPN: $($_.Exception.Message)" "WARN"
    }
}

function Add-VPNConnection {
    try {
        Write-Log "Creating VPN connection: $ConnectionName"
        
        $params = @{
            Name = $ConnectionName
            ServerAddress = $ServerAddress
            TunnelType = $TunnelType
            EncryptionLevel = "Required"
            AuthenticationMethod = $AuthenticationMethod
            SplitTunneling = $SplitTunneling
            RememberCredential = $RememberCredential
            RegisterDns = $RegisterDNS
            Force = $true
        }
        
        if ($AuthenticationMethod -eq "EAP" -and $CertCommonName) {
            # Configure EAP-TLS
            $eapConfig = @"
            <?xml version="1.0"?>
            <EapHostConfig xmlns="http://www.microsoft.com/provisioning/EapHostConfig">
                <EapMethod>
                    <Type xmlns="http://www.microsoft.com/provisioning/EapCommon">13</Type>
                </EapMethod>
            </EapHostConfig>
"@
            $params.EapConfigXmlStream = $eapConfig
        }
        
        Add-VpnConnection @params -ErrorAction Stop
        
        # Additional IKEv2 settings
        if ($TunnelType -eq "IKEv2" -and $DisableIKEv2Fragmentation) {
            Set-VpnConnectionIPsecConfiguration -ConnectionName $ConnectionName -Force -SADataSizeForRenegotiationKilobytes 0
        }
        
        Write-Log "VPN connection created successfully" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to create VPN: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Set-VPNRoutes {
    try {
        # Add common corporate routes
        $routes = @(
            @{DestinationPrefix = "10.0.0.0/8"; RouteMetric = 10}
            @{DestinationPrefix = "172.16.0.0/12"; RouteMetric = 10}
            @{DestinationPrefix = "192.168.0.0/16"; RouteMetric = 10}
        )
        
        foreach ($route in $routes) {
            try {
                Add-VpnConnectionRoute -ConnectionName $ConnectionName @route -ErrorAction SilentlyContinue
            }
            catch {
                # Route may already exist
            }
        }
        
        Write-Log "VPN routes configured"
    }
    catch {
        Write-Log "Could not configure routes: $($_.Exception.Message)" "WARN"
    }
}

# Main
Write-Log "=== VPN Profile Deployment Started ==="

Remove-ExistingVPN
$success = Add-VPNConnection

if ($success -and $SplitTunneling) {
    Set-VPNRoutes
}

if ($success) {
    Write-Log "=== VPN deployment completed ===" "SUCCESS"
    exit 0
} else {
    exit 1
}