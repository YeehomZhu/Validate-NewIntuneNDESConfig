
<#PSScriptInfo

.VERSION 1.8

.GUID f4f1a062-5425-4ace-a47d-5604c1ba7be0

.AUTHOR Leon Zhu, Premkumar N 

.COMPANYNAME 

.COPYRIGHT 

.TAGS NDES Intune SCEP CertificateConnector PKI Validation

.LICENSEURI 

.PROJECTURI https://github.com/leonzhu/Validate-NewIntuneNDESConfig



.ICONURI 

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS 

.EXTERNALSCRIPTDEPENDENCIES 

.RELEASENOTES
Version 1.0 Re-write part of functions in orginal Validate-NDESconfiguration script and support new NDES connector
Version 1.1 Bug fix
Version 1.4 Adding support to collect system/application/GPresult log. Meanwhile, collect AADAgent Updater log which monitor NDES connector update event as well as test the network connection to connector update endpoint
Version 1.5 Adding more codes to check event log
Version 1.6 Bug fix and add code to check connector status
Version 1.7 Add OS last restart time and NDES-related services last start time checks
Version 1.8 Bug fixes: null SID guard, ESC registry existence check, null accountName guard, replace Get-WmiObject with Get-CimInstance, Get-Service ErrorAction, LastConnectionTime parse guard, add Import-Module WebAdministration
#>

<# 

.DESCRIPTION  
Since Intune has released new certificate connector and way to issue SCEP cert from NDES server. This script improve and update the way to check the configuration on NDES based server on previous Validate-NDESConfig, and ensures it aligns to the "Configure and manage SCEP 
certificates with new Intune certification connector. This is based on https://github.com/microsoftgraph/powershell-intune-samples/blob/master/CertificationAuthority/Validate-NDESConfiguration.ps1  Validates and highlights configuration problems on an NDES server installed new Intune certificate connector. We don't need to install extra module in the tool now, all functions use nature Server supported commands.


After installing the script, run "Validate-NewIntuneNDESConfig.ps1" directly. 

NOTE: This script is used purely to validate the configuration. All remedial tasks will need to be carried out manually. W

Use of this script requires the following:

#Script should be run directly on the NDES Server
#Requires PowerShell version 3.0 at a minimum
#Requires PowerShell to be Run As Administrator

Re-write check Server version 
Re-write check NDES role and CA status
Re-write check SCEP in IIS application pool
Add certificate valid check for MSCEP and connector certificate
Add new feature to check Connector event log

#> 

Param(
[parameter(ParameterSetName="Help")]
[alias("h","?","/?")]
[switch]$help,

[parameter(ParameterSetName="Help")]
[alias("u")]
[switch]$usage  
)
    
#######################################################################

