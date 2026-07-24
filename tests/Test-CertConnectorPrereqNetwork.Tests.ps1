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
        $moduleInfo.Version | Should -Be ([Version]'2.2.0')
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
                'IisLogCount', 'PassThru'
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
