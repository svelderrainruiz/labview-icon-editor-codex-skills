[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$LinuxLabviewImage = 'nationalinstruments/labview:2026q1-linux-pwsh',

    [Parameter(Mandatory = $false)]
    [string]$ConsumerPath = 'consumer',

    [Parameter(Mandatory = $false)]
    [string]$ConsumerRepo = 'svelderrainruiz/labview-icon-editor',

    [Parameter(Mandatory = $false)]
    [string]$ConsumerRef = 'patch/456-2020-migration-branch-from-9e46ecf',

    [Parameter(Mandatory = $false)]
    [string]$ConsumerExpectedSha = '9e46ecf591bc36afca8ddf4ce688a5f58604a12a',

    [Parameter(Mandatory = $false)]
    [string]$VipcPath = 'consumer/.github/actions/apply-vipc/runner_dependencies.vipc',

    [Parameter(Mandatory = $false)]
    [string]$LabVIEWVersion = '',

    [Parameter(Mandatory = $false)]
    [ValidateSet('64')]
    [string]$Bitness = '64',

    [Parameter(Mandatory = $false)]
    [bool]$VipmCommunityEdition = $true,

    [Parameter(Mandatory = $false)]
    [string]$VipmCliUrl = '',

    [Parameter(Mandatory = $false)]
    [string]$VipmCliSha256 = '',

    [Parameter(Mandatory = $false)]
    [ValidateSet('tar.gz', 'tgz', 'zip')]
    [string]$VipmCliArchiveType = 'tar.gz',

    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory = '',

    [Parameter(Mandatory = $false)]
    [string]$VipmCapableImageTag = 'nationalinstruments/labview:2026q1-linux-pwsh-vipm-local'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-FullPath {
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path -Path $BasePath -ChildPath $Path))
}

function Convert-ToLabVIEWYear {
    param(
        [Parameter(Mandatory)]
        [string]$VersionText
    )

    $trimmed = $VersionText.Trim()
    if ($trimmed -match '^\d{4}$') {
        return $trimmed
    }

    if ($trimmed -match '^(\d{4})\.0$') {
        return $Matches[1]
    }

    if ($trimmed -match '^(\d{2})\.0$') {
        return "20$($Matches[1])"
    }

    if ($trimmed -match '^(\d{2})$') {
        return "20$trimmed"
    }

    throw "Unable to normalize LabVIEW version '$VersionText' to YYYY format."
}

function Resolve-VipcTargetVersion {
    param(
        [Parameter(Mandatory)]
        [string]$ResolvedVipcPath
    )

    $tempExtractRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("vipc-inspect-{0}" -f [guid]::NewGuid().ToString())
    New-Item -Path $tempExtractRoot -ItemType Directory -Force | Out-Null

    try {
        Expand-Archive -Path $ResolvedVipcPath -DestinationPath $tempExtractRoot -Force
        $configPath = Join-Path -Path $tempExtractRoot -ChildPath 'config.xml'
        if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
            throw "config.xml was not found inside VIPC '$ResolvedVipcPath'."
        }

        [xml]$xml = Get-Content -LiteralPath $configPath -Raw
        $targetNode = $xml.SelectSingleNode('//Target')
        if ($null -eq $targetNode) {
            $targetNode = $xml.SelectSingleNode('//target')
        }

        if ($null -eq $targetNode -or [string]::IsNullOrWhiteSpace($targetNode.Version)) {
            throw "Target version metadata was not found in VIPC config.xml."
        }

        return [string]$targetNode.Version
    }
    finally {
        Remove-Item -LiteralPath $tempExtractRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host $Message
    Add-Content -LiteralPath $script:LogPath -Value $Message -Encoding utf8
}

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $displayCommand = "$FilePath $($Arguments -join ' ')"
    Write-Log "[$Label] $displayCommand"

    $output = & $FilePath @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    if ($output) {
        foreach ($line in $output) {
            Write-Log ([string]$line)
        }
    }

    Write-Log "[$Label] exit=$exitCode"
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = @($output)
    }
}

$repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path -Path $repoRoot -ChildPath ("artifacts/vipm-vipc-apply/{0}" -f (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))
}

$OutputDirectory = Resolve-FullPath -BasePath $repoRoot -Path $OutputDirectory
if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

