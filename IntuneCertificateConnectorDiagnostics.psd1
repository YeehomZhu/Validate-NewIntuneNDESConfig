@{
    RootModule        = 'IntuneCertificateConnectorDiagnostics.psm1'
    ModuleVersion     = '2.2.0'
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

Full service-locator validation requires the enrolled agent certificate and verifies that EnrollmentService and RAODJPlusFEGatewayService resolve to absolute endpoint URIs.

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
Version 2.2.0:
- Tightens NET09 so only a successful client-certificate response containing
    EnrollmentService and RAODJPlusFEGatewayService passes full validation.
- Distinguishes transport-only validation when the agent certificate is absent.
- Makes authentication rejection, missing service names, and HTTP 5xx responses
    actionable failures while unexpected redirects and other 4xx responses warn.
- Makes DYN01 validate both required service-map keys and absolute endpoint URIs
    returned by the installed connector assembly.
- Converts unexpected environmental/runtime exceptions into a RUN01 failure
    report and fallback transcript instead of terminating the diagnostic.
- Retains Jerry Abouelnasr as co-author and acknowledges his feature-detection idea.
- Keeps the public command, alias, parameters, existing result IDs, and report
    schema compatible; RUN01 is emitted only for an unexpected runtime failure.
'@
        }
    }
}
