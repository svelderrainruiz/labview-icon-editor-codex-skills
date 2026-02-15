#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceProjectRoot,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [string]$DockerfilePath = 'docker/pylavi-ci.Dockerfile',

    [string]$LockFilePath = 'docker/pylavi.lock.json',

    [string]$PylaviConfigPath = 'consumer/Tooling/pylavi/vi-validate.yml'
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

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Value,
        [int]$Depth = 12
    )

    $parent = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        Ensure-Directory -Path $parent
    }

    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $entry = "[{0}] {1}" -f ((Get-Date).ToUniversalTime().ToString('o')), $Message
    $script:logLines.Add($entry)
    Write-Host $entry
}

function Get-CommandPreview {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $parts = @('docker')
    foreach ($arg in $Arguments) {
        if ($arg -match '\s') {
            $parts += ('"{0}"' -f $arg.Replace('"', '\"'))
        }
        else {
            $parts += $arg
        }
    }

    return ($parts -join ' ')
}

function Convert-ToDockerHostPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ($IsWindows) {
        return ($Path -replace '\\', '/')
    }

    return $Path
}

$startedUtc = (Get-Date).ToUniversalTime()
$logLines = New-Object 'System.Collections.Generic.List[string]'

$result = [ordered]@{
    schema_version = 1
    status = 'failed'
    started_utc = $startedUtc.ToString('o')
    completed_utc = $null
    duration_seconds = $null
    source_project_root = ''
    output_directory = ''
    repo_root = ''
    project_path = ''
    lvversion_path = ''
    pylavi_config_path = ''
    dockerfile_path = ''
    lock_file_path = ''
    image_tag = ''
    docker_source_mount_path = ''
    docker_mount_spec = ''
    lock = [ordered]@{
        name = ''
        version = ''
        url = ''
        sha256 = ''
    }
    docker_build_command = ''
    docker_build_exit_code = $null
    vi_validate_command = ''
    vi_validate_exit_code = $null
    vi_validate_stdout_path = ''
    vi_validate_stderr_path = ''
    error = $null
}

$statusPayload = [ordered]@{
    status = 'failed'
    reason = ''
    generated_utc = $null
}

$resolvedOutputDirectory = Resolve-FullPath -Path $OutputDirectory
Ensure-Directory -Path $resolvedOutputDirectory

$statusPath = Join-Path $resolvedOutputDirectory 'pylavi-docker.status.json'
$resultPath = Join-Path $resolvedOutputDirectory 'pylavi-docker.result.json'
$logPath = Join-Path $resolvedOutputDirectory 'pylavi-docker.log'
$stdoutPath = Join-Path $resolvedOutputDirectory 'vi-validate.stdout.txt'
$stderrPath = Join-Path $resolvedOutputDirectory 'vi-validate.stderr.txt'

$result.output_directory = $resolvedOutputDirectory
$result.vi_validate_stdout_path = $stdoutPath
$result.vi_validate_stderr_path = $stderrPath

