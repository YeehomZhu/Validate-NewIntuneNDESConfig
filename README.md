# IntuneCertificateConnectorDiagnostics

An import-safe PowerShell module for validating an NDES (Network Device Enrollment Service) server that uses the current **Certificate Connector for Microsoft Intune**.

## Single merged diagnostic

Run `Test-IntuneCertificateConnector` once to perform the complete validation. The module combines the former NDES configuration validator and Certificate Connector prerequisite/network diagnostic. Its implementation is self-contained in `IntuneCertificateConnectorDiagnostics.psm1`; importing the module only defines and exports commands and doesn't run checks or change server configuration.

The default run is non-interactive: it executes the applicable local, NDES, IIS, certificate, connector, network, TLS, updater, and event-log checks, then displays one direct `PASS`, `PASS-WITH-WARNINGS`, or `FAIL` result with the failure/warning list and transcript location.

> Based on the original [Validate-NDESConfiguration](https://github.com/microsoftgraph/powershell-intune-samples/blob/master/CertificationAuthority/Validate-NDESConfiguration.ps1) script, rewritten to support the new Intune certificate connector architecture.

## Overview

Since Microsoft Intune released the new Certificate Connector for SCEP certificate delivery, the original validation script required significant updates. This module validates all prerequisites and configuration settings on an NDES server running the new Intune Certificate Connector.

> **Note:** This script is used **purely to validate** the configuration. All remedial tasks will need to be carried out manually.

## Combined diagnostic features

- ✅ Windows Server, administrator, .NET Framework 4.7.2, TLS 1.2, system clock, and trusted-root checks
- ✅ Domain membership, domain-controller exclusion, NDES/CA role separation, and required Windows features
- ✅ SCEP application pool, localized `IIS_IUSRS` membership, and connector service-account checks
- ✅ HTTP.sys long-request and MSCEP certificate-template registry checks
- ✅ NDES template certificates and IIS HTTPS binding/server-certificate checks
- ✅ Connector installation, version, features, services, client certificate, proxy, and last connection
- ✅ Dynamic DNS, TCP, HTTP CONNECT, TLS, hostname, chain trust, TLS inspection, and CRL/OCSP checks
- ✅ Connector service-locator call using both `HttpClient` and the installed connector assembly
- ✅ Proxy-aware Azure update service validation for `autoupdate.msappproxy.net:443`
- ✅ Internal MSCEP direct-access and `GetCACaps` behavior
- ✅ Bounded recent-event analysis for Connector Admin/Operational, updater, Application, and System logs
- ✅ Optional ZIP collection using exported EVTX files, recent IIS logs, GPResult, transcript, and metadata
- ✅ Non-interactive execution and structured result objects for automation

## Prerequisites

- **Must be run directly on the NDES server**
- Requires **Windows PowerShell 5.1** or later
- Run **As Administrator** for complete results; restricted checks degrade to warnings when possible

## Installation and usage

Install from PowerShell Gallery:

```powershell
Install-Module -Name IntuneCertificateConnectorDiagnostics -Scope CurrentUser
Test-IntuneCertificateConnector
```

PowerShell automatically loads the installed module when the exported command is called. To run the repository version directly:

```powershell
Import-Module .\IntuneCertificateConnectorDiagnostics.psd1 -Force
Test-IntuneCertificateConnector
```

Run from elevated Windows PowerShell on the NDES/connector server for complete results. A reduced connector-only run is also supported:

```powershell
Test-IntuneCertificateConnector -SkipNdesChecks
```

Create a local troubleshooting archive explicitly:

```powershell
Test-IntuneCertificateConnector `
	-CollectLogs `
	-DiagnosticBundlePath C:\Temp\Intune-NDES-Diagnostics.zip
```

The compatibility alias `Test-CertConnectorPrereqNetwork` is also exported.

### Combined diagnostic parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `ConnectorType` | `PFXCertificateConnector` | Connector registry leaf below `HKLM\SOFTWARE\Microsoft\MicrosoftIntune` |
| `BaseAddress` | Connector registry or `https://manage.microsoft.com` | Overrides the Intune base address |
| `OutFile` | Timestamped ProgramData log | Transcript output path |
| `SkipDynamic` | Off | Skips invoking the installed ConnectorCommon assembly |
| `SkipNdesChecks` | Off | Skips NDES, IIS, MSCEP, and NDES certificate checks |
| `SkipNetworkChecks` | Off | Skips all external network/TLS calls and internal MSCEP requests |
| `SkipEventLogChecks` | Off | Skips recent event-log analysis |
| `TimeoutSeconds` | `30` | Per-network-operation timeout |
| `EventLookbackDays` | `2` | Event-log lookback window |
| `MaxEvents` | `5` | Maximum events reported per event check |
| `ConnectorStaleHours` | `24` | Last-connection warning threshold |
| `CollectLogs` | Off | Enables local diagnostic ZIP creation |
| `DiagnosticBundlePath` | Timestamped ProgramData ZIP | Optional ZIP output path |
| `IisLogCount` | `3` | Number of recent IIS logs included in the ZIP |
| `PassThru` | Off | Returns one structured report object for automation |

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

## Output and log files

The default execution displays the direct result without dumping individual objects. It writes a transcript under:

```text
%ProgramData%\Microsoft\IntuneCertificateConnector\Configuration\PrereqNetworkDiagnostic-<timestamp>.log
```

For automation, request one report object. Its `Results` collection contains `Id`, `Category`, `Name`, `Status`, `Detail`, `Remediation`, and `Case` for every check:

```powershell
$report = Test-IntuneCertificateConnector -PassThru
$report.Overall
$report.Counts
$report.Results | Where-Object Status -eq 'Fail'
```

When `CollectLogs` is specified, the ZIP can contain:

- Recent IIS logs
- Exported Intune Connector Admin and Operational logs
- Exported Azure AD Connect Agent Updater, Application, and System logs
- GPResult HTML
- Transcript and collection metadata

> **Sensitive data:** The transcript and ZIP can contain hostnames, account names, certificate details, policy data, and event messages. Store and share them according to your organization's data-handling policy. The script does not upload them.

## Safety and scope

The combined diagnostic is read-only with respect to server configuration. It doesn't install roles, write registry settings, restart services, remove certificates, or apply remediation. Its normal side effect is writing the transcript. A ZIP and temporary staging files are created only with `CollectLogs`; the staging directory is removed after packaging.

Some remote facts cannot be reliably validated from the local server and remain manual checks, including certificate-template ACLs on the issuing CA, `Issue and Manage Certificates`, KSP permissions for imported PFX, Microsoft Entra role/license assignment, and environment-dependent SPN requirements.

## Module layout

- [IntuneCertificateConnectorDiagnostics.psd1](IntuneCertificateConnectorDiagnostics.psd1) — module manifest and Gallery metadata
- [IntuneCertificateConnectorDiagnostics.psm1](IntuneCertificateConnectorDiagnostics.psm1) — self-contained private implementation, public command, compatibility alias, and explicit exports; import-safe and doesn't start diagnostics
- [build/Build-Module.ps1](build/Build-Module.ps1) — creates a clean, correctly named Gallery package folder
- [build/Publish-GalleryModule.ps1](build/Publish-GalleryModule.ps1) — validates and publishes with masked, memory-only API key handling
- [tests/Test-CertConnectorPrereqNetwork.Tests.ps1](tests/Test-CertConnectorPrereqNetwork.Tests.ps1) — manifest, import, API, repeated-run, alias, and smoke tests

The module exports only `Test-IntuneCertificateConnector` and the compatibility alias. All helper functions remain private.

## PowerShell Gallery publication

The `.psd1` manifest contains version, GUID, author, description, license, project URL, tags, release notes, and explicit exports. Validate the module before publishing:

```powershell
Test-ModuleManifest -Path .\IntuneCertificateConnectorDiagnostics.psd1
Invoke-ScriptAnalyzer -Path .\IntuneCertificateConnectorDiagnostics.psm1
Invoke-ScriptAnalyzer -Path .\build\Build-Module.ps1
Invoke-ScriptAnalyzer -Path .\build\Publish-GalleryModule.ps1
Invoke-ScriptAnalyzer -Path .\tests\Test-CertConnectorPrereqNetwork.Tests.ps1
Invoke-Pester -Path .\tests\Test-CertConnectorPrereqNetwork.Tests.ps1
$modulePath = .\build\Build-Module.ps1
Test-ModuleManifest -Path "$modulePath\IntuneCertificateConnectorDiagnostics.psd1"
```

The build step copies only `IntuneCertificateConnectorDiagnostics.psd1`, `IntuneCertificateConnectorDiagnostics.psm1`, `README.md`, and `LICENSE` into `out\IntuneCertificateConnectorDiagnostics`. Tests, `.git`, logs, and development files aren't included. Preview publication without uploading:

```powershell
.\build\Publish-GalleryModule.ps1 -WhatIf
```

Publish after reviewing the dry run:

```powershell
.\build\Publish-GalleryModule.ps1
```

The helper prompts for the API key with masked input, holds plaintext only while `Publish-Module` runs, clears its unmanaged buffer, and removes the in-memory key variable afterward. Never put an API key in source, command history, environment variables, logs, or chat. The key must permit **Push new or update packages** and match the `IntuneCertificateConnectorDiagnostics` package name.

## References

- [Configure SCEP certificate infrastructure](https://learn.microsoft.com/en-us/mem/intune/protect/certificates-scep-configure)
- [Certificate Connector for Microsoft Intune](https://learn.microsoft.com/en-us/mem/intune/protect/certificate-connector-overview)
- [Certificate Connector Prerequisites](https://learn.microsoft.com/en-us/mem/intune/protect/certificate-connector-prerequisites)

## Authors

Leon Zhu, Premkumar N

## Version History

| Version | Notes |
|---------|-------|
| 2.0.0 | Merged NDES and Certificate Connector validation into one import-safe, non-interactive, Gallery-ready module |
| 1.6 | Bug fixes and connector status checks |
| 1.5 | Added more event log checks |
| 1.4 | Added system/application/GPResult log collection; AAD Agent Updater log; network connectivity test |
| 1.1 | Bug fix |
| 1.0 | Initial rewrite to support new NDES connector |

## Disclaimer

This script is provided **as-is** for diagnostic purposes only. It does not make any changes to the server configuration.
