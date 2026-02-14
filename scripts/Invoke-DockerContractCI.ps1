param(
  [Parameter(Mandatory = $false)]
  [string]$DockerImage = 'mcr.microsoft.com/powershell:7.4-ubuntu-22.04',

  [Parameter(Mandatory = $false)]
  [string]$TestPath = './tests/*.Tests.ps1',

  [Parameter(Mandatory = $false)]
  [switch]$BootstrapPowerShell
)

$ErrorActionPreference = 'Stop'

if (-not $BootstrapPowerShell.IsPresent -and $DockerImage -like 'nationalinstruments/*') {
  $BootstrapPowerShell = $true
}

$repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path

$testRunnerPath = '/workspace/scripts/Invoke-ContractTests.ps1'

$entrypointCheck = "command -v pwsh >/dev/null 2>&1"

if ($BootstrapPowerShell) {
  $bootstrapAndRun = "set -eu; if ! command -v pwsh >/dev/null 2>&1; then export DEBIAN_FRONTEND=noninteractive; apt-get -qq update >/dev/null; apt-get -qq install -y wget apt-transport-https software-properties-common >/dev/null; wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb; dpkg -i /tmp/packages-microsoft-prod.deb >/dev/null; apt-get -qq update >/dev/null; apt-get -qq install -y powershell >/dev/null; fi; pwsh -NoProfile -File '$testRunnerPath' -TestPath '$TestPath'"

  docker run --rm `
    -v "${repoRoot}:/workspace" `
    -w /workspace `
    $DockerImage `
    bash -lc $bootstrapAndRun
  exit $LASTEXITCODE
}

docker run --rm `
  -v "${repoRoot}:/workspace" `
  -w /workspace `
  $DockerImage `
  bash -lc "$entrypointCheck"

if ($LASTEXITCODE -ne 0) {
  throw "Image '$DockerImage' does not include pwsh. Re-run with -BootstrapPowerShell or choose a PowerShell image."
}

docker run --rm `
  -v "${repoRoot}:/workspace" `
  -w /workspace `
  $DockerImage `
  pwsh -NoProfile -File $testRunnerPath -TestPath $TestPath