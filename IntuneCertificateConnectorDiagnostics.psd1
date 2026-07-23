@{
    RootModule        = 'IntuneCertificateConnectorDiagnostics.psm1'
    ModuleVersion     = '2.0.1'
    GUID              = 'bb2983e7-ce6b-4ffe-9a20-84f1c8ed502c'
    Author            = 'Leon Zhu'
    CompanyName       = ''
    Copyright         = 'Copyright (c) 2026 Leon Zhu. Licensed under the MIT License.'
    Description       = 'Read-only validation of Microsoft Intune Certificate Connector and NDES/SCEP prerequisites. Quick start: (1) install the module, (2) open elevated Windows PowerShell on the connector/NDES server, (3) run Test-IntuneCertificateConnector, (4) review PASS, PASS-WITH-WARNINGS, or FAIL plus remediation, (5) use -CollectLogs for a troubleshooting ZIP, and (6) use -PassThru for automation. Checks cover Windows/IIS roles, service accounts, certificates, registry configuration, event logs, proxy, DNS, TLS trust, revocation, service-locator connectivity, and automatic updates.'
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
Version 2.0.1:
- Updates package attribution.
- Adds detailed install, execution, result interpretation, log collection, and
    automation steps to the Gallery package documentation.
- Adds an acknowledgement to Jerry Abouelnasr for the new idea that inspired
    connector feature detection.
- Retains the import-safe module, PassThru reports, proxy-aware TLS and updater
    checks, event-log analysis, and optional evidence collection.
'@
        }
    }
}
