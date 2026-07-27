#Requires -Version 5.1

# Self-contained implementation for IntuneCertificateConnectorDiagnostics.
# Import IntuneCertificateConnectorDiagnostics.psd1 and invoke the exported
# Test-IntuneCertificateConnector command. Importing this module runs no checks.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'The default command contract is a color-coded direct diagnostic result.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingEmptyCatchBlock', '', Justification = 'Best-effort probes convert unavailable data into explicit diagnostic results.')]
param()

#region Module State and Constants

$script:DiagnosticRunning = $false
$script:EventLogNames = @(
    'Microsoft-Intune-CertificateConnectors/Admin',
    'Microsoft-Intune-CertificateConnectors/Operational',
    'Microsoft-AzureADConnect-AgentUpdater/Admin',
    'Application',
    'System'
)
$script:RequiredServiceNames = @(
    'EnrollmentService'
    'RAODJPlusFEGatewayService'
)

# Creates the per-invocation context that carries command options and values
# discovered by one diagnostic phase for use by later phases.
function Initialize-DiagnosticContext {
    param(
        [string]$ConnectorType,
        [string]$BaseAddress,
        [string]$OutFile,
        [switch]$SkipDynamic,
        [switch]$SkipNdesChecks,
        [switch]$SkipNetworkChecks,
        [switch]$SkipEventLogChecks,
        [int]$TimeoutSeconds,
        [int]$EventLookbackDays,
        [int]$MaxEvents,
        [int]$ConnectorStaleHours,
        [switch]$CollectLogs,
        [string]$DiagnosticBundlePath,
        [int]$IisLogCount,
        [switch]$HtmlReport,
        [string]$HtmlReportPath,
        [switch]$PassThru
    )

    return [pscustomobject]@{
        ConnectorType           = $ConnectorType
        BaseAddress             = $BaseAddress
        OutFile                 = $OutFile
        SkipDynamic             = [bool]$SkipDynamic
        SkipNdesChecks          = [bool]$SkipNdesChecks
        SkipNetworkChecks       = [bool]$SkipNetworkChecks
        SkipEventLogChecks      = [bool]$SkipEventLogChecks
        TimeoutSeconds          = $TimeoutSeconds
        EventLookbackDays       = $EventLookbackDays
        MaxEvents               = $MaxEvents
        ConnectorStaleHours     = $ConnectorStaleHours
        CollectLogs             = [bool]$CollectLogs
        DiagnosticBundlePath    = $DiagnosticBundlePath
        IisLogCount             = $IisLogCount
        HtmlReport              = [bool]$HtmlReport
        HtmlReportPath          = $HtmlReportPath
        PassThru                = [bool]$PassThru
        ConnKey                 = $null
        InstallFolder           = $null
        BaseHost                = $null
        AgentsHost              = $null
        LoginHost               = 'login.microsoftonline.com'
        LocationUrl             = $null
        Fqdn                    = $null
        ProxyServer             = $null
        ProxyPort               = $null
        ProxyUser               = $null
        ProxyResolution         = $null
        ProxyUri                = $null
        Product                 = $null
        ClientCert              = $null
        ConnectorServiceNames   = @()
        ConnectorServices       = @()
        ServiceSummary          = $null
        OperatingSystemVersion  = $null
        NdesRoleKnown           = $null
        NdesRoleInstalled       = $null
    }
}

#endregion Module State and Constants

#region Output and Formatting

# Writes a colorized console line and appends the same text to the transcript.
function Write-Line {
    param([AllowEmptyString()] [string]$Text, [string]$Color = 'Gray')

    [void]$script:Transcript.Add($Text)
    Write-Host $Text -ForegroundColor $Color
}

# Creates one structured check result, rejects duplicate IDs, stores the result,
# and renders its status, detail, and remediation to the console transcript.
function Add-Result {
    param(
        [Parameter(Mandatory = $true)] [string]$Id,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Config', 'Local', 'NDES', 'IIS', 'Certificate', 'Connector', 'Network', 'EventLog', 'Dynamic', 'Collection')]
        [string]$Category,
        [Parameter(Mandatory = $true)] [string]$Name,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Pass', 'Warn', 'Fail', 'Info')]
        [string]$Status,
        [string]$Detail = '',
        [string]$Remediation = '',
        [switch]$Case
    )

    $existing = $script:Results | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if ($existing) {
        throw "Duplicate result ID '$Id'."
    }

    $result = [pscustomobject]@{
        Id          = $Id
        Category    = $Category
        Name        = $Name
        Status      = $Status
        Detail      = $Detail
        Remediation = $Remediation
        Case        = [bool]$Case
    }
    [void]$script:Results.Add($result)

    $glyph = switch ($Status) {
        'Pass' { '[ OK ]' }
        'Warn' { '[WARN]' }
        'Fail' { '[FAIL]' }
        default { '[info]' }
    }
    $color = switch ($Status) {
        'Pass' { 'Green' }
        'Warn' { 'Yellow' }
        'Fail' { 'Red' }
        default { 'Cyan' }
    }
    $tag = if ($Case) { ' [CASE]' } else { '' }
    Write-Line ("  {0} {1,-16} {2}{3}" -f $glyph, $Id, $Name, $tag) $color
    if ($Detail) {
        Write-Line ("           {0}" -f $Detail) 'DarkGray'
    }
    if ($Status -ne 'Pass' -and $Remediation) {
        Write-Line ("           -> {0}" -f $Remediation) 'DarkGray'
    }
}

# Writes a consistently formatted heading that separates diagnostic sections.
function Write-DiagnosticSection {
    param([string]$Title)

    Write-Line ''
    Write-Line ("== {0} ==" -f $Title) 'White'
}

# Escapes text so environment-provided values such as certificate subjects,
# registry data, and event messages cannot inject markup into the HTML report.
function ConvertTo-HtmlText {
    param([AllowNull()] [AllowEmptyString()] [string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return ''
    }
    return [Net.WebUtility]::HtmlEncode($Text)
}

# Returns the stylesheet embedded in the HTML report. It is inlined so the file
# renders identically on an offline server without any external request.
function Get-DiagnosticReportStyle {
    return @(
        ':root{--pass:#0f7b0f;--warn:#9d5d00;--fail:#c50f1f;--info:#0f6cbd;--ink:#1b1a19;--muted:#605e5c;--line:#e1dfdd;--bg:#f3f2f1;--card:#ffffff}'
        '*{box-sizing:border-box}'
        'body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.55 "Segoe UI",-apple-system,Helvetica,Arial,sans-serif}'
        '.flt{position:absolute;width:1px;height:1px;margin:-1px;padding:0;border:0;clip:rect(0 0 0 0);clip-path:inset(50%);overflow:hidden;white-space:nowrap}'
        '.page{max-width:1080px;margin:0 auto;padding:28px 20px 56px}'
        'h1{margin:0 0 6px;font-size:22px}'
        'h2{font-size:16px;margin:28px 0 12px;padding-bottom:6px;border-bottom:2px solid var(--line)}'
        'h3{display:inline;font-size:14px;font-weight:600;margin:0}'
        '.meta{margin:0;color:var(--muted);font-size:12px;overflow-wrap:anywhere}'
        '.overall{margin:18px 0;padding:14px 18px;border-radius:6px;font-size:19px;font-weight:600;letter-spacing:.4px;color:#fff}'
        '.overall.pass{background:var(--pass)}'
        '.overall.warn{background:var(--warn)}'
        '.overall.fail{background:var(--fail)}'
        '.counts{display:flex;flex-wrap:wrap;gap:10px;margin:0 0 18px}'
        '.count{flex:1 1 110px;background:var(--card);border:1px solid var(--line);border-left-width:5px;border-radius:4px;padding:10px 14px}'
        '.count .n{display:block;font-size:24px;font-weight:600;line-height:1.2}'
        '.count .l{font-size:11px;color:var(--muted);text-transform:uppercase;letter-spacing:.7px}'
        '.count.fail{border-left-color:var(--fail)}.count.fail .n{color:var(--fail)}'
        '.count.warn{border-left-color:var(--warn)}.count.warn .n{color:var(--warn)}'
        '.count.pass{border-left-color:var(--pass)}.count.pass .n{color:var(--pass)}'
        '.count.info{border-left-color:var(--info)}.count.info .n{color:var(--info)}'
        '.count.total{border-left-color:var(--muted)}'
        '.badge{display:inline-block;padding:1px 8px;border-radius:10px;font-size:11px;font-weight:700;letter-spacing:.5px;color:#fff}'
        '.badge.pass{background:var(--pass)}.badge.warn{background:var(--warn)}.badge.fail{background:var(--fail)}.badge.info{background:var(--info)}'
        '.case{display:inline-block;margin-left:8px;padding:1px 7px;border:1px solid var(--warn);color:var(--warn);border-radius:10px;font-size:10px;font-weight:700}'
        '.case-note{background:#fff4ce;border:1px solid #f2d98c;border-radius:4px;padding:10px 14px;margin:0 0 18px;font-size:13px}'
        'code{font-family:Consolas,"Courier New",monospace;background:#edebe9;padding:1px 5px;border-radius:3px;font-size:12px}'
        '.plan{list-style:none;margin:0;padding:0}'
        '.plan li{background:var(--card);border:1px solid var(--line);border-left-width:5px;border-radius:4px;padding:12px 16px;margin:0 0 10px}'
        '.plan li.fail{border-left-color:var(--fail)}'
        '.plan li.warn{border-left-color:var(--warn)}'
        '.pri{display:inline-block;min-width:24px;color:var(--muted);font-weight:700}'
        '.plan .d{margin:8px 0 0;color:var(--muted);font-size:13px;overflow-wrap:anywhere}'
        '.plan .a{margin:6px 0 0;font-size:13px;overflow-wrap:anywhere}'
        '.plan .lnk{margin:6px 0 0;font-size:12px}'
        '.none{background:var(--card);border:1px solid var(--line);border-radius:4px;padding:12px 16px;margin:0}'
        '.toolbar{display:flex;flex-wrap:wrap;gap:8px;margin:0 0 14px}'
        '.toolbar label{cursor:pointer;border:1px solid var(--line);background:var(--card);border-radius:14px;padding:4px 14px;font-size:12px}'
        '.item{background:var(--card);border:1px solid var(--line);border-left-width:5px;border-radius:4px;padding:12px 16px;margin:0 0 8px}'
        '.item.s-pass{border-left-color:var(--pass)}'
        '.item.s-warn{border-left-color:var(--warn)}'
        '.item.s-fail{border-left-color:var(--fail)}'
        '.item.s-info{border-left-color:var(--info)}'
        '.item .cat{color:var(--muted);font-size:12px;margin:0 6px}'
        '.kv{margin:8px 0 0;display:grid;grid-template-columns:70px 1fr;gap:3px 12px}'
        '.kv dt{color:var(--muted);font-size:12px}'
        '.kv dd{margin:0;font-size:13px;overflow-wrap:anywhere}'
        'footer{margin-top:32px;padding-top:12px;border-top:1px solid var(--line);color:var(--muted);font-size:12px;overflow-wrap:anywhere}'
        'footer p{margin:2px 0}'
        '#flt-fail:checked ~ .page .item:not(.s-fail){display:none}'
        '#flt-warn:checked ~ .page .item:not(.s-warn){display:none}'
        '#flt-pass:checked ~ .page .item:not(.s-pass){display:none}'
        '#flt-info:checked ~ .page .item:not(.s-info){display:none}'
        '#flt-all:checked ~ .page label[for=flt-all],#flt-fail:checked ~ .page label[for=flt-fail],#flt-warn:checked ~ .page label[for=flt-warn],#flt-pass:checked ~ .page label[for=flt-pass],#flt-info:checked ~ .page label[for=flt-info]{background:var(--ink);color:#fff;border-color:var(--ink)}'
        '#flt-all:focus ~ .page label[for=flt-all],#flt-fail:focus ~ .page label[for=flt-fail],#flt-warn:focus ~ .page label[for=flt-warn],#flt-pass:focus ~ .page label[for=flt-pass],#flt-info:focus ~ .page label[for=flt-info]{outline:2px solid var(--info);outline-offset:2px}'
        '@media print{.toolbar{display:none}.item,.plan li{break-inside:avoid}}'
    ) -join "`n"
}

# Builds one self-contained HTML report that shows the overall verdict, the
# pass/warn/fail counts, a prioritized action plan, and every check result.
function ConvertTo-DiagnosticHtmlReport {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Context,
        [Parameter(Mandatory = $true)]
        [string]$Overall,
        [object[]]$Results,
        [datetime]$GeneratedAtUtc,
        [timespan]$Duration,
        [AllowEmptyString()] [string]$TranscriptPath = '',
        [AllowEmptyString()] [string]$DiagnosticBundlePath = ''
    )

    $checks = @($Results)
    $failures = @($checks | Where-Object { $_.Status -eq 'Fail' })
    $warnings = @($checks | Where-Object { $_.Status -eq 'Warn' })
    $passes = @($checks | Where-Object { $_.Status -eq 'Pass' })
    $information = @($checks | Where-Object { $_.Status -eq 'Info' })
    $caseFindings = @($checks | Where-Object { $_.Case -and $_.Status -in @('Fail', 'Warn') })

    $statusClass = @{ Pass = 'pass'; Warn = 'warn'; Fail = 'fail'; Info = 'info' }
    $overallClass = switch ($Overall) {
        'PASS' { 'pass' }
        'FAIL' { 'fail' }
        default { 'warn' }
    }
    $overallLabel = switch ($Overall) {
        'PASS' { 'PASS - no failures or warnings were reported' }
        'FAIL' { 'FAIL - action is required before the connector can work reliably' }
        default { 'PASS WITH WARNINGS - review the action plan below' }
    }

    $html = New-Object 'System.Collections.Generic.List[string]'
    $html.Add('<!DOCTYPE html>')
    $html.Add('<html lang="en">')
    $html.Add('<head>')
    $html.Add('<meta charset="utf-8">')
    $html.Add('<meta name="viewport" content="width=device-width, initial-scale=1">')
    $html.Add(('<title>{0}</title>' -f (ConvertTo-HtmlText ("Certificate Connector diagnostic - {0} - {1}" -f $env:COMPUTERNAME, $Overall))))
    $html.Add('<style>')
    $html.Add((Get-DiagnosticReportStyle))
    $html.Add('</style>')
    $html.Add('</head>')
    $html.Add('<body>')
    foreach ($filterName in @('all', 'fail', 'warn', 'pass', 'info')) {
        $checkedAttribute = if ($filterName -eq 'all') { ' checked' } else { '' }
        $html.Add(('<input type="radio" class="flt" name="statusfilter" id="flt-{0}"{1}>' -f $filterName, $checkedAttribute))
    }
    $html.Add('<div class="page">')

    $html.Add('<header>')
    $html.Add('<h1>Intune Certificate Connector and NDES diagnostic</h1>')
    $metaParts = @(
        ("Host {0}" -f $env:COMPUTERNAME)
        ("User {0}\{1}" -f $env:USERDOMAIN, $env:USERNAME)
        ("Generated {0:yyyy-MM-dd HH:mm:ss}Z" -f $GeneratedAtUtc)
        ("Duration {0:N1}s" -f $Duration.TotalSeconds)
        ("ConnectorType {0}" -f $Context.ConnectorType)
        ("Base {0}" -f $Context.BaseAddress)
    )
    $html.Add(('<p class="meta">{0}</p>' -f (ConvertTo-HtmlText ($metaParts -join '   |   '))))
    $html.Add(('<div class="overall {0}">{1}</div>' -f $overallClass, (ConvertTo-HtmlText $overallLabel)))
    $html.Add('</header>')

    $html.Add('<section class="counts">')
    foreach ($count in @(
            @{ Class = 'fail'; Label = 'Fail'; Value = $failures.Count }
            @{ Class = 'warn'; Label = 'Warn'; Value = $warnings.Count }
            @{ Class = 'pass'; Label = 'Pass'; Value = $passes.Count }
            @{ Class = 'info'; Label = 'Info'; Value = $information.Count }
            @{ Class = 'total'; Label = 'Total'; Value = $checks.Count }
        )) {
        $html.Add(('<div class="count {0}"><span class="n">{1}</span><span class="l">{2}</span></div>' -f $count.Class, $count.Value, $count.Label))
    }
    $html.Add('</section>')

    if ($caseFindings.Count -gt 0) {
        $caseText = "{0} finding(s) match incident 51000001082135: the connector service-locator call fails or stalls, and setup can then misreport Win32 1056 (an instance of the service is already running)." -f $caseFindings.Count
        $html.Add(('<p class="case-note">{0}</p>' -f (ConvertTo-HtmlText $caseText)))
    }

    $html.Add('<h2>Action plan</h2>')
    $planItems = @($failures) + @($warnings)
    if ($planItems.Count -eq 0) {
        $html.Add('<p class="none">No failures or warnings were reported, so no remediation is required. Review the informational results below to confirm the expected configuration.</p>')
    } else {
        $html.Add('<ol class="plan">')
        $priority = 0
        foreach ($item in $planItems) {
            $priority++
            $itemClass = $statusClass[[string]$item.Status]
            $anchor = 'chk-' + ([string]$item.Id -replace '[^A-Za-z0-9]', '-')
            $action = if ($item.Remediation) {
                [string]$item.Remediation
            } else {
                'Review the detail above and the matching transcript entry, then correct the reported configuration.'
            }
            $caseTag = if ($item.Case) { '<span class="case">KNOWN CASE</span>' } else { '' }
            $html.Add(('<li class="{0}">' -f $itemClass))
            $html.Add(('<div><span class="pri">{0}</span><span class="badge {1}">{2}</span> <code>{3}</code> <h3>{4}</h3>{5}</div>' -f $priority, $itemClass, (ConvertTo-HtmlText ([string]$item.Status).ToUpperInvariant()), (ConvertTo-HtmlText ([string]$item.Id)), (ConvertTo-HtmlText ([string]$item.Name)), $caseTag))
            if ($item.Detail) {
                $html.Add(('<p class="d">{0}</p>' -f (ConvertTo-HtmlText ([string]$item.Detail))))
            }
            $html.Add(('<p class="a"><strong>Action:</strong> {0}</p>' -f (ConvertTo-HtmlText $action)))
            $html.Add(('<p class="lnk"><a href="#{0}">Go to the full check result</a></p>' -f $anchor))
            $html.Add('</li>')
        }
        $html.Add('</ol>')
    }

    $html.Add('<h2>All check results</h2>')
    $html.Add('<div class="toolbar">')
    foreach ($filter in @(
            @{ Id = 'all'; Label = 'All'; Value = $checks.Count }
            @{ Id = 'fail'; Label = 'Fail'; Value = $failures.Count }
            @{ Id = 'warn'; Label = 'Warn'; Value = $warnings.Count }
            @{ Id = 'pass'; Label = 'Pass'; Value = $passes.Count }
            @{ Id = 'info'; Label = 'Info'; Value = $information.Count }
        )) {
        $html.Add(('<label for="flt-{0}">{1} ({2})</label>' -f $filter.Id, (ConvertTo-HtmlText $filter.Label), $filter.Value))
    }
    $html.Add('</div>')
    $html.Add('<section class="results">')
    foreach ($item in $checks) {
        $itemClass = $statusClass[[string]$item.Status]
        $anchor = 'chk-' + ([string]$item.Id -replace '[^A-Za-z0-9]', '-')
        $caseTag = if ($item.Case) { '<span class="case">KNOWN CASE</span>' } else { '' }
        $html.Add(('<article class="item s-{0}" id="{1}">' -f $itemClass, $anchor))
        $html.Add(('<div><span class="badge {0}">{1}</span> <code>{2}</code><span class="cat">{3}</span><h3>{4}</h3>{5}</div>' -f $itemClass, (ConvertTo-HtmlText ([string]$item.Status).ToUpperInvariant()), (ConvertTo-HtmlText ([string]$item.Id)), (ConvertTo-HtmlText ([string]$item.Category)), (ConvertTo-HtmlText ([string]$item.Name)), $caseTag))
        $html.Add('<dl class="kv">')
        if ($item.Detail) {
            $html.Add(('<dt>Detail</dt><dd>{0}</dd>' -f (ConvertTo-HtmlText ([string]$item.Detail))))
        }
        if ($item.Status -ne 'Pass' -and $item.Remediation) {
            $html.Add(('<dt>Action</dt><dd>{0}</dd>' -f (ConvertTo-HtmlText ([string]$item.Remediation))))
        }
        $html.Add('</dl>')
        $html.Add('</article>')
    }
    $html.Add('</section>')

    $html.Add('<footer>')
    if ($TranscriptPath) {
        $html.Add(('<p>Transcript: {0}</p>' -f (ConvertTo-HtmlText $TranscriptPath)))
    }
    if ($DiagnosticBundlePath) {
        $html.Add(('<p>Diagnostic bundle: {0}</p>' -f (ConvertTo-HtmlText $DiagnosticBundlePath)))
    }
    $html.Add('<p>Read-only diagnostic output. This report can contain hostnames, account names, certificate subjects, policy data, and event messages, so handle it as operational data.</p>')
    $html.Add('</footer>')

    $html.Add('</div>')
    $html.Add('</body>')
    $html.Add('</html>')

    return ($html -join "`r`n")
}

