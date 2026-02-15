#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$DockerImage = 'mcr.microsoft.com/powershell:7.4-ubuntu-22.04',
    [string]$DockerMemory = '3g',
    [string]$DockerCpus = '2',
    [ValidateRange(30, 3600)]
    [int]$TimeoutSeconds = 300,

    [string]$ConsumerPath = 'consumer',
    [string]$ConsumerRepo = '',
    [string]$ConsumerRef = '',
    [string]$ConsumerExpectedSha = '',

    [string]$OutputDirectory,

    [int]$VersionMajor = 0,
    [int]$VersionMinor = 1,
    [int]$VersionPatch = 0,
    [int]$VersionBuild = 1,
    [string]$VersionCommit = 'local-diagnostics'
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

function Resolve-GitHubRepositoryId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository
    )

    $trimmed = $Repository.Trim()
    if ($trimmed -match '^(?<repo>[^/\s]+/[^/\s]+)$') {
        return [string]$Matches.repo
    }

    if ($trimmed -match '^https://github\.com/(?<repo>[^/]+/[^/.]+?)(?:\.git)?/?$') {
        return [string]$Matches.repo
    }

    throw "Consumer repository '$Repository' is invalid. Expected '<owner>/<repo>' or 'https://github.com/<owner>/<repo>.git'."
}

function Resolve-CloneUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository
    )

    $trimmed = $Repository.Trim()
    if ($trimmed -match '^https://github\.com/[^/]+/[^/]+(?:\.git)?/?$') {
        return $trimmed
    }

    $repoId = Resolve-GitHubRepositoryId -Repository $trimmed
    return "https://github.com/$repoId.git"
}

function Resolve-DefaultSourceProjectRepo {
    if (-not [string]::IsNullOrWhiteSpace($env:LVIE_SOURCE_PROJECT_REPO)) {
        return [string]$env:LVIE_SOURCE_PROJECT_REPO
    }

    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_REPOSITORY)) {
        $owner = ([string]$env:GITHUB_REPOSITORY -split '/', 2)[0]
        if (-not [string]::IsNullOrWhiteSpace($owner)) {
            return "$owner/labview-icon-editor"
        }
    }

    return ''
}

function Resolve-SkillRepositoryId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_REPOSITORY)) {
        return [string]$env:GITHUB_REPOSITORY
    }

    try {
        $originUrl = (git -C $RepositoryRoot remote get-url origin).Trim()
        if ($originUrl -match 'github\.com[:/](?<repo>[^/]+/[^/.]+?)(?:\.git)?$') {
            return [string]$Matches.repo
        }
    }
    catch {
    }

    return 'unknown/unknown'
}

$repoRoot = Resolve-FullPath -Path (Join-Path $PSScriptRoot '..')
$resolvedConsumerPath = Resolve-FullPath -Path $ConsumerPath

if ([string]::IsNullOrWhiteSpace($ConsumerRepo)) {
    $ConsumerRepo = Resolve-DefaultSourceProjectRepo
}
if ([string]::IsNullOrWhiteSpace($ConsumerRepo)) {
    throw "ConsumerRepo is required. Provide -ConsumerRepo or set LVIE_SOURCE_PROJECT_REPO."
}
$consumerRepositoryId = Resolve-GitHubRepositoryId -Repository $ConsumerRepo
$consumerCloneUrl = Resolve-CloneUrl -Repository $ConsumerRepo

if ([string]::IsNullOrWhiteSpace($ConsumerRef)) {
    if (-not [string]::IsNullOrWhiteSpace($env:LVIE_SOURCE_PROJECT_REF)) {
        $ConsumerRef = [string]$env:LVIE_SOURCE_PROJECT_REF
    } else {
        $ConsumerRef = 'main'
    }
}

if ([string]::IsNullOrWhiteSpace($ConsumerExpectedSha)) {
    $ConsumerExpectedSha = [string]$env:LVIE_SOURCE_PROJECT_SHA
}
if ([string]::IsNullOrWhiteSpace($ConsumerExpectedSha)) {
    throw "ConsumerExpectedSha is required. Strict source pin is mandatory; provide -ConsumerExpectedSha or set LVIE_SOURCE_PROJECT_SHA."
}
$ConsumerExpectedSha = $ConsumerExpectedSha.Trim().ToLowerInvariant()
if ($ConsumerExpectedSha -notmatch '^[0-9a-f]{40}$') {
    throw "ConsumerExpectedSha '$ConsumerExpectedSha' is invalid. Expected 40-char lowercase hex."
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
    $OutputDirectory = Join-Path $repoRoot "artifacts/vipb-prepared-local/$timestamp"
}
$resolvedOutputDirectory = Resolve-FullPath -Path $OutputDirectory
Ensure-Directory -Path $resolvedOutputDirectory

