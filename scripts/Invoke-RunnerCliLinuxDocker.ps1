#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceProjectRoot,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [string]$DockerfilePath = 'docker/runner-cli-linux-ci.Dockerfile',

    [string]$LockFilePath = 'docker/runner-cli-linux-ci.lock.json',

    [string]$Runtime = 'linux-x64'
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
        } else {
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
    dockerfile_path = ''
    lock_file_path = ''
    runtime = $Runtime
    image_tag = ''
    docker_source_mount_path = ''
    docker_output_mount_path = ''
    docker_build_command = ''
    docker_build_exit_code = $null
    docker_run_command = ''
    docker_run_exit_code = $null
    publish_binary_path = ''
    lock = [ordered]@{
        dotnet_sdk_image = ''
        pylavi_name = ''
        pylavi_version = ''
        pylavi_url = ''
        pylavi_sha256 = ''
    }
    stdout_path = ''
    stderr_path = ''
    error = $null
}

$statusPayload = [ordered]@{
    status = 'failed'
    reason = ''
    generated_utc = $null
}

$resolvedOutputDirectory = Resolve-FullPath -Path $OutputDirectory
Ensure-Directory -Path $resolvedOutputDirectory

$statusPath = Join-Path $resolvedOutputDirectory 'runner-cli-linux-docker.status.json'
$resultPath = Join-Path $resolvedOutputDirectory 'runner-cli-linux-docker.result.json'
$logPath = Join-Path $resolvedOutputDirectory 'runner-cli-linux-docker.log'
$stdoutPath = Join-Path $resolvedOutputDirectory 'runner-cli-linux-docker.stdout.txt'
$stderrPath = Join-Path $resolvedOutputDirectory 'runner-cli-linux-docker.stderr.txt'

$result.output_directory = $resolvedOutputDirectory
$result.stdout_path = $stdoutPath
$result.stderr_path = $stderrPath