#endregion Output and Formatting

#region Diagnostic Phase Orchestration

# Converts an unexpected phase exception into a structured RUN01 failure,
# persists a fallback transcript, and returns the normal report schema when requested.
function Complete-UnhandledDiagnosticFailure {
    param(
        [psobject]$Context,
        [Management.Automation.ErrorRecord]$ErrorRecord,
        [bool]$PassThru,
        [string]$RequestedOutFile
    )

    if ($null -eq $script:Results) {
        $script:Results = New-Object System.Collections.Generic.List[object]
    }
    if ($null -eq $script:Transcript) {
        $script:Transcript = New-Object System.Collections.Generic.List[string]
    }

    $exception = $ErrorRecord.Exception
    $detail = if ($exception) {
        "Unexpected $($exception.GetType().FullName): $($exception.Message)"
    } else {
        "Unexpected diagnostic failure: $ErrorRecord"
    }
    if (-not ($script:Results | Where-Object Id -eq 'RUN01')) {
        Add-Result -Id 'RUN01' -Category Local -Name 'Unexpected diagnostic runtime failure' -Status 'Fail' `
            -Detail $detail `
            -Remediation 'Review the transcript, rerun from an elevated Windows PowerShell session, and report the RUN01 detail if the failure persists.'
    }

    $outFile = if ($Context -and $Context.OutFile) { $Context.OutFile } else { $RequestedOutFile }
    if (-not $outFile) {
        $fallbackDirectory = Join-Path ([IO.Path]::GetTempPath()) 'IntuneCertificateConnectorDiagnostics'
        try { $null = New-Item -ItemType Directory -Path $fallbackDirectory -Force -ErrorAction Stop } catch {}
        $outFile = Join-Path $fallbackDirectory ("UnexpectedFailure-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
    }
    Write-Line "  OVERALL: FAIL (RUN01)" 'Red'
    Write-Line "  Transcript target: $outFile" 'Cyan'
    try {
        $fallbackHeader = @(
            'Intune Certificate Connector and NDES diagnostic - unexpected failure',
            "Host=$env:COMPUTERNAME Date=$(Get-Date -Format o)",
            $detail,
            ''
        )
        Set-Content -Path $outFile -Value ($fallbackHeader + $script:Transcript) -Encoding UTF8 -ErrorAction Stop
    } catch {}

    if ($PassThru) {
        $completedAtUtc = (Get-Date).ToUniversalTime()
        $startedAtUtc = if ($script:StartedAtUtc) { $script:StartedAtUtc } else { $completedAtUtc }
        $passes = @($script:Results | Where-Object Status -eq 'Pass')
        $warnings = @($script:Results | Where-Object Status -eq 'Warn')
        $failures = @($script:Results | Where-Object Status -eq 'Fail')
        $information = @($script:Results | Where-Object Status -eq 'Info')
        Write-Output ([pscustomobject]@{
                PSTypeName           = 'Intune.CertificateConnector.DiagnosticReport'
                Overall              = 'FAIL'
                ComputerName         = $env:COMPUTERNAME
                GeneratedAtUtc       = $completedAtUtc
                Duration             = $completedAtUtc - $startedAtUtc
                Counts               = [pscustomobject]@{
                    Pass  = $passes.Count
                    Warn  = $warnings.Count
                    Fail  = $failures.Count
                    Info  = $information.Count
                    Total = $script:Results.Count
                }
                TranscriptPath       = $outFile
                DiagnosticBundlePath = $null
                HtmlReportPath       = $null
                Results              = $script:Results.ToArray()
            })
    }
}

# Runs event-log checks and optional evidence collection, calculates the final
# status, writes the transcript/bundle, and optionally returns the report object.
function Invoke-Finalization {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Context
    )

    $ConnectorType = $Context.ConnectorType
    $BaseAddress = $Context.BaseAddress
    $OutFile = $Context.OutFile
    $SkipDynamic = $Context.SkipDynamic
    $SkipNdesChecks = $Context.SkipNdesChecks
    $SkipNetworkChecks = $Context.SkipNetworkChecks
    $SkipEventLogChecks = $Context.SkipEventLogChecks
    $EventLookbackDays = $Context.EventLookbackDays
    $MaxEvents = $Context.MaxEvents
    $CollectLogs = $Context.CollectLogs
    $DiagnosticBundlePath = $Context.DiagnosticBundlePath
    $IisLogCount = $Context.IisLogCount
    $HtmlReport = $Context.HtmlReport
    $HtmlReportPath = $Context.HtmlReportPath
    $PassThru = $Context.PassThru
    $connectorServiceNames = $Context.ConnectorServiceNames

#region Event Log Validation

Write-DiagnosticSection 'Recent Certificate Connector and NDES event logs'
if ($SkipEventLogChecks) {
    Add-Result -Id 'EVT00' -Category EventLog -Name 'Recent event-log analysis' -Status 'Info' `
        -Detail 'Skipped with -SkipEventLogChecks.'
} elseif (-not (Get-Command Get-WinEvent -ErrorAction SilentlyContinue)) {
    Add-Result -Id 'EVT00' -Category EventLog -Name 'Recent event-log analysis' -Status 'Warn' `
        -Detail 'Get-WinEvent is unavailable.' `
        -Remediation 'Run this diagnostic in Windows PowerShell on the connector server.'
} else {
    $eventStartTime = (Get-Date).AddDays(-$EventLookbackDays)

    if (Test-EventLog 'Microsoft-Intune-CertificateConnectors/Admin') {
        $adminEvents = @()
        try {
            $adminEvents = @(Get-WinEvent -FilterHashtable @{
                    LogName   = 'Microsoft-Intune-CertificateConnectors/Admin'
                    StartTime = $eventStartTime
                    Id        = @(1001, 1201, 2001, 3001, 4001, 4002)
                } -MaxEvents $MaxEvents -ErrorAction Stop)
        } catch {}
        Add-Result -Id 'EVT01' -Category EventLog -Name 'Certificate Connector Admin failures' `
            -Status $(if ($adminEvents.Count -eq 0) { 'Pass' } else { 'Warn' }) `
            -Detail $(if ($adminEvents.Count -eq 0) { "No known failure event IDs in the last $EventLookbackDays day(s)." } else { Format-EventSummary $adminEvents }) `
            -Remediation 'Investigate the reported request failures in Event Viewer and correlate them with the local and network checks.'
    } else {
        Add-Result -Id 'EVT01' -Category EventLog -Name 'Certificate Connector Admin failures' -Status 'Info' `
            -Detail 'The Certificate Connector Admin event channel is unavailable.'
    }

    if (Test-EventLog 'Microsoft-Intune-CertificateConnectors/Operational') {
        $operationalEvents = @()
        try {
            $operationalEvents = @(Get-WinEvent -FilterHashtable @{
                    LogName   = 'Microsoft-Intune-CertificateConnectors/Operational'
                    StartTime = $eventStartTime
                    Level     = @(2, 3)
                } -MaxEvents $MaxEvents -ErrorAction Stop)
        } catch {}
        Add-Result -Id 'EVT02' -Category EventLog -Name 'Certificate Connector Operational errors and warnings' `
            -Status $(if ($operationalEvents.Count -eq 0) { 'Pass' } else { 'Warn' }) `
            -Detail $(if ($operationalEvents.Count -eq 0) { "No Level 2/3 events in the last $EventLookbackDays day(s)." } else { Format-EventSummary $operationalEvents }) `
            -Remediation 'Use the Operational log details to diagnose connector transport, issuance, revocation, SCEP, and health failures.'
    } else {
        Add-Result -Id 'EVT02' -Category EventLog -Name 'Certificate Connector Operational errors and warnings' -Status 'Info' `
            -Detail 'The Certificate Connector Operational event channel is unavailable.'
    }

    if (Test-EventLog 'Microsoft-AzureADConnect-AgentUpdater/Admin') {
        $updaterEvents = @()
        try {
            $updaterEvents = @(Get-WinEvent -FilterHashtable @{
                    LogName   = 'Microsoft-AzureADConnect-AgentUpdater/Admin'
                    StartTime = $eventStartTime
                    Level     = @(2, 3)
                } -MaxEvents $MaxEvents -ErrorAction Stop)
        } catch {}
        Add-Result -Id 'EVT03' -Category EventLog -Name 'Connector updater errors and warnings' `
            -Status $(if ($updaterEvents.Count -eq 0) { 'Pass' } else { 'Warn' }) `
            -Detail $(if ($updaterEvents.Count -eq 0) { "No Level 2/3 updater events in the last $EventLookbackDays day(s)." } else { Format-EventSummary $updaterEvents }) `
            -Remediation 'Resolve updater errors and confirm NET10 can reach the Azure update service.'
    } else {
        Add-Result -Id 'EVT03' -Category EventLog -Name 'Connector updater errors and warnings' -Status 'Info' `
            -Detail 'The Azure AD Connect Agent Updater Admin event channel is unavailable.'
    }

    $applicationEvents = @()
    try {
        $applicationCandidates = @(Get-WinEvent -FilterHashtable @{
                LogName   = 'Application'
                StartTime = $eventStartTime
                Level     = 2
            } -MaxEvents ([Math]::Max(200, $MaxEvents * 50)) -ErrorAction Stop)
        $applicationEvents = @($applicationCandidates |
                Where-Object { $_.ProviderName -match 'PKICertificateConnectorSvc|PFXCertificateConnectorSvc|PkiRevokeConnectorSvc|NetworkDeviceEnrollmentService' } |
                Select-Object -First $MaxEvents)
    } catch {}
    Add-Result -Id 'EVT04' -Category EventLog -Name 'NDES and Connector Application errors' `
        -Status $(if ($applicationEvents.Count -eq 0) { 'Pass' } else { 'Warn' }) `
        -Detail $(if ($applicationEvents.Count -eq 0) { "No matching Application errors in the last $EventLookbackDays day(s)." } else { Format-EventSummary $applicationEvents }) `
        -Remediation 'Investigate matching NDES and Certificate Connector provider errors in the Application log.'

    $systemEvents = @()
    try {
        $systemCandidates = @(Get-WinEvent -FilterHashtable @{
                LogName   = 'System'
                StartTime = $eventStartTime
                Level     = @(2, 3)
            } -MaxEvents ([Math]::Max(200, $MaxEvents * 50)) -ErrorAction Stop)
        $servicePattern = ($connectorServiceNames + @('W3SVC', 'Network Device Enrollment Service', 'SCEP')) -join '|'
        $systemEvents = @($systemCandidates |
                Where-Object { $_.ProviderName -eq 'Service Control Manager' -and $_.Message -match $servicePattern } |
                Select-Object -First $MaxEvents)
    } catch {}
    Add-Result -Id 'EVT05' -Category EventLog -Name 'Relevant Service Control Manager errors and warnings' `
        -Status $(if ($systemEvents.Count -eq 0) { 'Pass' } else { 'Warn' }) `
        -Detail $(if ($systemEvents.Count -eq 0) { "No matching System events in the last $EventLookbackDays day(s)." } else { Format-EventSummary $systemEvents }) `
        -Remediation 'Investigate service startup, timeout, identity, and dependency failures in the System log.'
}

#endregion Event Log Validation

#region Evidence Collection

Write-DiagnosticSection 'Diagnostic evidence collection'
if ($CollectLogs) {
    $collection = Initialize-DiagnosticCollection -RequestedPath $DiagnosticBundlePath -RecentIisLogCount $IisLogCount
    $script:BundleStage = $collection.Stage
    $script:BundleTarget = $collection.Target
    Add-Result -Id 'COL01' -Category Collection -Name 'Diagnostic evidence prepared' `
        -Status $(if (-not $collection.Success) { 'Fail' } elseif ($collection.Warnings.Count -gt 0) { 'Warn' } else { 'Pass' }) `
        -Detail ("Artifacts={0}; Target={1}; Warnings={2}; Error={3}" -f $collection.Count, $collection.Target, ($collection.Warnings -join ' | '), $collection.Error) `
        -Remediation 'Run elevated and verify IIS/event-log/GPResult access. The ZIP is local only and can contain sensitive operational data.'
} else {
    Add-Result -Id 'COL01' -Category Collection -Name 'Diagnostic evidence prepared' -Status 'Info' `
        -Detail 'Not requested. Specify -CollectLogs to create a local ZIP.'
}

#endregion Evidence Collection

#region Summary and Output

Write-DiagnosticSection 'Summary'
$passes = @($script:Results | Where-Object { $_.Status -eq 'Pass' })
$warnings = @($script:Results | Where-Object { $_.Status -eq 'Warn' })
$failures = @($script:Results | Where-Object { $_.Status -eq 'Fail' })
$information = @($script:Results | Where-Object { $_.Status -eq 'Info' })
$caseFailures = @($failures | Where-Object { $_.Case })

Write-Line ("  Pass={0}  Warn={1}  Fail={2}  Info={3}  Total={4}" -f $passes.Count, $warnings.Count, $failures.Count, $information.Count, $script:Results.Count) 'White'
if ($failures.Count -gt 0) {
    Write-Line '  Failures:' 'Red'
    foreach ($failure in $failures) {
        Write-Line ("    - {0} {1}: {2}" -f $failure.Id, $failure.Name, $failure.Detail) 'Red'
    }
}
if ($warnings.Count -gt 0) {
    Write-Line '  Warnings:' 'Yellow'
    foreach ($warning in $warnings) {
        Write-Line ("    - {0} {1}: {2}" -f $warning.Id, $warning.Name, $warning.Detail) 'Yellow'
    }
}
if ($caseFailures.Count -gt 0) {
    Write-Line ''
    Write-Line '  One or more failures match incident 51000001082135:' 'Yellow'
    Write-Line '    the connector service-locator call fails or stalls, and setup can then' 'Yellow'
    Write-Line '    misreport Win32 1056 (an instance of the service is already running).' 'Yellow'
}

$overall = if ($failures.Count -gt 0) {
    'FAIL'
} elseif ($warnings.Count -gt 0) {
    'PASS-WITH-WARNINGS'
} else {
    'PASS'
}
Write-Line ("  OVERALL: {0}" -f $overall) $(if ($overall -eq 'FAIL') { 'Red' } elseif ($overall -eq 'PASS') { 'Green' } else { 'Yellow' })

# ---------------------------------------------------------------------------
# Transcript output
# ---------------------------------------------------------------------------
if (-not $OutFile) {
    $defaultDirectory = Join-Path $env:ProgramData 'Microsoft\IntuneCertificateConnector\Configuration'
    try {
        $null = New-Item -ItemType Directory -Path $defaultDirectory -Force -ErrorAction Stop
    } catch {
        $defaultDirectory = [IO.Path]::GetTempPath()
    }
    $OutFile = Join-Path $defaultDirectory ("PrereqNetworkDiagnostic-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
} else {
    $outParent = Split-Path -Parent $OutFile
    if ($outParent) {
        try { $null = New-Item -ItemType Directory -Path $outParent -Force -ErrorAction Stop } catch {}
    }
}
$Context.OutFile = $OutFile

Write-Line ''
Write-Line "  Transcript target: $OutFile" 'Cyan'
$transcriptHeader = @(
    'Intune Certificate Connector and NDES complete pre-flight diagnostic',
    "Host=$env:COMPUTERNAME User=$env:USERDOMAIN\$env:USERNAME Date=$(Get-Date -Format o)",
    "ConnectorType=$ConnectorType Base=$BaseAddress Overall=$overall",
    "SkipNdesChecks=$SkipNdesChecks SkipNetworkChecks=$SkipNetworkChecks SkipEventLogChecks=$SkipEventLogChecks SkipDynamic=$SkipDynamic",
    ''
)
$transcriptWritten = $false
try {
    Set-Content -Path $OutFile -Value ($transcriptHeader + $script:Transcript) -Encoding UTF8 -ErrorAction Stop
    $transcriptWritten = $true
} catch {
    Write-Line "  Could not write transcript: $($_.Exception.Message)" 'Yellow'
}

# Optional HTML report. It is produced before the ZIP so the archive can carry it.
$htmlWrittenPath = $null
if ($HtmlReport) {
    $htmlTarget = $HtmlReportPath
    if ([string]::IsNullOrWhiteSpace($htmlTarget)) {
        $htmlTarget = [IO.Path]::ChangeExtension($OutFile, '.html')
    } elseif ([IO.Path]::GetExtension($htmlTarget) -notin @('.html', '.htm')) {
        $htmlTarget = "$htmlTarget.html"
    }
    $htmlParent = Split-Path -Parent $htmlTarget
    if ($htmlParent) {
        try { $null = New-Item -ItemType Directory -Path $htmlParent -Force -ErrorAction Stop } catch {}
    }
    try {
        $htmlContent = ConvertTo-DiagnosticHtmlReport `
            -Context $Context `
            -Overall $overall `
            -Results $script:Results.ToArray() `
            -GeneratedAtUtc ((Get-Date).ToUniversalTime()) `
            -Duration ((Get-Date).ToUniversalTime() - $script:StartedAtUtc) `
            -TranscriptPath $(if ($transcriptWritten) { $OutFile } else { '' }) `
            -DiagnosticBundlePath $(if ($CollectLogs) { [string]$script:BundleTarget } else { '' })
        Set-Content -Path $htmlTarget -Value $htmlContent -Encoding UTF8 -ErrorAction Stop
        $htmlWrittenPath = $htmlTarget
        Write-Line "  HTML report: $htmlTarget" 'Cyan'
        if ($CollectLogs -and $script:BundleStage -and (Test-Path $script:BundleStage)) {
            try {
                Copy-Item -Path $htmlTarget -Destination (Join-Path $script:BundleStage 'DiagnosticReport.html') -Force -ErrorAction Stop
            } catch {}
        }
    } catch {
        Write-Line "  Could not write the HTML report: $($_.Exception.Message)" 'Yellow'
    }
}

