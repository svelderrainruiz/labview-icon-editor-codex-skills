param(
  [Parameter(Mandatory = $true)]
  [long]$RunId,

  [Parameter(Mandatory = $true)]
  [string]$PlanPath,

  [Parameter(Mandatory = $false)]
  [string]$OwnerRepo = 'svelderrainruiz/labview-icon-editor-codex-skills',

  [Parameter(Mandatory = $false)]
  [string]$StatePath,

  [Parameter(Mandatory = $false)]
  [int]$PollSeconds = 30
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -Path $PlanPath -PathType Leaf)) {
  throw "Plan file not found: $PlanPath"
}

$runUrl = "https://api.github.com/repos/$OwnerRepo/actions/runs/$RunId"
$jobsUrl = "https://api.github.com/repos/$OwnerRepo/actions/runs/$RunId/jobs?per_page=100"
$artUrl = "https://api.github.com/repos/$OwnerRepo/actions/runs/$RunId/artifacts?per_page=100"

$requiredArtifacts = @(
  'docker-contract-ppl-bundle-windows-x64-',
  'docker-contract-ppl-bundle-linux-x64-',
  'docker-contract-vip-package-self-hosted-'
)

if (-not [string]::IsNullOrWhiteSpace($StatePath)) {
  $stateDir = Split-Path -Path $StatePath -Parent
  if (-not [string]::IsNullOrWhiteSpace($stateDir) -and -not (Test-Path -Path $stateDir -PathType Container)) {
    New-Item -Path $stateDir -ItemType Directory -Force | Out-Null
  }
}