$dockerOsType = (docker info --format '{{.OSType}}').Trim()
if ($LASTEXITCODE -ne 0) {
    throw "Unable to query Docker daemon. Ensure Docker Desktop is running with Linux containers."
}
if ($dockerOsType -ne 'linux') {
    throw "Docker daemon OSType must be 'linux', got '$dockerOsType'."
}

if (-not (Test-Path -LiteralPath (Join-Path $resolvedConsumerPath '.git') -PathType Container)) {
    if ((Test-Path -LiteralPath $resolvedConsumerPath -PathType Container) -and (Get-ChildItem -LiteralPath $resolvedConsumerPath -Force | Measure-Object).Count -gt 0) {
        throw "Consumer path exists and is not empty git repository: $resolvedConsumerPath"
    }
    git clone $consumerCloneUrl $resolvedConsumerPath
}

git -C $resolvedConsumerPath fetch origin $ConsumerRef
git -C $resolvedConsumerPath checkout -B $ConsumerRef "origin/$ConsumerRef"
$actualConsumerSha = (git -C $resolvedConsumerPath rev-parse HEAD).Trim()
if ($actualConsumerSha -ne $ConsumerExpectedSha) {
    throw "Consumer SHA mismatch. Expected '$ConsumerExpectedSha', got '$actualConsumerSha'."
}

$vipbPath = Join-Path $resolvedConsumerPath 'Tooling/deployment/NI Icon editor.vipb'
$releaseNotesPath = Join-Path $resolvedConsumerPath 'Tooling/deployment/release_notes.md'
if (-not (Test-Path -LiteralPath $releaseNotesPath -PathType Leaf)) {
    New-Item -Path $releaseNotesPath -ItemType File -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $vipbPath -PathType Leaf)) {
    throw "VIPB path not found: $vipbPath"
}

$versionHelperPath = Join-Path $resolvedConsumerPath 'Tooling/support/LabVIEWVersion.ps1'
if (-not (Test-Path -LiteralPath $versionHelperPath -PathType Leaf)) {
    throw "Version helper not found: $versionHelperPath"
}
. $versionHelperPath
$lvInfo = Get-LabVIEWVersionInfo -RepoRoot $resolvedConsumerPath

$releaseNotes = Get-Content -LiteralPath $releaseNotesPath -Raw
$skillRepositoryId = Resolve-SkillRepositoryId -RepositoryRoot $repoRoot
$skillOwner = ($skillRepositoryId -split '/', 2)[0]
if ([string]::IsNullOrWhiteSpace($skillOwner)) {
    $skillOwner = 'unknown'
}
$displayInfo = @{
    "Package Version" = @{
        "major" = $VersionMajor
        "minor" = $VersionMinor
        "patch" = $VersionPatch
        "build" = $VersionBuild
    }
    "Product Name" = "labview-icon-editor"
    "Company Name" = $skillOwner
    "Author Name (Person or Company)" = $skillRepositoryId
    "Product Homepage (URL)" = "https://github.com/$skillRepositoryId"
    "Legal Copyright" = "Copyright $(Get-Date -Format yyyy) $skillOwner"
    "Product Description Summary" = "labview-icon-editor VI Package diagnostics exercise."
    "Product Description" = "labview-icon-editor VI Package diagnostics exercise."
    "Release Notes - Change Log" = $releaseNotes
}
$displayInformationJson = $displayInfo | ConvertTo-Json -Depth 6 -Compress