# Finalize the optional ZIP only after the transcript exists.
if ($CollectLogs -and $script:BundleStage -and (Test-Path $script:BundleStage)) {
    try {
        if ($transcriptWritten) {
            Copy-Item -Path $OutFile -Destination (Join-Path $script:BundleStage 'PrereqNetworkDiagnostic.log') -Force -ErrorAction Stop
        }
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        if (Test-Path $script:BundleTarget) { Remove-Item -Path $script:BundleTarget -Force -ErrorAction Stop }
        [IO.Compression.ZipFile]::CreateFromDirectory($script:BundleStage, $script:BundleTarget)
        Write-Line "  Diagnostic bundle written: $script:BundleTarget" 'Cyan'
    } catch {
        Write-Line "  Could not create diagnostic bundle: $($_.Exception.Message)" 'Yellow'
    } finally {
        Remove-Item -Path $script:BundleStage -Recurse -Force -ErrorAction SilentlyContinue
    }
} elseif ($script:BundleStage -and (Test-Path $script:BundleStage)) {
    Remove-Item -Path $script:BundleStage -Recurse -Force -ErrorAction SilentlyContinue
}

# Rewrite the transcript so it also records the HTML report and bundle outcome.
if ($transcriptWritten) {
    try { Set-Content -Path $OutFile -Value ($transcriptHeader + $script:Transcript) -Encoding UTF8 -ErrorAction Stop } catch {}
}

# Return one structured report only when explicitly requested. A normal one-time
# run ends with the direct summary above and doesn't dump every check object.
if ($PassThru) {
    $completedAtUtc = (Get-Date).ToUniversalTime()
    $report = [pscustomobject]@{
        PSTypeName           = 'Intune.CertificateConnector.DiagnosticReport'
        Overall              = $overall
        ComputerName         = $env:COMPUTERNAME
        GeneratedAtUtc       = $completedAtUtc
        Duration             = $completedAtUtc - $script:StartedAtUtc
        Counts               = [pscustomobject]@{
            Pass  = $passes.Count
            Warn  = $warnings.Count
            Fail  = $failures.Count
            Info  = $information.Count
            Total = $script:Results.Count
        }
        TranscriptPath       = if ($transcriptWritten) { $OutFile } else { $null }
        DiagnosticBundlePath = if ($script:BundleTarget -and (Test-Path $script:BundleTarget)) { $script:BundleTarget } else { $null }
        HtmlReportPath       = $htmlWrittenPath
        Results              = $script:Results.ToArray()
    }
    Write-Output $report
}

#endregion Summary and Output

}

# Runs proxy, DNS, transport, TLS, revocation, service-locator, updater, internal
# NDES endpoint, and installed connector-assembly validation from explicit context.
function Invoke-NetworkAndDynamicValidation {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Context
    )

    $agentsHost = $Context.AgentsHost
    $baseHost = $Context.BaseHost
    $clientCert = $Context.ClientCert
    $installFolder = $Context.InstallFolder
    $locationUrl = $Context.LocationUrl
    $proxyPort = $Context.ProxyPort
    $proxyResolution = $Context.ProxyResolution
    $proxyServer = $Context.ProxyServer
    $proxyUri = $Context.ProxyUri
    $proxyUser = $Context.ProxyUser
    $SkipDynamic = $Context.SkipDynamic
    $SkipNdesChecks = $Context.SkipNdesChecks
    $SkipNetworkChecks = $Context.SkipNetworkChecks
    $TimeoutSeconds = $Context.TimeoutSeconds

#region Network Prerequisites

Write-DiagnosticSection 'Network prerequisites'

