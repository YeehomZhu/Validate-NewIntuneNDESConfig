@{
    RootModule        = 'IntuneCertificateConnectorDiagnostics.psm1'
    ModuleVersion     = '2.1.0'
    GUID              = 'bb2983e7-ce6b-4ffe-9a20-84f1c8ed502c'
    Author            = 'Leon Zhu, Jerry Abouelnasr'
    CompanyName       = ''
    Copyright         = 'Copyright (c) 2026 Leon Zhu. Licensed under the MIT License.'
    Description       = @'
Read-only validation of Microsoft Intune Certificate Connector and NDES/SCEP prerequisites.

Quick start:
1. Install: Install-Module IntuneCertificateConnectorDiagnostics
2. Open elevated Windows PowerShell on the connector/NDES server.
3. Run: Test-IntuneCertificateConnector
4. Review PASS, PASS-WITH-WARNINGS, or FAIL and the suggested remediation.
5. Add -CollectLogs to create a troubleshooting ZIP when needed.
6. Add -PassThru to return a structured report for automation.

Checks cover Windows and IIS roles, service accounts, certificates, registry configuration, event logs, proxy, DNS, TLS trust, revocation, service-locator connectivity, and automatic updates.

Acknowledgement: Thanks to Jerry Abouelnasr for the feature-detection idea.
'@
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport = @('Test-IntuneCertificateConnector')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @('Test-CertConnectorPrereqNetwork')

    FileList = @(
        'IntuneCertificateConnectorDiagnostics.psd1'
        'IntuneCertificateConnectorDiagnostics.psm1'
        'README.md'
        'LICENSE'
    )

    PrivateData = @{
        PSData = @{
            Tags = @(
                'Windows'
                'Intune'
                'CertificateConnector'
                'NDES'
                'SCEP'
                'PKI'
                'IIS'
                'TLS'
                'Certificate'
                'Network'
                'Diagnostics'
            )
            LicenseUri = 'https://github.com/YeehomZhu/Validate-NewIntuneNDESConfig/blob/master/LICENSE'
            ProjectUri = 'https://github.com/YeehomZhu/Validate-NewIntuneNDESConfig'
            ReleaseNotes = @'
Version 2.1.0:
- Adds Jerry Abouelnasr as a module co-author.
- Reorganizes the PSM1 into foldable functional and diagnostic-phase regions.
- Introduces an explicit per-run diagnostic context for cross-phase settings and
    removes implicit parameter lookup from network and finalization orchestration.
- Reduces module-global state to runtime result, transcript, bundle, concurrency,
    and TLS callback capture data.
- Retains the acknowledgement to Jerry Abouelnasr for the feature-detection idea.
- Keeps the public command, alias, parameters, result IDs, report schema, and
    diagnostic behavior compatible with version 2.0.2.
'@
        }
    }
}
