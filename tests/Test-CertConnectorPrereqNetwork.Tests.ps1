[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester BeforeAll fixture variables are consumed by It blocks at run time.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingCmdletAliases', '', Justification = 'The compatibility alias is invoked intentionally to validate the public contract.')]
param()

Describe 'IntuneCertificateConnectorDiagnostics static validation' {
    BeforeAll {
        $moduleRoot = Join-Path $PSScriptRoot '..'
        $manifestPath = Join-Path $moduleRoot 'IntuneCertificateConnectorDiagnostics.psd1'
        $modulePath = Join-Path $moduleRoot 'IntuneCertificateConnectorDiagnostics.psm1'
        $buildPath = Join-Path $moduleRoot 'build\Build-Module.ps1'
        $publishPath = Join-Path $moduleRoot 'build\Publish-GalleryModule.ps1'
        $readmePath = Join-Path $moduleRoot 'README.md'
    }

    It 'parses every module source file without errors' {
        foreach ($path in @($manifestPath, $modulePath, $buildPath, $publishPath)) {
            $tokens = $null
            $parseErrors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile(
                $path,
                [ref]$tokens,
                [ref]$parseErrors
            )
            @($parseErrors).Count | Should -Be 0
        }
    }

    It 'contains a valid PowerShell Gallery module manifest' {
        $moduleInfo = Test-ModuleManifest -Path $manifestPath
        $moduleInfo.Name | Should -Be 'IntuneCertificateConnectorDiagnostics'
        $moduleInfo.Version | Should -Be ([Version]'2.4.1')
        $moduleInfo.Guid | Should -Not -Be ([Guid]::Empty)
        $moduleInfo.Author | Should -Be 'Leon Zhu, Jerry Abouelnasr'
        $moduleInfo.Description | Should -Not -BeNullOrEmpty
        $moduleInfo.PrivateData.PSData.LicenseUri | Should -Not -BeNullOrEmpty
    }

    It 'includes detailed Gallery usage steps and feature-detection acknowledgement' {
        $moduleInfo = Test-ModuleManifest -Path $manifestPath
        $readme = Get-Content -Path $readmePath -Raw

        $moduleInfo.Description | Should -Match 'Quick start:\r?\n1\. Install:'
        foreach ($step in 1..6) {
            $moduleInfo.Description | Should -Match ("(?m)^{0}\. " -f $step)
        }
        $moduleInfo.Description | Should -Match '(?m)^Acknowledgement: Thanks to Jerry Abouelnasr'
        $moduleInfo.PrivateData.PSData.ReleaseNotes | Should -Match 'Jerry Abouelnasr'
        foreach ($step in 1..6) {
            $readme | Should -Match ("### Step {0}:" -f $step)
        }
        $readme | Should -Match 'Special thanks to \*\*Jerry Abouelnasr\*\*'
        $readme | Should -Match 'feature-detection capability'
        $readme | Should -Match '(?m)^- Jerry Abouelnasr\r?$'
    }

    It 'uses PSResourceGet for Gallery publication' {
        $publisher = Get-Content -Path $publishPath -Raw
        $publisher | Should -Match 'Publish-PSResource'
        $publisher | Should -Not -Match '(?m)^\s*Publish-Module\s'
        $publisher | Should -Match 'appears truncated'
        $publisher | Should -Match 'non-ASCII characters'
    }

    It 'defines the complete result ID set with supported literal statuses and categories' {
        $content = Get-Content -Path $modulePath -Raw
        $resultCalls = @([regex]::Matches($content, "Add-Result\s+-Id\s+'([^']+)'", 'IgnoreCase'))
        $literalResultIds = @($resultCalls | ForEach-Object { $_.Groups[1].Value })
        $resultCalls.Count | Should -BeGreaterThan 30
        foreach ($expectedId in @(
                'CFG01', 'CFG02', 'CFG03', 'CFG04', 'CFG05', 'CFG06',
                'RUN01',
                'LOC01', 'LOC02', 'LOC03', 'LOC04', 'LOC05', 'LOC06', 'LOC07', 'LOC08', 'LOC09',
                'CON01', 'CON02', 'CON03', 'CON04', 'CON05',
                'NDES00', 'NDES01', 'NDES02', 'NDES03', 'NDES04', 'NDES05', 'NDES06', 'NDES07', 'NDES08', 'NDES09',
                'IIS00', 'IIS01', 'IIS02', 'IIS03', 'IIS04', 'IIS05', 'IIS06',
                'CERT01', 'CERT04',
                'NET00', 'NET01', 'NET02', 'NET04', 'NET05', 'NET06', 'NET07', 'NET07b', 'NET08', 'NET09', 'NET10',
                'DYN01', 'EVT00', 'EVT01', 'EVT02', 'EVT03', 'EVT04', 'EVT05', 'COL01'
            )) {
            $literalResultIds | Should -Contain $expectedId
        }
        $content | Should -Not -Match "-Category\s+(?!Config|Local|NDES|IIS|Certificate|Connector|Network|EventLog|Dynamic|Collection)[A-Za-z]+"
        $content | Should -Not -Match "-Status\s+'(?!Pass'|Warn'|Fail'|Info')[^']+'"
    }

    It 'contains all complete validation stages' {
        $content = Get-Content -Path $modulePath -Raw
        foreach ($section in @(
                'Configuration discovered from the connector',
                'Local prerequisites',
                'Certificate Connector configuration and health',
                'NDES server roles and Windows features',
                'IIS and NDES service account',
                'NDES and IIS certificates',
                'Network prerequisites',
                'Internal NDES endpoint behavior',
                'Dynamic connector assembly validation',
                'Recent Certificate Connector and NDES event logs',
                'Diagnostic evidence collection',
                'Summary'
            )) {
            $content | Should -Match ([regex]::Escape($section))
        }
    }

    It 'organizes the implementation into balanced functional regions' {
        $content = Get-Content -Path $modulePath -Raw
        $regionNames = @(
            'Module State and Constants',
            'Output and Formatting',
            'Configuration and Parsing',
            'System and Service Inspection',
            'Account and Security Validation',
            'Certificate and Network Primitives',
            'IIS, Event Log, and Collection Helpers',
            'Diagnostic Phase Orchestration',
            'Public Command',
            'Aliases and Exports'
        )

        foreach ($regionName in $regionNames) {
            $content | Should -Match ("(?m)^#region {0}\r?$" -f [regex]::Escape($regionName))
            $content | Should -Match ("(?m)^#endregion {0}\r?$" -f [regex]::Escape($regionName))
        }
        [regex]::Matches($content, '(?m)^\s*#region\b').Count |
            Should -Be ([regex]::Matches($content, '(?m)^\s*#endregion\b').Count)
    }

    It 'uses an explicit diagnostic context for orchestration dependencies' {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $modulePath,
            [ref]$tokens,
            [ref]$parseErrors
        )
        foreach ($functionName in @('Invoke-NetworkAndDynamicValidation', 'Invoke-Finalization')) {
            $functionAst = $ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                    $node.Name -eq $functionName
                }, $true) | Select-Object -First 1
            $functionAst | Should -Not -BeNullOrEmpty
            @($functionAst.Body.ParamBlock.Parameters.Name.VariablePath.UserPath) |
                Should -Contain 'Context'
        }
        $content = Get-Content -Path $modulePath -Raw
        $content | Should -Match 'function Initialize-DiagnosticContext'
        $content | Should -Match 'Invoke-NetworkAndDynamicValidation -Context \$context'
        $content | Should -Match 'Invoke-Finalization -Context \$context'
    }

    It 'documents the responsibility of every function' {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $modulePath,
            [ref]$tokens,
            [ref]$parseErrors
        )
        $sourceLines = @(Get-Content -Path $modulePath)
        $functions = @($ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                }, $true))

        foreach ($function in $functions) {
            $precedingIndex = $function.Extent.StartLineNumber - 2
            $precedingLine = $sourceLines[$precedingIndex].Trim()
            if ($precedingLine -eq '#>') {
                $helpStart = $precedingIndex
                while ($helpStart -ge 0 -and $sourceLines[$helpStart].Trim() -ne '<#') {
                    $helpStart--
                }
                $helpText = $sourceLines[$helpStart..$precedingIndex] -join "`n"
                $helpText | Should -Match '\.SYNOPSIS'
            } else {
                $precedingLine | Should -Match '^#\s+\S'
                $precedingLine | Should -Not -Match '^#(end)?region\b'
            }
        }
    }

    It 'builds a clean Gallery module folder' {
        $packagePath = & $buildPath -OutputRoot $TestDrive
        $packagePath | Should -Be (Join-Path $TestDrive 'IntuneCertificateConnectorDiagnostics')
        $builtManifest = Join-Path $packagePath 'IntuneCertificateConnectorDiagnostics.psd1'
        (Test-ModuleManifest -Path $builtManifest).Name | Should -Be 'IntuneCertificateConnectorDiagnostics'

        $actualFiles = @(Get-ChildItem -Path $packagePath -File | Select-Object -ExpandProperty Name | Sort-Object)
        $expectedFiles = @(
            'IntuneCertificateConnectorDiagnostics.psd1'
            'IntuneCertificateConnectorDiagnostics.psm1'
            'LICENSE'
            'README.md'
        ) | Sort-Object
        $actualFiles | Should -Be $expectedFiles
    }
}

