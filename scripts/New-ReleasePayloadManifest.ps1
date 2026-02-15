#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseTag,

    [Parameter(Mandatory = $true)]
    [string]$StageDirectory,

    [Parameter(Mandatory = $true)]
    [string]$SourceProjectRepo,

    [Parameter(Mandatory = $true)]
    [string]$SourceProjectRef,

    [Parameter(Mandatory = $true)]
    [string]$SourceProjectSha,

    [Parameter(Mandatory = $true)]
    [string]$CiRepository,

    [Parameter(Mandatory = $true)]
    [string]$CiRunId,

    [Parameter(Mandatory = $true)]
    [string]$CiRunAttempt,

    [Parameter(Mandatory = $true)]
    [string]$CiRunUrl,

    [string]$OutputPath = 'release-payload-manifest.json',

    [string]$SchemaPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-FullPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location).Path -ChildPath $Path))
}

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

$resolvedStageDirectory = Resolve-FullPath -Path $StageDirectory
if (-not (Test-Path -LiteralPath $resolvedStageDirectory -PathType Container)) {
    throw "StageDirectory not found: $resolvedStageDirectory"
}

$resolvedOutputPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    Resolve-FullPath -Path $OutputPath
}
else {
    Resolve-FullPath -Path (Join-Path -Path $resolvedStageDirectory -ChildPath $OutputPath)
}

$requiredAssets = @(
    @{ name = 'lvie-codex-skill-layer-installer.exe'; category = 'installer' },
    @{ name = 'lvie-ppl-bundle-windows-x64.zip'; category = 'ppl_bundle_windows_x64' },
    @{ name = 'lvie-ppl-bundle-linux-x64.zip'; category = 'ppl_bundle_linux_x64' },
    @{ name = 'lvie-vip-package-self-hosted.zip'; category = 'vip_package_self_hosted' },
    @{ name = 'release-provenance.json'; category = 'provenance' }
)

$assetRecords = @()
foreach ($requiredAsset in $requiredAssets) {
    $assetPath = Join-Path -Path $resolvedStageDirectory -ChildPath $requiredAsset.name
    if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) {
        throw "Required staged release asset missing: $assetPath"
    }

    $assetItem = Get-Item -LiteralPath $assetPath
    $assetHash = (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $assetRecords += [pscustomobject]@{
        name = $requiredAsset.name
        sha256 = $assetHash
        size_bytes = [int64]$assetItem.Length
        category = $requiredAsset.category
    }
}

$manifest = [pscustomobject]@{
    schema_version = '1.0'
    generated_utc = (Get-Date).ToUniversalTime().ToString('o')
    release_tag = $ReleaseTag
    source_project = [pscustomobject]@{
        repo = $SourceProjectRepo
        ref = $SourceProjectRef
        sha = $SourceProjectSha
    }
    skills_ci_run = [pscustomobject]@{
        repository = $CiRepository
        run_id = $CiRunId
        run_attempt = $CiRunAttempt
        run_url = $CiRunUrl
    }
    assets = @($assetRecords)
}

$manifestJson = $manifest | ConvertTo-Json -Depth 10

if (-not [string]::IsNullOrWhiteSpace($SchemaPath)) {
    $resolvedSchemaPath = Resolve-FullPath -Path $SchemaPath
    if (-not (Test-Path -LiteralPath $resolvedSchemaPath -PathType Leaf)) {
        throw "SchemaPath not found: $resolvedSchemaPath"
    }

    $isValid = $manifestJson | Test-Json -SchemaFile $resolvedSchemaPath -ErrorAction Stop
    if (-not $isValid) {
        throw "Generated release payload manifest did not pass schema validation: $resolvedSchemaPath"
    }
}

$outputDirectory = Split-Path -Path $resolvedOutputPath -Parent
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
    Ensure-Directory -Path $outputDirectory
}

Set-Content -LiteralPath $resolvedOutputPath -Value $manifestJson -Encoding UTF8
Write-Host "Release payload manifest: $resolvedOutputPath"