try {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker CLI not found on PATH. Install Docker Desktop/Engine and retry."
    }

    $repoRoot = Resolve-FullPath -Path (Join-Path $PSScriptRoot '..')
    $resolvedSourceRoot = Resolve-FullPath -Path $SourceProjectRoot
    $resolvedDockerfilePath = Resolve-FullPath -Path $DockerfilePath
    $resolvedLockFilePath = Resolve-FullPath -Path $LockFilePath
    $resolvedConfigPath = Resolve-FullPath -Path $PylaviConfigPath

    $result.repo_root = $repoRoot
    $result.source_project_root = $resolvedSourceRoot
    $result.dockerfile_path = $resolvedDockerfilePath
    $result.lock_file_path = $resolvedLockFilePath
    $result.pylavi_config_path = $resolvedConfigPath

    if (-not (Test-Path -LiteralPath $resolvedSourceRoot -PathType Container)) {
        throw "Source project root not found: '$resolvedSourceRoot'."
    }
    if (-not (Test-Path -LiteralPath $resolvedDockerfilePath -PathType Leaf)) {
        throw "Dockerfile not found: '$resolvedDockerfilePath'."
    }
    if (-not (Test-Path -LiteralPath $resolvedLockFilePath -PathType Leaf)) {
        throw "Lock file not found: '$resolvedLockFilePath'."
    }
    if (-not (Test-Path -LiteralPath $resolvedConfigPath -PathType Leaf)) {
        throw "pylavi config not found: '$resolvedConfigPath'."
    }

    $projectCandidates = @(Get-ChildItem -LiteralPath $resolvedSourceRoot -Recurse -File -Filter 'lv_icon_editor.lvproj')
    if ($projectCandidates.Count -ne 1) {
        $candidateList = @($projectCandidates | ForEach-Object { $_.FullName })
        throw "Expected exactly one 'lv_icon_editor.lvproj' under '$resolvedSourceRoot'; found $($projectCandidates.Count). Candidates: $($candidateList -join '; ')"
    }

    $projectPath = $projectCandidates[0].FullName
    $lvversionPath = Join-Path (Split-Path -Path $projectPath -Parent) '.lvversion'
    if (-not (Test-Path -LiteralPath $lvversionPath -PathType Leaf)) {
        throw "Missing '.lvversion' alongside '$projectPath'. Expected '$lvversionPath'."
    }

    $result.project_path = $projectPath
    $result.lvversion_path = $lvversionPath

    $configRelative = [System.IO.Path]::GetRelativePath($resolvedSourceRoot, $resolvedConfigPath)
    if ($configRelative.StartsWith('..')) {
        throw "Configured pylavi config path '$resolvedConfigPath' must be under source project root '$resolvedSourceRoot'."
    }

    $containerConfigPath = '/source/{0}' -f ($configRelative -replace '\\', '/')
    $dockerSourceMountPath = Convert-ToDockerHostPath -Path $resolvedSourceRoot
    $dockerMountSpec = "type=bind,source=$dockerSourceMountPath,target=/source,readonly"

    $result.docker_source_mount_path = $dockerSourceMountPath
    $result.docker_mount_spec = $dockerMountSpec

    $lockRaw = Get-Content -LiteralPath $resolvedLockFilePath -Raw | ConvertFrom-Json
    $lockPackage = $lockRaw.package
    if ($null -eq $lockPackage) {
        throw "Lock file '$resolvedLockFilePath' missing 'package' object."
    }

    $lockName = [string]$lockPackage.name
    $lockVersion = [string]$lockPackage.version
    $lockUrl = [string]$lockPackage.url
    $lockSha = [string]$lockPackage.sha256

    if ([string]::IsNullOrWhiteSpace($lockName) -or [string]::IsNullOrWhiteSpace($lockVersion) -or [string]::IsNullOrWhiteSpace($lockUrl) -or [string]::IsNullOrWhiteSpace($lockSha)) {
        throw "Lock file '$resolvedLockFilePath' must define package.name, package.version, package.url, and package.sha256."
    }

    if ($lockSha -notmatch '^[0-9a-f]{64}$') {
        throw "Lock file package.sha256 must be lowercase 64-char hex. Found '$lockSha'."
    }

    $result.lock.name = $lockName
    $result.lock.version = $lockVersion
    $result.lock.url = $lockUrl
    $result.lock.sha256 = $lockSha

    $imageTagSuffix = if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID)) { [string]$env:GITHUB_RUN_ID } else { (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss') }
    $imageTag = "lvie-pylavi-ci:$imageTagSuffix"
    $result.image_tag = $imageTag

    $buildArgs = @(
        'build',
        '-t', $imageTag,
        '-f', $resolvedDockerfilePath,
        '--build-arg', "PYLAVI_URL=$lockUrl",
        '--build-arg', "PYLAVI_SHA256=$lockSha",
        $repoRoot
    )
    $result.docker_build_command = Get-CommandPreview -Arguments $buildArgs

    Write-Log ("Building deterministic pylavi image: {0}" -f $imageTag)
    Write-Log ("Build command: {0}" -f $result.docker_build_command)

    $buildOutput = & docker @buildArgs 2>&1
    $result.docker_build_exit_code = $LASTEXITCODE
    foreach ($line in @($buildOutput)) {
        Write-Log ("[docker-build] {0}" -f [string]$line)
    }

    if ([int]$result.docker_build_exit_code -ne 0) {
        throw "Docker image build failed with exit code $($result.docker_build_exit_code)."
    }

    $runArgs = @(
        'run', '--rm',
        '--mount', $dockerMountSpec,
        $imageTag,
        'vi_validate',
        '--config', $containerConfigPath,
        '-p', '/source'
    )
    $result.vi_validate_command = Get-CommandPreview -Arguments $runArgs

    Write-Log ("Running vi_validate command: {0}" -f $result.vi_validate_command)

    & docker @runArgs 1> $stdoutPath 2> $stderrPath
    $result.vi_validate_exit_code = $LASTEXITCODE

    Write-Log ("vi_validate exit code: {0}" -f [string]$result.vi_validate_exit_code)

    if ([int]$result.vi_validate_exit_code -ne 0) {
        $stderrPreview = ''
        if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
            $stderrPreview = (Get-Content -LiteralPath $stderrPath -TotalCount 10) -join ' | '
        }
        throw "vi_validate failed with exit code $($result.vi_validate_exit_code). stderr preview: $stderrPreview"
    }

    $result.status = 'passed'
    $statusPayload.status = 'passed'
    $statusPayload.reason = 'pylavi Docker validation completed successfully.'
}
catch {
    $message = $_.Exception.Message
    $result.status = 'failed'
    $statusPayload.status = 'failed'
    $statusPayload.reason = $message
    $result.error = [ordered]@{
        type = $_.Exception.GetType().FullName
        message = $message
    }
    Write-Log ("ERROR: {0}" -f $message)
}
finally {
    if (-not (Test-Path -LiteralPath $stdoutPath -PathType Leaf)) {
        Set-Content -LiteralPath $stdoutPath -Value '' -Encoding UTF8
    }
    if (-not (Test-Path -LiteralPath $stderrPath -PathType Leaf)) {
        Set-Content -LiteralPath $stderrPath -Value '' -Encoding UTF8
    }

    $completedUtc = (Get-Date).ToUniversalTime()
    $result.completed_utc = $completedUtc.ToString('o')
    $result.duration_seconds = [math]::Round(($completedUtc - $startedUtc).TotalSeconds, 3)
    $statusPayload.generated_utc = $completedUtc.ToString('o')

    Write-JsonFile -Path $resultPath -Value $result -Depth 16
    Write-JsonFile -Path $statusPath -Value $statusPayload -Depth 8
    Set-Content -LiteralPath $logPath -Value (@($logLines) -join [Environment]::NewLine) -Encoding UTF8
}

if ($result.status -eq 'failed') {
    throw "pylavi Docker validation failed: $($statusPayload.reason). See '$resultPath' and '$logPath'."
}