Describe 'IntuneCertificateConnectorDiagnostics module contract' {
    BeforeAll {
        $moduleRoot = Join-Path $PSScriptRoot '..'
        $manifestPath = Join-Path $moduleRoot 'IntuneCertificateConnectorDiagnostics.psd1'
        Remove-Module IntuneCertificateConnectorDiagnostics -Force -ErrorAction SilentlyContinue
        $importOutput = @(Import-Module $manifestPath -Force 6>&1)
    }

    AfterAll {
        Remove-Module IntuneCertificateConnectorDiagnostics -Force -ErrorAction SilentlyContinue
    }

    It 'imports without running a diagnostic or writing host output' {
        $importOutput.Count | Should -Be 0
    }

    It 'exports only the public command and compatibility alias' {
        $commands = @(Get-Command -Module IntuneCertificateConnectorDiagnostics)
        @($commands | Where-Object CommandType -eq 'Function').Name | Should -Be @('Test-IntuneCertificateConnector')
        @($commands | Where-Object CommandType -eq 'Alias').Name | Should -Be @('Test-CertConnectorPrereqNetwork')
    }

    It 'retains every public control parameter' {
        $parameterNames = @(Get-Command Test-IntuneCertificateConnector).Parameters.Keys
        foreach ($expected in @(
                'ConnectorType', 'BaseAddress', 'OutFile', 'SkipDynamic',
                'SkipNdesChecks', 'SkipNetworkChecks', 'SkipEventLogChecks',
                'TimeoutSeconds', 'EventLookbackDays', 'MaxEvents',
                'ConnectorStaleHours', 'CollectLogs', 'DiagnosticBundlePath',
                'IisLogCount', 'HtmlReport', 'HtmlReportPath', 'PassThru'
            )) {
            $parameterNames | Should -Contain $expected
        }
    }

    It 'passes a fully authenticated ServiceAddresses response with both required services' {
        InModuleScope IntuneCertificateConnectorDiagnostics {
            $content = '{"EnrollmentService":"https://enrollment.example.test/","RAODJPlusFEGatewayService":"https://gateway.example.test/"}'
            $assessment = Get-ServiceLocatorHttpAssessment `
                -StatusCode 200 `
                -ClientCertificatePresented $true `
                -Content $content

            $assessment.Status | Should -Be 'Pass'
            $assessment.MissingServices.Count | Should -Be 0
        }
    }

    It 'fails incomplete or rejected authenticated ServiceAddresses responses' {
        InModuleScope IntuneCertificateConnectorDiagnostics {
            $incomplete = Get-ServiceLocatorHttpAssessment `
                -StatusCode 200 `
                -ClientCertificatePresented $true `
                -Content '{"EnrollmentService":"https://enrollment.example.test/"}'
            $rejected = Get-ServiceLocatorHttpAssessment `
                -StatusCode 403 `
                -ClientCertificatePresented $true
            $serverError = Get-ServiceLocatorHttpAssessment `
                -StatusCode 503 `
                -ClientCertificatePresented $true

            $incomplete.Status | Should -Be 'Fail'
            $incomplete.MissingServices | Should -Contain 'RAODJPlusFEGatewayService'
            $rejected.Status | Should -Be 'Fail'
            $serverError.Status | Should -Be 'Fail'
        }
    }

    It 'warns when only transport can be validated without an agent certificate' {
        InModuleScope IntuneCertificateConnectorDiagnostics {
            $successWithoutCertificate = Get-ServiceLocatorHttpAssessment `
                -StatusCode 200 `
                -ClientCertificatePresented $false `
                -Content '{"EnrollmentService":"https://enrollment.example.test/","RAODJPlusFEGatewayService":"https://gateway.example.test/"}'
            $unauthorizedWithoutCertificate = Get-ServiceLocatorHttpAssessment `
                -StatusCode 401 `
                -ClientCertificatePresented $false
            $unexpectedClientResponse = Get-ServiceLocatorHttpAssessment `
                -StatusCode 404 `
                -ClientCertificatePresented $false

            $successWithoutCertificate.Status | Should -Be 'Warn'
            $unauthorizedWithoutCertificate.Status | Should -Be 'Warn'
            $unexpectedClientResponse.Status | Should -Be 'Warn'
        }
    }

    It 'requires both connector service-map keys to resolve absolute endpoints' {
        InModuleScope IntuneCertificateConnectorDiagnostics {
            $complete = Get-ServiceLocatorMapAssessment -ServiceMap @{
                EnrollmentService          = [Uri]'https://enrollment.example.test/'
                RAODJPlusFEGatewayService  = [Uri]'https://gateway.example.test/'
            }
            $missing = Get-ServiceLocatorMapAssessment -ServiceMap @{
                EnrollmentService = [Uri]'https://enrollment.example.test/'
            }
            $invalid = Get-ServiceLocatorMapAssessment -ServiceMap @{
                EnrollmentService          = [Uri]'https://enrollment.example.test/'
                RAODJPlusFEGatewayService  = '/relative/path'
            }

            $complete.Complete | Should -BeTrue
            $complete.ResolvedServices.Count | Should -Be 2
            $missing.Complete | Should -BeFalse
            $missing.MissingServices | Should -Contain 'RAODJPlusFEGatewayService'
            $invalid.Complete | Should -BeFalse
            $invalid.InvalidServices | Should -Contain 'RAODJPlusFEGatewayService'
        }
    }

    It 'reads every Subject Alternative Name DNS entry from raw extension data' {
        InModuleScope IntuneCertificateConnectorDiagnostics {
            $expected = @(
                'ndes.contoso.test'
                'scep.contoso.test'
                'ndes-external.contoso.test'
                'autodiscover.contoso.test'
                'enrollment.contoso.test'
                'ndes-legacy.contoso.test'
            )
            $body = New-Object 'System.Collections.Generic.List[byte]'
            foreach ($name in $expected) {
                $encoded = [Text.Encoding]::ASCII.GetBytes($name)
                $body.Add(0x82)
                $body.Add([byte]$encoded.Length)
                $body.AddRange($encoded)
            }
            # An iPAddress GeneralName must be skipped instead of decoded as DNS.
            $body.Add(0x87)
            $body.Add(4)
            $body.AddRange([byte[]]@(10, 0, 0, 1))

            $body.Count | Should -BeGreaterThan 127
            $raw = New-Object 'System.Collections.Generic.List[byte]'
            $raw.Add(0x30)
            $raw.Add(0x81)
            $raw.Add([byte]$body.Count)
            $raw.AddRange($body)

            $names = @(Get-SubjectAlternativeDnsName -RawData $raw.ToArray())
            $names | Should -Be $expected
        }
    }

    It 'matches the NDES FQDN against any certificate name, not only the first' {
        InModuleScope IntuneCertificateConnectorDiagnostics {
            $presented = @('autodiscover.contoso.test', 'ndes.contoso.test', '*.wildcard.contoso.test')

            @($presented | Where-Object { Test-DnsNameMatch -Expected 'ndes.contoso.test' -Presented $_ }) |
                Should -Be @('ndes.contoso.test')
            @($presented | Where-Object { Test-DnsNameMatch -Expected 'host.wildcard.contoso.test' -Presented $_ }) |
                Should -Be @('*.wildcard.contoso.test')
            @($presented | Where-Object { Test-DnsNameMatch -Expected 'other.contoso.test' -Presented $_ }).Count |
                Should -Be 0
        }
    }

    It 'returns a closable socket when a TCP connection attempt fails' {
        InModuleScope IntuneCertificateConnectorDiagnostics {
            # Loopback port 1 is refused immediately, which exercises the same
            # failure path as a connect timeout without depending on the network.
            $connection = Connect-Tls443 -TargetHost '127.0.0.1' -Port 1 -TimeoutMs 2000
            try {
                $connection.Ok | Should -BeFalse
                $connection.Error | Should -Not -BeNullOrEmpty
                $connection.Tcp | Should -Not -BeNullOrEmpty
            } finally {
                if ($connection.Tcp) { $connection.Tcp.Close() }
            }
        }
    }

    It 'reports whether the IIS HTTPS binding list is authoritative' {
        InModuleScope IntuneCertificateConnectorDiagnostics {
            $configuration = Get-IisScepConfiguration
            $configuration.PSObject.Properties.Name | Should -Contain 'BindingsKnown'
            $configuration.BindingsKnown | Should -BeOfType [bool]
            if (-not $configuration.BindingsKnown) {
                @($configuration.HttpsBindings).Count | Should -Be 0
            }
        }
    }

    It 'marks group enumeration incomplete when a group cannot be read' {
        InModuleScope IntuneCertificateConnectorDiagnostics {
            $missingGroup = "WinNT://{0}/NoSuchGroup{1},group" -f $env:COMPUTERNAME, [guid]::NewGuid().ToString('N')
            $enumeration = Get-GroupMemberSidSet -AdsPath $missingGroup

            $enumeration.Complete | Should -BeFalse
            $enumeration.Sids.Count | Should -Be 0
        }
    }

    It 'restores the process-wide TLS configuration after a run' {
        InModuleScope IntuneCertificateConnectorDiagnostics {
            $original = [Net.ServicePointManager]::SecurityProtocol
            Mock Get-ConnectorProduct {
                [Net.ServicePointManager]::SecurityProtocol =
                    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
                return $null
            }
            $logPath = Join-Path ([IO.Path]::GetTempPath()) ("tls-restore-{0}.log" -f [guid]::NewGuid())
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::SystemDefault
                $null = Test-IntuneCertificateConnector `
                    -SkipNdesChecks `
                    -SkipNetworkChecks `
                    -SkipEventLogChecks `
                    -SkipDynamic `
                    -OutFile $logPath 6>$null

                [Net.ServicePointManager]::SecurityProtocol |
                    Should -Be ([Net.SecurityProtocolType]::SystemDefault)
            } finally {
                [Net.ServicePointManager]::SecurityProtocol = $original
                Remove-Item $logPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'renders a self-contained HTML report with a prioritized action plan' {
        InModuleScope IntuneCertificateConnectorDiagnostics {
            $context = Initialize-DiagnosticContext -ConnectorType 'PFXCertificateConnector' -BaseAddress 'https://manage.microsoft.com'
            $results = @(
                [pscustomobject]@{ Id = 'AAA01'; Category = 'Local'; Name = 'Passing check'; Status = 'Pass'; Detail = 'pass detail'; Remediation = 'hidden for a pass'; Case = $false }
                [pscustomobject]@{ Id = 'BBB02'; Category = 'Network'; Name = 'Warning check'; Status = 'Warn'; Detail = 'warn detail'; Remediation = 'do the warn fix'; Case = $false }
                [pscustomobject]@{ Id = 'CCC03'; Category = 'NDES'; Name = 'Failing check'; Status = 'Fail'; Detail = 'fail detail'; Remediation = 'do the fail fix'; Case = $true }
            )
            $html = ConvertTo-DiagnosticHtmlReport -Context $context -Overall 'FAIL' -Results $results `
                -GeneratedAtUtc ([datetime]::UtcNow) -Duration ([timespan]::FromSeconds(2))

            $html | Should -Match '^<!DOCTYPE html>'
            $html.TrimEnd() | Should -Match '</html>$'
            $html | Should -Not -Match '<script'
            $html | Should -Not -Match '(src|href)="https?://'
            $html | Should -Match '<h2>Action plan</h2>'
            $html | Should -Match 'KNOWN CASE'
            $html | Should -Match 'id="chk-AAA01"'

            # Failures are actioned before warnings.
            $html.IndexOf('do the fail fix') | Should -BeLessThan $html.IndexOf('do the warn fix')
            # A passing check still gets a card, but never an action entry.
            $html | Should -Not -Match 'hidden for a pass'
        }
    }

    It 'states that no action is required when nothing failed or warned' {
        InModuleScope IntuneCertificateConnectorDiagnostics {
            $context = Initialize-DiagnosticContext -ConnectorType 'PFXCertificateConnector'
            $results = @(
                [pscustomobject]@{ Id = 'AAA01'; Category = 'Local'; Name = 'Passing check'; Status = 'Pass'; Detail = 'pass detail'; Remediation = ''; Case = $false }
            )
            $html = ConvertTo-DiagnosticHtmlReport -Context $context -Overall 'PASS' -Results $results `
                -GeneratedAtUtc ([datetime]::UtcNow) -Duration ([timespan]::FromSeconds(1))

            $html | Should -Match 'no remediation is required'
            $html | Should -Not -Match '<ol class="plan">'
        }
    }

    It 'encodes environment data so the HTML report cannot be injected' {
        InModuleScope IntuneCertificateConnectorDiagnostics {
            $context = Initialize-DiagnosticContext -ConnectorType 'PFXCertificateConnector'
            $results = @(
                [pscustomobject]@{
                    Id          = 'XSS01'
                    Category    = 'Certificate'
                    Name        = '<img src=x onerror=alert(1)>'
                    Status      = 'Fail'
                    Detail      = '</style><script>alert("xss")</script>'
                    Remediation = 'a & b < c > d'
                    Case        = $false
                }
            )
            $html = ConvertTo-DiagnosticHtmlReport -Context $context -Overall 'FAIL' -Results $results `
                -GeneratedAtUtc ([datetime]::UtcNow) -Duration ([timespan]::FromSeconds(1))

            $html | Should -Not -Match '<script>'
            $html | Should -Not -Match '<img '
            $html | Should -Match '&lt;script&gt;'
            $html | Should -Match 'a &amp; b &lt; c &gt; d'
        }
    }

    It 'renders a Key=Value detail as a labeled field list' {
        InModuleScope IntuneCertificateConnectorDiagnostics {
            $html = ConvertTo-DetailHtml 'Type=PFXCertificateConnector; Product=; Subject=CN=ndes.contoso.test'

            $html | Should -Match '<dl class="fields">'
            $html | Should -Match '<dt>Type</dt><dd>PFXCertificateConnector</dd>'
            # An empty value is marked instead of rendering a blank cell.
            $html | Should -Match '<dt>Product</dt><dd class="empty">not set</dd>'
            # Only the first equals sign separates the key from the value.
            $html | Should -Match '<dt>Subject</dt><dd>CN=ndes.contoso.test</dd>'
        }
    }

    It 'keeps prose and pipe-delimited records readable instead of forcing fields' {
        InModuleScope IntuneCertificateConnectorDiagnostics {
            $events = ConvertTo-DetailHtml '2026-07-27 01:00:00Z ID=1001 Provider=Svc: first | 2026-07-27 02:00:00Z ID=2001 Provider=Svc: second'
            $mixed = ConvertTo-DetailHtml 'GET https://host/x -> HTTP 200 OK; ClientCertificate=True'
            $prose = ConvertTo-DetailHtml 'No addresses were returned.'

            # A timestamped event summary must not become a bogus key/value row.
            $events | Should -Match '<ul class="seg">'
            $events | Should -Not -Match '<dl class="fields">'
            ([regex]::Matches($events, '<li>')).Count | Should -Be 2

            $mixed | Should -Match '<p class="line">GET https://host/x -&gt; HTTP 200 OK</p>'
            $mixed | Should -Match '<dt>ClientCertificate</dt><dd>True</dd>'

            $prose | Should -Be '<p class="line">No addresses were returned.</p>'
        }
    }

    It 'turns a multi-sentence action into an ordered checklist' {
        InModuleScope IntuneCertificateConnectorDiagnostics {
            $steps = ConvertTo-ActionHtml 'A failure reproduces the connector trust error. Check roots, hostname, clock, and CRL access.'
            $single = ConvertTo-ActionHtml 'Install .NET Framework 4.7.2 or later; the connector targets .NET Framework 4.7.2.'

            $steps | Should -Match '<ol class="steps">'
            ([regex]::Matches($steps, '<li>')).Count | Should -Be 2
            # The sentence terminator removed by the split is restored.
            $steps | Should -Match '<li>A failure reproduces the connector trust error.</li>'

            # A version number must not be mistaken for a sentence boundary.
            $single | Should -Not -Match '<ol class="steps">'
            $single | Should -Match '^<p class="line">'
        }
    }

    It 'writes the HTML report and returns its path' {
        $logPath = Join-Path $TestDrive 'html-smoke.log'
        $htmlPath = Join-Path $TestDrive 'html-smoke.html'
        $report = Test-IntuneCertificateConnector `
            -SkipNdesChecks -SkipNetworkChecks -SkipEventLogChecks -SkipDynamic `
            -OutFile $logPath -HtmlReport -HtmlReportPath $htmlPath -PassThru 6>$null

        Test-Path $htmlPath | Should -BeTrue
        $report.HtmlReportPath | Should -Be $htmlPath
        (Get-Content $htmlPath -Raw) | Should -Match 'Intune Certificate Connector and NDES diagnostic'
    }

    It 'omits the HTML report unless it is requested' {
        $logPath = Join-Path $TestDrive 'no-html.log'
        $report = Test-IntuneCertificateConnector `
            -SkipNdesChecks -SkipNetworkChecks -SkipEventLogChecks -SkipDynamic `
            -OutFile $logPath -PassThru 6>$null

        $report.HtmlReportPath | Should -BeNullOrEmpty
        Test-Path ([IO.Path]::ChangeExtension($logPath, '.html')) | Should -BeFalse
    }

    It 'resolves requested Windows features without discarding the whole query' {
        InModuleScope IntuneCertificateConnectorDiagnostics {
            # ServerManager is absent on a client OS, so stand in for the cmdlet
            # that the availability probe looks for.
            function Get-WindowsFeature { param([string[]]$Name) $null = $Name }
            Mock Get-WindowsFeature {
                @(
                    [pscustomobject]@{ Name = 'Web-Server'; Installed = $true }
                    [pscustomobject]@{ Name = 'Web-WMI'; Installed = $false }
                )
            }

            $script:WindowsFeatureInventory = $null
            $script:WindowsFeatureError = $null
            try {
                $state = Get-WindowsFeatureState @('Web-Server', 'Web-WMI', 'NoSuchFeature')

                $state.Available | Should -BeTrue
                $state.Error | Should -BeNullOrEmpty
                $state.Installed | Should -Be @('Web-Server')
                $state.NotInstalled | Should -Be @('Web-WMI')
                # A name this OS never offers must not be reported as missing.
                $state.Unknown | Should -Be @('NoSuchFeature')

                # The inventory is read once per run, not once per query.
                $null = Get-WindowsFeatureState @('Web-Server')
                Should -Invoke Get-WindowsFeature -Times 1 -Exactly
            } finally {
                $script:WindowsFeatureInventory = $null
            }
        }
    }

    It 'warns instead of failing for a least-privileged connector account' {
        InModuleScope IntuneCertificateConnectorDiagnostics {
            Mock Get-ServiceDetail {
                if ($Name -ne 'PFXCertificateConnectorSvc') { return $null }
                [pscustomobject]@{
                    Name = $Name; Status = 'Running'; StartName = 'CONTOSO\svcConnector'
                    StartMode = 'Auto'; ProcessId = 4242; StartedUtc = [datetime]::UtcNow
                }
            }
            Mock Test-AccountUserRight { [pscustomobject]@{ Known = $true; HasRight = $true; Error = $null } }
            Mock Test-LocalGroupMembershipBySid {
                [pscustomobject]@{ Known = $true; IsMember = $false; GroupName = 'Administrators'; Error = $null }
            }

            $logPath = Join-Path ([IO.Path]::GetTempPath()) ("con04-lp-{0}.log" -f [guid]::NewGuid())
            try {
                $report = Test-IntuneCertificateConnector `
                    -SkipNdesChecks -SkipNetworkChecks -SkipEventLogChecks -SkipDynamic `
                    -OutFile $logPath -PassThru 6>$null

                $accounts = @($report.Results | Where-Object Id -like 'CON04:*')
                $accounts.Count | Should -Be 1
                $accounts[0].Status | Should -Be 'Warn'
                $accounts[0].Detail | Should -Match 'not a local administrator'
            } finally {
                Remove-Item $logPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'fails a connector account only when the logon right is absent and nothing runs' {
        InModuleScope IntuneCertificateConnectorDiagnostics {
            Mock Test-AccountUserRight { [pscustomobject]@{ Known = $true; HasRight = $false; Error = $null } }
            Mock Test-LocalGroupMembershipBySid {
                [pscustomobject]@{ Known = $true; IsMember = $true; GroupName = 'Administrators'; Error = $null }
            }
            $serviceStatus = 'Stopped'
            Mock Get-ServiceDetail {
                if ($Name -ne 'PFXCertificateConnectorSvc') { return $null }
                [pscustomobject]@{
                    Name = $Name; Status = $serviceStatus; StartName = 'CONTOSO\svcConnector'
                    StartMode = 'Auto'; ProcessId = 0; StartedUtc = $null
                }
            }

            $logPath = Join-Path ([IO.Path]::GetTempPath()) ("con04-fail-{0}.log" -f [guid]::NewGuid())
            try {
                $stopped = Test-IntuneCertificateConnector `
                    -SkipNdesChecks -SkipNetworkChecks -SkipEventLogChecks -SkipDynamic `
                    -OutFile $logPath -PassThru 6>$null
                @($stopped.Results | Where-Object Id -like 'CON04:*')[0].Status | Should -Be 'Fail'

                # A running service proves the right is granted through a group.
                $serviceStatus = 'Running'
                $running = Test-IntuneCertificateConnector `
                    -SkipNdesChecks -SkipNetworkChecks -SkipEventLogChecks -SkipDynamic `
                    -OutFile $logPath -PassThru 6>$null
                @($running.Results | Where-Object Id -like 'CON04:*')[0].Status | Should -Be 'Warn'
            } finally {
                Remove-Item $logPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'passes a built-in connector service account without probing rights' {
        InModuleScope IntuneCertificateConnectorDiagnostics {
            Mock Get-ServiceDetail {
                if ($Name -ne 'PFXCertificateConnectorSvc') { return $null }
                [pscustomobject]@{
                    Name = $Name; Status = 'Running'; StartName = 'LocalSystem'
                    StartMode = 'Auto'; ProcessId = 4242; StartedUtc = [datetime]::UtcNow
                }
            }
            Mock Test-AccountUserRight { throw 'secedit must not run for a built-in account' }
            Mock Test-LocalGroupMembershipBySid { throw 'group enumeration must not run for a built-in account' }

            $logPath = Join-Path ([IO.Path]::GetTempPath()) ("con04-system-{0}.log" -f [guid]::NewGuid())
            try {
                $report = Test-IntuneCertificateConnector `
                    -SkipNdesChecks -SkipNetworkChecks -SkipEventLogChecks -SkipDynamic `
                    -OutFile $logPath -PassThru 6>$null

                $accounts = @($report.Results | Where-Object Id -like 'CON04:*')
                $accounts[0].Status | Should -Be 'Pass'
                $accounts[0].Detail | Should -Match 'BuiltInAccount=True'
                Should -Invoke Test-AccountUserRight -Times 0
            } finally {
                Remove-Item $logPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'converts an unexpected runtime exception into a RUN01 report' {
        InModuleScope IntuneCertificateConnectorDiagnostics {
            Mock Get-ConnectorProduct { throw 'Simulated unexpected discovery failure' }
            $logPath = Join-Path ([IO.Path]::GetTempPath()) ("RUN01-{0}.log" -f [guid]::NewGuid())
            try {
                $report = Test-IntuneCertificateConnector `
                    -SkipNdesChecks `
                    -SkipNetworkChecks `
                    -SkipEventLogChecks `
                    -SkipDynamic `
                    -OutFile $logPath `
                    -PassThru 6>$null

                $report.Overall | Should -Be 'FAIL'
                $report.Counts.Fail | Should -BeGreaterThan 0
                @($report.Results | Where-Object Id -eq 'RUN01').Count | Should -Be 1
                Test-Path $logPath | Should -BeTrue
            } finally {
                Remove-Item $logPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'completes without pipeline objects by default' {
        $logPath = Join-Path $TestDrive 'direct-smoke.log'
        $output = @(Test-IntuneCertificateConnector `
                -SkipNdesChecks -SkipNetworkChecks -SkipEventLogChecks -SkipDynamic `
                -OutFile $logPath 6>$null)

        Test-Path $logPath | Should -BeTrue
        $output.Count | Should -Be 0
    }

    It 'returns one structured report through the public command' {
        $logPath = Join-Path $TestDrive 'report-smoke.log'
        $report = Test-IntuneCertificateConnector `
            -SkipNdesChecks -SkipNetworkChecks -SkipEventLogChecks -SkipDynamic `
            -OutFile $logPath -PassThru 6>$null

        $report.PSObject.TypeNames | Should -Contain 'Intune.CertificateConnector.DiagnosticReport'
        $report.Overall | Should -BeIn @('PASS', 'PASS-WITH-WARNINGS', 'FAIL')
        $report.Counts.Total | Should -BeGreaterThan 0
        $report.Counts.Total | Should -Be $report.Results.Count
        @($report.Results | Group-Object Id | Where-Object Count -gt 1).Count | Should -Be 0
        @($report.Results | Where-Object Status -notin @('Pass', 'Warn', 'Fail', 'Info')).Count | Should -Be 0
    }

    It 'resets diagnostic state between repeated calls' {
        $first = Test-IntuneCertificateConnector `
            -SkipNdesChecks -SkipNetworkChecks -SkipEventLogChecks -SkipDynamic `
            -OutFile (Join-Path $TestDrive 'repeat-one.log') -PassThru 6>$null
        $second = Test-IntuneCertificateConnector `
            -SkipNdesChecks -SkipNetworkChecks -SkipEventLogChecks -SkipDynamic `
            -OutFile (Join-Path $TestDrive 'repeat-two.log') -PassThru 6>$null

        $first.Counts.Total | Should -Be $second.Counts.Total
        $second.Counts.Total | Should -Be $second.Results.Count
        @($second.Results | Group-Object Id | Where-Object Count -gt 1).Count | Should -Be 0
    }

    It 'supports the compatibility alias' {
        $report = Test-CertConnectorPrereqNetwork `
            -SkipNdesChecks -SkipNetworkChecks -SkipEventLogChecks -SkipDynamic `
            -OutFile (Join-Path $TestDrive 'alias.log') -PassThru 6>$null

        $report.PSObject.TypeNames | Should -Contain 'Intune.CertificateConnector.DiagnosticReport'
    }
}
