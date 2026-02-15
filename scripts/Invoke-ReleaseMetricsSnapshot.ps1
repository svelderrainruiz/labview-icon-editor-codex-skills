param(
  [Parameter(Mandatory = $true)]
  [long]$RunId,

  [Parameter(Mandatory = $false)]
  [string]$OwnerRepo = 'svelderrainruiz/labview-icon-editor-codex-skills',

  [Parameter(Mandatory = $false)]
  [string]$ReleaseTag,

  [Parameter(Mandatory = $false)]
  [string]$OutputDir,

  [Parameter(Mandatory = $false)]
  [bool]$RollbackTriggered = $false,

  [Parameter(Mandatory = $false)]
  [string]$GitHubToken
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $OutputDir = Join-Path (Join-Path $PSScriptRoot '..') 'artifacts/release-metrics'
}

if (-not (Test-Path -Path $OutputDir -PathType Container)) {
  New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
}

$runUrl = "https://api.github.com/repos/$OwnerRepo/actions/runs/$RunId"
$jobsUrl = "https://api.github.com/repos/$OwnerRepo/actions/runs/$RunId/jobs?per_page=100"
$artifactsUrl = "https://api.github.com/repos/$OwnerRepo/actions/runs/$RunId/artifacts?per_page=100"

function Get-GitHubJson {
  param(
    [string]$Path
  )

  $gh = Get-Command gh -ErrorAction SilentlyContinue
  if ($gh) {
    $ghOutput = & gh api $Path
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($ghOutput)) {
      return ($ghOutput | ConvertFrom-Json -ErrorAction Stop)
    }
  }

  $headers = @{ 'User-Agent' = 'codex-release-metrics' }
  $token = if ($GitHubToken) { $GitHubToken } elseif ($env:GH_TOKEN) { $env:GH_TOKEN } elseif ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } else { $null }
  if (-not [string]::IsNullOrWhiteSpace($token)) {
    $headers.Authorization = "Bearer $token"
    $headers.Accept = 'application/vnd.github+json'
    $headers.'X-GitHub-Api-Version' = '2022-11-28'
  }

  return (Invoke-RestMethod -Uri ("https://api.github.com/{0}" -f $Path) -Headers $headers)
}

$run = Get-GitHubJson -Path "repos/$OwnerRepo/actions/runs/$RunId"
$jobs = Get-GitHubJson -Path "repos/$OwnerRepo/actions/runs/$RunId/jobs?per_page=100"
$artifacts = Get-GitHubJson -Path "repos/$OwnerRepo/actions/runs/$RunId/artifacts?per_page=100"

if ([string]::IsNullOrWhiteSpace($ReleaseTag)) {
  $manifestPath = Join-Path (Join-Path $PSScriptRoot '..') 'manifest.json'
  if (-not (Test-Path -Path $manifestPath -PathType Leaf)) {
    throw "manifest.json not found: $manifestPath"
  }

  $manifest = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json
  $ReleaseTag = "v$($manifest.version)"
}

$requiredArtifacts = @(
  'docker-contract-ppl-bundle-windows-x64-',
  'docker-contract-ppl-bundle-linux-x64-',
  'docker-contract-vip-package-self-hosted-'
)

$observedArtifacts = @($artifacts.artifacts | ForEach-Object { $_.name })
$missingArtifacts = @()
foreach ($requiredArtifactPrefix in $requiredArtifacts) {
  $matchFound = $false
  foreach ($artifactName in $observedArtifacts) {
    if ($artifactName.StartsWith($requiredArtifactPrefix, [System.StringComparison]::Ordinal)) {
      $matchFound = $true
      break
    }
  }

  if (-not $matchFound) {
    $missingArtifacts += $requiredArtifactPrefix
  }
}
$failedJobs = @($jobs.jobs | Where-Object {
    $_.conclusion -in @('failure', 'cancelled', 'timed_out', 'startup_failure', 'action_required')
  })

$createdAt = [datetimeoffset]::Parse($run.created_at)
$updatedAt = [datetimeoffset]::Parse($run.updated_at)
$durationMinutes = [math]::Max(0, [math]::Round(($updatedAt - $createdAt).TotalMinutes, 2))

$topFailureCauses = @($failedJobs | Group-Object -Property conclusion | Sort-Object -Property Count -Descending | Select-Object -First 3 | ForEach-Object { "$($_.Name):$($_.Count)" })

$isCompleted = $run.status -eq 'completed'
$isSuccess = $run.conclusion -eq 'success'
$isGo = $isCompleted -and $isSuccess -and $failedJobs.Count -eq 0 -and $missingArtifacts.Count -eq 0
$gateOutcome = if ($isGo) { 'go' } else { 'no-go' }

$payload = [pscustomobject]@{
  schema_version = '1.0'
  generated_utc = (Get-Date).ToUniversalTime().ToString('o')
  owner_repo = $OwnerRepo
  consumer_run_id = $RunId
  consumer_run_url = "https://github.com/$OwnerRepo/actions/runs/$RunId"
  release_tag = $ReleaseTag
  run_status = $run.status
  run_conclusion = if ($null -eq $run.conclusion) { 'pending' } else { [string]$run.conclusion }
  duration_minutes = $durationMinutes
  failed_job_count = $failedJobs.Count
  missing_required_artifact_count = $missingArtifacts.Count
  gate_outcome = $gateOutcome
  rollback_triggered = $RollbackTriggered
  top_failure_causes = $topFailureCauses
  failed_jobs = @($failedJobs | ForEach-Object {
      [pscustomobject]@{
        name = $_.name
        conclusion = $_.conclusion
      }
    })
  missing_required_artifacts = $missingArtifacts
}

$outputPath = Join-Path $OutputDir ("release-metrics-{0}.json" -f $RunId)
$payload | ConvertTo-Json -Depth 8 | Set-Content -Path $outputPath -Encoding utf8

$payload
