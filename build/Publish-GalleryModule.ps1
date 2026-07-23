#Requires -Version 5.1

<#
.SYNOPSIS
    Securely publishes IntuneCertificateConnectorDiagnostics to PowerShell Gallery.

.DESCRIPTION
    Builds and validates the module, checks for a Gallery version conflict, then
    publishes by using a SecureString API key. Unless a SecureString is passed
    explicitly, the script always prompts locally with masked input so a stale
    key cannot be reused accidentally. The plaintext key exists only in unmanaged
    memory for the duration of Publish-PSResource and is explicitly cleared afterward.

.PARAMETER ApiKey
    Optional API key as a SecureString. If omitted, the script always prompts for
    masked input.

.PARAMETER Repository
    PowerShell repository name. Default: PSGallery.

.PARAMETER SkipTests
    Skips Pester and ScriptAnalyzer validation. Not recommended for publication.

.EXAMPLE
    .\build\Publish-GalleryModule.ps1 -WhatIf

.EXAMPLE
    .\build\Publish-GalleryModule.ps1
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Security.SecureString]$ApiKey,
    [string]$Repository = 'PSGallery',
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $PSScriptRoot 'Build-Module.ps1'
$manifestSource = Join-Path $repositoryRoot 'IntuneCertificateConnectorDiagnostics.psd1'
$testPath = Join-Path $repositoryRoot 'tests\Test-CertConnectorPrereqNetwork.Tests.ps1'
$analysisPaths = @(
    (Join-Path $repositoryRoot 'IntuneCertificateConnectorDiagnostics.psm1')
    (Join-Path $repositoryRoot 'build\Build-Module.ps1')
    (Join-Path $repositoryRoot 'build\Publish-GalleryModule.ps1')
    $testPath
)

$inheritedWhatIfPreference = $WhatIfPreference
try {
    # Validation and staging must execute even when publication is a dry run.
    $WhatIfPreference = $false
    $manifest = Test-ModuleManifest -Path $manifestSource
    if (-not $SkipTests) {
        $analyzer = Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue
        if (-not $analyzer) {
            throw 'PSScriptAnalyzer is required unless -SkipTests is specified.'
        }
        $findings = @($analysisPaths | ForEach-Object { Invoke-ScriptAnalyzer -Path $_ })
        if ($findings.Count -gt 0) {
            $findings | Format-Table RuleName, Severity, ScriptName, Line, Message -Wrap
            throw "PSScriptAnalyzer returned $($findings.Count) finding(s)."
        }

        $pester = Get-Command Invoke-Pester -ErrorAction SilentlyContinue
        if (-not $pester) {
            throw 'Pester is required unless -SkipTests is specified.'
        }
        $testResult = Invoke-Pester -Path $testPath -PassThru -Output None 6>$null
        if ($testResult.FailedCount -gt 0) {
            throw "Pester reported $($testResult.FailedCount) failed test(s)."
        }
    }

    $publisher = Get-Command Publish-PSResource -ErrorAction SilentlyContinue
    if (-not $publisher) {
        throw 'Microsoft.PowerShell.PSResourceGet 1.0 or later is required to publish this module.'
    }

    $published = Find-Module -Name $manifest.Name -Repository $Repository -ErrorAction SilentlyContinue
    if ($published -and $manifest.Version -le $published.Version) {
        throw "Local version $($manifest.Version) must be greater than published version $($published.Version)."
    }

    $modulePath = & $buildScript
    $builtManifest = Test-ModuleManifest -Path (Join-Path $modulePath 'IntuneCertificateConnectorDiagnostics.psd1')
    if ($builtManifest.Version -ne $manifest.Version) {
        throw 'The built module version does not match the source manifest.'
    }
} finally {
    $WhatIfPreference = $inheritedWhatIfPreference
}

$target = "$Repository/$($manifest.Name) $($manifest.Version)"
if (-not $PSCmdlet.ShouldProcess($target, 'Publish PowerShell module')) {
    return
}

if (-not $ApiKey) {
    $ApiKey = Read-Host 'Paste a NEW PowerShell Gallery API key with Push new or update packages permission' -AsSecureString
}

$keyPointer = [IntPtr]::Zero
try {
    $keyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ApiKey)
    $plainApiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPointer)
    if ([string]::IsNullOrWhiteSpace($plainApiKey)) {
        throw 'The API key is empty.'
    }

    Publish-PSResource `
        -Path $modulePath `
        -Repository $Repository `
        -ApiKey $plainApiKey `
        -Confirm:$false `
        -ErrorAction Stop
} finally {
    if ($keyPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPointer)
    }
    Remove-Variable plainApiKey, ApiKey, keyPointer -Force -ErrorAction SilentlyContinue
}

Write-Output "Published $($manifest.Name) $($manifest.Version) to $Repository."