if ($SkipNetworkChecks) {
    Add-Result -Id 'NET00' -Category Network -Name 'External network validation' -Status 'Info' `
        -Detail 'Skipped with -SkipNetworkChecks.'
} else {
    if ($proxyServer) {
        Add-Result -Id 'NET01' -Category Network -Name 'Proxy address is well formed' `
            -Status $(if ($proxyResolution.Valid) { 'Pass' } else { 'Fail' }) -Case `
            -Detail $(if ($proxyResolution.Valid) { "Parsed proxy=$($proxyUri.AbsoluteUri)" } else { "Configured proxy '$proxyServer' with port '$proxyPort' is invalid: $($proxyResolution.Error)" }) `
            -Remediation 'Use an absolute http:// or https:// proxy URI. A missing scheme can cause the connector to ignore the proxy.'
    } else {
        Add-Result -Id 'NET01' -Category Network -Name 'Proxy address is well formed' -Status 'Info' `
            -Detail 'No connector proxy is configured.'
    }

    if ($proxyServer) {
        Add-Result -Id 'NET02' -Category Network -Name 'Proxy is unauthenticated' `
            -Status $(if ([string]::IsNullOrEmpty($proxyUser)) { 'Pass' } else { 'Fail' }) -Case `
            -Detail $(if ([string]::IsNullOrEmpty($proxyUser)) { 'No proxy Username is configured.' } else { "Proxy Username '$proxyUser' is configured." }) `
            -Remediation 'Provide unauthenticated proxy access for the connector endpoints. NET05 also detects a live HTTP 407 response.'
    } else {
        Add-Result -Id 'NET02' -Category Network -Name 'Proxy is unauthenticated' -Status 'Info' `
            -Detail 'No connector proxy is configured.'
    }

    $dnsTargets = @($baseHost, $agentsHost, $Context.LoginHost)
    if ($proxyUri) { $dnsTargets += $proxyUri.Host }
    foreach ($dnsHost in @($dnsTargets | Select-Object -Unique)) {
        $addresses = $null
        try {
            $addresses = @([Net.Dns]::GetHostAddresses($dnsHost) | ForEach-Object { $_.IPAddressToString })
        } catch {}
        Add-Result -Id ("NET03:{0}" -f $dnsHost) -Category Network -Name "DNS resolves $dnsHost" `
            -Status $(if ($addresses.Count -gt 0) { 'Pass' } else { 'Fail' }) -Case `
            -Detail $(if ($addresses.Count -gt 0) { $addresses -join ', ' } else { 'No addresses were returned.' }) `
            -Remediation 'Ensure DNS resolution works for connector endpoints and for the configured proxy host.'
    }

    if ($proxyUri) {
        $proxyConnection = Connect-Tls443 -TargetHost $proxyUri.Host -Port $proxyUri.Port -TimeoutMs ($TimeoutSeconds * 1000)
        if ($proxyConnection.Tcp) { $proxyConnection.Tcp.Close() }
        Add-Result -Id 'NET04' -Category Network -Name 'TCP connection to proxy' `
            -Status $(if ($proxyConnection.Ok) { 'Pass' } else { 'Fail' }) -Case `
            -Detail $(if ($proxyConnection.Ok) { "Connected to $($proxyUri.Host):$($proxyUri.Port)." } else { $proxyConnection.Error }) `
            -Remediation 'Allow the connector server to reach the configured proxy host and port.'
    } else {
        Add-Result -Id 'NET04' -Category Network -Name 'TCP connection to proxy' -Status 'Info' `
            -Detail 'No valid connector proxy is configured; direct transport will be tested.'
    }

    $tlsConnection = Connect-Tls443 -TargetHost $agentsHost -Port 443 -ProxyUri $proxyUri -TimeoutMs ($TimeoutSeconds * 1000)
    if ($proxyUri) {
        $proxyAuthenticationRequired = $tlsConnection.ProxyStatus -match ' 407 '
        Add-Result -Id 'NET05' -Category Network -Name 'Proxy CONNECT tunnel to agents endpoint' `
            -Status $(if ($tlsConnection.Ok) { 'Pass' } else { 'Fail' }) -Case `
            -Detail $(if ($tlsConnection.ProxyStatus) { "Proxy response=$($tlsConnection.ProxyStatus)" } else { $tlsConnection.Error }) `
            -Remediation $(if ($proxyAuthenticationRequired) { 'The proxy returned 407. Permit unauthenticated access for the connector server.' } else { "Allow HTTP CONNECT to $agentsHost`:443." })
    } else {
        Add-Result -Id 'NET05' -Category Network -Name 'Proxy CONNECT tunnel to agents endpoint' -Status 'Info' `
            -Detail 'No valid connector proxy is configured; using direct transport.'
    }

    Add-Result -Id 'NET06' -Category Network -Name 'Agents endpoint reachable on TCP 443' `
        -Status $(if ($tlsConnection.Ok) { 'Pass' } else { 'Fail' }) -Case `
        -Detail $(if ($tlsConnection.Ok) { "Transport to $agentsHost`:443 established$(if ($proxyUri) { ' through the connector proxy' } else { ' directly' })." } else { $tlsConnection.Error }) `
        -Remediation 'Allow outbound TCP 443 to the Intune endpoints directly or through the configured connector proxy.'

    $revocationUrls = @()
    $net07ChainOk = $false
    $net07RevocationProblem = $false
    if ($tlsConnection.Ok -and $tlsConnection.Stream) {
        $script:capturedCertificateBytes = $null
        $script:capturedPolicyErrors = [Net.Security.SslPolicyErrors]::None
        $certificateCallback = [Net.Security.RemoteCertificateValidationCallback] {
            param($callbackSource, $certificate, $handshakeChain, $policyErrors)
            $null = $callbackSource
            $null = $handshakeChain
            if ($certificate) { $script:capturedCertificateBytes = $certificate.GetRawCertData() }
            $script:capturedPolicyErrors = $policyErrors
            return $true
        }
        $sslStream = $null
        try {
            $sslStream = New-Object Net.Security.SslStream($tlsConnection.Stream, $false, $certificateCallback)
            $sslStream.ReadTimeout = $TimeoutSeconds * 1000
            $sslStream.WriteTimeout = $TimeoutSeconds * 1000
            $sslStream.AuthenticateAsClient($agentsHost, $null, [Net.SecurityProtocolType]::Tls12, $false)
            if (-not $script:capturedCertificateBytes -and $sslStream.RemoteCertificate) {
                $script:capturedCertificateBytes = $sslStream.RemoteCertificate.GetRawCertData()
            }
            if (-not $script:capturedCertificateBytes) { throw 'The server certificate was not captured during the TLS handshake.' }

            $serverCertificate = New-Object Security.Cryptography.X509Certificates.X509Certificate2 (, [byte[]]$script:capturedCertificateBytes)
            $issuer = $serverCertificate.Issuer
            $expectedIssuer = $issuer -match 'Microsoft|DigiCert|Baltimore'
            $chain = New-Object Security.Cryptography.X509Certificates.X509Chain
            $chain.ChainPolicy.RevocationMode = [Security.Cryptography.X509Certificates.X509RevocationMode]::Online
            $chain.ChainPolicy.RevocationFlag = [Security.Cryptography.X509Certificates.X509RevocationFlag]::EntireChain
            $chain.ChainPolicy.UrlRetrievalTimeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
            $chainBuilt = $chain.Build($serverCertificate)
            $chainStatus = @($chain.ChainStatus | ForEach-Object { $_.Status.ToString() }) -join ','
            if (-not $chainStatus) { $chainStatus = 'OK' }
            $nameMismatch = ($script:capturedPolicyErrors -band [Net.Security.SslPolicyErrors]::RemoteCertificateNameMismatch) -ne 0
            $trusted = $chainBuilt -and -not $nameMismatch
            $net07ChainOk = $trusted
            $net07RevocationProblem = $chainStatus -match 'Revocation|Offline'

            foreach ($chainElement in $chain.ChainElements) {
                foreach ($extension in $chainElement.Certificate.Extensions) {
                    if ($extension.Oid.Value -in @('1.3.6.1.5.5.7.1.1', '2.5.29.31')) {
                        $formatted = $extension.Format($true)
                        [regex]::Matches($formatted, 'https?://[^\s\)\]]+') | ForEach-Object {
                            $revocationUrls += $_.Value.TrimEnd(')', ',', ' ', '.')
                        }
                    }
                }
            }
            $revocationUrls = @($revocationUrls | Select-Object -Unique)

            Add-Result -Id 'NET07' -Category Network -Name 'Server certificate chain and hostname are trusted' `
                -Status $(if ($trusted) { 'Pass' } else { 'Fail' }) -Case `
                -Detail ("Subject={0}; Issuer={1}; PolicyErrors={2}; ChainStatus={3}" -f $serverCertificate.Subject, $issuer, $script:capturedPolicyErrors, $chainStatus) `
                -Remediation 'A failure reproduces the connector trust error. Check roots, hostname, clock, SSL inspection, and CRL/OCSP access.'
            Add-Result -Id 'NET07b' -Category Network -Name 'No unexpected TLS interception issuer' `
                -Status $(if ($expectedIssuer) { 'Pass' } else { 'Fail' }) -Case `
                -Detail "Presented issuer=$issuer" `
                -Remediation 'A non-Microsoft/DigiCert issuer indicates likely TLS inspection. Bypass TLS inspection for Intune service endpoints.'
        } catch {
            $exception = $_.Exception
            $inner = $exception
            while ($inner.InnerException) { $inner = $inner.InnerException }
            Add-Result -Id 'NET07' -Category Network -Name 'TLS 1.2 handshake and server certificate trust' -Status 'Fail' -Case `
                -Detail ("{0}: {1}" -f $exception.GetType().Name, $inner.Message) `
                -Remediation 'Resolve transport, proxy, trust, TLS interception, root certificate, revocation, or clock problems before starting the connector.'
            Add-Result -Id 'NET07b' -Category Network -Name 'No unexpected TLS interception issuer' -Status 'Info' `
                -Detail 'The server certificate was unavailable because the TLS validation did not complete.'
        } finally {
            if ($sslStream) { $sslStream.Dispose() }
        }
    } else {
        Add-Result -Id 'NET07' -Category Network -Name 'TLS 1.2 handshake and server certificate trust' -Status 'Fail' -Case `
            -Detail 'Transport was not established; NET05/NET06 must be resolved first.'
        Add-Result -Id 'NET07b' -Category Network -Name 'No unexpected TLS interception issuer' -Status 'Info' `
            -Detail 'No server certificate was available.'
    }
    if ($tlsConnection.Tcp) { $tlsConnection.Tcp.Close() }

    if ($revocationUrls.Count -gt 0) {
        $revocationHosts = @{}
        foreach ($revocationUrl in $revocationUrls) {
            try {
                $revocationUri = [Uri]$revocationUrl
                $key = "{0}:{1}" -f $revocationUri.Host, $revocationUri.Port
                if (-not $revocationHosts.ContainsKey($key)) {
                    $revocationHosts[$key] = @{ Host = $revocationUri.Host; Port = $revocationUri.Port }
                }
            } catch {}
        }
        $unreachableRevocationHosts = @()
        foreach ($key in $revocationHosts.Keys) {
            $target = $revocationHosts[$key]
            $tcp = $null
            $reachable = $false
            try {
                $tcp = New-Object Net.Sockets.TcpClient
                $async = $tcp.BeginConnect($target.Host, $target.Port, $null, $null)
                if ($async.AsyncWaitHandle.WaitOne([Math]::Min($TimeoutSeconds, 10) * 1000)) {
                    $tcp.EndConnect($async)
                    $reachable = $true
                }
            } catch {} finally {
                if ($tcp) { $tcp.Close() }
            }
            if (-not $reachable) { $unreachableRevocationHosts += $key }
        }
        $revocationStatus = if ($unreachableRevocationHosts.Count -eq 0) {
            'Pass'
        } elseif ($net07ChainOk -and -not $net07RevocationProblem) {
            'Warn'
        } else {
            'Fail'
        }
        Add-Result -Id 'NET08' -Category Network -Name 'Live-chain CRL and OCSP hosts are reachable' -Status $revocationStatus -Case `
            -Detail $(if ($unreachableRevocationHosts.Count -eq 0) { "Reachable=$($revocationHosts.Keys -join ', ')" } else { "Unreachable=$($unreachableRevocationHosts -join ', '); NET07ChainTrusted=$net07ChainOk" }) `
            -Remediation 'Permit the CRL/OCSP hosts extracted from the live chain. The connector enables online certificate revocation checking.'
    } else {
        Add-Result -Id 'NET08' -Category Network -Name 'Live-chain CRL and OCSP hosts are reachable' -Status 'Info' `
            -Detail 'No revocation URLs were extracted because a usable live chain was unavailable.'
    }

    $systemHttpAvailable = $false
    try { Add-Type -AssemblyName System.Net.Http -ErrorAction Stop; $systemHttpAvailable = $true } catch {}
    if ($systemHttpAvailable) {
        $httpHandler = New-Object Net.Http.HttpClientHandler
        try { $httpHandler.CheckCertificateRevocationList = $true } catch {}
        if ($clientCert) {
            try {
                $httpHandler.ClientCertificateOptions = [Net.Http.ClientCertificateOption]::Manual
                [void]$httpHandler.ClientCertificates.Add($clientCert)
            } catch {}
        }
        if ($proxyUri) {
            $httpHandler.Proxy = New-Object Net.WebProxy($proxyUri, $false)
            $httpHandler.UseProxy = $true
        }
        # Restored by the public command so the diagnostic never leaves the
        # caller's process-wide TLS configuration modified.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $httpClient = New-Object Net.Http.HttpClient($httpHandler)
        $httpClient.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
        $locationResponse = $null
        try {
            $locationResponse = $httpClient.GetAsync($locationUrl).GetAwaiter().GetResult()
            $locationStatus = [int]$locationResponse.StatusCode
            $locationContent = $locationResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $locationAssessment = Get-ServiceLocatorHttpAssessment `
                -StatusCode $locationStatus `
                -ClientCertificatePresented ($null -ne $clientCert) `
                -Content $locationContent
            $foundServiceText = if ($locationAssessment.FoundServices.Count) {
                $locationAssessment.FoundServices -join ', '
            } else {
                '<none>'
            }
            $missingServiceText = if ($locationAssessment.MissingServices.Count) {
                $locationAssessment.MissingServices -join ', '
            } else {
                '<none>'
            }
            Add-Result -Id 'NET09' -Category Network -Name 'Connector service-locator HTTP call' `
                -Status $locationAssessment.Status -Case `
                -Detail "GET $locationUrl -> HTTP $locationStatus $($locationResponse.StatusCode); ClientCertificate=$($locationAssessment.ClientCertificatePresented); FoundServices=$foundServiceText; MissingServices=$missingServiceText" `
                -Remediation $locationAssessment.Remediation
        } catch {
            $exception = $_.Exception
            $inner = $exception
            while ($inner.InnerException) { $inner = $inner.InnerException }
            $trustFailure = $inner -is [Security.Authentication.AuthenticationException] -or $inner.Message -match 'SSL|trust relationship|remote certificate'
            Add-Result -Id 'NET09' -Category Network -Name 'Connector service-locator HTTP call' -Status 'Fail' -Case `
                -Detail "GET $locationUrl failed: $($inner.GetType().Name): $($inner.Message)" `
                -Remediation $(if ($trustFailure) { 'This matches the known TLS/trust incident. Review NET07, NET07b, NET08, LOC05, and LOC06.' } else { 'Resolve the connector proxy or endpoint connectivity failure.' })
        } finally {
            if ($locationResponse) { $locationResponse.Dispose() }
            $httpClient.Dispose()
            $httpHandler.Dispose()
        }
    } else {
        Add-Result -Id 'NET09' -Category Network -Name 'Connector service-locator HTTP call' -Status 'Info' `
            -Detail 'System.Net.Http is unavailable in this PowerShell host.'
    }

    $updateHost = 'autoupdate.msappproxy.net'
    $updateConnection = Connect-Tls443 -TargetHost $updateHost -Port 443 -ProxyUri $proxyUri -TimeoutMs ($TimeoutSeconds * 1000)
    $updateSsl = $null
    $updateTlsOk = $false
    $updateError = $updateConnection.Error
    try {
        if ($updateConnection.Ok) {
            $updateSsl = New-Object Net.Security.SslStream($updateConnection.Stream, $false)
            $updateSsl.ReadTimeout = $TimeoutSeconds * 1000
            $updateSsl.WriteTimeout = $TimeoutSeconds * 1000
            $updateSsl.AuthenticateAsClient($updateHost, $null, [Net.SecurityProtocolType]::Tls12, $false)
            $updateTlsOk = $true
        }
    } catch {
        $inner = $_.Exception
        while ($inner.InnerException) { $inner = $inner.InnerException }
        $updateError = $inner.Message
    } finally {
        if ($updateSsl) { $updateSsl.Dispose() }
        if ($updateConnection.Tcp) { $updateConnection.Tcp.Close() }
    }
    Add-Result -Id 'NET10' -Category Network -Name 'Azure connector update service reachable with trusted TLS' `
        -Status $(if ($updateTlsOk) { 'Pass' } else { 'Fail' }) `
        -Detail $(if ($updateTlsOk) { "TLS to $updateHost`:443 succeeded$(if ($proxyUri) { ' through the connector proxy' } else { ' directly' })." } else { $updateError }) `
        -Remediation 'Allow trusted TLS 1.2 access to autoupdate.msappproxy.net on TCP 443 so the connector can update automatically.'
}

#endregion Network Prerequisites

#region Internal NDES Endpoint

if (-not $SkipNdesChecks) {
    Write-DiagnosticSection 'Internal NDES endpoint behavior'
    if ($Context.NdesRoleKnown -and -not $Context.NdesRoleInstalled) {
        Add-Result -Id 'NDES08' -Category NDES -Name 'Direct MSCEP URL is protected' -Status 'Info' -Detail 'NDES role is not installed; not applicable.'
        Add-Result -Id 'NDES09' -Category NDES -Name 'MSCEP GetCACaps response' -Status 'Info' -Detail 'NDES role is not installed; not applicable.'
    } elseif (-not $Context.NdesRoleKnown) {
        Add-Result -Id 'NDES08' -Category NDES -Name 'Direct MSCEP URL is protected' -Status 'Info' -Detail 'NDES role state is unknown; endpoint request skipped.'
        Add-Result -Id 'NDES09' -Category NDES -Name 'MSCEP GetCACaps response' -Status 'Info' -Detail 'NDES role state is unknown; endpoint request skipped.'
    } elseif ($SkipNetworkChecks) {
        Add-Result -Id 'NDES08' -Category NDES -Name 'Direct MSCEP URL is protected' -Status 'Info' -Detail 'Skipped with -SkipNetworkChecks.'
        Add-Result -Id 'NDES09' -Category NDES -Name 'MSCEP GetCACaps response' -Status 'Info' -Detail 'Skipped with -SkipNetworkChecks.'
    } else {
        $ndesBaseUrl = "https://$($Context.Fqdn)/certsrv/mscep/mscep.dll"
        $directNdesResponse = Invoke-DiagnosticWebRequest -Uri $ndesBaseUrl -TimeoutSec $TimeoutSeconds -NoProxy
        # An unprotected HTTP 200 is only a failure once this connector actually
        # services SCEP; before that the Intune policy module is not expected.
        $scepPolicyModuleExpected = [string](Get-Reg $Context.ConnKey 'EnableSCEP') -eq '1'
        $directStatus = 'Fail'
        $directRemediation = 'Direct access must return 403. Investigate the SCEP application pool, the IIS HTTPS binding, and the NDES configuration; HTTP 503 usually indicates application-pool failure.'
        if ($directNdesResponse.StatusCode -eq 403) {
            $directStatus = 'Pass'
            $directRemediation = ''
        } elseif ($directNdesResponse.StatusCode -eq 200) {
            if ($scepPolicyModuleExpected) {
                $directRemediation = 'SCEP is enabled on this connector, so the Intune SCEP policy module must return 403 for direct access. Reinstall or reconfigure the policy module.'
            } else {
                $directStatus = 'Warn'
                $directRemediation = 'NDES answers directly because SCEP is not enabled on this connector yet. Direct access must return 403 once the Intune SCEP policy module is configured.'
            }
        }
        Add-Result -Id 'NDES08' -Category NDES -Name 'Direct MSCEP URL is protected' -Status $directStatus `
            -Detail ("GET {0} -> HTTP {1}; ConnectorScepEnabled={2}; Error={3}" -f $ndesBaseUrl, $directNdesResponse.StatusCode, $scepPolicyModuleExpected, $directNdesResponse.Error) `
            -Remediation $directRemediation

        $caCapsUrl = "$ndesBaseUrl`?operation=GetCACaps&message=test"
        $caCapsResponse = Invoke-DiagnosticWebRequest -Uri $caCapsUrl -TimeoutSec $TimeoutSeconds -NoProxy
        $caCapsOk = $caCapsResponse.StatusCode -eq 200 -and -not [string]::IsNullOrWhiteSpace($caCapsResponse.Content)
        $caCapsPreview = ([string]$caCapsResponse.Content -replace '[\r\n]+', ' ').Trim()
        if ($caCapsPreview.Length -gt 300) { $caCapsPreview = $caCapsPreview.Substring(0, 300) + '...' }
        Add-Result -Id 'NDES09' -Category NDES -Name 'MSCEP GetCACaps response' `
            -Status $(if ($caCapsOk) { 'Pass' } else { 'Fail' }) `
            -Detail ("GET {0} -> HTTP {1}; Content={2}; Error={3}" -f $caCapsUrl, $caCapsResponse.StatusCode, $caCapsPreview, $caCapsResponse.Error) `
            -Remediation 'Verify the SCEP application pool, IIS HTTPS certificate, MSCEP configuration, Intune policy module, and required account permissions.'
    }
}

#endregion Internal NDES Endpoint

#region Dynamic Connector Assembly

Write-DiagnosticSection 'Dynamic connector assembly validation'
if ($SkipDynamic) {
    Add-Result -Id 'DYN01' -Category Dynamic -Name 'ServiceLocatorClient via connector assembly' -Status 'Info' `
        -Detail 'Skipped with -SkipDynamic.'
} elseif ($SkipNetworkChecks) {
    Add-Result -Id 'DYN01' -Category Dynamic -Name 'ServiceLocatorClient via connector assembly' -Status 'Info' `
        -Detail 'Skipped because -SkipNetworkChecks was specified.'
} elseif (-not $installFolder) {
    Add-Result -Id 'DYN01' -Category Dynamic -Name 'ServiceLocatorClient via connector assembly' -Status 'Info' `
        -Detail $(if ($clientCert) { 'InstallFolder is unknown; NET09 exercised the authenticated static equivalent.' } else { 'InstallFolder and agent certificate are unavailable; NET09 validated transport and TLS only.' })
} else {
    $connectorCommonDll = Join-Path $installFolder 'Microsoft.Management.Services.ConnectorCommon.dll'
    if (Test-Path $connectorCommonDll) {
        try {
            Add-Type -Path $connectorCommonDll -ErrorAction Stop
            $serviceLocatorClient = New-Object Microsoft.Management.Services.ConnectorCommon.ServiceLocatorClient
            $webProxy = $null
            if ($proxyUri) { $webProxy = New-Object Net.WebProxy($proxyUri, $false) }
            if ($clientCert) {
                $serviceMap = $serviceLocatorClient.RetrieveServiceLocations($clientCert, $webProxy, [Uri]$locationUrl)
                $serviceMapAssessment = Get-ServiceLocatorMapAssessment -ServiceMap $serviceMap
                $missingServiceText = if ($serviceMapAssessment.MissingServices.Count) {
                    $serviceMapAssessment.MissingServices -join ', '
                } else {
                    '<none>'
                }
                $invalidServiceText = if ($serviceMapAssessment.InvalidServices.Count) {
                    $serviceMapAssessment.InvalidServices -join ', '
                } else {
                    '<none>'
                }
                $resolvedServiceText = @($serviceMapAssessment.ResolvedServices.GetEnumerator() | ForEach-Object {
                        "$($_.Key)=$($_.Value)"
                    }) -join '; '
                Add-Result -Id 'DYN01' -Category Dynamic -Name 'ServiceLocatorClient via connector assembly' `
                    -Status $(if ($serviceMapAssessment.Complete) { 'Pass' } else { 'Fail' }) -Case `
                    -Detail ("Connector assembly returned {0} key(s): {1}; MissingServices={2}; InvalidServices={3}; ResolvedServices={4}" -f $serviceMapAssessment.Keys.Count, ($serviceMapAssessment.Keys -join ', '), $missingServiceText, $invalidServiceText, $resolvedServiceText) `
                    -Remediation 'RetrieveServiceLocations must resolve valid EnrollmentService and RAODJPlusFEGatewayService endpoints. Re-enroll the connector or investigate Intune service discovery.'
            } else {
                Add-Result -Id 'DYN01' -Category Dynamic -Name 'ServiceLocatorClient via connector assembly' -Status 'Info' `
                    -Detail 'Assembly loaded, but no enrolled agent certificate is available. NET09 can validate only transport and TLS without it.'
            }
        } catch {
            $inner = $_.Exception
            while ($inner.InnerException) { $inner = $inner.InnerException }
            $trustFailure = $inner -is [Security.Authentication.AuthenticationException] -or $inner.Message -match 'SSL|trust relationship|remote certificate'
            Add-Result -Id 'DYN01' -Category Dynamic -Name 'ServiceLocatorClient via connector assembly' -Status 'Fail' -Case `
                -Detail "$($inner.GetType().Name): $($inner.Message)" `
                -Remediation $(if ($trustFailure) { 'The connector assembly reproduced the TLS/trust incident; review NET07 through NET09.' } else { 'The connector assembly call failed; review its dependencies, registration, certificate, proxy, and network results.' })
        }
    } else {
        Add-Result -Id 'DYN01' -Category Dynamic -Name 'ServiceLocatorClient via connector assembly' -Status 'Info' `
            -Detail $(if ($clientCert) { "ConnectorCommon assembly was not found at $connectorCommonDll; NET09 covered the authenticated static equivalent." } else { "ConnectorCommon assembly was not found at $connectorCommonDll and no agent certificate is available; NET09 validated transport and TLS only." })
    }
}

#endregion Dynamic Connector Assembly

}

#endregion Diagnostic Phase Orchestration

#region Configuration and Parsing

# Reads one named value from an HKLM registry path and returns null when unavailable.
function Get-Reg {
    param([string]$Path, [string]$Name)

    try {
        $item = Get-ItemProperty -Path ("HKLM:\{0}" -f $Path.TrimStart('\')) -Name $Name -ErrorAction Stop
        return $item.$Name
    } catch {
        return $null
    }
}

# Normalizes registry or object date values to UTC, including DateTimeOffset,
# DateTime, Windows file time, current-culture text, and invariant-culture text.
function ConvertTo-UtcDateTime {
    param($Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    try {
        if ($Value -is [DateTimeOffset]) {
            return $Value.UtcDateTime
        }
        if ($Value -is [DateTime]) {
            return $Value.ToUniversalTime()
        }

        $text = ([string]$Value).Trim()
        $number = 0L
        if ([Int64]::TryParse($text, [ref]$number) -and $number -gt 10000000000000000L) {
            return [DateTime]::FromFileTimeUtc($number)
        }

        $dto = [DateTimeOffset]::MinValue
        if ([DateTimeOffset]::TryParse(
                $text,
                [Globalization.CultureInfo]::CurrentCulture,
                [Globalization.DateTimeStyles]::AllowWhiteSpaces,
                [ref]$dto)) {
            return $dto.UtcDateTime
        }
        if ([DateTimeOffset]::TryParse(
                $text,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AllowWhiteSpaces,
                [ref]$dto)) {
            return $dto.UtcDateTime
        }
    } catch {}

    return $null
}

# Validates the connector proxy configuration and returns a normalized URI plus
# configured/valid/error metadata without throwing for malformed user settings.
function Resolve-ConnectorProxyUri {
    param([string]$Server, $Port)

    $result = [pscustomobject]@{
        Configured = -not [string]::IsNullOrWhiteSpace($Server)
        Valid      = $false
        Uri        = $null
        Candidate  = $Server
        Error      = $null
    }
    if (-not $result.Configured) {
        return $result
    }

    try {
        $candidate = $Server.Trim()
        $uri = [Uri]$candidate
        if (-not $uri.IsAbsoluteUri -or $uri.Scheme -notin @('http', 'https') -or [string]::IsNullOrWhiteSpace($uri.Host)) {
            throw 'Proxy must be an absolute http:// or https:// URI with a host.'
        }

        if ($null -ne $Port -and -not [string]::IsNullOrWhiteSpace([string]$Port)) {
            $portNumber = 0
            if (-not [Int32]::TryParse([string]$Port, [ref]$portNumber) -or $portNumber -lt 1 -or $portNumber -gt 65535) {
                throw "Invalid proxy port '$Port'."
            }
            $builder = New-Object UriBuilder($uri)
            $builder.Port = $portNumber
            $uri = $builder.Uri
        }

        $result.Candidate = $uri.AbsoluteUri
        $result.Valid = $true
        $result.Uri = $uri
    } catch {
        $result.Error = $_.Exception.Message
    }

    return $result
}

# Finds the installed Certificate Connector product record in both uninstall
# registry views and returns the highest discovered display version.
function Get-ConnectorProduct {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    try {
        return Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -eq 'Certificate Connector for Microsoft Intune' } |
            Sort-Object DisplayVersion -Descending |
            Select-Object -First 1
    } catch {
        return $null
    }
}

#endregion Configuration and Parsing

#region System and Service Inspection

# Resolves the local computer's fully qualified DNS hostname with a safe fallback
# to the short COMPUTERNAME value when DNS lookup is unavailable.
function Get-FullyQualifiedHostName {
    try {
        return ([Net.Dns]::GetHostEntry($env:COMPUTERNAME)).HostName
    } catch {
        return $env:COMPUTERNAME
    }
}

# Queries requested Windows Server roles/features and returns availability,
# feature objects, and any query error in a consistent result object.
function Get-WindowsFeatureState {
    param([string[]]$Names)

    $command = Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue
    if (-not $command) {
        return [pscustomobject]@{ Available = $false; Features = @(); Error = 'Get-WindowsFeature is unavailable.' }
    }

    try {
        $features = @(Get-WindowsFeature -Name $Names -ErrorAction Stop)
        return [pscustomobject]@{ Available = $true; Features = $features; Error = $null }
    } catch {
        return [pscustomobject]@{ Available = $true; Features = @(); Error = $_.Exception.Message }
    }
}

# Returns a service's status, startup identity/mode, process ID, and most recent
# process start time by combining ServiceController and CIM information.
function Get-ServiceDetail {
    param([string]$Name)

    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $service) {
        return $null
    }

    $cim = $null
    try {
        $safeName = $Name.Replace("'", "''")
        $cim = Get-CimInstance -ClassName Win32_Service -Filter "Name='$safeName'" -ErrorAction Stop
    } catch {}

    $started = $null
    if ($cim -and $cim.ProcessId -gt 0) {
        try {
            $started = (Get-Process -Id $cim.ProcessId -ErrorAction Stop).StartTime.ToUniversalTime()
        } catch {}
    }

    return [pscustomobject]@{
        Name      = $Name
        Status    = [string]$service.Status
        StartName = if ($cim) { $cim.StartName } else { $null }
        StartMode = if ($cim) { $cim.StartMode } else { $null }
        ProcessId = if ($cim) { $cim.ProcessId } else { $null }
        StartedUtc = $started
    }
}

#endregion System and Service Inspection

#region Account and Security Validation

# Resolves a Windows account name to its security identifier (SID), returning
# null when the account cannot be translated in the current environment.
function Resolve-AccountSid {
    param([string]$AccountName)

    if ([string]::IsNullOrWhiteSpace($AccountName)) {
        return $null
    }
    try {
        return (New-Object Security.Principal.NTAccount($AccountName)).Translate(
            [Security.Principal.SecurityIdentifier]
        ).Value
    } catch {
        return $null
    }
}

# Enumerates the member SIDs of a WinNT group and expands nested groups within
# bounded depth and size limits, so an account that inherits access through a
# nested domain group is still detected. Reports whether enumeration completed.
function Get-GroupMemberSidSet {
    param(
        [string]$AdsPath,
        [int]$MaxDepth = 2,
        [int]$MaxMembers = 5000
    )

    $sids = New-Object 'System.Collections.Generic.HashSet[string]'
    $visited = New-Object 'System.Collections.Generic.HashSet[string]'
    $queue = New-Object 'System.Collections.Generic.Queue[object]'
    $complete = $true
    $queue.Enqueue([pscustomobject]@{ Path = $AdsPath; Depth = 0 })

    while ($queue.Count -gt 0) {
        if ($sids.Count -ge $MaxMembers) {
            $complete = $false
            break
        }

        $current = $queue.Dequeue()
        if (-not $visited.Add(([string]$current.Path).ToLowerInvariant())) {
            continue
        }

        $members = $null
        try {
            $members = @(([ADSI]$current.Path).psbase.Invoke('Members'))
        } catch {
            $complete = $false
            continue
        }

        foreach ($member in $members) {
            try {
                $bytes = [byte[]]$member.GetType().InvokeMember(
                    'objectSid',
                    'GetProperty',
                    $null,
                    $member,
                    $null
                )
                $null = $sids.Add((New-Object Security.Principal.SecurityIdentifier($bytes, 0)).Value)

                $memberClass = [string]$member.GetType().InvokeMember('Class', 'GetProperty', $null, $member, $null)
                if ($memberClass -eq 'Group' -and $current.Depth -lt $MaxDepth) {
                    $memberPath = [string]$member.GetType().InvokeMember('ADsPath', 'GetProperty', $null, $member, $null)
                    if ($memberPath) {
                        $queue.Enqueue([pscustomobject]@{ Path = $memberPath; Depth = $current.Depth + 1 })
                    }
                }
            } catch {
                $complete = $false
            }
        }
    }

    return [pscustomobject]@{ Sids = $sids; Complete = $complete }
}

# Tests whether an account SID is a member of a localized built-in group by using
# the group's well-known SID and recursive ADSI member enumeration.
function Test-LocalGroupMembershipBySid {
    param([string]$AccountName, [string]$GroupSid)

    $output = [pscustomobject]@{
        Known     = $false
        IsMember  = $false
        GroupName = $null
        Error     = $null
    }
    try {
        $group = Get-CimInstance -ClassName Win32_Group -Filter "LocalAccount=True AND SID='$GroupSid'" -ErrorAction Stop |
            Select-Object -First 1
        if (-not $group) {
            throw "Local group with SID $GroupSid was not found."
        }
        $output.GroupName = $group.Name
        $accountSid = Resolve-AccountSid $AccountName
        if (-not $accountSid) {
            throw "Could not resolve SID for account '$AccountName'."
        }

        $membership = Get-GroupMemberSidSet -AdsPath ("WinNT://{0}/{1},group" -f $env:COMPUTERNAME, $group.Name)
        $output.IsMember = $membership.Sids.Contains($accountSid)
        if (-not $output.IsMember -and -not $membership.Complete) {
            throw "Membership of '$AccountName' in '$($group.Name)' is unknown because one or more nested groups could not be enumerated."
        }
        $output.Known = $true
    } catch {
        $output.Error = $_.Exception.Message
    }

    return $output
}

# Exports local user-right assignments with secedit and checks whether the target
# account SID holds a requested right such as Log on as a service.
function Test-AccountUserRight {
    param([string]$AccountName, [string]$Right = 'SeServiceLogonRight')

    $result = [pscustomobject]@{ Known = $false; HasRight = $false; Error = $null }
    if ([string]::IsNullOrWhiteSpace($AccountName)) {
        $result.Error = 'Account name is empty.'
        return $result
    }
    if ($AccountName -in @('LocalSystem', 'NT AUTHORITY\SYSTEM', '.\LocalSystem')) {
        $result.Known = $true
        $result.HasRight = $true
        return $result
    }

    $sid = Resolve-AccountSid $AccountName
    if (-not $sid) {
        $result.Error = "Could not resolve SID for '$AccountName'."
        return $result
    }

    $tempFile = [IO.Path]::GetTempFileName()
    try {
        $null = & secedit.exe /export /areas USER_RIGHTS /cfg $tempFile /quiet 2>&1
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tempFile)) {
            throw "secedit export failed with exit code $LASTEXITCODE."
        }
        $line = Get-Content -Path $tempFile -ErrorAction Stop |
            Where-Object { $_ -match ("^\s*{0}\s*=" -f [regex]::Escape($Right)) } |
            Select-Object -First 1
        if ($line) {
            $result.HasRight = ($line -match ("\*?{0}(,|\s|$)" -f [regex]::Escape($sid)))
        }
        $result.Known = $true
    } catch {
        $result.Error = $_.Exception.Message
    } finally {
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
    }

    return $result
}

#endregion Account and Security Validation

#region Certificate and Network Primitives

# Evaluates a ServiceAddresses HTTP response against the connector's required
# services and distinguishes full client-certificate validation from transport-only validation.
function Get-ServiceLocatorHttpAssessment {
    param(
        [int]$StatusCode,
        [bool]$ClientCertificatePresented,
        [AllowEmptyString()]
        [string]$Content = ''
    )

    $foundServices = @($script:RequiredServiceNames | Where-Object {
            $Content -match [regex]::Escape($_)
        })
    $missingServices = @($script:RequiredServiceNames | Where-Object {
            $_ -notin $foundServices
        })
    $status = 'Warn'
    $remediation = 'Review the unexpected HTTP response and the Intune service status.'

    if ($StatusCode -ge 200 -and $StatusCode -lt 300) {
        if (-not $ClientCertificatePresented) {
            $status = 'Warn'
            $remediation = 'Transport and TLS succeeded, but the exact authenticated connector call requires a valid agent encryption certificate.'
        } elseif ($missingServices.Count -eq 0) {
            $status = 'Pass'
            $remediation = ''
        } else {
            $status = 'Fail'
            $remediation = 'The ServiceAddresses response must include EnrollmentService and RAODJPlusFEGatewayService. Review connector enrollment and Intune service discovery.'
        }
    } elseif ($StatusCode -in @(401, 403)) {
        if ($ClientCertificatePresented) {
            $status = 'Fail'
            $remediation = 'The endpoint rejected the enrolled agent certificate. Re-enroll the connector and verify its certificate and tenant registration.'
        } else {
            $status = 'Warn'
            $remediation = 'The response proves transport and TLS trust, but authentication could not be validated without the agent certificate.'
        }
    } elseif ($StatusCode -ge 500) {
        $status = 'Fail'
        $remediation = 'The service locator returned a server-side error. Check Microsoft service health and retry after local connectivity is confirmed.'
    }

    return [pscustomobject]@{
        Status                     = $status
        ClientCertificatePresented = $ClientCertificatePresented
        FoundServices              = $foundServices
        MissingServices            = $missingServices
        Remediation                = $remediation
    }
}

# Validates that the connector assembly returned both required service-map keys
# and that each key resolves to a non-empty absolute endpoint URI.
function Get-ServiceLocatorMapAssessment {
    param([object]$ServiceMap)

    $keys = @()
    if ($null -ne $ServiceMap -and $null -ne $ServiceMap.Keys) {
        $keys = @($ServiceMap.Keys | ForEach-Object { [string]$_ })
    }

    $missingServices = @()
    $invalidServices = @()
    $resolvedServices = [ordered]@{}
    foreach ($requiredService in $script:RequiredServiceNames) {
        $matchingKey = $keys | Where-Object {
            $_.Equals($requiredService, [StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1
        if (-not $matchingKey) {
            $missingServices += $requiredService
            continue
        }

        $endpointValue = $null
        try { $endpointValue = $ServiceMap[$matchingKey] } catch {}
        $endpointUri = $null
        if ($null -eq $endpointValue -or
            -not [Uri]::TryCreate([string]$endpointValue, [UriKind]::Absolute, [ref]$endpointUri)) {
            $invalidServices += $requiredService
            continue
        }
        $resolvedServices[$requiredService] = $endpointUri.AbsoluteUri
    }

    return [pscustomobject]@{
        Complete         = $missingServices.Count -eq 0 -and $invalidServices.Count -eq 0
        Keys             = $keys
        MissingServices  = $missingServices
        InvalidServices  = $invalidServices
        ResolvedServices = $resolvedServices
    }
}

# Extracts certificate-template names from Microsoft template extension OIDs and
# returns a unique list suitable for NDES certificate matching.
function Get-CertificateTemplateName {
    param([Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)

    $names = @()
    if (-not $Certificate) {
        return $names
    }

    foreach ($extension in $Certificate.Extensions) {
        if ($extension.Oid.Value -notin @('1.3.6.1.4.1.311.21.7', '1.3.6.1.4.1.311.20.2')) {
            continue
        }
        try {
            $formatted = $extension.Format($false).Trim()
            if ($extension.Oid.Value -eq '1.3.6.1.4.1.311.20.2') {
                if ($formatted) { $names += $formatted.Trim('"') }
            } else {
                $match = [regex]::Match($formatted, '(?i)Template\s*=\s*([^\(,\r\n]+)')
                if ($match.Success) {
                    $names += $match.Groups[1].Value.Trim()
                }
                $match = [regex]::Match($formatted, '^([^\(,\r\n]+)')
                if ($match.Success -and $match.Groups[1].Value -notmatch '(?i)Template') {
                    $names += $match.Groups[1].Value.Trim()
                }
            }
        } catch {}
    }

    return @($names | Where-Object { $_ } | Select-Object -Unique)
}

# Reads a DER length prefix at the referenced offset and advances that offset
# past the consumed length bytes.
function Read-DerLength {
    param(
        [byte[]]$Data,
        [ref]$Offset
    )

    $first = $Data[$Offset.Value]
    $Offset.Value = $Offset.Value + 1
    if ($first -lt 0x80) {
        return [int]$first
    }

    $byteCount = $first -band 0x7F
    if ($byteCount -eq 0 -or $byteCount -gt 4) {
        throw 'Unsupported DER length encoding.'
    }

    $length = 0
    for ($index = 0; $index -lt $byteCount; $index++) {
        $length = ($length -shl 8) -bor $Data[$Offset.Value]
        $Offset.Value = $Offset.Value + 1
    }
    return $length
}

# Extracts every dNSName entry from a raw Subject Alternative Name extension.
# The DER walk avoids the localized text that AsnEncodedData.Format produces.
function Get-SubjectAlternativeDnsName {
    param([byte[]]$RawData)

    $names = @()
    if ($null -eq $RawData -or $RawData.Length -lt 2 -or $RawData[0] -ne 0x30) {
        return $names
    }

    try {
        $offset = 1
        $sequenceLength = Read-DerLength -Data $RawData -Offset ([ref]$offset)
        $end = [Math]::Min($RawData.Length, $offset + $sequenceLength)
        while ($offset -lt $end) {
            $tag = $RawData[$offset]
            $offset = $offset + 1
            $length = Read-DerLength -Data $RawData -Offset ([ref]$offset)
            if ($length -lt 0 -or ($offset + $length) -gt $RawData.Length) {
                break
            }
            if ($tag -eq 0x82) {
                $names += [Text.Encoding]::ASCII.GetString($RawData, $offset, $length)
            }
            $offset = $offset + $length
        }
    } catch {}

    return $names
}

# Returns every DNS name a certificate can present by combining all Subject
# Alternative Name dNSName entries with the subject common name.
function Get-CertificateDnsName {
    param([Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)

    $names = @()
    if (-not $Certificate) {
        return $names
    }

    foreach ($extension in $Certificate.Extensions) {
        if ($extension.Oid.Value -eq '2.5.29.17') {
            $names += Get-SubjectAlternativeDnsName -RawData $extension.RawData
        }
    }

    try {
        $commonName = $Certificate.GetNameInfo(
            [Security.Cryptography.X509Certificates.X509NameType]::SimpleName,
            $false
        )
        if ($commonName) { $names += $commonName }
    } catch {}

    return @($names | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Select-Object -Unique)
}

# Compares an expected DNS hostname with a presented certificate name, including
# single-label wildcard certificate matching.
function Test-DnsNameMatch {
    param([string]$Expected, [string]$Presented)

    if ([string]::IsNullOrWhiteSpace($Expected) -or [string]::IsNullOrWhiteSpace($Presented)) {
        return $false
    }
    if ($Expected.Equals($Presented, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    if ($Presented.StartsWith('*.')) {
        $suffix = $Presented.Substring(1)
        return $Expected.EndsWith($suffix, [StringComparison]::OrdinalIgnoreCase) -and
            ($Expected.Split('.').Count -eq $Presented.Split('.').Count)
    }
    return $false
}

# Performs a bounded diagnostic HTTP GET and returns status, content, and error
# details while optionally bypassing the system proxy for internal NDES requests.
function Invoke-DiagnosticWebRequest {
    param(
        [string]$Uri,
        [int]$TimeoutSec = 30,
        [switch]$NoProxy
    )

    $result = [pscustomobject]@{ StatusCode = $null; Content = $null; Error = $null }
    $response = $null
    try {
        $request = [Net.HttpWebRequest]::Create($Uri)
        $request.Method = 'GET'
        $request.Timeout = $TimeoutSec * 1000
        $request.ReadWriteTimeout = $TimeoutSec * 1000
        $request.AllowAutoRedirect = $false
        if ($NoProxy) { $request.Proxy = $null }
        $response = $request.GetResponse()
        $result.StatusCode = [int]$response.StatusCode
    } catch [Net.WebException] {
        if ($_.Exception.Response) {
            $response = $_.Exception.Response
            try { $result.StatusCode = [int]$response.StatusCode } catch {}
        } else {
            $result.Error = $_.Exception.Message
        }
    } catch {
        $result.Error = $_.Exception.Message
    }

    if ($response) {
        try {
            $reader = New-Object IO.StreamReader($response.GetResponseStream())
            $result.Content = $reader.ReadToEnd()
            $reader.Dispose()
        } catch {}
        try { $response.Close() } catch {}
    }

    return $result
}

# ---------------------------------------------------------------------------
# Network primitive: direct TCP or an HTTP CONNECT tunnel through the exact
# proxy configured by the connector. Returns Ok, Stream, Tcp, ProxyStatus, Error.
# ---------------------------------------------------------------------------
# Opens a direct TCP connection or an HTTP CONNECT proxy tunnel and returns the
# live stream/socket plus proxy status and error information for TLS validation.
function Connect-Tls443 {
    param(
        [string]$TargetHost,
        [int]$Port = 443,
        $ProxyUri,
        [int]$TimeoutMs = 15000
    )

    $result = @{ Ok = $false; Stream = $null; Tcp = $null; ProxyStatus = $null; Error = $null }
    try {
        $tcp = New-Object Net.Sockets.TcpClient
        # Publish the socket before connecting so every failure path, including a
        # connect timeout, still lets the caller close it instead of leaking it.
        $result.Tcp = $tcp
        if ($ProxyUri) {
            $async = $tcp.BeginConnect($ProxyUri.Host, $ProxyUri.Port, $null, $null)
            if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs)) {
                throw "TCP connect to proxy $($ProxyUri.Host):$($ProxyUri.Port) timed out."
            }
            $tcp.EndConnect($async)
            $networkStream = $tcp.GetStream()
            $networkStream.ReadTimeout = $TimeoutMs
            $networkStream.WriteTimeout = $TimeoutMs
            $connectRequest = "CONNECT {0}:{1} HTTP/1.1`r`nHost: {0}:{1}`r`nProxy-Connection: keep-alive`r`n`r`n" -f $TargetHost, $Port
            $requestBytes = [Text.Encoding]::ASCII.GetBytes($connectRequest)
            $networkStream.Write($requestBytes, 0, $requestBytes.Length)
            $buffer = New-Object byte[] 4096
            $builder = New-Object Text.StringBuilder
            do {
                $count = $networkStream.Read($buffer, 0, $buffer.Length)
                if ($count -le 0) { break }
                [void]$builder.Append([Text.Encoding]::ASCII.GetString($buffer, 0, $count))
            } while ($builder.ToString() -notmatch "`r`n`r`n" -and $builder.Length -lt 8192)

            $statusLine = ($builder.ToString() -split "`r`n")[0]
            $result.ProxyStatus = $statusLine
            if ($statusLine -notmatch ' 200 ') {
                $result.Error = "Proxy CONNECT refused: $statusLine"
                return $result
            }
        } else {
            $async = $tcp.BeginConnect($TargetHost, $Port, $null, $null)
            if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs)) {
                throw "TCP connect to ${TargetHost}:$Port timed out."
            }
            $tcp.EndConnect($async)
        }

        $result.Stream = $tcp.GetStream()
        $result.Ok = $true
    } catch {
        $result.Error = $_.Exception.Message
    }

    return $result
}

#endregion Certificate and Network Primitives

#region IIS, Event Log, and Collection Helpers

# Discovers the SCEP application pool, process-model identity, state, and HTTPS
# bindings through WebAdministration with an appcmd.exe fallback for the pool.
# BindingsKnown reports whether the HTTPS binding list is authoritative.
function Get-IisScepConfiguration {
    $result = [pscustomobject]@{
        Available       = $false
        PoolExists      = $false
        PoolState       = $null
        IdentityType    = $null
        UserName        = $null
        BindingsKnown   = $false
        HttpsBindings   = @()
        Error           = $null
    }

    $webAdministrationLoaded = $false
    try {
        Import-Module WebAdministration -ErrorAction Stop
        $webAdministrationLoaded = $true
        $result.Available = $true
    } catch {
        $result.Error = $_.Exception.Message
    }

    if ($webAdministrationLoaded) {
        try {
            if (Test-Path 'IIS:\AppPools\SCEP') {
                $result.PoolExists = $true
                $result.PoolState = [string](Get-WebAppPoolState -Name 'SCEP' -ErrorAction Stop).Value
                $processModel = Get-ItemProperty 'IIS:\AppPools\SCEP' -Name processModel -ErrorAction Stop
                $result.IdentityType = [string]$processModel.identityType
                $result.UserName = [string]$processModel.userName
            }
        } catch {
            if (-not $result.Error) { $result.Error = $_.Exception.Message }
        }

        # Enumerated separately so an application-pool read failure never hides
        # the HTTPS bindings that the certificate checks depend on.
        try {
            $result.HttpsBindings = @(Get-WebBinding -Protocol https -ErrorAction Stop)
            $result.BindingsKnown = $true
        } catch {
            if (-not $result.Error) { $result.Error = $_.Exception.Message }
        }
    }

    if (-not $result.PoolExists) {
        $appCmd = Join-Path $env:SystemRoot 'System32\inetsrv\appcmd.exe'
        if (Test-Path $appCmd) {
            try {
                $state = & $appCmd list apppool /name:SCEP /text:state 2>$null
                if ($LASTEXITCODE -eq 0 -and $state) {
                    $result.Available = $true
                    $result.PoolExists = $true
                    $result.PoolState = ([string]$state).Trim()
                    $result.UserName = ([string](& $appCmd list apppool /name:SCEP /text:processModel.userName 2>$null)).Trim()
                    $result.IdentityType = ([string](& $appCmd list apppool /name:SCEP /text:processModel.identityType 2>$null)).Trim()
                }
            } catch {
                if (-not $result.Error) { $result.Error = $_.Exception.Message }
            }
        }
    }

    return $result
}

# Converts an IIS application-pool identity type and optional configured username
# into the effective Windows account used by the SCEP pool.
function Get-AppPoolAccountName {
    param($IisConfiguration)

    if (-not $IisConfiguration -or -not $IisConfiguration.PoolExists) {
        return $null
    }
    if (-not [string]::IsNullOrWhiteSpace($IisConfiguration.UserName)) {
        return $IisConfiguration.UserName
    }

    switch -Regex ([string]$IisConfiguration.IdentityType) {
        '0|LocalSystem' { return 'NT AUTHORITY\SYSTEM' }
        '1|LocalService' { return 'NT AUTHORITY\LOCAL SERVICE' }
        '2|NetworkService' { return 'NT AUTHORITY\NETWORK SERVICE' }
        '4|ApplicationPoolIdentity' { return 'IIS APPPOOL\SCEP' }
        default { return $null }
    }
}

# Formats recent event records into compact, single-line diagnostic summaries and
# truncates long event messages for readable console and transcript output.
function Format-EventSummary {
    param([object[]]$Events)

    $parts = @()
    foreach ($eventRecord in @($Events)) {
        $message = ([string]$eventRecord.Message -replace '[\r\n]+', ' ').Trim()
        if ($message.Length -gt 180) { $message = $message.Substring(0, 180) + '...' }
        $parts += ("{0:u} ID={1} Provider={2}: {3}" -f $eventRecord.TimeCreated.ToUniversalTime(), $eventRecord.Id, $eventRecord.ProviderName, $message)
    }
    return ($parts -join ' | ')
}

# Reports whether a named Windows event-log channel is registered and accessible.
function Test-EventLog {
    param([string]$LogName)

    try {
        $null = Get-WinEvent -ListLog $LogName -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# Stages metadata, recent IIS logs, exported EVTX files, and GPResult output, then
# returns the staging/target paths and warnings needed for final ZIP creation.
function Initialize-DiagnosticCollection {
    param([string]$RequestedPath, [int]$RecentIisLogCount)

    $stage = Join-Path ([IO.Path]::GetTempPath()) ("IntuneNdesDiagnostics-{0}" -f [Guid]::NewGuid())
    $warnings = @()
    $collected = 0
    try {
        $null = New-Item -ItemType Directory -Path $stage -Force -ErrorAction Stop

        $metadata = @(
            'Intune Certificate Connector and NDES diagnostic bundle',
            "Host=$env:COMPUTERNAME",
            "User=$env:USERDOMAIN\$env:USERNAME",
            "Created=$(Get-Date -Format o)",
            'Warning=This archive can contain hostnames, account names, policy data, certificates, and event messages.'
        )
        Set-Content -Path (Join-Path $stage 'metadata.txt') -Value $metadata -Encoding UTF8
        $collected++

        $iisRoot = Join-Path $env:SystemDrive 'inetpub\logs\LogFiles'
        if (Test-Path $iisRoot) {
            $iisDestination = Join-Path $stage 'IIS'
            $null = New-Item -ItemType Directory -Path $iisDestination -Force
            $iisLogs = Get-ChildItem -Path $iisRoot -Filter '*.log' -File -Recurse -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First $RecentIisLogCount
            foreach ($iisLog in $iisLogs) {
                # Prefix the site folder because recursive collection routinely
                # finds identically named daily logs under several W3SVC folders.
                $uniqueName = "{0}_{1}" -f $iisLog.Directory.Name, $iisLog.Name
                Copy-Item -Path $iisLog.FullName -Destination (Join-Path $iisDestination $uniqueName) -Force -ErrorAction Stop
                $collected++
            }
            if (-not $iisLogs) { $warnings += 'No IIS log files were found.' }
        } else {
            $warnings += "IIS log root '$iisRoot' was not found."
        }

        $eventDestination = Join-Path $stage 'EventLogs'
        $null = New-Item -ItemType Directory -Path $eventDestination -Force
        $wevtutil = Get-Command wevtutil.exe -ErrorAction SilentlyContinue
        if ($wevtutil) {
            foreach ($logName in $script:EventLogNames) {
                if (-not (Test-EventLog $logName)) {
                    $warnings += "Event log '$logName' is unavailable."
                    continue
                }
                $safeName = $logName -replace '[\\/:*?"<>|]', '_'
                $destination = Join-Path $eventDestination ("{0}.evtx" -f $safeName)
                $null = & $wevtutil.Source epl $logName $destination /ow:true 2>&1
                if ($LASTEXITCODE -eq 0 -and (Test-Path $destination)) {
                    $collected++
                } else {
                    $warnings += "Failed to export event log '$logName'."
                }
            }
        } else {
            $warnings += 'wevtutil.exe is unavailable.'
        }

        $gpresult = Get-Command gpresult.exe -ErrorAction SilentlyContinue
        if ($gpresult) {
            $gpPath = Join-Path $stage 'gpresult.html'
            $null = & $gpresult.Source /h $gpPath /f 2>&1
            if ($LASTEXITCODE -eq 0 -and (Test-Path $gpPath)) {
                $collected++
            } else {
                $warnings += 'GPResult collection failed.'
            }
        } else {
            $warnings += 'gpresult.exe is unavailable.'
        }

        if ([string]::IsNullOrWhiteSpace($RequestedPath)) {
            $bundleRoot = Join-Path $env:ProgramData 'Microsoft\IntuneCertificateConnector\Diagnostics'
            $null = New-Item -ItemType Directory -Path $bundleRoot -Force -ErrorAction Stop
            $RequestedPath = Join-Path $bundleRoot ("Intune-NDES-Diagnostics-{0:yyyyMMdd-HHmmss}.zip" -f (Get-Date))
        } elseif ([IO.Path]::GetExtension($RequestedPath) -ne '.zip') {
            $RequestedPath = "$RequestedPath.zip"
        }
        $parent = Split-Path -Parent $RequestedPath
        if ($parent) { $null = New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop }

        return [pscustomobject]@{
            Success   = $true
            Stage     = $stage
            Target    = $RequestedPath
            Count     = $collected
            Warnings  = $warnings
            Error     = $null
        }
    } catch {
        return [pscustomobject]@{
            Success   = $false
            Stage     = $stage
            Target    = $RequestedPath
            Count     = $collected
            Warnings  = $warnings
            Error     = $_.Exception.Message
        }
    }
}

#endregion IIS, Event Log, and Collection Helpers

#region Public Command

<#
.SYNOPSIS
    Tests Microsoft Intune Certificate Connector and NDES prerequisites.

.DESCRIPTION
    Performs one non-interactive, read-only validation of the Certificate
    Connector, NDES/SCEP, IIS, certificates, recent event logs, and network
    connectivity. The default output is a color-coded direct result and a local
    transcript. Use PassThru to return one structured report object.

.PARAMETER ConnectorType
    Connector registry leaf under HKLM\SOFTWARE\Microsoft\MicrosoftIntune.

.PARAMETER BaseAddress
    Overrides the Intune base service address discovered from the connector.

.PARAMETER OutFile
    Transcript path. Defaults to a timestamped file under ProgramData.

.PARAMETER SkipDynamic
    Skips invoking the installed connector assembly.

.PARAMETER SkipNdesChecks
    Skips NDES, IIS, MSCEP, and NDES certificate checks.

.PARAMETER SkipNetworkChecks
    Skips external network, TLS, revocation, and internal NDES URL requests.

.PARAMETER SkipEventLogChecks
    Skips recent event-log analysis.

.PARAMETER TimeoutSeconds
    Timeout for each network operation. Default is 30 seconds.

.PARAMETER EventLookbackDays
    Event-log lookback window. Default is two days.

.PARAMETER MaxEvents
    Maximum events reported per event-log check. Default is five.

.PARAMETER ConnectorStaleHours
    Warns when LastConnectionTime is older than this threshold. Default is 24.

.PARAMETER CollectLogs
    Creates a local diagnostic ZIP. The archive can contain sensitive data.

.PARAMETER DiagnosticBundlePath
    Optional destination for the diagnostic ZIP.

.PARAMETER IisLogCount
    Number of recent IIS logs to collect. Default is three.

.PARAMETER HtmlReport
    Writes a self-contained HTML report with an at-a-glance status summary and a
    prioritized action plan. Defaults to the transcript path with an .html extension.

.PARAMETER HtmlReportPath
    Optional destination for the HTML report. Implies HtmlReport is meaningful only
    when HtmlReport is also specified.

.PARAMETER PassThru
    Returns one Intune.CertificateConnector.DiagnosticReport object.

.EXAMPLE
    Test-IntuneCertificateConnector

.EXAMPLE
    Test-IntuneCertificateConnector -HtmlReport

.EXAMPLE
    $report = Test-IntuneCertificateConnector -PassThru
    $report.Results | Where-Object Status -eq 'Fail'

.EXAMPLE
    Test-CertConnectorPrereqNetwork -CollectLogs

.OUTPUTS
    Intune.CertificateConnector.DiagnosticReport when PassThru is specified.

.LINK
    https://github.com/YeehomZhu/Validate-NewIntuneNDESConfig
#>
function Test-IntuneCertificateConnector {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'The default contract is a color-coded direct diagnostic result.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingEmptyCatchBlock', '', Justification = 'Best-effort probes convert unavailable data into explicit diagnostic results.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Every parameter is forwarded to Initialize-DiagnosticContext and consumed by the private orchestration functions through that context object.')]
    param(
        [string]$ConnectorType = 'PFXCertificateConnector',
        [string]$BaseAddress,
        [string]$OutFile,
        [switch]$SkipDynamic,
        [switch]$SkipNdesChecks,
        [switch]$SkipNetworkChecks,
        [switch]$SkipEventLogChecks,
        [ValidateRange(1, 300)] [int]$TimeoutSeconds = 30,
        [ValidateRange(1, 30)] [int]$EventLookbackDays = 2,
        [ValidateRange(1, 100)] [int]$MaxEvents = 5,
        [ValidateRange(1, 8760)] [int]$ConnectorStaleHours = 24,
        [switch]$CollectLogs,
        [string]$DiagnosticBundlePath,
        [ValidateRange(1, 100)] [int]$IisLogCount = 3,
        [switch]$HtmlReport,
        [string]$HtmlReportPath,
        [switch]$PassThru
    )

    if ($script:DiagnosticRunning) {
        throw 'A Certificate Connector diagnostic is already running in this module session.'
    }

    $script:DiagnosticRunning = $true
    $originalSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
        # Best-effort probes are the norm here, but an explicit -ErrorAction from
        # the caller still wins.
        if (-not $PSBoundParameters.ContainsKey('ErrorAction')) {
            $ErrorActionPreference = 'Continue'
        }
        $script:StartedAtUtc = (Get-Date).ToUniversalTime()
        $script:Results = New-Object System.Collections.Generic.List[object]
        $script:Transcript = New-Object System.Collections.Generic.List[string]
        $script:BundleStage = $null
        $script:BundleTarget = $null
        $script:capturedCertificateBytes = $null
        $script:capturedPolicyErrors = $null

        $context = Initialize-DiagnosticContext `
            -ConnectorType $ConnectorType `
            -BaseAddress $BaseAddress `
            -OutFile $OutFile `
            -SkipDynamic:$SkipDynamic `
            -SkipNdesChecks:$SkipNdesChecks `
            -SkipNetworkChecks:$SkipNetworkChecks `
            -SkipEventLogChecks:$SkipEventLogChecks `
            -TimeoutSeconds $TimeoutSeconds `
            -EventLookbackDays $EventLookbackDays `
            -MaxEvents $MaxEvents `
            -ConnectorStaleHours $ConnectorStaleHours `
            -CollectLogs:$CollectLogs `
            -DiagnosticBundlePath $DiagnosticBundlePath `
            -IisLogCount $IisLogCount `
            -HtmlReport:$HtmlReport `
            -HtmlReportPath $HtmlReportPath `
            -PassThru:$PassThru

    #region Phase 1 - Configuration Discovery

Write-Line ''
Write-Line '===============================================================================' 'White'
Write-Line ' Intune Certificate Connector + NDES complete pre-flight diagnostic' 'White'
Write-Line ("   host={0}  user={1}\{2}  {3}" -f $env:COMPUTERNAME, $env:USERDOMAIN, $env:USERNAME, (Get-Date)) 'DarkGray'
Write-Line '===============================================================================' 'White'

Write-DiagnosticSection 'Configuration discovered from the connector'
$connKey = "SOFTWARE\Microsoft\MicrosoftIntune\$ConnectorType"
$proxyKey = "$connKey\Proxy"
$statusKey = "$connKey\ConnectionStatus"

$installFolder = Get-Reg $connKey 'InstallFolder'
$storedBase = Get-Reg $connKey 'BaseServiceAddress'
$encThumb = Get-Reg $connKey 'EncryptionCertThumbprint'
$lastConn = Get-Reg $statusKey 'LastConnectionTime'
if (-not $lastConn) { $lastConn = Get-Reg $connKey 'LastConnectionTime' }
$issueDetails = Get-Reg $statusKey 'IssueDetails'
if (-not $issueDetails) { $issueDetails = Get-Reg $connKey 'IssueDetails' }

$proxyServer = Get-Reg $proxyKey 'ProxyServer'
$proxyPort = Get-Reg $proxyKey 'Port'
$proxyUser = Get-Reg $proxyKey 'Username'

if (-not $BaseAddress) {
    if ($storedBase) { $BaseAddress = $storedBase } else { $BaseAddress = 'https://manage.microsoft.com' }
}
$baseUri = $null
try { $baseUri = [Uri]$BaseAddress } catch {}
$baseHost = if ($baseUri -and $baseUri.IsAbsoluteUri) { $baseUri.Host } else { 'manage.microsoft.com' }
$agentsHost = "agents.$baseHost"
$locationUrl = "https://$agentsHost/RestUserAuthLocationService/RestUserAuthLocationService/Certificate/ServiceAddresses"
$fqdn = Get-FullyQualifiedHostName
$product = Get-ConnectorProduct
$proxyResolution = Resolve-ConnectorProxyUri -Server $proxyServer -Port $proxyPort
$proxyUri = if ($proxyResolution.Valid) { $proxyResolution.Uri } else { $null }

$context.BaseAddress = $BaseAddress
$context.ConnKey = $connKey
$context.InstallFolder = $installFolder
$context.BaseHost = $baseHost
$context.AgentsHost = $agentsHost
$context.LocationUrl = $locationUrl
$context.Fqdn = $fqdn
$context.ProxyServer = $proxyServer
$context.ProxyPort = $proxyPort
$context.ProxyUser = $proxyUser
$context.ProxyResolution = $proxyResolution
$context.ProxyUri = $proxyUri
$context.Product = $product

Add-Result -Id 'CFG01' -Category Config -Name 'Connector installation discovered' `
    -Status $(if ($installFolder -or $product) { 'Pass' } else { 'Warn' }) `
    -Detail ("Type={0}; Product={1}; Version={2}; InstallFolder={3}" -f $ConnectorType, $product.DisplayName, $product.DisplayVersion, $installFolder) `
    -Remediation 'If blank, install the Certificate Connector or specify the connector registry leaf with -ConnectorType.'
Add-Result -Id 'CFG02' -Category Config -Name 'Intune base service address' -Status 'Info' `
    -Detail ("Base={0}; agents host={1}; location URL={2}" -f $BaseAddress, $agentsHost, $locationUrl)
Add-Result -Id 'CFG03' -Category Config -Name 'Agent encryption certificate thumbprint' `
    -Status $(if ($encThumb) { 'Pass' } else { 'Info' }) `
    -Detail $(if ($encThumb) { "Thumbprint=$encThumb (connector is enrolled)." } else { 'Not set; client-certificate checks are limited until enrollment completes.' })
if ($lastConn) {
    Add-Result -Id 'CFG04' -Category Config -Name 'Last successful connection value' -Status 'Info' -Detail "LastConnectionTime=$lastConn"
}
if ($issueDetails) {
    Add-Result -Id 'CFG05' -Category Config -Name 'Connector-reported issue detail' -Status 'Warn' -Detail "IssueDetails=$issueDetails"
}
Add-Result -Id 'CFG06' -Category Config -Name 'Connector proxy configuration' -Status 'Info' `
    -Detail $(if ($proxyServer) { "ProxyServer=$proxyServer; Port=$proxyPort; UsernameConfigured=$(-not [string]::IsNullOrEmpty($proxyUser)); Parsed=$($proxyResolution.Candidate)" } else { 'No connector proxy configured; direct internet access is expected.' })

    #endregion Phase 1 - Configuration Discovery

    #region Phase 2 - Local Prerequisites

Write-DiagnosticSection 'Local prerequisites'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
Add-Result -Id 'LOC01' -Category Local -Name 'Running elevated (Administrator)' `
    -Status $(if ($isAdmin) { 'Pass' } else { 'Warn' }) `
    -Detail "IsAdmin=$isAdmin" `
    -Remediation 'Run from an elevated Windows PowerShell session for complete role, IIS, account-right, and event-log results.'

# Win32_OperatingSystem reports the real build number. [Environment]::OSVersion
# is shimmed to 6.2 for hosts without a supportedOS application manifest.
$os = $null
$osSource = 'Win32_OperatingSystem'
try {
    $osVersionText = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).Version
    if ($osVersionText) { $os = [Version]$osVersionText }
} catch {}
if (-not $os) {
    $os = [Environment]::OSVersion.Version
    $osSource = 'Environment.OSVersion'
}
$osOk = ($os.Major -gt 6) -or ($os.Major -eq 6 -and $os.Minor -ge 3)
Add-Result -Id 'LOC02' -Category Local -Name 'Operating system version' `
    -Status $(if ($osOk) { 'Pass' } else { 'Fail' }) `
    -Detail "OSVersion=$os; Source=$osSource" `
    -Remediation 'Windows Server 2012 R2 or later is required. Windows Server 2019 or later is required for Certificate Connector strong mapping support.'

$ndpRelease = Get-Reg 'SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' 'Release'
$netOk = ($null -ne $ndpRelease -and [int]$ndpRelease -ge 461808)
Add-Result -Id 'LOC03' -Category Local -Name '.NET Framework 4.7.2 or later' `
    -Status $(if ($netOk) { 'Pass' } else { 'Fail' }) `
    -Detail "NDP v4 Full Release=$ndpRelease" `
    -Remediation 'Install .NET Framework 4.7.2 or later; the Certificate Connector targets .NET Framework 4.7.2.'

$schannelClient = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client'
$tls12Enabled = Get-Reg $schannelClient 'Enabled'
$tls12Disabled = Get-Reg $schannelClient 'DisabledByDefault'
$tls12BadClient = ($null -ne $tls12Enabled -and [int]$tls12Enabled -eq 0) -or
    ($null -ne $tls12Disabled -and [int]$tls12Disabled -eq 1)
$netStrong = Get-Reg 'SOFTWARE\Microsoft\.NETFramework\v4.0.30319' 'SchUseStrongCrypto'
$netStrongWow = Get-Reg 'SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319' 'SchUseStrongCrypto'
$systemTls = Get-Reg 'SOFTWARE\Microsoft\.NETFramework\v4.0.30319' 'SystemDefaultTlsVersions'
$systemTlsWow = Get-Reg 'SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319' 'SystemDefaultTlsVersions'
$strongOk = (($null -ne $netStrong -and [int]$netStrong -eq 1) -or ($null -ne $netStrongWow -and [int]$netStrongWow -eq 1))
$tlsStatus = if ($tls12BadClient) { 'Fail' } elseif (-not $strongOk) { 'Warn' } else { 'Pass' }
Add-Result -Id 'LOC04' -Category Local -Name 'TLS 1.2 available for .NET and SChannel' -Status $tlsStatus -Case `
    -Detail ("TLS1.2 Client Enabled={0}; DisabledByDefault={1}; SchUseStrongCrypto x64={2}, x86={3}; SystemDefaultTlsVersions x64={4}, x86={5}" -f $tls12Enabled, $tls12Disabled, $netStrong, $netStrongWow, $systemTls, $systemTlsWow) `
    -Remediation 'Ensure SChannel TLS 1.2 Client is not disabled and configure SchUseStrongCrypto/SystemDefaultTlsVersions under both .NET Framework v4 registry views.'

if ($SkipNetworkChecks) {
    Add-Result -Id 'LOC05' -Category Local -Name 'System clock within tolerance' -Status 'Info' -Detail 'Skipped with -SkipNetworkChecks.'
} else {
    $referenceTime = $null
    foreach ($probeUri in @("https://$agentsHost/", "https://$baseHost/", 'http://www.microsoft.com/')) {
        if ($referenceTime) { break }
        foreach ($method in @('GET', 'HEAD')) {
            if ($referenceTime) { break }
            try {
                $request = [Net.WebRequest]::Create($probeUri)
                $request.Method = $method
                $request.Timeout = [Math]::Min($TimeoutSeconds, 10) * 1000
                if ($proxyUri) { $request.Proxy = New-Object Net.WebProxy($proxyUri, $false) }
                $response = $null
                $dateHeader = $null
                try {
                    $response = $request.GetResponse()
                    $dateHeader = $response.Headers['Date']
                } catch {
                    if ($_.Exception.Response) { $dateHeader = $_.Exception.Response.Headers['Date'] }
                } finally {
                    if ($response) { $response.Close() }
                }
                if ($dateHeader) {
                    # The HTTP Date header is RFC 1123, so it must be parsed with
                    # the invariant culture to stay correct on every locale.
                    $headerDate = [DateTimeOffset]::MinValue
                    if ([DateTimeOffset]::TryParse(
                            $dateHeader,
                            [Globalization.CultureInfo]::InvariantCulture,
                            [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AllowWhiteSpaces,
                            [ref]$headerDate)) {
                        $referenceTime = $headerDate.UtcDateTime
                    }
                }
            } catch {}
        }
    }

    if ($referenceTime) {
        $clockSkew = [Math]::Abs(((Get-Date).ToUniversalTime() - $referenceTime).TotalMinutes)
        Add-Result -Id 'LOC05' -Category Local -Name 'System clock within tolerance' `
            -Status $(if ($clockSkew -le 5) { 'Pass' } else { 'Fail' }) -Case `
            -Detail ("Local-to-server Date header skew={0:N1} minutes." -f $clockSkew) `
            -Remediation 'Synchronize Windows time. Clock skew can invalidate certificates and revocation data.'
    } else {
        Add-Result -Id 'LOC05' -Category Local -Name 'System clock within tolerance' -Status 'Info' `
            -Detail 'No reference Date header could be obtained; verify time synchronization manually.'
    }
}

$knownRoots = @{
    'DigiCert Global Root G2' = 'DF3C24F9BFD666761B268073FE06D1CC8D4F82A4'
    'DigiCert Global Root CA' = 'A8985D3A65E5E5C4B2D7D66D40C6DD2FB19C5436'
    'Microsoft RSA Root Certificate Authority 2017' = '73A5E64A3BFF8316FF0EDCCC618A906E4EAE4D74'
    'Microsoft ECC Root Certificate Authority 2017' = '999A64C37FF47D9FAB95F14769891460EEC4C3C5'
    'Baltimore CyberTrust Root' = 'D4DE20D05E66FC53FE1A50882C78DB2852CAE474'
}
$rootStore = @{}
try {
    Get-ChildItem Cert:\LocalMachine\Root -ErrorAction Stop | ForEach-Object {
        $rootStore[$_.Thumbprint.ToUpperInvariant()] = $true
    }
} catch {}
$missingRoots = @()
foreach ($entry in $knownRoots.GetEnumerator()) {
    if (-not $rootStore.ContainsKey($entry.Value)) { $missingRoots += $entry.Key }
}
Add-Result -Id 'LOC06' -Category Local -Name 'Reference Microsoft and DigiCert roots present' `
    -Status $(if ($missingRoots.Count -eq 0) { 'Pass' } else { 'Warn' }) -Case `
    -Detail $(if ($missingRoots.Count -eq 0) { "All $($knownRoots.Count) reference roots are present." } else { 'Missing reference roots: ' + ($missingRoots -join ', ') }) `
    -Remediation 'Update trusted roots or enable automatic root update. NET07 validates the actual live service chain and is authoritative.'

$connectorServiceNames = @(
    'PFXCertificateConnectorSvc',
    'PKICertificateConnectorSvc',
    'PkiCreateConnectorSvc',
    'PkiRevokeConnectorSvc',
    'PfxCreateLegacyConnectorSvc',
    'PKIConnectorSvc'
)
$connectorServices = @()
foreach ($serviceName in $connectorServiceNames) {
    $details = Get-ServiceDetail $serviceName
    if ($details) { $connectorServices += $details }
}
$pendingServices = @($connectorServices | Where-Object { $_.Status -notin @('Running', 'Stopped') })
$serviceSummary = @($connectorServices | ForEach-Object {
        "{0}={1}, Account={2}, StartedUtc={3}" -f $_.Name, $_.Status, $_.StartName, $_.StartedUtc
    }) -join '; '
Add-Result -Id 'LOC07' -Category Local -Name 'Connector service state' `
    -Status $(if ($pendingServices.Count -gt 0) { 'Warn' } elseif ($connectorServices.Count -gt 0) { 'Pass' } else { 'Info' }) `
    -Detail $(if ($serviceSummary) { $serviceSummary } else { 'No known Certificate Connector services were found.' }) `
    -Remediation 'A service stuck in StartPending can be caused by a synchronous service-locator TLS or proxy failure; review the network checks.'

$clientCert = $null
if ($encThumb) {
    $normalizedThumbprint = ([string]$encThumb -replace '\s', '').ToUpperInvariant()
    try { $clientCert = Get-Item "Cert:\LocalMachine\My\$normalizedThumbprint" -ErrorAction Stop } catch {}
    if ($clientCert) {
        $now = Get-Date
        $clientCertValid = $clientCert.NotBefore -le $now -and $clientCert.NotAfter -gt $now -and $clientCert.HasPrivateKey
        Add-Result -Id 'LOC08' -Category Local -Name 'Agent encryption certificate usable' `
            -Status $(if ($clientCertValid) { 'Pass' } else { 'Fail' }) -Case `
            -Detail ("Subject={0}; NotBefore={1:u}; NotAfter={2:u}; HasPrivateKey={3}" -f $clientCert.Subject, $clientCert.NotBefore.ToUniversalTime(), $clientCert.NotAfter.ToUniversalTime(), $clientCert.HasPrivateKey) `
            -Remediation 'Re-enroll the connector if the agent certificate is missing, not yet valid, expired, or lacks its private key.'
    } else {
        Add-Result -Id 'LOC08' -Category Local -Name 'Agent encryption certificate usable' -Status 'Warn' -Case `
            -Detail "Thumbprint $normalizedThumbprint was not found in LocalMachine\My." `
            -Remediation 'Re-enroll the connector to obtain a new agent encryption certificate.'
    }
} else {
    Add-Result -Id 'LOC08' -Category Local -Name 'Agent encryption certificate usable' -Status 'Info' `
        -Detail 'Connector is not enrolled; no EncryptionCertThumbprint is configured.'
}

$lastBootUtc = $null
try {
    $lastBootValue = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime
    if ($lastBootValue) { $lastBootUtc = ([DateTime]$lastBootValue).ToUniversalTime() }
} catch {}
Add-Result -Id 'LOC09' -Category Local -Name 'Operating system last boot time' -Status 'Info' `
    -Detail $(if ($lastBootUtc) { "LastBootUtc=$($lastBootUtc.ToString('u'))" } else { 'Last boot time could not be read.' })

$context.ClientCert = $clientCert
$context.ConnectorServiceNames = $connectorServiceNames
$context.ConnectorServices = $connectorServices
$context.ServiceSummary = $serviceSummary
$context.OperatingSystemVersion = $os

    #endregion Phase 2 - Local Prerequisites

    #region Phase 3 - Connector Health

Write-DiagnosticSection 'Certificate Connector configuration and health'

Add-Result -Id 'CON01' -Category Connector -Name 'Installed product details' `
    -Status $(if ($product -or $installFolder) { 'Pass' } else { 'Warn' }) `
    -Detail ("DisplayName={0}; Version={1}; InstallDate={2}; Publisher={3}; InstallFolder={4}" -f $product.DisplayName, $product.DisplayVersion, $product.InstallDate, $product.Publisher, $installFolder) `
    -Remediation 'Install and configure the current Certificate Connector for Microsoft Intune.'

$connectorFeatures = [ordered]@{
    PFX        = Get-Reg $connKey 'EnablePFxCreate'
    PFXImport  = Get-Reg $connKey 'EnablePFxImport'
    Revocation = Get-Reg $connKey 'EnableRevocation'
    SCEP       = Get-Reg $connKey 'EnableSCEP'
}
$enabledFeatures = @($connectorFeatures.GetEnumerator() | Where-Object { [string]$_.Value -eq '1' } | ForEach-Object { $_.Key })
$featureDetail = @($connectorFeatures.GetEnumerator() | ForEach-Object { "{0}={1}" -f $_.Key, $_.Value }) -join '; '
Add-Result -Id 'CON02' -Category Connector -Name 'Enabled connector features' `
    -Status $(if ($enabledFeatures.Count -gt 0) { 'Pass' } elseif ($product -or $installFolder) { 'Warn' } else { 'Info' }) `
    -Detail "$featureDetail; Enabled=$($enabledFeatures -join ', ')" `
    -Remediation 'Run connector configuration and enable each feature this server is intended to service.'

Add-Result -Id 'CON03' -Category Connector -Name 'Connector services and startup accounts' `
    -Status $(if ($connectorServices.Count -gt 0) { 'Pass' } elseif ($product -or $installFolder) { 'Fail' } else { 'Info' }) `
    -Detail $(if ($serviceSummary) { $serviceSummary } else { 'No known connector service is installed.' }) `
    -Remediation 'Repair or reinstall the connector if the product is installed but no connector service exists.'

$connectorAccounts = @($connectorServices | Where-Object { $_.StartName } | Select-Object -ExpandProperty StartName -Unique)
if ($connectorAccounts.Count -eq 0) {
    Add-Result -Id 'CON04' -Category Connector -Name 'Connector service-account prerequisites' -Status 'Info' `
        -Detail 'No connector service account could be discovered.'
} else {
    $accountIndex = 0
    foreach ($connectorAccount in $connectorAccounts) {
        $accountIndex++
        $isSystem = $connectorAccount -in @('LocalSystem', 'NT AUTHORITY\SYSTEM', '.\LocalSystem')
        $right = Test-AccountUserRight -AccountName $connectorAccount
        $adminMembership = Test-LocalGroupMembershipBySid -AccountName $connectorAccount -GroupSid 'S-1-5-32-544'
        $accountStatus = if ($isSystem) {
            'Pass'
        } elseif ($right.Known -and -not $right.HasRight) {
            'Fail'
        } elseif ($adminMembership.Known -and -not $adminMembership.IsMember) {
            'Fail'
        } elseif (-not $right.Known -or -not $adminMembership.Known) {
            'Warn'
        } else {
            'Pass'
        }
        Add-Result -Id ("CON04:{0}" -f $accountIndex) -Category Connector -Name "Connector account $connectorAccount" `
            -Status $accountStatus `
            -Detail ("LocalSystem={0}; SeServiceLogonRight={1}/{2}; LocalAdministrators={3}/{4}; Errors={5} {6}" -f $isSystem, $right.Known, $right.HasRight, $adminMembership.Known, $adminMembership.IsMember, $right.Error, $adminMembership.Error) `
            -Remediation 'Supported connector identities are LocalSystem or a domain account with Log on as a service and local administrator permissions, plus the required CA/template permissions.'
    }
}

$lastConnectionUtc = ConvertTo-UtcDateTime $lastConn
if ($lastConn -and -not $lastConnectionUtc) {
    Add-Result -Id 'CON05' -Category Connector -Name 'Connector last successful connection' -Status 'Warn' `
        -Detail "LastConnectionTime='$lastConn' could not be parsed." `
        -Remediation 'Review the connector ConnectionStatus registry values and event logs.'
} elseif ($lastConnectionUtc) {
    $connectionAge = ((Get-Date).ToUniversalTime() - $lastConnectionUtc).TotalHours
    Add-Result -Id 'CON05' -Category Connector -Name 'Connector last successful connection' `
        -Status $(if ($connectionAge -le $ConnectorStaleHours -and $connectionAge -ge -1) { 'Pass' } else { 'Warn' }) `
        -Detail ("LastConnectionUtc={0:u}; AgeHours={1:N1}; ThresholdHours={2}" -f $lastConnectionUtc, $connectionAge, $ConnectorStaleHours) `
        -Remediation 'If the connector has not connected recently, review service state, proxy/TLS checks, connector health events, and tenant connector status.'
} else {
    Add-Result -Id 'CON05' -Category Connector -Name 'Connector last successful connection' -Status 'Info' `
        -Detail 'LastConnectionTime is not configured; the connector may not have completed enrollment.'
}

    #endregion Phase 3 - Connector Health

    #region Phase 4 - NDES, IIS, and Certificates

if ($SkipNdesChecks) {
    Write-DiagnosticSection 'NDES and IIS validation'
    Add-Result -Id 'NDES00' -Category NDES -Name 'NDES and IIS validation' -Status 'Info' -Detail 'Skipped with -SkipNdesChecks.'
} else {
    Write-DiagnosticSection 'NDES server roles and Windows features'

    $computerSystem = $null
    try { $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop } catch {}
    Add-Result -Id 'NDES01' -Category NDES -Name 'Server is joined to an Active Directory domain' `
        -Status $(if ($computerSystem -and $computerSystem.PartOfDomain) { 'Pass' } elseif ($computerSystem) { 'Fail' } else { 'Warn' }) `
        -Detail $(if ($computerSystem) { "PartOfDomain=$($computerSystem.PartOfDomain); Domain=$($computerSystem.Domain)" } else { 'Win32_ComputerSystem could not be queried.' }) `
        -Remediation 'The NDES and connector server must be domain-joined and in the same forest as the Enterprise CA.'

    $isDomainController = $computerSystem -and [int]$computerSystem.DomainRole -in @(4, 5)
    Add-Result -Id 'NDES02' -Category NDES -Name 'Server is not a domain controller' `
        -Status $(if (-not $computerSystem) { 'Warn' } elseif ($isDomainController) { 'Fail' } else { 'Pass' }) `
        -Detail $(if ($computerSystem) { "DomainRole=$($computerSystem.DomainRole)" } else { 'Domain role is unavailable.' }) `
        -Remediation 'Move NDES and the Certificate Connector to a supported member server.'

    $roleState = Get-WindowsFeatureState @('ADCS-Cert-Authority', 'ADCS-Device-Enrollment')
    $caFeature = $roleState.Features | Where-Object { $_.Name -eq 'ADCS-Cert-Authority' } | Select-Object -First 1
    $ndesFeature = $roleState.Features | Where-Object { $_.Name -eq 'ADCS-Device-Enrollment' } | Select-Object -First 1
    $caInstalled = $caFeature -and $caFeature.Installed
    $ndesInstalled = $ndesFeature -and $ndesFeature.Installed
    $context.NdesRoleInstalled = [bool]$ndesInstalled
    $context.NdesRoleKnown = $roleState.Available -and -not $roleState.Error
    $roleStatus = if (-not $context.NdesRoleKnown) {
        'Warn'
    } elseif ($ndesInstalled -and -not $caInstalled) {
        'Pass'
    } else {
        'Fail'
    }
    Add-Result -Id 'NDES03' -Category NDES -Name 'NDES installed and issuing CA role separated' -Status $roleStatus `
        -Detail ("NDES={0}; CertificationAuthority={1}; Error={2}" -f $ndesInstalled, $caInstalled, $roleState.Error) `
        -Remediation 'Install Network Device Enrollment Service on this member server and do not install the issuing Certification Authority role on the same server.'

    $requiredFeatureNames = @(
        'Web-Server',
        'Web-Filtering',
        'Web-Net-Ext45',
        'Web-Asp-Net45',
        'NET-WCF-HTTP-Activation45',
        'Web-Mgmt-Console',
        'Web-Metabase',
        'Web-WMI',
        'NET-Framework-Features',
        'NET-HTTP-Activation'
    )
    $featureState = Get-WindowsFeatureState $requiredFeatureNames
    $missingFeatures = @()
    if ($featureState.Available -and -not $featureState.Error) {
        foreach ($requiredName in $requiredFeatureNames) {
            $feature = $featureState.Features | Where-Object { $_.Name -eq $requiredName } | Select-Object -First 1
            if (-not $feature -or -not $feature.Installed) { $missingFeatures += $requiredName }
        }
    }
    Add-Result -Id 'NDES04' -Category NDES -Name 'Required NDES and IIS Windows features' `
        -Status $(if (-not $featureState.Available -or $featureState.Error) { 'Warn' } elseif ($missingFeatures.Count -eq 0) { 'Pass' } else { 'Fail' }) `
        -Detail $(if (-not $featureState.Available -or $featureState.Error) { "Feature state unavailable: $($featureState.Error)" } elseif ($missingFeatures.Count -eq 0) { 'All required role services and features are installed.' } else { 'Missing: ' + ($missingFeatures -join ', ') }) `
        -Remediation 'Install the documented NDES prerequisites: IIS Request Filtering, ASP.NET/.NET 3.5 and 4.7.2, WCF HTTP Activation, and IIS 6 Metabase/WMI compatibility.'

    if ($ndesInstalled -and $os -lt [Version]'10.0.17763') {
        Add-Result -Id 'NDES05' -Category NDES -Name 'Strong certificate mapping server support' -Status 'Warn' `
            -Detail "OSVersion=$os; Certificate Connector strong mapping is supported on Windows Server 2019 or later." `
            -Remediation 'Use Windows Server 2019 or later when strong certificate mapping support is required.'
    } else {
        Add-Result -Id 'NDES05' -Category NDES -Name 'Strong certificate mapping server support' -Status 'Pass' `
            -Detail "OSVersion=$os"
    }

    $escPaths = @(
        'SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}',
        'SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}'
    )
    $escValues = @($escPaths | ForEach-Object { Get-Reg $_ 'IsInstalled' } | Where-Object { $null -ne $_ })
    $escEnabled = @($escValues | Where-Object { [int]$_ -ne 0 })
    Add-Result -Id 'NDES06' -Category NDES -Name 'Internet Explorer Enhanced Security Configuration disabled' `
        -Status $(if ($escValues.Count -eq 0) { 'Warn' } elseif ($escEnabled.Count -eq 0) { 'Pass' } else { 'Fail' }) `
        -Detail $(if ($escValues.Count -eq 0) { 'ESC registry state was not found.' } else { "IsInstalled values=$($escValues -join ',')" }) `
        -Remediation 'Disable Enhanced Security Configuration on the NDES and Certificate Connector server.'

    $strongProviderPath = 'HKLM:\SOFTWARE\Microsoft\Cryptography\Defaults\Provider\Microsoft Strong Cryptographic Provider'
    $strongProviderPresent = Test-Path $strongProviderPath
    Add-Result -Id 'NDES07' -Category NDES -Name 'Microsoft Strong Cryptographic Provider available' `
        -Status $(if ($strongProviderPresent) { 'Pass' } else { 'Warn' }) `
        -Detail "ProviderRegistryPathPresent=$strongProviderPresent" `
        -Remediation 'This is an availability heuristic, not proof of the provider selected during NDES setup. Review NDES cryptography configuration if absent.'

    if ($context.NdesRoleKnown -and -not $context.NdesRoleInstalled) {
        Write-DiagnosticSection 'IIS and NDES service account'
        Add-Result -Id 'IIS00' -Category IIS -Name 'NDES-specific IIS and account checks' -Status 'Info' `
            -Detail 'NDES role is not installed; SCEP application-pool, account, MSCEP, and NDES certificate checks are not applicable.'
    } elseif (-not $context.NdesRoleKnown) {
        Write-DiagnosticSection 'IIS and NDES service account'
        Add-Result -Id 'IIS00' -Category IIS -Name 'NDES-specific IIS and account checks' -Status 'Warn' `
            -Detail 'NDES role state could not be determined; NDES-specific IIS and certificate checks were skipped.' `
            -Remediation 'Run on Windows Server with the ServerManager module available.'
    } else {
    Write-DiagnosticSection 'IIS and NDES service account'
    $iisConfiguration = Get-IisScepConfiguration
    $appPoolAccount = Get-AppPoolAccountName $iisConfiguration
    Add-Result -Id 'IIS01' -Category IIS -Name 'SCEP application pool exists and is started' `
        -Status $(if (-not $iisConfiguration.Available) { 'Warn' } elseif (-not $iisConfiguration.PoolExists) { 'Fail' } elseif ($iisConfiguration.PoolState -eq 'Started') { 'Pass' } else { 'Fail' }) `
        -Detail ("Available={0}; Exists={1}; State={2}; Error={3}" -f $iisConfiguration.Available, $iisConfiguration.PoolExists, $iisConfiguration.PoolState, $iisConfiguration.Error) `
        -Remediation 'Install/configure NDES and ensure the SCEP application pool can start. A 503 often indicates missing account permissions.'
    Add-Result -Id 'IIS02' -Category IIS -Name 'SCEP application pool identity' `
        -Status $(if ($appPoolAccount) { 'Pass' } else { 'Warn' }) `
        -Detail ("IdentityType={0}; Account={1}" -f $iisConfiguration.IdentityType, $appPoolAccount) `
        -Remediation 'Configure the intended NDES application-pool account and grant its documented template and local permissions.'

    if ($appPoolAccount) {
        $iisUsersMembership = Test-LocalGroupMembershipBySid -AccountName $appPoolAccount -GroupSid 'S-1-5-32-568'
        Add-Result -Id 'IIS03' -Category IIS -Name 'NDES account is a member of IIS_IUSRS' `
            -Status $(if (-not $iisUsersMembership.Known) { 'Warn' } elseif ($iisUsersMembership.IsMember) { 'Pass' } else { 'Fail' }) `
            -Detail ("Account={0}; Group={1}; Known={2}; Member={3}; Error={4}" -f $appPoolAccount, $iisUsersMembership.GroupName, $iisUsersMembership.Known, $iisUsersMembership.IsMember, $iisUsersMembership.Error) `
            -Remediation 'Add the NDES application-pool account to the local IIS_IUSRS group.'

        $ndesAdminMembership = Test-LocalGroupMembershipBySid -AccountName $appPoolAccount -GroupSid 'S-1-5-32-544'
        Add-Result -Id 'IIS04' -Category IIS -Name 'NDES account local-administrator exposure' `
            -Status $(if (-not $ndesAdminMembership.Known) { 'Info' } elseif ($ndesAdminMembership.IsMember) { 'Warn' } else { 'Pass' }) `
            -Detail ("Account={0}; LocalAdministrators={1}; Error={2}" -f $appPoolAccount, $ndesAdminMembership.IsMember, $ndesAdminMembership.Error) `
            -Remediation 'Prefer least privilege for the NDES application-pool identity; IIS_IUSRS and certificate-template permissions are required.'
    } else {
        Add-Result -Id 'IIS03' -Category IIS -Name 'NDES account is a member of IIS_IUSRS' -Status 'Warn' `
            -Detail 'SCEP application-pool account is unknown.'
        Add-Result -Id 'IIS04' -Category IIS -Name 'NDES account local-administrator exposure' -Status 'Info' `
            -Detail 'SCEP application-pool account is unknown.'
    }

    $httpParameters = 'SYSTEM\CurrentControlSet\Services\HTTP\Parameters'
    $maxFieldLength = Get-Reg $httpParameters 'MaxFieldLength'
    $maxRequestBytes = Get-Reg $httpParameters 'MaxRequestBytes'
    $longRequestOk = [string]$maxFieldLength -eq '65534' -and [string]$maxRequestBytes -eq '65534'
    Add-Result -Id 'IIS05' -Category IIS -Name 'HTTP.sys long-request compatibility values' `
        -Status $(if ($longRequestOk) { 'Pass' } else { 'Warn' }) `
        -Detail "MaxFieldLength=$maxFieldLength; MaxRequestBytes=$maxRequestBytes; Expected=65534" `
        -Remediation 'Review long-URI requirements for the NDES publication design. Where applicable, set both HTTP.sys values to 65534 and restart the server.'

    $mscepPath = 'SOFTWARE\Microsoft\Cryptography\MSCEP'
    $signatureTemplate = Get-Reg $mscepPath 'SignatureTemplate'
    $encryptionTemplate = Get-Reg $mscepPath 'EncryptionTemplate'
    $generalTemplate = Get-Reg $mscepPath 'GeneralPurposeTemplate'
    $templateValues = @($signatureTemplate, $encryptionTemplate, $generalTemplate)
    $templateValuesPresent = @($templateValues | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $defaultTemplates = @($templateValuesPresent | Where-Object { [string]$_ -eq 'IPSECIntermediateOffline' })
    $templateStatus = if ($templateValuesPresent.Count -ne 3) {
        'Fail'
    } elseif ($defaultTemplates.Count -eq 3) {
        'Fail'
    } elseif ($defaultTemplates.Count -gt 0) {
        'Warn'
    } else {
        'Pass'
    }
    Add-Result -Id 'IIS06' -Category IIS -Name 'MSCEP certificate-template registry configuration' -Status $templateStatus `
        -Detail ("SignatureTemplate={0}; EncryptionTemplate={1}; GeneralPurposeTemplate={2}" -f $signatureTemplate, $encryptionTemplate, $generalTemplate) `
        -Remediation 'Set each applicable MSCEP registry value to the certificate template name, not its display name; do not leave applicable values at IPSECIntermediateOffline.'

    Write-DiagnosticSection 'NDES and IIS certificates'
    # A cross-signed copy of a root that is also installed as a self-signed root
    # is expected, so it is reported separately from a genuinely misplaced
    # intermediate certificate.
    $misplacedIntermediates = @()
    $crossSignedRoots = @()
    try {
        $rootCertificates = @(Get-ChildItem Cert:\LocalMachine\Root -ErrorAction Stop)
        $selfSignedRootSubjects = @{}
        foreach ($rootCertificate in $rootCertificates) {
            if ($rootCertificate.Issuer -eq $rootCertificate.Subject) {
                $selfSignedRootSubjects[$rootCertificate.Subject] = $true
            }
        }
        foreach ($rootCertificate in $rootCertificates) {
            if ($rootCertificate.Issuer -eq $rootCertificate.Subject) { continue }
            if ($selfSignedRootSubjects.ContainsKey($rootCertificate.Subject)) {
                $crossSignedRoots += $rootCertificate
            } else {
                $misplacedIntermediates += $rootCertificate
            }
        }
    } catch {}
    Add-Result -Id 'CERT01' -Category Certificate -Name 'Trusted Root store has no intermediate certificates' `
        -Status $(if ($misplacedIntermediates.Count -eq 0) { 'Pass' } else { 'Warn' }) `
        -Detail ("CrossSignedRoots={0}; Misplaced={1}" -f $crossSignedRoots.Count, $(if ($misplacedIntermediates.Count -eq 0) { '<none>' } else { ($misplacedIntermediates | ForEach-Object { "$($_.Subject) [$($_.Thumbprint)]" }) -join '; ' })) `
        -Remediation 'Move genuine intermediate CA certificates to LocalMachine\CA after confirming the intended trust chain. NET07 validates the live service chain and is authoritative.'

    $machineCertificates = @()
    try { $machineCertificates = @(Get-ChildItem Cert:\LocalMachine\My -ErrorAction Stop) } catch {}
    $ndesTemplateRequirements = @('EnrollmentAgentOffline', 'CEPEncryption')
    $templateIndex = 1
    foreach ($requiredTemplate in $ndesTemplateRequirements) {
        $matchingCertificates = @($machineCertificates | Where-Object {
                (Get-CertificateTemplateName $_) -contains $requiredTemplate
            })
        $usableCertificates = @($matchingCertificates | Where-Object {
                $_.NotBefore -le (Get-Date) -and $_.NotAfter -gt (Get-Date) -and $_.HasPrivateKey
            })
        Add-Result -Id ("CERT0{0}" -f ($templateIndex + 1)) -Category Certificate -Name "$requiredTemplate certificate" `
            -Status $(if ($usableCertificates.Count -gt 0) { 'Pass' } else { 'Fail' }) `
            -Detail $(if ($matchingCertificates.Count -eq 0) { 'Certificate not found by template OID.' } else { ($matchingCertificates | ForEach-Object { "Subject=$($_.Subject), NotAfter=$($_.NotAfter.ToUniversalTime().ToString('u')), HasPrivateKey=$($_.HasPrivateKey)" }) -join '; ' }) `
            -Remediation 'Configure NDES with the required permissions or renew/reinstall NDES so a valid template certificate with a private key is issued.'
        $templateIndex++
    }

    $httpsBindings = @($iisConfiguration.HttpsBindings)
    $bindingCertificates = @()
    foreach ($binding in $httpsBindings) {
        try {
            $hash = $binding.certificateHash
            if ($hash -is [byte[]]) { $hash = ($hash | ForEach-Object { $_.ToString('X2') }) -join '' }
            $hash = [string]$hash -replace '\s', ''
            $storeName = [string]$binding.certificateStoreName
            if ([string]::IsNullOrWhiteSpace($storeName)) { $storeName = 'My' }
            if ($hash) {
                $certificate = Get-Item "Cert:\LocalMachine\$storeName\$hash" -ErrorAction Stop
                $bindingCertificates += [pscustomobject]@{ Binding = $binding.bindingInformation; Certificate = $certificate }
            }
        } catch {}
    }

    if (-not $iisConfiguration.BindingsKnown) {
        Add-Result -Id 'CERT04' -Category Certificate -Name 'IIS HTTPS server-authentication binding' -Status 'Warn' `
            -Detail ("IIS HTTPS bindings could not be enumerated; Error={0}" -f $iisConfiguration.Error) `
            -Remediation 'Run this diagnostic in elevated Windows PowerShell where the WebAdministration module is available, then confirm the NDES HTTPS binding manually.'
    } elseif ($httpsBindings.Count -eq 0) {
        Add-Result -Id 'CERT04' -Category Certificate -Name 'IIS HTTPS server-authentication binding' -Status 'Fail' `
            -Detail 'No IIS HTTPS binding was discovered.' `
            -Remediation 'Install a valid Server Authentication certificate and bind it to the NDES IIS site on TCP 443.'
    } elseif ($bindingCertificates.Count -eq 0) {
        Add-Result -Id 'CERT04' -Category Certificate -Name 'IIS HTTPS server-authentication binding' -Status 'Warn' `
            -Detail "$($httpsBindings.Count) HTTPS binding(s) found, but their certificates could not be resolved." `
            -Remediation 'Verify each HTTPS binding references a certificate in LocalMachine with its private key.'
    } else {
        $usableBinding = $null
        $bindingDetails = @()
        foreach ($item in $bindingCertificates) {
            $certificate = $item.Certificate
            $dnsNames = @(Get-CertificateDnsName -Certificate $certificate)
            $serverAuth = @($certificate.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.37' } | ForEach-Object { $_.Format($false) }) -join ';'
            $ekuOk = -not $serverAuth -or $serverAuth -match '1\.3\.6\.1\.5\.5\.7\.3\.1|Server Authentication'
            $nameOk = @($dnsNames | Where-Object { Test-DnsNameMatch -Expected $context.Fqdn -Presented $_ }).Count -gt 0
            $timeOk = $certificate.NotBefore -le (Get-Date) -and $certificate.NotAfter -gt (Get-Date)
            if ($timeOk -and $certificate.HasPrivateKey -and $ekuOk -and $nameOk) { $usableBinding = $item }
            $bindingDetails += "Binding=$($item.Binding), Subject=$($certificate.Subject), DNS=$($dnsNames -join '|'), NotAfter=$($certificate.NotAfter.ToUniversalTime().ToString('u')), PrivateKey=$($certificate.HasPrivateKey), ServerAuth=$ekuOk, NameMatch=$nameOk"
        }
        Add-Result -Id 'CERT04' -Category Certificate -Name 'IIS HTTPS server-authentication binding' `
            -Status $(if ($usableBinding) { 'Pass' } else { 'Fail' }) `
            -Detail ($bindingDetails -join '; ') `
            -Remediation 'Use a currently valid certificate with a private key, Server Authentication EKU, and a CN/SAN matching the NDES FQDN.'
    }
    }
}

    #endregion Phase 4 - NDES, IIS, and Certificates

    #region Phase 5 - Network and Dynamic Validation

Invoke-NetworkAndDynamicValidation -Context $context

    #endregion Phase 5 - Network and Dynamic Validation

    #region Phase 6 - Event Logs, Evidence, and Summary

        Invoke-Finalization -Context $context

    #endregion Phase 6 - Event Logs, Evidence, and Summary
    } catch {
        $unhandledError = $_
        try {
            Complete-UnhandledDiagnosticFailure `
                -Context $context `
                -ErrorRecord $unhandledError `
                -PassThru ([bool]$PassThru) `
                -RequestedOutFile $OutFile
        } catch {
            Write-Warning "The diagnostic and its fallback reporter both failed: $($_.Exception.Message)"
        }
    } finally {
        if ($script:BundleStage -and (Test-Path $script:BundleStage)) {
            Remove-Item -Path $script:BundleStage -Recurse -Force -ErrorAction SilentlyContinue
        }
        [Net.ServicePointManager]::SecurityProtocol = $originalSecurityProtocol
        $script:DiagnosticRunning = $false
    }
}

#endregion Public Command

#region Aliases and Exports

Set-Alias -Name Test-CertConnectorPrereqNetwork -Value Test-IntuneCertificateConnector -Scope Script

Export-ModuleMember -Function Test-IntuneCertificateConnector -Alias Test-CertConnectorPrereqNetwork

#endregion Aliases and Exports
