[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$BundleDirectory,

    [Parameter(Mandatory)]
    [string]$OutputPplPath,

    [Parameter()]
    [string]$ManifestFileName = 'ppl-manifest.json',

    [Parameter()]
    [string]$ExpectedLabVIEWVersion,

    [Parameter()]
    [ValidateSet('32', '64')]
    [string]$ExpectedBitness,

    [Parameter()]
    [string]$ExpectedSha256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedBundleDirectory = (Resolve-Path -LiteralPath $BundleDirectory).Path
$manifestPath = Join-Path -Path $resolvedBundleDirectory -ChildPath $ManifestFileName
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Bundle manifest not found: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($manifest.ppl_file_name)) {
    throw "Bundle manifest is missing ppl_file_name."
}
if ([string]::IsNullOrWhiteSpace($manifest.ppl_sha256)) {
    throw "Bundle manifest is missing ppl_sha256."
}

$bundlePplPath = Join-Path -Path $resolvedBundleDirectory -ChildPath ([string]$manifest.ppl_file_name)
if (-not (Test-Path -LiteralPath $bundlePplPath -PathType Leaf)) {
    throw "Bundle PPL file not found: $bundlePplPath"
}

$actualSha256 = (Get-FileHash -LiteralPath $bundlePplPath -Algorithm SHA256).Hash.ToLowerInvariant()
$manifestSha256 = ([string]$manifest.ppl_sha256).ToLowerInvariant()
if ($actualSha256 -ne $manifestSha256) {
    throw "Bundle PPL hash mismatch. Expected from manifest '$manifestSha256', got '$actualSha256'."
}

if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256)) {
    $normalizedExpectedSha256 = $ExpectedSha256.ToLowerInvariant()
    if ($actualSha256 -ne $normalizedExpectedSha256) {
        throw "Bundle PPL hash mismatch. Expected explicit '$normalizedExpectedSha256', got '$actualSha256'."
    }
}

if (-not [string]::IsNullOrWhiteSpace($ExpectedLabVIEWVersion)) {
    if ([string]::IsNullOrWhiteSpace($manifest.labview_version) -or [string]$manifest.labview_version -ne $ExpectedLabVIEWVersion) {
        throw "LabVIEW version mismatch. Expected '$ExpectedLabVIEWVersion', got '$($manifest.labview_version)'."
    }
}

if (-not [string]::IsNullOrWhiteSpace($ExpectedBitness)) {
    if ([string]::IsNullOrWhiteSpace($manifest.bitness) -or [string]$manifest.bitness -ne $ExpectedBitness) {
        throw "Bitness mismatch. Expected '$ExpectedBitness', got '$($manifest.bitness)'."
    }
}

$outputDirectory = Split-Path -Path $OutputPplPath -Parent
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
}

Copy-Item -LiteralPath $bundlePplPath -Destination $OutputPplPath -Force

Write-Host "Consumed PPL bundle from: $resolvedBundleDirectory"
Write-Host "Manifest verified: $manifestPath"
Write-Host "Installed PPL: $OutputPplPath"
Write-Host "SHA256: $actualSha256"
