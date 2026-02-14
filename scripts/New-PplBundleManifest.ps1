[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PplPath,

    [Parameter(Mandatory)]
    [string]$OutputDirectory,

    [Parameter(Mandatory)]
    [string]$LabVIEWVersion,

    [Parameter()]
    [ValidateSet('32', '64')]
    [string]$Bitness = '64',

    [Parameter()]
    [string]$WindowsImage,

    [Parameter()]
    [string]$BuildRunId,

    [Parameter()]
    [string]$BuildRunAttempt
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedPplPath = (Resolve-Path -LiteralPath $PplPath).Path
if (-not (Test-Path -LiteralPath $resolvedPplPath -PathType Leaf)) {
    throw "PPL file not found: $PplPath"
}

if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

$pplItem = Get-Item -LiteralPath $resolvedPplPath
$pplHash = (Get-FileHash -LiteralPath $resolvedPplPath -Algorithm SHA256).Hash.ToLowerInvariant()
$pplFileName = [System.IO.Path]::GetFileName($resolvedPplPath)
$bundlePplPath = Join-Path -Path $OutputDirectory -ChildPath $pplFileName
Copy-Item -LiteralPath $resolvedPplPath -Destination $bundlePplPath -Force

$manifestPath = Join-Path -Path $OutputDirectory -ChildPath 'ppl-manifest.json'
$manifest = [pscustomobject]@{
    generated_utc      = (Get-Date).ToUniversalTime().ToString('o')
    source_sha         = $env:GITHUB_SHA
    source_repository  = $env:GITHUB_REPOSITORY
    windows_image      = $WindowsImage
    windows_run_id     = $BuildRunId
    windows_run_attempt = $BuildRunAttempt
    labview_version    = $LabVIEWVersion
    bitness            = $Bitness
    ppl_file_name      = $pplFileName
    ppl_sha256         = $pplHash
    ppl_size_bytes     = [int64]$pplItem.Length
}

$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host "PPL bundle created: $OutputDirectory"
Write-Host "Manifest: $manifestPath"
Write-Host "PPL: $bundlePplPath"
Write-Host "SHA256: $pplHash"
