@{
    RootModule        = 'IntuneCertificateConnectorDiagnostics.psm1'
    ModuleVersion     = '2.0.1'
    GUID              = 'bb2983e7-ce6b-4ffe-9a20-84f1c8ed502c'
    Author            = 'Leon Zhu'
    CompanyName       = ''
    Copyright         = 'Copyright (c) 2026 Leon Zhu. Licensed under the MIT License.'
    Description       = 'Read-only validation of Microsoft Intune Certificate Connector, NDES/SCEP, IIS, certificates, event logs, proxy, TLS, revocation, service-locator connectivity, and automatic-update prerequisites.'
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
Version 2.0.1 updates package attribution and documentation. It retains the
import-safe module, direct human-readable output, PassThru reports, proxy-aware
TLS and updater checks, event-log analysis, and optional evidence collection.
'@
        }
    }
}
