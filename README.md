# Validate-NewIntuneNDESConfig

A PowerShell script to validate the configuration of an NDES (Network Device Enrollment Service) server with the new **Intune Certificate Connector**.

> Based on the original [Validate-NDESConfiguration](https://github.com/microsoftgraph/powershell-intune-samples/blob/master/CertificationAuthority/Validate-NDESConfiguration.ps1) script, rewritten to support the new Intune certificate connector architecture.

## Overview

Since Microsoft Intune released the new Certificate Connector for SCEP certificate delivery, the original validation script required significant updates. This script validates all prerequisites and configuration settings on an NDES server running the new Intune Certificate Connector.

> **Note:** This script is used **purely to validate** the configuration. All remedial tasks will need to be carried out manually.

## Features

- ✅ Check Server OS version (requires Windows Server 2012 R2 or later)
- ✅ Check NDES and CA role installation status
- ✅ Check required Windows features and .NET Framework version
- ✅ Check SCEP Application Pool status in IIS
- ✅ Check NDES service account permissions (Administrators / IIS_IUSRS)
- ✅ Check registry settings for long URL support
- ✅ Check for intermediate certificates in the Trusted Root store
- ✅ Validate MSCEP certificates (EnrollmentAgentOffline / CEPEncryption) expiry
- ✅ Check SCEP certificate template registry configuration
- ✅ Verify Intune Certificate Connector installation and version
- ✅ Validate Connector certificate and its expiry
- ✅ Check Connector features (SCEP, PFX, PFX Import, Revocation)
- ✅ Check Connector proxy configuration and last sync time
- ✅ Check NDES internal URL behaviour
- ✅ Scan Event Logs for errors (Intune Connector Admin/Operational, AAD Agent Updater, Application, System)
- ✅ Test connectivity to Azure Update Service (`autoupdate.msappproxy.net:443`)
- ✅ Collect and zip troubleshooting logs (IIS logs, Event Logs, GPResult)

## Prerequisites

- **Must be run directly on the NDES server**
- Requires **PowerShell 3.0** or later
- Requires **Run As Administrator**

## Usage

```powershell
.\Validate-NewIntuneNDESConfig.ps1
```

### Parameters

| Parameter | Alias | Description |
|-----------|-------|-------------|
| `-help`   | `-h`, `-?`, `-/?` | Displays help information |
| `-usage`  | `-u`  | Displays usage information |

## What Gets Checked

| Check | Expected Result |
|-------|----------------|
| OS Version | Windows Server 2012 R2 (`6.3.9600`) or later |
| CA Role | **Not** installed on NDES server |
| NDES Role | Installed |
| IIS + .NET Features | All required features installed |
| .NET Framework | 4.7 or later |
| SCEP App Pool | Started |
| Service Account | Member of `IIS_IUSRS`, not `Administrators` |
| HTTP Registry | `MaxFieldLength` and `MaxRequestBytes` set to `65534` |
| Trusted Root Store | No intermediate certificates |
| MSCEP Certificates | Present and not expired |
| SCEP Template Registry | Not default (`IPSECIntermediateOffline`) |
| Intune Connector | Installed |
| Connector Certificate | Present and not expired |
| Connector Last Sync | Within the last 1 day |
| Internal NDES URL | Returns HTTP 403 |
| Azure Update Endpoint | TCP 443 reachable |

## Log Files

The script generates a CMTrace-compatible log file at:
```
%TEMP%\<GUID>\Validate-NewIntuneNDESConfig.log
```

When prompted, the script can also collect and zip the following into `%TEMP%\<timestamp>-Logs-<hostname>.zip`:
- Last 3 IIS W3SVC1 log files
- Intune Connector Admin and Operational Event Logs (`.evtx`)
- AAD Agent Updater Admin Event Log
- Application and System Event Logs
- GPResult HTML report

## References

- [Configure SCEP certificate infrastructure](https://learn.microsoft.com/en-us/mem/intune/protect/certificates-scep-configure)
- [Certificate Connector for Microsoft Intune](https://learn.microsoft.com/en-us/mem/intune/protect/certificate-connector-overview)
- [Certificate Connector Prerequisites](https://learn.microsoft.com/en-us/mem/intune/protect/certificate-connector-prerequisites)

## Authors

Leon Zhu, Premkumar N

## Version History

| Version | Notes |
|---------|-------|
| 1.6 | Bug fixes and connector status checks |
| 1.5 | Added more event log checks |
| 1.4 | Added system/application/GPResult log collection; AAD Agent Updater log; network connectivity test |
| 1.1 | Bug fix |
| 1.0 | Initial rewrite to support new NDES connector |

## Disclaimer

This script is provided **as-is** for diagnostic purposes only. It does not make any changes to the server configuration.