try {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker CLI not found on PATH. Install Docker Desktop/Engine and retry."
    }

    if ($Runtime -notmatch '^linux-(x64|arm64)$') {
        throw "Runtime '$Runtime' is not supported. Expected linux-x64 or linux-arm64."
    }

    $repoRoot = Resolve-FullPath -Path (Join-Path $PSScriptRoot '..')
    $resolvedSourceRoot = Resolve-FullPath -Path $SourceProjectRoot
    $resolvedDockerfilePath = Resolve-FullPath -Path $DockerfilePath
    $resolvedLockFilePath = Resolve-FullPath -Path $LockFilePath

    $result.repo_root = $repoRoot
    $result.source_project_root = $resolvedSourceRoot
    $result.dockerfile_path = $resolvedDockerfilePath
    $result.lock_file_path = $resolvedLockFilePath

    if (-not (Test-Path -LiteralPath $resolvedSourceRoot -PathType Container)) {
        throw "Source project root not found: '$resolvedSourceRoot'."
    }
    if (-not (Test-Path -LiteralPath $resolvedDockerfilePath -PathType Leaf)) {
        throw "Dockerfile not found: '$resolvedDockerfilePath'."
    }
    if (-not (Test-Path -LiteralPath $resolvedLockFilePath -PathType Leaf)) {
        throw "Lock file not found: '$resolvedLockFilePath'."
    }

    $runnerCliRoot = Join-Path $resolvedSourceRoot 'Tooling/runner-cli'
    $runnerCliProject = Join-Path $runnerCliRoot 'RunnerCli/RunnerCli.csproj'
    $runnerCliTestsProject = Join-Path $runnerCliRoot 'RunnerCli.Tests/RunnerCli.Tests.csproj'
    if (-not (Test-Path -LiteralPath $runnerCliProject -PathType Leaf)) {
        throw "Runner CLI project not found at '$runnerCliProject'."
    }
    if (-not (Test-Path -LiteralPath $runnerCliTestsProject -PathType Leaf)) {
        throw "Runner CLI test project not found at '$runnerCliTestsProject'."
    }

    $lockRaw = Get-Content -LiteralPath $resolvedLockFilePath -Raw | ConvertFrom-Json
    $dotnetSdkImage = [string]$lockRaw.dotnet_sdk_image
    $pylavi = $lockRaw.pylavi
    if ([string]::IsNullOrWhiteSpace($dotnetSdkImage)) {
        throw "Lock file '$resolvedLockFilePath' missing 'dotnet_sdk_image'."
    }
    if ($null -eq $pylavi) {
        throw "Lock file '$resolvedLockFilePath' missing 'pylavi' object."
    }

    $pylaviName = [string]$pylavi.name
    $pylaviVersion = [string]$pylavi.version
    $pylaviUrl = [string]$pylavi.url
    $pylaviSha = [string]$pylavi.sha256
    if ([string]::IsNullOrWhiteSpace($pylaviName) -or [string]::IsNullOrWhiteSpace($pylaviVersion) -or [string]::IsNullOrWhiteSpace($pylaviUrl) -or [string]::IsNullOrWhiteSpace($pylaviSha)) {
        throw "Lock file '$resolvedLockFilePath' must define pylavi.name, pylavi.version, pylavi.url, and pylavi.sha256."
    }
    if ($pylaviSha -notmatch '^[0-9a-f]{64}$') {
        throw "Lock file pylavi.sha256 must be lowercase 64-char hex. Found '$pylaviSha'."
    }

    $result.lock.dotnet_sdk_image = $dotnetSdkImage
    $result.lock.pylavi_name = $pylaviName
    $result.lock.pylavi_version = $pylaviVersion
    $result.lock.pylavi_url = $pylaviUrl
    $result.lock.pylavi_sha256 = $pylaviSha

    $imageTagSuffix = if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID)) { [string]$env:GITHUB_RUN_ID } else { (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss') }
    $imageTag = "lvie-runner-cli-linux-ci:$imageTagSuffix"
    $result.image_tag = $imageTag

    $buildArgs = @(
        'build',
        '-t', $imageTag,
        '-f', $resolvedDockerfilePath,
        '--build-arg', "DOTNET_SDK_IMAGE=$dotnetSdkImage",
        '--build-arg', "PYLAVI_URL=$pylaviUrl",
        '--build-arg', "PYLAVI_SHA256=$pylaviSha",
        $repoRoot
    )
    $result.docker_build_command = Get-CommandPreview -Arguments $buildArgs

    Write-Log ("Building deterministic runner-cli image: {0}" -f $imageTag)
    Write-Log ("Build command: {0}" -f $result.docker_build_command)

    $buildOutput = & docker @buildArgs 2>&1
    $result.docker_build_exit_code = $LASTEXITCODE
    foreach ($line in @($buildOutput)) {
        Write-Log ("[docker-build] {0}" -f [string]$line)
    }
    if ([int]$result.docker_build_exit_code -ne 0) {
        throw "Docker image build failed with exit code $($result.docker_build_exit_code)."
    }

    $dockerSourceMountPath = Convert-ToDockerHostPath -Path $resolvedSourceRoot
    $dockerOutputMountPath = Convert-ToDockerHostPath -Path $resolvedOutputDirectory
    $sourceMountSpec = "type=bind,source=$dockerSourceMountPath,target=/source,readonly"
    $outputMountSpec = "type=bind,source=$dockerOutputMountPath,target=/artifacts"

    $result.docker_source_mount_path = $dockerSourceMountPath
    $result.docker_output_mount_path = $dockerOutputMountPath

    $containerScript = @'
set -euo pipefail
mkdir -p /workspace/src /artifacts/commands /artifacts/test-results /artifacts/publish
rm -rf /workspace/src/*
cp -a /source/. /workspace/src/
cd /workspace/src/Tooling/runner-cli
dotnet --info | tee /artifacts/commands/dotnet-info.txt
vi_validate --help > /artifacts/commands/vi-validate-help.txt 2>&1 || true
dotnet test RunnerCli.Tests/RunnerCli.Tests.csproj --configuration Release --results-directory /artifacts/test-results --logger "trx;LogFileName=runner-cli-tests.trx" | tee /artifacts/commands/dotnet-test.txt
dotnet publish RunnerCli/RunnerCli.csproj --configuration Release --runtime __RUNTIME__ --self-contained true -p:PublishSingleFile=true -p:PublishTrimmed=true --output /artifacts/publish/__RUNTIME__ | tee /artifacts/commands/dotnet-publish.txt
'@
    $containerScript = $containerScript.Replace('__RUNTIME__', $Runtime)

    $runArgs = @(
        'run', '--rm',
        '--mount', $sourceMountSpec,
        '--mount', $outputMountSpec,
        $imageTag,
        'bash', '-lc', $containerScript
    )
    $result.docker_run_command = Get-CommandPreview -Arguments $runArgs

    Write-Log ("Running runner-cli Linux container command: {0}" -f $result.docker_run_command)
    & docker @runArgs 1> $stdoutPath 2> $stderrPath
    $result.docker_run_exit_code = $LASTEXITCODE
    Write-Log ("Runner-cli container exit code: {0}" -f [string]$result.docker_run_exit_code)

    if ([int]$result.docker_run_exit_code -ne 0) {
        $stderrPreview = ''
        if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
            $stderrPreview = (Get-Content -LiteralPath $stderrPath -TotalCount 12) -join ' | '
        }
        throw "Runner-cli Linux container run failed with exit code $($result.docker_run_exit_code). stderr preview: $stderrPreview"
    }

    $publishBinaryPath = Join-Path $resolvedOutputDirectory ("publish/{0}/runner-cli" -f $Runtime)
    $result.publish_binary_path = $publishBinaryPath
    if (-not (Test-Path -LiteralPath $publishBinaryPath -PathType Leaf)) {
        throw "Expected published runner-cli binary not found at '$publishBinaryPath'."
    }

    $result.status = 'passed'
    $statusPayload.status = 'passed'
    $statusPayload.reason = 'runner-cli Linux Docker build/test/publish completed successfully.'
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
    throw "runner-cli Linux Docker validation failed: $($statusPayload.reason). See '$resultPath' and '$logPath'."
}
