param(
  [Parameter(Mandatory = $true)]
  [long]$RunId,

  [Parameter(Mandatory = $false)]
  [string]$OwnerRepo = 'svelderrainruiz/labview-icon-editor',

  [Parameter(Mandatory = $false)]
  [string]$ReleaseTag,

  [Parameter(Mandatory = $false)]
  [string]$OutputDir,

  [Parameter(Mandatory = $false)]
  [bool]$RollbackTriggered = $false
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

$headers = @{ 'User-Agent' = 'codex-release-metrics' }
$run = Invoke-RestMethod -Uri $runUrl -Headers $headers
$jobs = Invoke-RestMethod -Uri $jobsUrl -Headers $headers
$artifacts = Invoke-RestMethod -Uri $artifactsUrl -Headers $headers

if ([string]::IsNullOrWhiteSpace($ReleaseTag)) {
  $manifestPath = Join-Path (Join-Path $PSScriptRoot '..') 'manifest.json'
  if (-not (Test-Path -Path $manifestPath -PathType Leaf)) {
    throw "manifest.json not found: $manifestPath"
  }

  $manifest = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json
  $ReleaseTag = "v$($manifest.version)"
}

$requiredArtifacts = @(
  'lv_icon_x64.lvlibp',
  'lv_icon_x86.lvlibp',
  'conformance-full',
  'core-conformance-linux-evidence',
  'core-conformance-windows-evidence'
)

$observedArtifacts = @($artifacts.artifacts | ForEach-Object { $_.name })
$missingArtifacts = @($requiredArtifacts | Where-Object { $_ -notin $observedArtifacts })
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