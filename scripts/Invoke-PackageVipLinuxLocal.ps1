param(
  [Parameter(Mandatory = $false)]
  [string]$LinuxLabviewImage = 'nationalinstruments/labview:2026q1-linux-pwsh',

  [Parameter(Mandatory = $false)]
  [string]$ConsumerPath = 'consumer',

  [Parameter(Mandatory = $false)]
  [string]$VipmProjectPath = 'consumer/Tooling/deployment/NI Icon editor.vipb',

  [Parameter(Mandatory = $false)]
  [bool]$VipmCommunityEdition = $true,
  [Parameter(Mandatory = $false)]
  [bool]$LabviewCommunityEdition = $true
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
$consumerFullPath = Join-Path $repoRoot $ConsumerPath

if (-not (Test-Path -LiteralPath $consumerFullPath -PathType Container)) {
  throw "Consumer path not found: '$consumerFullPath'. Checkout or create the consumer repo first."
}

$normalizedVipmProjectPath = $VipmProjectPath -replace '\\', '/'
$vipmProjectPathInContainer = "/workspace/$($normalizedVipmProjectPath -replace '^consumer/', '')"
$vipmCommunityEditionValue = if ($VipmCommunityEdition) { 'true' } else { 'false' }
$labviewCommunityEditionValue = if ($LabviewCommunityEdition) { 'true' } else { 'false' }

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
  echo "vipm is not available on PATH inside Linux image: $LINUX_LABVIEW_IMAGE" >&2
  echo "PATH=$PATH" >&2
  echo "vipm lookup: $(command -v vipm || echo not-found)" >&2
  echo "vipm search roots: /usr/local/bin /usr/bin /opt /usr/local/natinst" >&2
  echo "To triage deterministically, rebuild with VIPM CLI args:" >&2
  echo "  docker build --build-arg VIPM_CLI_URL=ARTIFACT_URL --build-arg VIPM_CLI_SHA256=SHA256 --build-arg VIPM_CLI_ARCHIVE_TYPE=tar.gz -t $LINUX_LABVIEW_IMAGE -f docker/ni-lv-pwsh.Dockerfile ." >&2
  exit 1
fi

if [[ "$VIPM_COMMUNITY_EDITION" == "true" || "$VIPM_COMMUNITY_EDITION" == "1" || "$VIPM_COMMUNITY_EDITION" == "yes" || "$VIPM_COMMUNITY_EDITION" == "on" ]]; then
  vipm activate
fi

vipm build "$VIPM_PROJECT_PATH_IN_CONTAINER"
'@

$inContainerScript = $inContainerScript -replace "`r`n", "`n"

$dockerArgs = @(
  'run', '--rm',
  '-v', "${consumerFullPath}:/workspace",
  '-w', '/workspace',
  '-e', "VIPM_COMMUNITY_EDITION=$vipmCommunityEditionValue",
  '-e', "LABVIEW_COMMUNITY_EDITION=$labviewCommunityEditionValue",
  '-e', "VIPM_PROJECT_PATH_IN_CONTAINER=$vipmProjectPathInContainer",
  '-e', "LINUX_LABVIEW_IMAGE=$LinuxLabviewImage",
  $LinuxLabviewImage,
  'bash', '-lc', $inContainerScript
)

& docker @dockerArgs

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}