$repoRootUri = [Uri]("{0}{1}" -f $repoRoot, [System.IO.Path]::DirectorySeparatorChar)
$outputUri = [Uri]("{0}{1}" -f $resolvedOutputDirectory, [System.IO.Path]::DirectorySeparatorChar)
if (-not $repoRootUri.IsBaseOf($outputUri)) {
    throw "OutputDirectory must be inside repository root '$repoRoot' for Docker mount compatibility."
}
$outputRelative = [Uri]::UnescapeDataString($repoRootUri.MakeRelativeUri($outputUri).ToString()).TrimEnd('/')
if ([string]::IsNullOrWhiteSpace($outputRelative)) {
    throw "OutputDirectory relative path was empty."
}
$outputRelativePosix = $outputRelative.Replace('\', '/')
$containerOutputDirectory = "/workspace/$outputRelativePosix"

$containerCommand = @"
set -euo pipefail
if command -v timeout >/dev/null 2>&1; then
  timeout ${TimeoutSeconds}s pwsh -NoProfile -File /workspace/scripts/Invoke-PrepareVipbDiagnostics.ps1 \
    -RepoRoot '/workspace/consumer' \
    -VipbPath '/workspace/consumer/Tooling/deployment/NI Icon editor.vipb' \
    -ReleaseNotesFile '/workspace/consumer/Tooling/deployment/release_notes.md' \
    -DisplayInformationJson "`$DISPLAY_INFORMATION_JSON" \
    -LabVIEWVersionYear $($lvInfo.Year) \
    -LabVIEWMinorRevision $($lvInfo.MinorRevision) \
    -SupportedBitness '64' \
    -Major $VersionMajor \
    -Minor $VersionMinor \
    -Patch $VersionPatch \
    -Build $VersionBuild \
    -Commit '${VersionCommit}' \
    -OutputDirectory '${containerOutputDirectory}' \
    -SourceRepository '${consumerRepositoryId}' \
    -SourceRef '${ConsumerRef}' \
    -SourceSha '${actualConsumerSha}' \
    -BuildRunId 'local' \
    -BuildRunAttempt '1' \
    -UpdateScriptPath '/workspace/scripts/Update-Vipb.DisplayInfo.ps1'
else
  pwsh -NoProfile -File /workspace/scripts/Invoke-PrepareVipbDiagnostics.ps1 \
    -RepoRoot '/workspace/consumer' \
    -VipbPath '/workspace/consumer/Tooling/deployment/NI Icon editor.vipb' \
    -ReleaseNotesFile '/workspace/consumer/Tooling/deployment/release_notes.md' \
    -DisplayInformationJson "`$DISPLAY_INFORMATION_JSON" \
    -LabVIEWVersionYear $($lvInfo.Year) \
    -LabVIEWMinorRevision $($lvInfo.MinorRevision) \
    -SupportedBitness '64' \
    -Major $VersionMajor \
    -Minor $VersionMinor \
    -Patch $VersionPatch \
    -Build $VersionBuild \
    -Commit '${VersionCommit}' \
    -OutputDirectory '${containerOutputDirectory}' \
    -SourceRepository '${consumerRepositoryId}' \
    -SourceRef '${ConsumerRef}' \
    -SourceSha '${actualConsumerSha}' \
    -BuildRunId 'local' \
    -BuildRunAttempt '1' \
    -UpdateScriptPath '/workspace/scripts/Update-Vipb.DisplayInfo.ps1'
fi
"@

$dockerArguments = @(
    'run', '--rm',
    '--memory', $DockerMemory,
    '--cpus', $DockerCpus,
    '-v', "${repoRoot}:/workspace",
    '-w', '/workspace',
    '-e', "DISPLAY_INFORMATION_JSON=$displayInformationJson",
    $DockerImage,
    'bash', '-lc', $containerCommand
)

$stdoutPath = Join-Path $resolvedOutputDirectory 'docker.stdout.log'
$stderrPath = Join-Path $resolvedOutputDirectory 'docker.stderr.log'
$dockerOutput = & docker @dockerArguments 2>&1
$dockerExitCode = $LASTEXITCODE
$dockerOutputText = (@($dockerOutput) -join [Environment]::NewLine)
Set-Content -LiteralPath $stdoutPath -Value $dockerOutputText -Encoding UTF8
Set-Content -LiteralPath $stderrPath -Value '' -Encoding UTF8
if ($dockerExitCode -ne 0) {
    throw "Docker command exited with code $dockerExitCode. See '$stdoutPath'."
}

$requiredFiles = @(
    'NI Icon editor.vipb',
    'vipb.before.xml',
    'vipb.after.xml',
    'vipb.before.sha256',
    'vipb.after.sha256',
    'vipb-diff.json',
    'vipb-diff-summary.md',
    'vipb-diagnostics.json',
    'vipb-diagnostics-summary.md',
    'prepare-vipb.status.json',
    'prepare-vipb.log',
    'display-information.input.json'
)
foreach ($file in $requiredFiles) {
    $filePath = Join-Path $resolvedOutputDirectory $file
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        throw "Expected diagnostics file missing: $filePath"
    }
}

$statusPath = Join-Path $resolvedOutputDirectory 'prepare-vipb.status.json'
$diagnosticsPath = Join-Path $resolvedOutputDirectory 'vipb-diagnostics.json'
$summaryPath = Join-Path $resolvedOutputDirectory 'vipb-diagnostics-summary.md'
$statusPayload = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
$diagnosticsPayload = Get-Content -LiteralPath $diagnosticsPath -Raw | ConvertFrom-Json

Write-Host ("Diagnostics status: {0}" -f $statusPayload.status)
Write-Host ("Changed fields: {0}" -f $diagnosticsPayload.diff.changed_field_count)
Write-Host ("Diagnostics directory: {0}" -f $resolvedOutputDirectory)
Write-Host ("Summary markdown: {0}" -f $summaryPath)
Write-Host ("Docker output log: {0}" -f $stdoutPath)
