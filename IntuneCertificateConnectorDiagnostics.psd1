@{
    RootModule        = 'IntuneCertificateConnectorDiagnostics.psm1'
    ModuleVersion     = '2.4.0'
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

Add -HtmlReport to also write a self-contained HTML report that shows the pass, warning, and failure status at a glance and lists a prioritized action plan.

Checks cover Windows and IIS roles, service accounts, certificates, registry configuration, event logs, proxy, DNS, TLS trust, revocation, service-locator connectivity, and automatic updates.

Full service-locator validation requires the enrolled agent certificate and verifies that EnrollmentService and RAODJPlusFEGatewayService resolve to absolute endpoint URIs.

Run in Windows PowerShell 5.1 on the server for complete results. PowerShell 7 can import the module, but the Windows role and IIS configuration providers are unavailable there, so those checks report warnings instead of pass or fail.

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
Version 2.4.0:
- Adds -HtmlReport and -HtmlReportPath, which write one self-contained HTML
    report next to the transcript.
- The report leads with a color-coded overall verdict and pass, warning,
    failure, and informational counts so status is visible at a glance.
- Adds a prioritized action plan that lists every failure before every warning
    with its detail, its remediation, and a link to the full check result.
- Every check is rendered as a readable card with a status badge, check ID,
    category, detail, and action, plus a CSS-only status filter.
- The report embeds its stylesheet, contains no script and no external
    reference, and HTML-encodes all environment data.
- The structured report object now exposes HtmlReportPath, and -CollectLogs
    packages the HTML report into the diagnostic ZIP.

Version 2.3.0:
- Fixes a socket leak: a failed or timed-out connection attempt now returns the
    TcpClient so the caller can always close it.
- CERT04 reads every Subject Alternative Name DNS entry from the raw extension,
    so multi-name IIS certificates are no longer reported as a name mismatch.
- Local group membership is resolved through nested groups, and an enumeration
    that cannot be completed now warns instead of failing CON04 and IIS03.
- CERT04 warns instead of failing when the IIS HTTPS binding list cannot be
    enumerated, and application-pool discovery no longer hides that list.
- Collected IIS logs are prefixed with their site folder so identically named
    daily logs are no longer overwritten in the diagnostic ZIP.
- LOC05 parses the HTTP Date header with the invariant culture, so clock-skew
    detection is correct on every locale.
- LOC02 and NDES05 read the operating-system version from Win32_OperatingSystem
    and report the source.
- NDES08 distinguishes an unprotected endpoint from a connector that has not
    enabled SCEP yet, and CERT01 separates cross-signed roots from genuinely
    misplaced intermediates.
- The diagnostic restores the process-wide ServicePointManager TLS setting and
    honors an explicit -ErrorAction from the caller.
- Renames the private Section helper to Write-DiagnosticSection.
- Keeps the public command, alias, parameters, result IDs, and report schema
    compatible with 2.2.0.

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