$script:LogPath = Join-Path -Path $OutputDirectory -ChildPath 'vipm-apply.log'
$resultPath = Join-Path -Path $OutputDirectory -ChildPath 'vipm-apply.result.json'
Set-Content -LiteralPath $script:LogPath -Value '' -Encoding utf8

$startedUtc = (Get-Date).ToUniversalTime()
$scriptExitCode = 0
$errorMessage = $null
$consumerActualSha = $null
$vipcSha256 = $null
$vipcTargetVersion = $null
$resolvedLabVIEWYear = $null
$selectedImage = $null
$vipcContainerPath = $null
$vipmInstallCommand = $null

try {
    if ((-not [string]::IsNullOrWhiteSpace($VipmCliUrl)) -xor (-not [string]::IsNullOrWhiteSpace($VipmCliSha256))) {
        throw "VipmCliUrl and VipmCliSha256 must be provided together."
    }

    $dockerInfo = Invoke-LoggedCommand -Label 'docker-info' -FilePath 'docker' -Arguments @('info', '--format', 'OSType={{.OSType}};Server={{.ServerVersion}}')
    if ($dockerInfo.ExitCode -ne 0) {
        throw "Unable to query Docker daemon info."
    }

    $dockerInfoText = ($dockerInfo.Output -join "`n")
    if ($dockerInfoText -notmatch 'OSType=linux') {
        throw "Docker engine OSType is not linux. Ensure Docker Desktop is running Linux containers."
    }

    $consumerRoot = Resolve-FullPath -BasePath $repoRoot -Path $ConsumerPath
    $consumerGitRoot = Join-Path -Path $consumerRoot -ChildPath '.git'
    if (-not (Test-Path -LiteralPath $consumerGitRoot -PathType Container)) {
        if (Test-Path -LiteralPath $consumerRoot -PathType Container) {
            $existing = @(Get-ChildItem -LiteralPath $consumerRoot -Force -ErrorAction SilentlyContinue)
            if ($existing.Count -gt 0) {
                throw "Consumer path '$consumerRoot' is not empty and not a git repository."
            }
        }
        else {
            $consumerParent = Split-Path -Path $consumerRoot -Parent
            if (-not [string]::IsNullOrWhiteSpace($consumerParent) -and -not (Test-Path -LiteralPath $consumerParent -PathType Container)) {
                New-Item -Path $consumerParent -ItemType Directory -Force | Out-Null
            }
        }

        $cloneUrl = "https://github.com/$ConsumerRepo.git"
        $cloneResult = Invoke-LoggedCommand -Label 'consumer-clone' -FilePath 'git' -Arguments @('clone', $cloneUrl, $consumerRoot)
        if ($cloneResult.ExitCode -ne 0) {
            throw "Failed to clone consumer repository '$cloneUrl'."
        }
    }

    $fetchResult = Invoke-LoggedCommand -Label 'consumer-fetch' -FilePath 'git' -Arguments @('-C', $consumerRoot, 'fetch', 'origin', $ConsumerRef)
    if ($fetchResult.ExitCode -ne 0) {
        throw "Failed to fetch consumer ref '$ConsumerRef'."
    }

    $checkoutResult = Invoke-LoggedCommand -Label 'consumer-checkout' -FilePath 'git' -Arguments @('-C', $consumerRoot, 'checkout', '-B', $ConsumerRef, "origin/$ConsumerRef")
    if ($checkoutResult.ExitCode -ne 0) {
        throw "Failed to checkout consumer ref '$ConsumerRef'."
    }

    $headResult = Invoke-LoggedCommand -Label 'consumer-rev-parse' -FilePath 'git' -Arguments @('-C', $consumerRoot, 'rev-parse', 'HEAD')
    if ($headResult.ExitCode -ne 0) {
        throw "Failed to resolve consumer HEAD SHA."
    }

    $consumerActualSha = (($headResult.Output | Select-Object -Last 1).ToString().Trim())
    if ($consumerActualSha -ne $ConsumerExpectedSha) {
        throw "Consumer SHA mismatch. Expected '$ConsumerExpectedSha', got '$consumerActualSha'."
    }

    $resolvedVipcPath = Resolve-FullPath -BasePath $repoRoot -Path $VipcPath
    if (-not (Test-Path -LiteralPath $resolvedVipcPath -PathType Leaf)) {
        throw "VIPC path does not exist: '$resolvedVipcPath'."
    }

    $vipcSha256 = (Get-FileHash -LiteralPath $resolvedVipcPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $vipcTargetVersion = Resolve-VipcTargetVersion -ResolvedVipcPath $resolvedVipcPath
    $resolvedLabVIEWYear = if ([string]::IsNullOrWhiteSpace($LabVIEWVersion)) {
        Convert-ToLabVIEWYear -VersionText $vipcTargetVersion
    }
    else {
        Convert-ToLabVIEWYear -VersionText $LabVIEWVersion
    }

    $normalizedConsumerRoot = [System.IO.Path]::GetFullPath($consumerRoot).TrimEnd('\', '/')
    $normalizedVipcPath = [System.IO.Path]::GetFullPath($resolvedVipcPath)
    if (-not $normalizedVipcPath.StartsWith($normalizedConsumerRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "VIPC path '$normalizedVipcPath' must be under consumer path '$normalizedConsumerRoot' so it can be mounted to /workspace."
    }

    $vipcRelativeToConsumer = $normalizedVipcPath.Substring($normalizedConsumerRoot.Length).TrimStart('\', '/')
    $vipcContainerPath = "/workspace/$($vipcRelativeToConsumer -replace '\\', '/')"

    $inspectBaseImage = Invoke-LoggedCommand -Label 'docker-image-inspect-base' -FilePath 'docker' -Arguments @('image', 'inspect', $LinuxLabviewImage)
    if ($inspectBaseImage.ExitCode -ne 0) {
        $pullBaseImage = Invoke-LoggedCommand -Label 'docker-image-pull-base' -FilePath 'docker' -Arguments @('pull', $LinuxLabviewImage)
        if ($pullBaseImage.ExitCode -ne 0) {
            throw "Unable to inspect or pull base Linux image '$LinuxLabviewImage'."
        }
    }

    $vipmInBaseImage = Invoke-LoggedCommand -Label 'vipm-presence-base' -FilePath 'docker' -Arguments @('run', '--rm', $LinuxLabviewImage, 'bash', '-lc', 'command -v vipm >/dev/null 2>&1')
    if ($vipmInBaseImage.ExitCode -eq 0) {
        $selectedImage = $LinuxLabviewImage
    }
    else {
        if ([string]::IsNullOrWhiteSpace($VipmCliUrl) -or [string]::IsNullOrWhiteSpace($VipmCliSha256)) {
            throw "vipm was not found in '$LinuxLabviewImage'. Provide VipmCliUrl and VipmCliSha256 to build a VIPM-capable image."
        }

        $dockerfilePath = Join-Path -Path $repoRoot -ChildPath 'docker/ni-lv-pwsh.Dockerfile'
        if (-not (Test-Path -LiteralPath $dockerfilePath -PathType Leaf)) {
            throw "Required Dockerfile was not found: '$dockerfilePath'."
        }

        $buildResult = Invoke-LoggedCommand -Label 'docker-build-vipm-capable' -FilePath 'docker' -Arguments @(
            'build',
            '-t', $VipmCapableImageTag,
            '--build-arg', "VIPM_CLI_URL=$VipmCliUrl",
            '--build-arg', "VIPM_CLI_SHA256=$VipmCliSha256",
            '--build-arg', "VIPM_CLI_ARCHIVE_TYPE=$VipmCliArchiveType",
            '-f', $dockerfilePath,
            $repoRoot
        )
        if ($buildResult.ExitCode -ne 0) {
            throw "Failed to build VIPM-capable image '$VipmCapableImageTag'."
        }

        $vipmInFallbackImage = Invoke-LoggedCommand -Label 'vipm-presence-fallback' -FilePath 'docker' -Arguments @('run', '--rm', $VipmCapableImageTag, 'bash', '-lc', 'command -v vipm >/dev/null 2>&1')
        if ($vipmInFallbackImage.ExitCode -ne 0) {
            throw "vipm was not found in fallback image '$VipmCapableImageTag' after build."
        }

        $selectedImage = $VipmCapableImageTag
    }

    $vipmInstallCommand = "vipm --labview-version $resolvedLabVIEWYear --labview-bitness $Bitness install $vipcContainerPath"
    $vipmCommunityEditionValue = if ($VipmCommunityEdition) { 'true' } else { 'false' }

    $inContainerScript = @'
set -euo pipefail

resolve_vipm() {
  if command -v vipm >/dev/null 2>&1; then
    return 0
  fi

  vipm_candidate="$(find /usr/local/bin /usr/bin /opt /usr/local/natinst -maxdepth 6 -type f -name vipm -perm -111 2>/dev/null | head -n 1 || true)"
  if [[ -n "$vipm_candidate" ]]; then
    export PATH="$(dirname "$vipm_candidate"):$PATH"
    echo "vipm candidate discovered at: $vipm_candidate" >&2
  fi

  command -v vipm >/dev/null 2>&1
}

if ! resolve_vipm; then
  echo "vipm is not available on PATH inside Linux image." >&2
  echo "PATH=$PATH" >&2
  echo "vipm lookup: $(command -v vipm || echo not-found)" >&2
  echo "vipm search roots: /usr/local/bin /usr/bin /opt /usr/local/natinst" >&2
  exit 127
fi

if [[ ! -f "$VIPC_PATH_IN_CONTAINER" ]]; then
  echo "VIPC file not found in container at: $VIPC_PATH_IN_CONTAINER" >&2
  exit 2
fi

echo "vipm help preview (first 20 lines):" >&2
if ! (vipm help 2>&1 || vipm --help 2>&1) | sed -n "1,20p" >&2; then
  echo "Unable to print vipm help output from resolved vipm binary." >&2
  exit 1
fi

if [[ "$VIPM_COMMUNITY_EDITION" == "true" || "$VIPM_COMMUNITY_EDITION" == "1" || "$VIPM_COMMUNITY_EDITION" == "yes" || "$VIPM_COMMUNITY_EDITION" == "on" ]]; then
  vipm activate
fi

vipm --labview-version "$LABVIEW_YEAR" --labview-bitness "$LABVIEW_BITNESS" install "$VIPC_PATH_IN_CONTAINER"
'@

    $installResult = Invoke-LoggedCommand -Label 'vipm-install' -FilePath 'docker' -Arguments @(
        'run',
        '--rm',
        '-v', "${consumerRoot}:/workspace",
        '-w', '/workspace',
        '-e', "VIPM_COMMUNITY_EDITION=$vipmCommunityEditionValue",
        '-e', "LABVIEW_YEAR=$resolvedLabVIEWYear",
        '-e', "LABVIEW_BITNESS=$Bitness",
        '-e', "VIPC_PATH_IN_CONTAINER=$vipcContainerPath",
        $selectedImage,
        'bash',
        '-lc',
        $inContainerScript
    )

    if ($installResult.ExitCode -ne 0) {
        $scriptExitCode = $installResult.ExitCode
        throw "VIPM install command failed with exit code $scriptExitCode."
    }

    $scriptExitCode = 0
}
catch {
    $errorMessage = $_.Exception.Message
    if ($scriptExitCode -eq 0) {
        $scriptExitCode = 1
    }
    Write-Log "ERROR: $errorMessage"
}
finally {
    $completedUtc = (Get-Date).ToUniversalTime()
    $result = [ordered]@{
        started_utc            = $startedUtc.ToString('o')
        completed_utc          = $completedUtc.ToString('o')
        output_directory       = $OutputDirectory
        log_path               = $script:LogPath
        consumer_repo          = $ConsumerRepo
        consumer_ref           = $ConsumerRef
        consumer_expected_sha  = $ConsumerExpectedSha
        consumer_actual_sha    = $consumerActualSha
        vipc_path              = $VipcPath
        vipc_path_in_container = $vipcContainerPath
        vipc_sha256            = $vipcSha256
        vipc_target_version    = $vipcTargetVersion
        resolved_labview_year  = $resolvedLabVIEWYear
        bitness                = $Bitness
        requested_image        = $LinuxLabviewImage
        execution_image        = $selectedImage
        vipm_community_edition = $VipmCommunityEdition
        vipm_command           = $vipmInstallCommand
        exit_code              = [int]$scriptExitCode
        error_message          = $errorMessage
    }

    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding utf8
    Write-Host "VIPM apply log: $script:LogPath"
    Write-Host "VIPM apply result: $resultPath"
}

if ($scriptExitCode -ne 0) {
    exit $scriptExitCode
}
