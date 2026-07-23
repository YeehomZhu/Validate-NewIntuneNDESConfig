#Requires -Version 5.1

<#
.SYNOPSIS
    Builds a clean PowerShell Gallery module folder.

.DESCRIPTION
    Copies only the self-contained runtime module, manifest, license, and README
    into an output folder whose name matches the module manifest.
    The resulting folder is validated with Test-ModuleManifest and can be passed
    directly to Publish-Module.

.PARAMETER OutputRoot
    Parent directory for the generated module folder. Defaults to ../out.

.EXAMPLE
    .\build\Build-Module.ps1

.EXAMPLE
    $modulePath = .\build\Build-Module.ps1 -OutputRoot $env:TEMP
    Publish-Module -Path $modulePath -Repository PSGallery -WhatIf
#>
[CmdletBinding()]
[OutputType([string])]
param(
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'out')
)

$ErrorActionPreference = 'Stop'
$moduleName = 'IntuneCertificateConnectorDiagnostics'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $OutputRoot $moduleName
$runtimeFiles = @(
    'IntuneCertificateConnectorDiagnostics.psd1'
    'IntuneCertificateConnectorDiagnostics.psm1'
    'README.md'
    'LICENSE'
)

if (Test-Path -LiteralPath $destination) {
    Remove-Item -LiteralPath $destination -Recurse -Force
}
$null = New-Item -ItemType Directory -Path $destination -Force

foreach ($fileName in $runtimeFiles) {
    $source = Join-Path $repositoryRoot $fileName
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Required module file is missing: $source"
    }
    Copy-Item -LiteralPath $source -Destination (Join-Path $destination $fileName) -Force
}

$manifestPath = Join-Path $destination 'IntuneCertificateConnectorDiagnostics.psd1'
$moduleInfo = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
if ($moduleInfo.Name -ne $moduleName) {
    throw "Built manifest name '$($moduleInfo.Name)' doesn't match '$moduleName'."
}

Write-Output $destination
