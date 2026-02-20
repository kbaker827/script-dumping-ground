#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Deploys certificates for WiFi/VPN authentication via Intune.

.DESCRIPTION
    Installs certificates from files or AD to LocalMachine certificate stores.
    Supports root CA, intermediate CA, and client authentication certificates.

.PARAMETER CertFile
    Path to certificate file (.cer, .crt, .p7b, .pfx)

.PARAMETER CertStore
    Certificate store: Root, CA, My (Personal)

.PARAMETER PFXPassword
    Password for PFX file (if applicable)

.PARAMETER ExportFromAD
    Export certificate from Active Directory

.PARAMETER ADCertTemplate
    Certificate template name (when using ExportFromAD)

.PARAMETER AutoEnroll
    Trigger certificate auto-enrollment

.PARAMETER LogPath
    Path for operation logs

.EXAMPLE
    .\Install-Certificate.ps1 -CertFile "C:\Certs\RootCA.cer" -CertStore Root

.EXAMPLE
    .\Install-Certificate.ps1 -CertFile "C:\Certs\Client.pfx" -CertStore My -PFXPassword "password123"

.EXAMPLE
    .\Install-Certificate.ps1 -AutoEnroll

.NOTES
    Version:        1.0
    Author:         IT Admin
    Creation Date:  2025-02-19
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$CertFile = "",

    [Parameter(Mandatory=$false)]
    [ValidateSet("Root", "CA", "My")]
    [string]$CertStore = "Root",

    [Parameter(Mandatory=$false)]
    [string]$PFXPassword = "",

    [Parameter(Mandatory=$false)]
    [switch]$ExportFromAD,

    [Parameter(Mandatory=$false)]
    [string]$ADCertTemplate = "",

    [Parameter(Mandatory=$false)]
    [switch]$AutoEnroll,

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
)

$ScriptName = "CertificateInstall"
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

function Install-CertFromFile {
    try {
        Write-Log "Installing certificate from: $CertFile"
        
        if (!(Test-Path $CertFile)) {
            throw "Certificate file not found"
        }
        
        $storeLocation = "Cert:\LocalMachine\"
        switch ($CertStore) {
            "Root" { $storePath = $storeLocation + "Root" }
            "CA" { $storePath = $storeLocation + "CA" }
            "My" { $storePath = $storeLocation + "My" }
        }
        
        $extension = [System.IO.Path]::GetExtension($CertFile).ToLower()
        
        if ($extension -eq ".pfx") {
            # Import PFX
            $password = ConvertTo-SecureString $PFXPassword -AsPlainText -Force
            Import-PfxCertificate -FilePath $CertFile -CertStoreLocation $storePath -Password $password -ErrorAction Stop
        } else {
            # Import CER/CRT/P7B
            Import-Certificate -FilePath $CertFile -CertStoreLocation $storePath -ErrorAction Stop
        }
        
        Write-Log "Certificate installed to $CertStore store" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to install certificate: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Invoke-AutoEnrollment {
    try {
        Write-Log "Triggering certificate auto-enrollment"
        
        # Trigger auto-enrollment via certutil
        $result = certutil -pulse 2>&1
        Write-Log "Auto-enrollment triggered"
        
        # Alternative: Group Policy update
        gpupdate /force /target:computer 2>&1 | Out-Null
        
        Write-Log "Auto-enrollment completed" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Auto-enrollment failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Get-CertificateFromAD {
    try {
        if ([string]::IsNullOrEmpty($ADCertTemplate)) {
            throw "ADCertTemplate required when using ExportFromAD"
        }
        
        Write-Log "Requesting certificate from AD: $ADCertTemplate"
        
        # Request certificate via certreq
        $infContent = @"
[NewRequest]
Subject = "CN=$env:COMPUTERNAME"
MachineKeySet = TRUE
KeyLength = 2048
Exportable = TRUE
[RequestAttributes]
CertificateTemplate = $ADCertTemplate
"@
        
        $infPath = "$env:TEMP\certreq.inf"
        $reqPath = "$env:TEMP\certreq.req"
        $cerPath = "$env:TEMP\certreq.cer"
        
        $infContent | Out-File -FilePath $infPath -Encoding ASCII
        
        # Create request
        certreq -new $infPath $reqPath 2>&1 | Out-Null
        
        # Submit to CA
        certreq -submit $reqPath $cerPath 2>&1 | Out-Null
        
        # Install certificate
        if (Test-Path $cerPath) {
            Import-Certificate -FilePath $cerPath -CertStoreLocation "Cert:\LocalMachine\My" -ErrorAction Stop
            Write-Log "Certificate from AD installed" "SUCCESS"
            
            # Cleanup
            Remove-Item $infPath, $reqPath, $cerPath -ErrorAction SilentlyContinue
            
            return $true
        } else {
            throw "Certificate was not issued"
        }
    }
    catch {
        Write-Log "AD certificate request failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Main
Write-Log "=== Certificate Deployment Started ==="

$success = $false

if ($AutoEnroll) {
    $success = Invoke-AutoEnrollment
}
elseif ($ExportFromAD) {
    $success = Get-CertificateFromAD
}
elseif ($CertFile) {
    $success = Install-CertFromFile
}
else {
    Write-Log "No action specified" "ERROR"
    exit 1
}

if ($success) {
    Write-Log "=== Certificate deployment completed ===" "SUCCESS"
    exit 0
} else {
    exit 1
}