Function Log-ScriptEvent{
    
    [CmdletBinding()]
    
    Param(
      [parameter(Mandatory=$True)]
      [String]$LogFilePath,

      [parameter(Mandatory=$True)]
      [String]$Value,

      [parameter(Mandatory=$True)]
      [String]$Component,

      [parameter(Mandatory=$True)]
      [ValidateRange(1,3)]
      [Single]$Severity
      )

        $DateTime = New-Object -ComObject WbemScripting.SWbemDateTime 
        $DateTime.SetVarDate($(Get-Date))
        $UtcValue = $DateTime.Value
        $UtcOffset = $UtcValue.Substring(21, $UtcValue.Length - 21)

        $LogLine =  "<![LOG[$Value]LOG]!>" +`
                    "<time=`"$(Get-Date -Format HH:mm:ss.fff)$($UtcOffset)`" " +`
                    "date=`"$(Get-Date -Format M-d-yyyy)`" " +`
                    "component=`"$Component`" " +`
                    "context=`"$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " +`
                    "type=`"$Severity`" " +`
                    "thread=`"$([Threading.Thread]::CurrentThread.ManagedThreadId)`" " +`
                    "file=`"`">"

        Add-Content -Path $LogFilePath -Value $LogLine

}

##########################################################################################################

function Show-Usage {

    Write-Host
    Write-Host "-help                       -h         Displays the help."
    Write-Host "-usage                      -u         Displays this usage information."
    Write-Host

}

#######################################################################

function Get-NDESHelp {

    Write-Host
    Write-Host "Verifies if the NDES server meets the required configuration for new Intune certificate connector. "
    Write-Host
    Write-Host "The NDES server role is required as back-end infrastructure for Intune Standalone for delivering VPN and Wi-Fi certificates via the SCEP protocol to mobile devices and desktop clients."
    Write-Host "See https://learn.microsoft.com/en-us/mem/intune/protect/certificates-scep-configure."
    Write-Host "The script will check"
    Write-Host "Server OS version."
    Write-Host
   

}

#######################################################################

    if ($help){

        Get-NDESHelp
        break

    }

    if ($usage){

        Show-Usage
        break
    }

#######################################################################

#Requires -version 3.0
#Requires -RunAsAdministrator

#######################################################################

$parent = [System.IO.Path]::GetTempPath()
[string] $name = [System.Guid]::NewGuid()
New-Item -ItemType Directory -Path (Join-Path $parent $name) | Out-Null
$TempDirPath = "$parent$name"
$LogFilePath = "$($TempDirPath)\Validate-NewIntuneNDESConfig.log"

#######################################################################
Write-host "##########################################################################################"
Write-Host "##                                                                                      ##"
Write-Host "##                 You are using new Intune NDES vertification script.                  ##"
Write-Host "##                 This script is used purely to validate the configuration.            ##"
Write-Host "##                 All remedial tasks will need to be carried out manually..            ##"
Write-Host "##                                                                                      ##"
Write-host "##########################################################################################"
Write-Host
Write-Host "We are on server " -NoNewline
Write-Host $(([System.Net.Dns]::GetHostByName(($env:computerName))).hostname) -ForegroundColor Cyan
Write-Host "Would you like to procee with variables? [Y]es, [N]o" -ForegroundColor Cyan
    
$confirmation = Read-Host

if ($confirmation -eq 'y'){
    
    Write-Host
    Write-host "Starting validation job" -ForegroundColor Cyan -NoNewline
    Write-Host "..............................."
    Log-ScriptEvent $LogFilePath "Initializing log file $($TempDirPath)\Validate-NewIntuneNDESConfig.log"  NDES_Validation 1
    Log-ScriptEvent $LogFilePath "Proceeding with variables=YES"  NDES_Validation 1

#######################################################################

#region checking Server OS version
Write-host
Write-host "......................................................."
Write-host
Write-host "Checking Current Server OS version..." -ForegroundColor Yellow
Write-host
Log-ScriptEvent $LogFilePath "Checking OS Version" NDES_Validation 1
$OSVersion = (Get-CimInstance -class Win32_OperatingSystem).Version

#Require version requires 2012 R2 and above
$MinOSVersion = "6.3.9600"

if ([version]$OSVersion -lt [version]$MinOSVersion){

    Write-host "Error: " -ForegroundColor Red -NoNewline
    Write-host "Unsupported OS Version. NDES Requires 2012 R2 and above." 
    Write-host "Please check General prerequisites of Connector"
    Write-host "URL: https://learn.microsoft.com/en-us/mem/intune/protect/certificate-connector-prerequisites#general-prerequisites"
    Log-ScriptEvent $LogFilePath "Unsupported OS Version. NDES Server Requires 2012 R2 and above. Server version is  $($OSVersion)" NDES_Validation 3
    
    } 
else {

    Write-Host "Success: " -ForegroundColor Green -NoNewline
    Write-Host "OS Version " -NoNewline
    write-host "$($OSVersion)" -NoNewline -ForegroundColor Cyan
    write-host " meet prerequisites."
    Log-ScriptEvent $LogFilePath "Success: Server version is  $($OSVersion)" NDES_Validation 1

}

Log-ScriptEvent $LogFilePath "*********************************************************************************"  NDES_Validation 1
#endregion

#######################################################################

#region Checking OS last restart and NDES-related services last start time
Write-host
Write-host "......................................................."
Write-host
Write-host "Checking OS last restart time and NDES-related services last start time..." -ForegroundColor Yellow
Write-host
Log-ScriptEvent $LogFilePath "Checking OS last restart time and NDES-related services last start time" NDES_Validation 1

# OS last restart
$LastBootUpTime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
Write-Host "OS last restart time: " -NoNewline
Write-Host $LastBootUpTime -ForegroundColor Cyan
Log-ScriptEvent $LogFilePath "OS last restart time: $($LastBootUpTime)" NDES_Validation 1

# NDES-related services to check
$NDESRelatedServices = @(
    "W3SVC",                      # IIS - World Wide Web Publishing Service
    "PFXCertificateConnectorSvc", # Certificate Connector for Microsoft Intune
    "PKICertificateConnectorSvc", # PKI Certificate Connector
    "PkiRevokeConnectorSvc"       # PKI Revoke Connector
)

Write-host
Write-Host "NDES-related services last start time:" -ForegroundColor Yellow
Write-host

foreach ($serviceName in $NDESRelatedServices) {
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.Status -eq "Running") {
            $svcWMI = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
            if ($svcWMI -and $svcWMI.ProcessId -and $svcWMI.ProcessId -ne 0) {
                $proc = Get-Process -Id $svcWMI.ProcessId -ErrorAction SilentlyContinue
                if ($proc) {
                    Write-Host "$($serviceName): " -NoNewline -ForegroundColor Cyan
                    Write-Host "Running, last started at " -NoNewline
                    Write-Host $proc.StartTime -ForegroundColor Cyan
                    Log-ScriptEvent $LogFilePath "Service $($serviceName) is running, last started at $($proc.StartTime)" NDES_Validation 1
                } else {
                    Write-Host "$($serviceName): " -NoNewline -ForegroundColor Cyan
                    Write-Host "Running (start time unavailable)"
                    Log-ScriptEvent $LogFilePath "Service $($serviceName) is running (start time unavailable)" NDES_Validation 1
                }
            } else {
                Write-Host "$($serviceName): " -NoNewline -ForegroundColor Cyan
                Write-Host "Running (start time unavailable)"
                Log-ScriptEvent $LogFilePath "Service $($serviceName) is running (start time unavailable)" NDES_Validation 1
            }
        } else {
            Write-Host "$($serviceName): " -NoNewline -ForegroundColor DarkCyan
            Write-Host "Not running (Status: $($svc.Status))"
            Log-ScriptEvent $LogFilePath "Service $($serviceName) is not running. Status: $($svc.Status)" NDES_Validation 2
        }
    } else {
        Write-Host "$($serviceName): " -NoNewline
        Write-Host "Not found on this server" -ForegroundColor Gray
        Log-ScriptEvent $LogFilePath "Service $($serviceName) not found on this server" NDES_Validation 1
    }
}

Log-ScriptEvent $LogFilePath "*********************************************************************************"  NDES_Validation 1
#endregion

#######################################################################

#region Checking if NDES server is the CA and NDES install

Write-host "`n.......................................................`n"
Write-host "Checking if NDES server is the CA...`n" -ForegroundColor Yellow
Log-ScriptEvent $LogFilePath "Checking if NDES server is the CA" NDES_Validation 1


# Check if Certification Authority is installed
$caRole = (Get-WindowsFeature -Name ADCS-Cert-Authority -ErrorAction SilentlyContinue).InstallState

# Check if Network Device Enrollment Service is installed
$ndeRole = (Get-WindowsFeature -Name ADCS-Device-Enrollment -ErrorAction SilentlyContinue).InstallState

if ($caRole -ne "Installed" -and $ndeRole -eq "Installed") {

    Write-Host "Success: " -ForegroundColor Green -NoNewline
    Write-Host "The server has the 'Network Device Enrollment Service' role installed but does not have the 'Certification Authority' role installed." 
    Log-ScriptEvent $LogFilePath "Success: The server has the 'Network Device Enrollment Service' role installed but does not have the 'Certification Authority' role installed." NDES_Validation 1

} elseif ($caRole -eq "Installed") {

    Write-Host "Error: " -ForegroundColor Red -NoNewline
    Write-Host "NDES server has Certification Authority Role installed. This is an unsupported configuration." 
    Write-host "Please check Servers and server roles "
    Write-Host "URL: https://learn.microsoft.com/en-us/mem/intune/protect/certificates-scep-configure#servers-and-server-roles "
    Log-ScriptEvent $LogFilePath "Error: NDES server has Certification Authority Role installed. This is an unsupported configuration!" NDES_Validation 3

} elseif ($ndeRole -ne "Installed") {

    Write-Host "Error: " -ForegroundColor Red -NoNewline
    Write-Host "The server does not have 'Network Device Enrollment Service' role installed."
    Write-host "Please check Servers and server roles "
    Write-Host "URL: https://learn.microsoft.com/en-us/mem/intune/protect/certificates-scep-configure#servers-and-server-roles "
    Log-ScriptEvent $LogFilePath "Error:The server does not have 'Network Device Enrollment Service' role installed." NDES_Validation 3


} else {

    Write-Host "Error: " -ForegroundColor Red -NoNewline
    Write-Host "The server does not have 'Network Device Enrollment Service' role installed." 
    Write-host "Please check Servers and server roles "
    Write-Host "URL: https://learn.microsoft.com/en-us/mem/intune/protect/certificates-scep-configure#servers-and-server-roles "
    Log-ScriptEvent $LogFilePath "Error:The server does not have 'Network Device Enrollment Service' role installed." NDES_Validation 3
}
Log-ScriptEvent $LogFilePath "*********************************************************************************"  NDES_Validation 1

#endregion

#######################################################################

#region Define the server roles and prerequest features to check
Write-host
Write-host "......................................................."
Write-host
Write-host "Checking if NDES server has installed required features`n" -ForegroundColor Yellow
Log-ScriptEvent $LogFilePath "Checking if NDES server has installed required features" NDES_Validation 1 

$requiredRolesAndFeatures = @(
                                "Web-Server", # Web Server (IIS)
                                "NET-Framework-45-Features", # Assuming .NET Framework 4.5 Features as a placeholder for .NET 4.7
                                "Web-Asp-Net45", # Assuming ASP.NET 4.5 as a placeholder for ASP.NET 4.7
                                "NET-WCF-HTTP-Activation45", # HTTP Activation
                                "Web-Filtering", # Request Filtering
                                "Web-WMI", #IIS 6 WMI Compatibility
                                "Web-Metabase", #IIS 6 Metabase Compatibility
                                "Web-Mgmt-Console", #IIS 6 Management Console
                                "NET-HTTP-Activation" #HTTP Activation
                            )

# Checking each role and feature
foreach ($feature in $requiredRolesAndFeatures) {
    $status = Get-WindowsFeature -Name $feature
    
    if ($status.Installed) {
        
        Write-Host "Success: " -ForegroundColor Green -NoNewline
        write-host "$($status.DisplayName)" -NoNewline -ForegroundColor Cyan
        Write-Host " is installed."
        Log-ScriptEvent $LogFilePath "$($status.DisplayName) is installed." NDES_Validation 1 

    } else {

        Write-Host "Error: " -ForegroundColor Red -NoNewline
        write-host "$($status.DisplayName)" -NoNewline -ForegroundColor DarkCyan
        Write-Host " is not installed." 
        Write-host "Please check NDES compopnents "
        Write-Host "URL: https://learn.microsoft.com/en-us/mem/intune/protect/certificates-scep-configure#install-the-ndes-service and https://learn.microsoft.com/en-us/mem/intune/protect/certificate-connector-prerequisites#scep"
        Log-ScriptEvent $LogFilePath "Error: $($status.DisplayName) is not installed." NDES_Validation 3

    }
}

# Additional check for .NET Framework 4.7 - This is a simplified approach
# You might need a more specific check depending on your requirements
$dotNet47Key = "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"

if ((Get-ItemProperty -Path $dotNet47Key -Name Release).Release -ge 460798) {
    
    Write-Host "Success: " -ForegroundColor Green -NoNewline
    Write-Host ".NET Framework 4.7 or later is installed." 
    Log-ScriptEvent $LogFilePath "Success: .NET Framework 4.7 or later is installed." NDES_Validation 1 

} else {

    Write-Host "Error: " -ForegroundColor Red -NoNewline
    Write-Host ".NET Framework 4.7 or later is not installed." 
    Write-host "Please check NDES compopnents "
    Write-Host "URL: https://learn.microsoft.com/en-us/mem/intune/protect/certificates-scep-configure#install-the-ndes-service and https://learn.microsoft.com/en-us/mem/intune/protect/certificate-connector-prerequisites#scep"
    Log-ScriptEvent $LogFilePath ".NET Framework 4.7 or later is not installed." NDES_Validation 1 

}
Log-ScriptEvent $LogFilePath "*********************************************************************************"  NDES_Validation 1
#endregion

#######################################################################

################################################################
#The detection way is not good and need to improve
################################################################ 

#region Checking NDES Install Paramaters
Write-host
Write-host "......................................................."
Write-host
Write-host "Checking if NDES Configured paramters correctly`n" -ForegroundColor Yellow
Log-ScriptEvent $LogFilePath "Checking if NDES Configured paramters correctly" NDES_Validation 1 

# Specify the registry path for the NDES CSP
$ndesCspRegPath = "HKLM:\SOFTWARE\Microsoft\Cryptography\Defaults\Provider\Microsoft Strong Cryptographic Provider"

# Check if the registry path exists
if (Test-Path $ndesCspRegPath) {

    Write-Host "Success: " -ForegroundColor Green -NoNewline
    Write-Host "The NDES server is using the correct signature provider." 
    Log-ScriptEvent $LogFilePath "Success: The NDES server is using the correct signature provider." NDES_Validation 1 


} else {

    Write-Host "Error: " -ForegroundColor Red -NoNewline
    Write-Host "Warning: The NDES server is not using the correct signature provider." 
    Log-ScriptEvent $LogFilePath "The NDES server is not using the correct signature provider." NDES_Validation 3
}
Log-ScriptEvent $LogFilePath "*********************************************************************************"  NDES_Validation 1
#endregion

#################################################################
#region  Check is Enhanced Configuration is Deactivated
Write-host
Write-host "......................................................."
Write-host
Write-Host "Checking the Enhanced Configuration settings" -ForegroundColor Yellow
Log-ScriptEvent $LogFilePath "Checking the Enhanced Configuration settings" NDES_Validation 1 

# Check for the current state of Enhanced Security Configuration
$escRegPath = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
if (-not (Test-Path $escRegPath)) {
    Write-Host "Warning: " -ForegroundColor Yellow -NoNewline
    Write-Host "Enhanced Security Configuration registry key not found. Skipping check."
    Log-ScriptEvent $LogFilePath "Enhanced Security Configuration registry key not found." NDES_Validation 2
} else {
$escState = Get-ItemProperty $escRegPath

# If Enhanced Security Configuration is deactivated
if ($escState.IsInstalled -eq 0) {

    Write-Host "Success: " -ForegroundColor Green -NoNewline
    Write-Host "Enhanced Security Configuration is deactivated." 
    Log-ScriptEvent $LogFilePath "Enhanced Security Configuration is deactivated."  NDES_Validation 1


} else {

    Write-Host "Error: " -ForegroundColor Red -NoNewline
    Write-Host "Enhanced Security Configuration is activated."
    Log-ScriptEvent $LogFilePath "Enhanced Security Configuration is activated."  NDES_Validation 3

}
} # end if Test-Path escRegPath

Log-ScriptEvent $LogFilePath "*********************************************************************************"  NDES_Validation 1
#endregion

#################################################################

#region  Check SCEP Application is running in IIS (Need admin permission)
Write-host
Write-host "......................................................."
Write-host
Write-host "Checking if SCEP Application is running in IIS `n" -ForegroundColor Yellow
Log-ScriptEvent $LogFilePath "Checking if SCEP Application is running in IIS " NDES_Validation 1 

# Define the name of the application pool you want to check
$appPoolName = "SCEP"

# Use appcmd.exe to list the application pool and find its state
$appCmdPath = "${env:SystemRoot}\system32\inetsrv\appcmd.exe"

try {

    $appPoolState = & $appCmdPath list apppool /name:"$appPoolName" /text:state
    
    if ($appPoolState -eq "Started") {

        Write-Host "Success: " -ForegroundColor Green -NoNewline
        Write-Host "The application pool " -NoNewline 
        write-host "$($appPoolName)" -NoNewline -ForegroundColor Cyan
        Write-Host " is running." 
        Log-ScriptEvent $LogFilePath "Success: The application pool '$appPoolName' is running." NDES_Validation 1 
    
    } elseif ($appPoolState -eq "Stopped") { 

        Write-Host "Error: " -ForegroundColor Red -NoNewline
        Write-Host "The application pool " -NoNewline 
        write-host "$($appPoolName)" -NoNewline -ForegroundColor DarkCyan
        Write-Host " is stop." 
        Log-ScriptEvent $LogFilePath "The application pool '$appPoolName' is stopped." NDES_Validation 3 
    
    } else {

        Write-Host "Error: " -ForegroundColor Red -NoNewline
        Write-Host "The application pool " -NoNewline 
        write-host "$($appPoolName)" -NoNewline -ForegroundColor DarkCyan
        Write-Host " is in an unknown state:" -NoNewline
        Write-Host "$($appPoolState)" -ForegroundColor Red
        Log-ScriptEvent $LogFilePath "The application pool '$appPoolName' is in an unknown state: $appPoolState" NDES_Validation 3
    
    }
} catch {
    
    Write-Host "An error occurred while checking the application pool status. Error: $_" -ForegroundColor Red
    Log-ScriptEvent $LogFilePath "An error occurred while checking the application pool status. Error: $_" NDES_Validation 3

}
Log-ScriptEvent $LogFilePath "*********************************************************************************"  NDES_Validation 1
#endregion
#################################################################

#region Checking NDES Service Account local permissions

Write-host
Write-host "......................................................."
Write-host
Write-host "Checking NDES/SCEP Service Account local permissions..." -ForegroundColor Yellow
Write-host
Log-ScriptEvent $LogFilePath "Checking NDES Service Account local permissions" NDES_Validation 1 

$scepAppPoolinfo = Get-CimInstance -Namespace root/MicrosoftIISv2 -ClassName IIsApplicationPoolSetting -Property Name, WAMUserName -ErrorAction SilentlyContinue |select-Object -Property Name, WAMUserName | Where-Object {$_.name -like "*SCEP"}

$accountName = $scepAppPoolinfo.WAMUserName 
Write-host "SCEP is being run by account "  -NoNewline
Write-Host $accountName  -ForegroundColor Cyan 

if (-not $accountName) {
    Write-Warning "Could not determine SCEP service account. IIS6 WMI Compatibility may not be installed or SCEP app pool not configured."
    Log-ScriptEvent $LogFilePath "Could not determine SCEP service account" NDES_Validation 2
}

# Get the SID of the account
#$accountSID = (Get-WmiObject -Class Win32_UserAccount | Where-Object {$_.caption -eq "$accountName"}).SID

if ((net localgroup) -match "Administrators"){

    $LocalAdminsMember = ((net localgroup Administrators))

        if ($LocalAdminsMember -like "*$accountName*"){
        
            Write-Warning "NDES Service Account: $($accountName) is a member of the local Administrators group. This will provide the requisite rights but is _not_ a secure configuration. Use IIS_IUSERS instead."
            Log-ScriptEvent $LogFilePath "NDES Service Account is a member of the local Administrators group. This will provide the requisite rights but is _not_ a secure configuration. Use IIS_IUSERS instead."  NDES_Validation 2

        }
        else {

            Write-Host "Success: " -ForegroundColor Green -NoNewline
            Write-Host "NDES Service account $($accountName) is not a member of the Local Administrators group"
            Log-ScriptEvent $LogFilePath "NDES Service account is not a member of the Local Administrators group"  NDES_Validation 1
    
        }

    Write-host
    Write-Host "Checking NDES Service account $($accountName) is a member of the IIS_IUSR group..." -ForegroundColor Yellow
    Write-host

    if ((net localgroup) -match "IIS_IUSRS"){

        $IIS_IUSRMembers = ((net localgroup IIS_IUSRS))

        if ($IIS_IUSRMembers -like "*$accountName*"){

            Write-Host "Success: " -ForegroundColor Green -NoNewline
            Write-Host "NDES Service Account $($accountName) is a member of the local IIS_IUSR group" -NoNewline
            Log-ScriptEvent $LogFilePath "NDES Service Account is a member of the local IIS_IUSR group" NDES_Validation 1
    
        }
        else {

            Write-Host "Error: " -ForegroundColor Red -NoNewline
            Write-Host "NDES Service Account $($accountName) is not a member of the local IIS_IUSR group" 
            Log-ScriptEvent $LogFilePath "NDES Service Account is not a member of the local IIS_IUSR group"  NDES_Validation 3 

            Write-host
            Write-host "Checking Local Security Policy for explicit rights via gpedit..." -ForegroundColor Yellow
            Write-Host
            $TempFile = [System.IO.Path]::GetTempFileName()
            & "secedit" "/export" "/cfg" "$TempFile" | Out-Null
            $LocalSecPol = Get-Content $TempFile
            try {
                $nTAccount = New-Object System.Security.Principal.NTAccount($accountName)
                $NDESSVCAccountSID = $nTAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
            } catch {
                Write-Warning "Could not resolve SID for account $accountName. Skipping local security policy check."
                $NDESSVCAccountSID = $null
            }
            if (-not $NDESSVCAccountSID) {
                Write-Warning "Skipping local security policy check as SID could not be resolved."
            } else {
            $LocalSecPolResults = $LocalSecPol | Select-String $NDESSVCAccountSID

                if ($LocalSecPolResults -match "SeServiceLogonRight"){
            
                    Write-Host "Success: " -ForegroundColor Green -NoNewline
                    Write-Host "NDES Service Account has been assigned the Logon as a Service."
                    Log-ScriptEvent $LogFilePath "NDES Service Account has been assigned Logon as a Service." NDES_Validation 1
                    Write-Host
                    Write-Host "Note:" -ForegroundColor Red -NoNewline
                    Write-Host " The Logon Locally is not required in normal runtime."
                    Write-Host
                    Write-Host "Note:" -ForegroundColor Red -NoNewline
                    Write-Host 'Consider using the IIS_IUSERS group instead of explicit rights as documented under "Install the NDES service".'
                    write-host "URL: https://learn.microsoft.com/en-us/mem/intune/protect/certificate-connector-prerequisites#certificate-connector-service-account"
            
                }
            
                else {

                    Write-Warning "NDES Service Account may _NOT_ been assigned Logon as a Service." 
                    Log-ScriptEvent $LogFilePath "NDES Service Account may _NOT_ been assigned Logon as a Service." NDES_Validation 3
            
                }
            } # end if $NDESSVCAccountSID
        }

    }

    else {

        Write-Warning "Error: No IIS_IUSRS group exists. Ensure IIS is installed." 
        Log-ScriptEvent $LogFilePath "No IIS_IUSRS group exists. Ensure IIS is installed." NDES_Validation 3
    }
}
else {

        Write-Warning "No local Administrators group exists, likely due to this being a Domain Controller. It is not recommended to run NDES on a Domain Controller."
        Log-ScriptEvent $LogFilePath "No local Administrators group exists, likely due to this being a Domain Controller. It is not recommended to run NDES on a Domain Controller." NDES_Validation 2
    
    }

#endregion

Log-ScriptEvent $LogFilePath "*********************************************************************************"  NDES_Validation 1
#######################################################################

#region Checking registry has been set to allow long URLs
Write-host
Write-host "......................................................."
Write-host
Write-Host 'Checking registry "HKLM:SYSTEM\CurrentControlSet\Services\HTTP\Parameters" has been set to allow long URLs...' -ForegroundColor Yellow
Write-host
Log-ScriptEvent $LogFilePath "Checking registry (HKLM:SYSTEM\CurrentControlSet\Services\HTTP\Parameters) has been set to allow long URLs" NDES_Validation 1

    if ((Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue).InstallState -eq "Installed"){

        If ((Get-ItemProperty -Path HKLM:SYSTEM\CurrentControlSet\Services\HTTP\Parameters -Name MaxFieldLength).MaxfieldLength -notmatch "65534"){

            Write-Host "Error: " -ForegroundColor red -NoNewline 
            Write-Host "MaxFieldLength not set to 65534 in the registry!"
            Write-Host "Please review "
            write-host "URL: https://learn.microsoft.com/en-us/mem/intune/protect/certificates-scep-configure#support-for-ndes-on-the-internet"
            Log-ScriptEvent $LogFilePath "MaxFieldLength not set to 65534 in the registry" NDES_Validation 3
        } 

        else {

            Write-Host "Success: " -ForegroundColor Green -NoNewline
            write-host "MaxFieldLength set correctly"
            Log-ScriptEvent $LogFilePath "MaxFieldLength set correctly"  NDES_Validation 1
    
        }
		
        if ((Get-ItemProperty -Path HKLM:SYSTEM\CurrentControlSet\Services\HTTP\Parameters -Name MaxRequestBytes).MaxRequestBytes -notmatch "65534"){

            Write-Host "Error: " -ForegroundColor red -NoNewline 
            Write-Host "MaxRequestBytes not set to 65534 in the registry!" 
            Write-Host "Please review "
            write-host "URL: https://learn.microsoft.com/en-us/mem/intune/protect/certificates-scep-configure#support-for-ndes-on-the-internet"
            Log-ScriptEvent $LogFilePath "MaxRequestBytes not set to 65534 in the registry" NDES_Validation 3 

        }
        else {

            Write-Host "Success: " -ForegroundColor Green -NoNewline
            write-host "MaxRequestBytes set correctly"
            Log-ScriptEvent $LogFilePath "MaxRequestBytes set correctly"  NDES_Validation 1
        
        }

    }

    else {

        Write-Host "Error: " -ForegroundColor Red -NoNewline
        Write-Host "IIS is not installed." 
        Log-ScriptEvent $LogFilePath "IIS is not installed." NDES_Validation 3

    }

Log-ScriptEvent $LogFilePath "*********************************************************************************"  NDES_Validation 1
#endregion
#######################################################################
<#
#region Checking SPN has been set...
Write-host
Write-host "......................................................."
Write-host
Write-Host "Checking SPN has been set..." -ForegroundColor Yellow
Write-host
Log-ScriptEvent $LogFilePath "Checking SPN has been set" NDES_Validation 1

$hostname = ([System.Net.Dns]::GetHostByName(($env:computerName))).hostname

$spn = setspn.exe -L $accountName

    if ($spn -match $hostname){
    
        Write-Host "Success: " -ForegroundColor Green -NoNewline
        write-host "Correct SPN set for the NDES service account:"
        Write-host
        Write-Host $spn -ForegroundColor Cyan
        Log-ScriptEvent $LogFilePath "Correct SPN set for the NDES service account: $($spn)"  NDES_Validation 1
    
    }
    
    else {

        Write-Host "Error: " -BackgroundColor red -NoNewline
        Write-Host "Missing or Incorrect SPN set for the NDES Service Account!"
        Write-Host 'Please review "Configure prerequisites on the NDES server".'
        Log-ScriptEvent $LogFilePath "Missing or Incorrect SPN set for the NDES Service Account"  NDES_Validation 3 
    
    }

Log-ScriptEvent $LogFilePath "*********************************************************************************"  NDES_Validation 1
#endregion
#>
#######################################################################

#region Checking there are no intermediate certs are in the Trusted Root store
       
Write-host
Write-host "......................................................."
Write-host
Write-Host "Checking there are no intermediate certs are in the Trusted Root store..." -ForegroundColor Yellow
Write-host
Log-ScriptEvent $LogFilePath "Checking there are no intermediate certs are in the Trusted Root store" NDES_Validation 1

$IntermediateCertCheck = Get-Childitem cert:\LocalMachine\root -Recurse | Where-Object {$_.Issuer -ne $_.Subject}

    if ($IntermediateCertCheck){
    
        Write-Host "Error: " -ForegroundColor red 
        Write-Host "Intermediate certificate found in the Trusted Root store. This can cause undesired effects and should be removed."
        Write-Host "Certificates:" 
        Write-Host $IntermediateCertCheck
        Log-ScriptEvent $LogFilePath "Intermediate certificate found in the Trusted Root store: $($IntermediateCertCheck)"  NDES_Validation 3
    
    }
    
    else {

        Write-Host "Success: " -ForegroundColor Green -NoNewline
        Write-Host "Trusted Root store does not contain any Intermediate certificates."
        Log-ScriptEvent $LogFilePath "Trusted Root store does not contain any Intermediate certificates."  NDES_Validation 1
    
    }

Log-ScriptEvent $LogFilePath "*********************************************************************************"  NDES_Validation 1
#endregion
#######################################################################

#region Checking the EnrollmentAgentOffline and CEPEncryption are present and still valid

$ErrorActionPreference = "Silentlycontinue"

Write-host
Write-host "......................................................."
Write-host
Write-Host "Checking the EnrollmentAgentOffline and CEPEncryption are present..." -ForegroundColor Yellow
Write-host
Log-ScriptEvent $LogFilePath "Checking the MSCEP certificates of EnrollmentAgentOffline and CEPEncryption are present and valid" NDES_Validation 1

$certs = Get-ChildItem cert:\LocalMachine\My\

#get current time
$currentDate = Get-Date

# Looping through all certificates in LocalMachine Store
Foreach ($item in $certs){

    $Output = ($item.Extensions | Where-Object {$_.oid.FriendlyName -like "Certificate Template*"}).format(0).split(",")
    $expirationDate = $item.NotAfter

    if (($Output -match "EnrollmentAgentOffline") -and ($expirationDate -gt $currentDate)){
    
        $EnrollmentAgentOffline = $TRUE
        $EnrollmentAgentOfflineNotAfter = $expirationDate
    
    }
        
    if (($Output -match "CEPEncryption") -and ($expirationDate -gt $currentDate)){
        
        $CEPEncryption = $TRUE
        $CEPEncryptionNotAfter = $expirationDate
        
    }

} 

# Checking if EnrollmentAgentOffline certificate is present
if ($EnrollmentAgentOffline){

    Write-Host "Success: " -ForegroundColor Green -NoNewline
    Write-Host "EnrollmentAgentOffline certificate is present and valid till: " -NoNewline
    write-host "$($EnrollmentAgentOfflineNotAfter)"  -ForegroundColor Cyan
    Log-ScriptEvent $LogFilePath "Success: EnrollmentAgentOffline certificate is present and valid"  NDES_Validation 1

} else {

    Write-Host "Error: " -ForegroundColor Red -NoNewline
    Write-Host "EnrollmentAgentOffline certificate is not present or expired !" 
    Write-Host "This can take place when an account without Enterprise Admin permissions installs NDES. You may need to remove the NDES role and reinstall with the correct permissions." 
    Log-ScriptEvent $LogFilePath "EnrollmentAgentOffline certificate is not present or expired"  NDES_Validation 3 

}

# Checking if CEPEncryption is present
if ($CEPEncryption){
    
    Write-Host "Success: " -ForegroundColor Green -NoNewline
    Write-Host "CEPEncryption is present and valid till: " -NoNewline
    Write-Host "$($CEPEncryptionNotAfter)" -ForegroundColor Cyan  
    Log-ScriptEvent $LogFilePath "CEPEncryption certificate is present and valid"  NDES_Validation 1
    
} else {

    Write-Host "Error: " -ForegroundColor Red -NoNewline
    Write-Host "CEPEncryption certificate is not present or expired!"
    Write-Host "This can take place when an account without Enterprise Admin permissions installs NDES. You may need to remove the NDES role and reinstall with the correct permissions." 
    Log-ScriptEvent $LogFilePath "Success: CEPEncryption certificate is not present or expired!"  NDES_Validation 3
    
}
Log-ScriptEvent $LogFilePath "*********************************************************************************"  NDES_Validation 1

$ErrorActionPreference = "Continue"

#endregion

#################################################################

#region Checking registry has been set with the SCEP certificate template name

Write-host
Write-host "......................................................."
Write-host
Write-Host 'Checking registry "HKLM:SOFTWARE\Microsoft\Cryptography\MSCEP" has been set with the SCEP certificate template name...' -ForegroundColor Yellow
Write-host
Log-ScriptEvent $LogFilePath "Checking if registry (HKLM:SOFTWARE\Microsoft\Cryptography\MSCEP) has been set with the SCEP certificate template name" NDES_Validation 1

if (-not (Test-Path HKLM:SOFTWARE\Microsoft\Cryptography\MSCEP)){

    Write-host "Error: " -ForegroundColor Red -NoNewline
    Write-host "Registry key does not exist. This can occur if the NDES role has been installed but not configured." 
    Log-ScriptEvent $LogFilePath "MSCEP Registry key does not exist."  NDES_Validation 3 

} else {

            $SignatureTemplate = (Get-ItemProperty -Path HKLM:SOFTWARE\Microsoft\Cryptography\MSCEP\ -Name SignatureTemplate).SignatureTemplate
            $EncryptionTemplate = (Get-ItemProperty -Path HKLM:SOFTWARE\Microsoft\Cryptography\MSCEP\ -Name EncryptionTemplate).EncryptionTemplate
            $GeneralPurposeTemplate = (Get-ItemProperty -Path HKLM:SOFTWARE\Microsoft\Cryptography\MSCEP\ -Name GeneralPurposeTemplate).GeneralPurposeTemplate 
            $DefaultUsageTemplate = "IPSECIntermediateOffline"

            if ($SignatureTemplate -match $DefaultUsageTemplate -AND $EncryptionTemplate -match $DefaultUsageTemplate -AND $GeneralPurposeTemplate -match $DefaultUsageTemplate){
                
                Write-host "Error: " -ForegroundColor Red -NoNewline
                Write-Host "Registry has not been configured with the SCEP Certificate template name. Default values have _not_ been changed." 
                Write-Host
                Log-ScriptEvent $LogFilePath "Registry has not been configured with the SCEP Certificate template name. Default values have _not_ been changed."  NDES_Validation 3
            
            } else {

                Write-Host "One or more default values have been changed."
                Write-Host 
                write-host "Checking key..."
                Write-host
                write-host "Signature template value: " -NoNewline
                Write-host "$($SignatureTemplate)" -ForegroundColor Cyan
                write-host "Encryption template value: " -NoNewline
                Write-host "$($EncryptionTemplate)" -ForegroundColor Cyan
                write-host "GeneralPurpose template value: " -NoNewline
                Write-host "$($GeneralPurposeTemplate)" -ForegroundColor Cyan
                Log-ScriptEvent $LogFilePath "Signature template value: $($SignatureTemplate)" NDES_Validation 1
                Log-ScriptEvent $LogFilePath "Encryption template value: $($EncryptionTemplate)" NDES_Validation 1
                Log-ScriptEvent $LogFilePath "GeneralPurpose template value: $($GeneralPurposeTemplate)" NDES_Validation 1

            }
}

Log-ScriptEvent $LogFilePath "*********************************************************************************"  NDES_Validation 1
$ErrorActionPreference = "Continue"

#endregion

#################################################################

#region Checking Intune Connector is installed

Write-host
Write-host "......................................................."
Write-host
Write-Host "Checking Intune Connector is installed..." -ForegroundColor Yellow
Write-host
Log-ScriptEvent $LogFilePath "Checking Intune Connector is installed" NDES_Validation 1 

if ($IntuneConnector = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |  Select-Object DisplayName, DisplayVersion, Publisher, InstallDate | Where-Object {$_.DisplayName -eq "Certificate Connector for Microsoft Intune"}){

    Write-Host "Success: " -ForegroundColor Green -NoNewline
    Write-Host "$($IntuneConnector.DisplayName) was installed on " -NoNewline 
    Write-Host "$($IntuneConnector.InstallDate)" -ForegroundColor Cyan -NoNewline 
    write-host " and is version " -NoNewline
    Write-Host "$($IntuneConnector.DisplayVersion)" -ForegroundColor Cyan -NoNewline
    Write-host
    Log-ScriptEvent $LogFilePath "Connector installed and ConnectorVersion:$IntuneConnector"  NDES_Validation 1

} else {

    Write-host "Error: " -ForegroundColor Red -NoNewline
    Write-Host "Intune Connector not installed" 
    Log-ScriptEvent $LogFilePath "ConnectorNotInstalled"  NDES_Validation 3 
    
}

Log-ScriptEvent $LogFilePath "*********************************************************************************"  NDES_Validation 1
#endregion

#################################################################

#region Checking the service account running as in Intune connector
Write-host
Write-host "......................................................."
Write-host
Write-Host "Checking the 'Log on As' for Certificate Connector " -ForegroundColor Yellow
Write-host
Log-ScriptEvent $LogFilePath "Checking the 'Log on As' for Certificate Connector " NDES_Validation 1 

$connectorService = Get-Service -Name "PFXCertificateConnectorSvc" -ErrorAction SilentlyContinue

if ($connectorService) {
    # Get the service's process
    $serviceProcess = Get-CimInstance Win32_Service -Filter "Name='PFXCertificateConnectorSvc'" -ErrorAction SilentlyContinue

    # Check if the service is running as Local System or as a specific user
    if ($serviceProcess.StartName -eq "LocalSystem") {
        Write-Host $connectorService.Name -ForegroundColor Cyan -NoNewline
        Write-Host " is running as " -NoNewline
        Write-Host "Local System" -ForegroundColor Cyan
        Log-ScriptEvent $LogFilePath "$($connectorService.Name) is running as local system" NDES_Validation 1 

    } else {
        Write-Host $connectorService.Name -ForegroundColor Cyan -NoNewline
        Write-Host " is running as " -NoNewline
        Write-Host $serviceProcess.StartName -ForegroundColor Cyan
        Log-ScriptEvent $LogFilePath "$($connectorService.Name) is running as $($serviceProcess.StartName)" NDES_Validation 1 

        if ($accountName -match $serviceProcess.StartName)
        {
            Write-Host "SCEP in IIS and Cert connector are using same service account"
            Log-ScriptEvent $LogFilePath "SCEP in IIS and Cert connector are using same service account" NDES_Validation 1 

        } else {
            Write-Warning "SCEP in IIS and Cert connector are using different service account"
            Log-ScriptEvent $LogFilePath "SCEP in IIS and Cert connector are using different service account" NDES_Validation 3
        }
    }
} else {
    Write-Host "Warning: Service not found, NDES connector may not be installed on this server" -ForegroundColor Yellow
    Log-ScriptEvent $LogFilePath "Service not found, NDES connector may not install on this server" NDES_Validation 3
}

Log-ScriptEvent $LogFilePath "*********************************************************************************"  NDES_Validation 1
#endregion
#################################################################

#region Checking Intune Connector registry keys and check if connector certificate is vaild.

Write-host
Write-host "......................................................."
Write-host
Write-Host "Checking Intune Connector registry keys are intact" -ForegroundColor Yellow
Write-host
Log-ScriptEvent $LogFilePath "Checking Intune Connector registry keys are intact and certificate" NDES_Validation 1

$ErrorActionPreference = "SilentlyContinue"
$connectorPath = "HKLM:SOFTWARE\Microsoft\MicrosoftIntune\PFXCertificateConnector"

if (-not (Test-Path $connectorPath)){
    
    Write-host "Error: " -ForegroundColor Red -NoNewline
    Write-host "Connector Registry key does not exist. Connector didn't install" 
    Log-ScriptEvent $LogFilePath "Connector Registry key does not exist. Connecotr didn't configure"  NDES_Validation 3 

} else {
    
    $EncryptionCertThumbprint = (Get-ItemProperty -Path $connectorPath -Name EncryptionCertThumbprint).EncryptionCertThumbprint
    
    if (-not ($EncryptionCertThumbprint)){
        
        Write-host "Error: " -ForegroundColor Red -NoNewline
        Write-host "EncryptionCertThumbprint Registry key does not exist. Connector didn't finish configuration" 
        Log-ScriptEvent $LogFilePath "EncryptionCertThumbprint Registry key does not exist. Connecotr didn't configure"  NDES_Validation 3 
    
    } else {

        # Get the certificate from the Personal certificate store
          $Connectorcert = Get-ChildItem -Path cert:\LocalMachine\My\ -Recurse | Where-Object {$_.Thumbprint -eq $EncryptionCertThumbprint}
          #get current time
          $currentDate = Get-Date

         #Connector certificate still valid
        if ($Connectorcert) {
            Write-Host "Certificate found:"
            Write-Host "Subject : "  -NoNewline
            Write-Host $Connectorcert.Subject -ForegroundColor Cyan 
            Write-Host "Issuer  : "  -NoNewline
            Write-Host $Connectorcert.Issuer -ForegroundColor Cyan 
            Write-Host "Thumbprint : "  -NoNewline
            Write-Host $Connectorcert.Thumbprint -ForegroundColor Cyan
            Write-Host "Valid From : "  -NoNewline
            Write-Host $Connectorcert.NotBefore -ForegroundColor Cyan 
            Write-Host "Valid To   : "  -NoNewline
            Write-Host $Connectorcert.NotAfter -ForegroundColor Cyan 

            if ($Connectorcert.NotAfter -gt $currentDate){
            
             Write-Host "Certificate is valid:"  -NoNewline
             Write-Host $Connectorcert.NotAfter -ForegroundColor Cyan
             Log-ScriptEvent $LogFilePath "Certificate $($Connectorcert.Subject) is valid: $($Connectorcert.NotAfter)"  NDES_Validation 1 

            
            }
            else{
                
              Write-host "Error: " -ForegroundColor Red -NoNewline
              Write-Host "Conncetor Certificate is expired and we need to renew cert:"
              Write-Host "Valid To: " -NoNewline
              Write-Host $Connectorcert.NotAfter -ForegroundColor Red
              Write-Host "You can delete exipred cert in store and sign-in connector again" 
              Log-ScriptEvent $LogFilePath "Conncer Certificate is expired at $($Connectorcert.NotAfter) and we need to renew cert:"  NDES_Validation 3 
          
            }


            #Show Connector features 
            $EnablePFxCreate = (Get-ItemProperty -Path $connectorPath -Name EnablePFxCreate).EnablePFxCreate

            if ($EnablePFxCreate -eq "1") {
                Write-Host "PFX " -ForegroundColor Cyan -NoNewline
                Write-Host "is enabled"
                Log-ScriptEvent $LogFilePath "PFX feature is enabled in connector"  NDES_Validation 1
            }

            $EnablePFxImport = (Get-ItemProperty -Path $connectorPath -Name EnablePFxImport).EnablePFxImport
            if ($EnablePFxImport -eq "1") {
                Write-Host "Imported PFX " -ForegroundColor Cyan -NoNewline
                Write-Host "is enabled"
                Log-ScriptEvent $LogFilePath "Imported PFX feature is enabled in connector"  NDES_Validation 1
            }

            $EnableRevocation = (Get-ItemProperty -Path $connectorPath -Name EnableRevocation).EnableRevocation
            if ($EnableRevocation -eq "1") {
                Write-Host "Cert revocation " -ForegroundColor Cyan -NoNewline
                Write-Host "is enabled"
                Log-ScriptEvent $LogFilePath "Certificate revocation feature is enabled in connector"  NDES_Validation 1
            }

            $EnableSCEP = (Get-ItemProperty -Path $connectorPath -Name EnableSCEP).EnableSCEP
            if ($EnableSCEP -eq "1") {
                Write-Host "SCEP " -ForegroundColor Cyan -NoNewline
                Write-Host "is enabled"
                Log-ScriptEvent $LogFilePath "SCEP feature is enabled in connector"  NDES_Validation 1
            }

            #Show proxy configuration
            $connectorProxyPath = "HKLM:SOFTWARE\Microsoft\MicrosoftIntune\PFXCertificateConnector\Proxy"
            $ProxyServer = (Get-ItemProperty -Path $connectorProxyPath -Name ProxyServer).ProxyServer
            
            if (-not ($ProxyServer))
            {
                Write-Host "No proxy configured"
                Log-ScriptEvent $LogFilePath "No proxy is configured in connector"  NDES_Validation 1
            }else{
                Write-Host "Proxy is configured as " -NoNewline
                Write-Host $ProxyServer -ForegroundColor Cyan
                Write-Host "Port: " -NoNewline
                Write-Host (Get-ItemProperty -Path $connectorProxyPath -Name Port).Port -ForegroundColor Cyan
                Log-ScriptEvent $LogFilePath "Proxy $($ProxyServer) is configured in Connector"  NDES_Validation 1
            }

            #Connector sync time
            $connectorStatusPath = "HKLM:SOFTWARE\Microsoft\MicrosoftIntune\PFXCertificateConnector\ConnectionStatus"
            $LastConnectionTime = (Get-ItemProperty -Path $connectorStatusPath -Name LastConnectionTime).LastConnectionTime
            
            Write-Host "Connector last sync time: " -NoNewline
            Write-Host $LastConnectionTime -ForegroundColor Cyan
            Log-ScriptEvent $LogFilePath "Connector last sync time: $($LastConnectionTime)."  NDES_Validation 1

            try { $LastConnectionTime = Get-Date $LastConnectionTime } catch {
                Write-Warning "Could not parse LastConnectionTime value from registry."
                Log-ScriptEvent $LogFilePath "Could not parse LastConnectionTime value from registry." NDES_Validation 2
                $LastConnectionTime = $null
            }
            if ($LastConnectionTime) {
            $daysDifference = ($currentDate - $LastConnectionTime).Days

            # Check if the last sync date is not updated for more than 2 days
            if ($daysDifference -gt 1) {
                Write-Warning "Last sync date is not updated for more than 1 day."
                Log-ScriptEvent $LogFilePath "Last sync date is not updated for more than 1 day."  NDES_Validation 3

            } else {
                Write-Host "Last sync date is updated within the last 1 day."
                Log-ScriptEvent $LogFilePath "Last sync date is updated within the last 1 day."  NDES_Validation 1
            }
            } # end if $LastConnectionTime

        } else  {
            Write-Host "Certificate with thumbprint $EncryptionCertThumbprint not found in the Personal certificate store."
            Log-ScriptEvent $LogFilePath "Certificate with thumbprint $EncryptionCertThumbprint not found in the Personal certificate store."  NDES_Validation 3 
        }        
    }
}

$ErrorActionPreference = "Continue"
Log-ScriptEvent $LogFilePath "*********************************************************************************"  NDES_Validation 1
#endregion

#################################################################

#region Checking behaviour of internal NDES URL

$hostname = ([System.Net.Dns]::GetHostByName(($env:computerName))).hostname
Write-host
Write-host "......................................................."
Write-host
Write-Host "Checking behaviour of internal NDES URL: " -NoNewline -ForegroundColor Yellow
Write-Host "https://$hostname/certsrv/mscep/mscep.dll" -ForegroundColor Cyan
Write-host
Log-ScriptEvent $LogFilePath "Checking behaviour of internal NDES URL" NDES_Validation 1

Log-ScriptEvent $LogFilePath "Https://$hostname/certsrv/mscep/mscep.dll" NDES_Validation 1

$Statuscode = try {(Invoke-WebRequest -Uri https://$hostname/certsrv/mscep/mscep.dll).statuscode} catch {$_.Exception.Response.StatusCode.Value__}

if ($statuscode -eq "200")
{

    Write-host "Error: " -ForegroundColor Red -NoNewline
    write-host "https://$hostname/certsrv/mscep/mscep.dll returns 200 OK. This usually signifies an error with the Intune Connector registering itself or not being installed." 
    Log-ScriptEvent $LogFilePath "https://$hostname/certsrv/mscep/mscep.dll returns 200 OK. This usually signifies an error with the Intune Connector registering itself or not being installed"  NDES_Validation 3

} elseif ($statuscode -eq "403"){
    
    Write-Host "Trying to retrieve CA Capabilitiess..." -ForegroundColor Yellow
    Write-Host
    
    $Newstatuscode = try {(Invoke-WebRequest -Uri "https://$hostname/certsrv/mscep/mscep.dll?operation=GetCACaps&message=test").statuscode} catch {$_.Exception.Response.StatusCode.Value__}
    
    if ($Newstatuscode -eq "200"){
        
        $CACaps = (Invoke-WebRequest -Uri "https://$hostname/certsrv/mscep/mscep.dll?operation=GetCACaps&message=test").content
    }
    
    if ($CACaps){

        Write-Host "Success: " -ForegroundColor Green -NoNewline
        write-host "CA Capabilities retrieved:"
        Write-Host
        write-host $CACaps
        Log-ScriptEvent $LogFilePath "CA Capabilities retrieved:$CACaps"  NDES_Validation 1
            
        }

}else {

    Write-host "Error: " -ForegroundColor Red -NoNewline
    Write-Host "Unexpected Error code! This usually signifies an error with the Intune Connector registering itself or not being installed" 
    Write-host "Expected value is a 403. We received a $($Statuscode). This could be down to a missing reboot post policy module install. Verify last boot time and module install time further down the validation."
    Log-ScriptEvent $LogFilePath "Unexpected Error code. Expected:403|Received:$Statuscode"  NDES_Validation 3

}
Log-ScriptEvent $LogFilePath "*********************************************************************************"  NDES_Validation 1
#endregion


#################################################################

#This part will be improved to show more detials based on Error message
#region Checking eventlog for pertinent errors https://learn.microsoft.com/en-us/mem/intune/protect/certificate-connector-overview

Write-host
Write-host "......................................................."
Write-host
Write-Host "Checking Error logs in Event Viewer for last 2 days" -ForegroundColor Yellow
Log-ScriptEvent $LogFilePath "Checking Event log for connector" NDES_Validation 1

$ErrorActionPreference = "SilentlyContinue"

# Define the log name and time frame
$ConnectorlogAdmin = "Microsoft-Intune-CertificateConnectors/Admin"

$ConnectorlogOperational = "Microsoft-Intune-CertificateConnectors/Operational"

$AADAgentUpdaterlogAdmin = "Microsoft-AzureADConnect-AgentUpdater/Admin"

#check last 2 days event log
$EventstartTime = (Get-Date).AddDays(-2)

# Get the error events from the intune connector Admin log and check error. 
$errorEventsAdminLog = Get-WinEvent -FilterHashtable @{LogName=$ConnectorlogAdmin;StartTime=$EventstartTime;ID='1001','1201','2001','3001','4001','4002'} -MaxEvents 5 -ErrorAction SilentlyContinue

# Display the error events in Admin 
if ($errorEventsAdminLog) {
    
    Write-Warning "Errors found in the Microsoft Intune Connector Admin Event log" 
    write-host "List first 5 errors in the Microsoft Intune Connector Admin Event log in the last 2 days"
    Log-ScriptEvent $LogFilePath "Errors found in the Microsoft Intune Connector Admin Event log" NDES_Validation 3
    Log-ScriptEvent $LogFilePath "List first 5 errors in the Microsoft Intune Connector Admin Event log" NDES_Validation 3

    foreach ($event in $errorEventsAdminLog) {
        
        $Time = $event.TimeCreated
        $ID = $event.Id
        $Message = $event.Message
    
        Write-Host "......................................................."
        Write-Host "Event Time: "-NoNewline
        Write-Host $Time -ForegroundColor Cyan
        Write-Host "EVent ID: " -NoNewline
        Write-Host $ID -ForegroundColor Magenta
        Write-Host "Message: " -NoNewline
        Write-Host $Message -ForegroundColor Red
        Write-Host "......................................................."
     
        Log-ScriptEvent $LogFilePath "Event Time: $Time EVent ID: $ID" NDES_Validation 3
        Log-ScriptEvent $LogFilePath "Message:  $Message" NDES_Validation 3
    }
} else {

    Write-Host "Success: " -ForegroundColor Green -NoNewline
    write-Host "No errors found in the Microsoft Intune Connector " -NoNewline
    Write-Host "Admin Event log" -ForegroundColor Cyan
    Write-Host "......................................................."
    Log-ScriptEvent $LogFilePath "No errors found in the Microsoft Intune Connector Admin Event log" NDES_Validation 3

}

# Get the error & Warning events from the intune connector log and check error. Get last 5
$errorEventsOperationalLog = Get-WinEvent -FilterHashtable @{LogName=$ConnectorlogOperational;StartTime=$EventstartTime} -ErrorAction SilentlyContinue | Where-Object -FilterScript {($_.Level -eq 2) -or ($_.Level -eq 3)} | Select-Object -First 5

# Display the error events in opertional log
if ($errorEventsOperationalLog) {
    
    Write-Warning "Errors found in the Microsoft Intune Connector Opertional Event log" 
    write-host "List first 5 errors in the Microsoft Intune Connector Opertional Event log in the last 2 days" 
    Log-ScriptEvent $LogFilePath "Errors found in the Microsoft Intune Connector Opertional Event log" NDES_Validation 3
    Log-ScriptEvent $LogFilePath "List first 5 errors in the Microsoft Intune Connector Opertional Event log" NDES_Validation 3
    
    foreach ($event in $errorEventsOperationalLog) {
        
        $Time = $event.TimeCreated
        $ID = $event.Id
        $Message = $event.Message
    
        Write-Host "......................................................."
        Write-Host "Event Time: "-NoNewline
        Write-Host $Time -ForegroundColor Cyan
        Write-Host "EVent ID: " -NoNewline
        Write-Host $ID -ForegroundColor Magenta
        Write-Host "Message: " -NoNewline
        Write-Host $Message -ForegroundColor Red
        Write-Host "......................................................."
        Write-Host ""
        Log-ScriptEvent $LogFilePath "Event Time: $Time EVent ID: $ID" NDES_Validation 3
        Log-ScriptEvent $LogFilePath "Message:  $Message" NDES_Validation 3
    }
} else {
    
    Write-Host "Success: " -ForegroundColor Green -NoNewline
    write-host "No errors found in the Microsoft Intune Connector " -NoNewline
    Write-Host "Opertional Event log" -ForegroundColor Cyan 
    Write-Host "......................................................."
    Log-ScriptEvent $LogFilePath "No errors found in the Microsoft Intune Connector Opertional Event log" NDES_Validation 3

}

# Get the error & Warning events from the AzureAD updaters log and check error. Get last 5
$errorEventsAADUpdaterAdminLog = Get-WinEvent -FilterHashtable @{LogName=$AADAgentUpdaterlogAdmin;StartTime=$EventstartTime} -ErrorAction SilentlyContinue | Where-Object -FilterScript {($_.Level -eq 2) -or ($_.Level -eq 3)} | Select-Object -First 5
# Display the error events in AADupdaters Admin log
if ($errorEventsAADUpdaterAdminLog) {
    
    Write-Warning "Errors found in the Microsoft Azure AD Agent updater Admin Event log" 
    Write-Host "Microsoft Azure AD Agent updater handle updating job of NDES Cert Connector" 
    write-host "List first 5 errors in the Microsoft Azure AD Agent updater Admin Event log in the last 2 days" 
    Log-ScriptEvent $LogFilePath "Errors found in the Microsoft Azure AD Agent updater Admin Event log" NDES_Validation 3
    Log-ScriptEvent $LogFilePath "List first 5 errors in the Microsoft Azure AD Agent updater Admin Event log" NDES_Validation 3
    
    foreach ($event in $errorEventsAADUpdaterAdminLog) {
        
        $Time = $event.TimeCreated
        $ID = $event.Id
        $Message = $event.Message
    
        Write-Host "......................................................."
        Write-Host "Event Time: "-NoNewline
        Write-Host $Time -ForegroundColor Cyan
        Write-Host "EVent ID: " -NoNewline
        Write-Host $ID -ForegroundColor Magenta
        Write-Host "Message: " -NoNewline
        Write-Host $Message -ForegroundColor Red
        Write-Host "......................................................."
        Write-Host ""
        Log-ScriptEvent $LogFilePath "Event Time: $Time EVent ID: $ID" NDES_Validation 3
        Log-ScriptEvent $LogFilePath "Message:  $Message" NDES_Validation 3
    }
} else {
    
    Write-Host "Success: " -ForegroundColor Green -NoNewline
    write-host "No errors found in the Microsoft Azure AD Agent updater  " -NoNewline
    Write-Host "Admin Event log" -ForegroundColor Cyan 
    Write-host "Microsoft Azure AD Agent updater handle updating job of NDES Cert Connector" 
    Write-Host "......................................................."
    Log-ScriptEvent $LogFilePath "No errors found in the Microsoft Azure AD Agent updater Admin Event log" NDES_Validation 3

}
  
  
  #Checking error event in Application log and source from NetworkDeviceEnrollmentService and PKI certificate connector
  $errorEventsApplicationLog = Get-EventLog -LogName "Application" -EntryType Error -Source PKICertificateConnectorSvc,PFXCertificateConnectorSvc,PkiRevokeConnectorSvc,Microsoft-Windows-NetworkDeviceEnrollmentService -After $EventstartTime -Newest 5 | Select-Object TimeGenerated,Source,Message

 if (-not ($errorEventsApplicationLog)) {

        Write-Host "Success: " -ForegroundColor Green -NoNewline
        write-host "No errors found in the Application log from source NetworkDeviceEnrollmentService or NDESConnector"
        Write-Host "......................................................."
        Log-ScriptEvent $LogFilePath "No errors found in the Application log from source NetworkDeviceEnrollmentService or NDESConnector"  NDES_Validation 1

    }else {

            Write-Warning "Errors found in the Application Event log from source NetworkDeviceEnrollmentService or NDESConnector. Please see below for the most recent 5, and investigate further in Event Viewer."
            $errorEventsApplicationLog | Format-List
            foreach ($item in $errorEventsApplicationLog) {

                Log-ScriptEvent $LogFilePath "$($item.TimeGenerated);$($item.Message);$($item.Source)"  NDES_Eventvwr 3
            }
        }


#Checking error event in System log and source from NetworkDeviceEnrollmentService
  $errorEventsSystemLog = Get-EventLog -LogName "System" -EntryType Error -Source "Service Control Manager" -After $EventstartTime -Newest 5 | Select-Object TimeGenerated,Source,Message
  if (-not ($errorEventsSystemLog)) {

    Write-Host "Success: " -ForegroundColor Green -NoNewline
    write-host "No errors found in the System log from source Service control manager or NDESConnector"
    Write-Host "......................................................."
    Log-ScriptEvent $LogFilePath "No errors found in the System log from source source Service control manager on NDESConnector"  NDES_Validation 1

}else {

        Write-Warning "Errors found in the System Event log from source Service control manager. Please see below for the most recent 5, and investigate further in Event Viewer."
        $errorEventsSystemLog | Format-List
        foreach ($item in $errorEventsSystemLog) {

            Log-ScriptEvent $LogFilePath "$($item.TimeGenerated);$($item.Message);$($item.Source)"  NDES_Eventvwr 3
        }
    }


Log-ScriptEvent $LogFilePath "*********************************************************************************"  NDES_Validation 1
$ErrorActionPreference = "Continue"

#endregion

################################################################
#Region Checking the Connectivity to Azure Update Service
Write-host
Write-host "......................................................."
Write-host
Write-Host "Checking Connectivity to Azure Update Service" -ForegroundColor Yellow
Log-ScriptEvent $LogFilePath "Checking Connectivity to Azure Update Service" NDES_Validation 1

# Perform connectivity test
$connectionResult = Test-NetConnection -ComputerName autoupdate.msappproxy.net -Port 443

# Check if the TCP test succeeded
if ($connectionResult.TcpTestSucceeded) {

    Write-Host "Success: " -ForegroundColor Green -NoNewline
    Write-Host "Connection to autoupdate.msappproxy.net on port 443 is successful." 
    Log-ScriptEvent $LogFilePath "Connection to autoupdate.msappproxy.net on port 443 is successful."  NDES_Validation 1

} else {

    Write-Host "Error: " -ForegroundColor Red -NoNewline
    Write-Host "Connection to autoupdate.msappproxy.net on port 443 failed." -ForegroundColor Red
    Log-ScriptEvent $LogFilePath "Connection to autoupdate.msappproxy.net on port 443 failed."  NDES_Validation 3
}

Log-ScriptEvent $LogFilePath "*********************************************************************************"  NDES_Validation 1
#endregion

################################################################
#Region Check IIS log



#endregion

#################################################################

#region Zip up logfiles
Write-host "......................................................."
Write-host
Write-host "Log Files.............................................." -ForegroundColor Yellow
Write-host 
write-host "Do you want to gather troubleshooting files? This includes IIS, NDES Connector logs in addition to the SCEP template configuration.  [Y]es, [N]o:"
$LogFileCollectionConfirmation = Read-Host

if($LogFileCollectionConfirmation -eq "y"){

    Import-Module WebAdministration -ErrorAction SilentlyContinue
    #get IIS log file location
    $IISLogPath = (Get-WebConfigurationProperty "/system.applicationHost/sites/siteDefaults" -name logfile.directory).Value + "\W3SVC1" -replace "%SystemDrive%",$env:SystemDrive
    $IISLogs = Get-ChildItem $IISLogPath| Sort-Object -Descending -Property LastWriteTime | Select-Object -First 3

    # Get the Event Log path
    $ConnectorAdminEventLogFile = Get-WinEvent -ListLog "Microsoft-Intune-CertificateConnectors/Admin" | Select-Object -ExpandProperty LogFilePath
    $ConnectorAdminEventLogFilePath = [System.Environment]::ExpandEnvironmentVariables($ConnectorAdminEventLogFile)

    $ConnectorOperationalEventLogFile = Get-WinEvent -ListLog "Microsoft-Intune-CertificateConnectors/Operational" | Select-Object -ExpandProperty LogFilePath
    $ConnectorOperationalEventLogFilePath = [System.Environment]::ExpandEnvironmentVariables($ConnectorOperationalEventLogFile)

    $AADAgentUpdaterAdminEventLogFile = Get-WinEvent -ListLog "Microsoft-AzureADConnect-AgentUpdater/Admin" | Select-Object -ExpandProperty LogFilePath
    $AADAgentUpdaterAdminEventLogFilePath = [System.Environment]::ExpandEnvironmentVariables($AADAgentUpdaterAdminEventLogFile)

    $ApplicationEventLogFile = Get-WinEvent -ListLog "Application" | Select-Object -ExpandProperty LogFilePath
    $ApplicationLogFilePath = [System.Environment]::ExpandEnvironmentVariables( $ApplicationEventLogFile)

    $SystemEventLogFile = Get-WinEvent -ListLog "System" | Select-Object -ExpandProperty LogFilePath
    $SystemLogFilePath = [System.Environment]::ExpandEnvironmentVariables( $SystemEventLogFile)
    
    #Copy IIS log to log file location
    Write-host "Collecting IIS log......................." -ForegroundColor Yellow
    foreach ($IISLog in $IISLogs){
        
        Copy-Item -Path $IISLog.FullName -Destination $TempDirPath
    
    }
    
    #copy event log to log file location
    Write-host "Collecting Event log......................." -ForegroundColor Yellow
    Copy-Item -Path $ConnectorAdminEventLogFilePath -Destination $TempDirPath
    Copy-Item -Path $ConnectorOperationalEventLogFilePath -Destination $TempDirPath
    Copy-Item -Path $AADAgentUpdaterAdminEventLogFilePath -Destination $TempDirPath
    Copy-Item -Path $ApplicationLogFilePath -Destination $TempDirPath
    Copy-Item -Path $SystemLogFilePath -Destination $TempDirPath


    Write-host "Collecting GPresult........................." -ForegroundColor Yellow
    $GPresultPath = "$($TempDirPath)\gpresult_temp.html"
    gpresult /h $GPresultPath
#This following use to check cert template 
#$SCEPUserCertTemplateOutputFilePath = "$($TempDirPath)\SCEPUserCertTemplate.txt"
# certutil -v -template $SCEPUserCertTemplate > $SCEPUserCertTemplateOutputFilePath

Log-ScriptEvent $LogFilePath "This is the end of logs"  NDES_Validation 1

Add-Type -assembly "system.io.compression.filesystem"
$Currentlocation =  $env:temp
$date = Get-Date -Format ddMMyyhhmm
[io.compression.zipfile]::CreateFromDirectory($TempDirPath, "$($Currentlocation)\$($date)-Logs-$($hostname).zip")

#Show in Explorer
Start-Process $Currentlocation

Write-host
Write-Host "Success: " -ForegroundColor Green -NoNewline
write-host "Log files copied to $($TempDirPath) and zip to $env:temp\$($date)-Logs-$($hostname).zip"
Write-host

}else {

    Write-Host "Logs is not collected"
    Log-ScriptEvent $LogFilePath "Do not collect logs"  NDES_Validation 1
    #$WriteLogOutputPath = $True
}

Write-Host "End of NDES configuration validation" 

#endregion

#################################################################


} else {

        Write-Host
        Write-host "......................................................."
        Write-Host
        Write-host "Incorrect variables. Please run the script again..." -ForegroundColor Red
        Write-Host
        Write-Host "Exiting................................................"
        Write-Host
        exit

}