while ($true) {
  try {
    $run = Invoke-RestMethod -Uri $runUrl
  } catch {
    Start-Sleep -Seconds $PollSeconds
    continue
  }

  $jobs = $null
  try {
    $jobs = Invoke-RestMethod -Uri $jobsUrl
  } catch {
    $jobs = @{ jobs = @() }
  }

  $art = $null
  try {
    $art = Invoke-RestMethod -Uri $artUrl
  } catch {
    $art = @{ artifacts = @() }
  }

  $artifactNames = @($art.artifacts | ForEach-Object { $_.name })
  $missingArtifacts = @()
  foreach ($requiredArtifactPrefix in $requiredArtifacts) {
    $matchFound = $false
    foreach ($artifactName in $artifactNames) {
      if ($artifactName.StartsWith($requiredArtifactPrefix, [System.StringComparison]::Ordinal)) {
        $matchFound = $true
        break
      }
    }

    if (-not $matchFound) {
      $missingArtifacts += $requiredArtifactPrefix
    }
  }
  $badJobs = @($jobs.jobs | Where-Object {
      $_.conclusion -in @('failure', 'cancelled', 'timed_out', 'startup_failure', 'action_required')
    })
  $isCompleted = $run.status -eq 'completed'
  $runConclusion = if ($null -eq $run.conclusion) { 'pending' } else { [string]$run.conclusion }
  $isSuccess = $runConclusion -eq 'success'
  $hasNoBadJobs = $badJobs.Count -eq 0
  $hasRequiredArtifacts = $missingArtifacts.Count -eq 0
  $isGo = $isCompleted -and $isSuccess -and $hasNoBadJobs -and $hasRequiredArtifacts

  $content = Get-Content -Raw -Path $PlanPath
  $content = $content -replace 'Checked at:.*', ('Checked at: ' + (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') + ' UTC')
  $content = $content -replace 'Run status:.*', ('Run status: ' + $run.status)
  $content = $content -replace 'Run conclusion:.*', ('Run conclusion: ' + ($(if ($null -eq $run.conclusion) { 'pending' } else { $run.conclusion })))
  $content = $content -replace 'Failed/cancelled/timed_out jobs observed:.*', ('Failed/cancelled/timed_out jobs observed: ' + $badJobs.Count)
  $content = $content -replace 'Missing required artifacts observed:.*', ('Missing required artifacts observed: ' + $missingArtifacts.Count)
  if (-not [string]::IsNullOrWhiteSpace($StatePath)) {
    $stateDisplayPath = $StatePath
    try {
      $repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
      $resolvedStatePath = (Resolve-Path -Path $StatePath).Path
      $stateDisplayPath = [System.IO.Path]::GetRelativePath($repoRoot, $resolvedStatePath).Replace('\\', '/')
    } catch {
      $stateDisplayPath = $StatePath
    }
    $content = $content -replace '- release_state_json:.*', ('- release_state_json: ' + $stateDisplayPath)
  }

  if ($run.status -eq 'completed') {
    $content = $content -replace ('- \[ \] Consumer run ' + $RunId + ' is fully completed \(status = completed\)'), ('- [x] Consumer run ' + $RunId + ' is fully completed (status = completed)')
  } else {
    $content = $content -replace ('- \[x\] Consumer run ' + $RunId + ' is fully completed \(status = completed\)'), ('- [ ] Consumer run ' + $RunId + ' is fully completed (status = completed)')
  }

  if ($run.conclusion -eq 'success') {
    $content = $content -replace ('- \[ \] Consumer run ' + $RunId + ' conclusion = success'), ('- [x] Consumer run ' + $RunId + ' conclusion = success')
  } elseif ($run.status -eq 'completed' -and $run.conclusion -ne 'success') {
    $content = $content -replace ('- \[x\] Consumer run ' + $RunId + ' conclusion = success'), ('- [ ] Consumer run ' + $RunId + ' conclusion = success')
  }

  if ($badJobs.Count -gt 0) {
    $content = $content -replace '- \[x\] No required CI job concluded with failure/cancelled/timed_out', '- [ ] No required CI job concluded with failure/cancelled/timed_out'
  } else {
    $content = $content -replace '- \[ \] No required CI job concluded with failure/cancelled/timed_out', '- [x] No required CI job concluded with failure/cancelled/timed_out'
  }

  if ($missingArtifacts.Count -gt 0) {
    $content = $content -replace '- \[x\] Required release artifacts exist: windows x64 bundle, linux x64 bundle, and self-hosted VIP package', '- [ ] Required release artifacts exist: windows x64 bundle, linux x64 bundle, and self-hosted VIP package'
  } else {
    $content = $content -replace '- \[ \] Required release artifacts exist: windows x64 bundle, linux x64 bundle, and self-hosted VIP package', '- [x] Required release artifacts exist: windows x64 bundle, linux x64 bundle, and self-hosted VIP package'
  }

  Set-Content -Path $PlanPath -Value $content -Encoding utf8

  if (-not [string]::IsNullOrWhiteSpace($StatePath)) {
    $statePayload = [pscustomobject]@{
      schema_version = '1.0'
      generated_utc = (Get-Date).ToUniversalTime().ToString('o')
      owner_repo = $OwnerRepo
      run_id = $RunId
      run_url = "https://github.com/$OwnerRepo/actions/runs/$RunId"
      run_status = $run.status
      run_conclusion = $runConclusion
      required_artifacts = $requiredArtifacts
      observed_artifacts = $artifactNames
      missing_required_artifacts = $missingArtifacts
      bad_jobs = @($badJobs | ForEach-Object {
          [pscustomobject]@{
            name = $_.name
            status = $_.status
            conclusion = $_.conclusion
            html_url = $_.html_url
          }
        })
      gate = [pscustomobject]@{
        is_completed = $isCompleted
        is_success = $isSuccess
        has_no_bad_jobs = $hasNoBadJobs
        has_required_artifacts = $hasRequiredArtifacts
      }
      is_go_eligible = $isGo
      plan_path = (Resolve-Path $PlanPath).Path
      phase = if ($isCompleted) { 'terminal' } else { 'monitoring' }
    }

    $statePayload | ConvertTo-Json -Depth 8 | Set-Content -Path $StatePath -Encoding utf8
  }

  if ($isCompleted) {
    [pscustomobject]@{
      run_id = $RunId
      status = $run.status
      conclusion = $run.conclusion
      updated_at = $run.updated_at
      failed_or_cancelled = $badJobs.Count
      missing_required_artifacts = $missingArtifacts.Count
      plan_file = (Resolve-Path $PlanPath).Path
    } | ConvertTo-Json -Depth 4
    break
  }

  Start-Sleep -Seconds $PollSeconds
}
