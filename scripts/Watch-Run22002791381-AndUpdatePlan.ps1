$ErrorActionPreference = 'Stop'

$runId = 22002791381
$ownerRepo = 'svelderrainruiz/labview-icon-editor'
$planPath = Join-Path $PSScriptRoot '..\release-plan-22002791381.md'

$runUrl = "https://api.github.com/repos/$ownerRepo/actions/runs/$runId"
$jobsUrl = "https://api.github.com/repos/$ownerRepo/actions/runs/$runId/jobs?per_page=100"
$artUrl = "https://api.github.com/repos/$ownerRepo/actions/runs/$runId/artifacts?per_page=100"

$requiredArtifacts = @(
  'lv_icon_x64.lvlibp',
  'lv_icon_x86.lvlibp',
  'conformance-full',
  'core-conformance-linux-evidence',
  'core-conformance-windows-evidence'
)

if (-not (Test-Path -Path $planPath -PathType Leaf)) {
  throw "Plan file not found: $planPath"
}

while ($true) {
  $run = Invoke-RestMethod -Uri $runUrl
  $jobs = Invoke-RestMethod -Uri $jobsUrl
  $art = Invoke-RestMethod -Uri $artUrl

  $artifactNames = @($art.artifacts | ForEach-Object { $_.name })
  $missingArtifacts = @($requiredArtifacts | Where-Object { $_ -notin $artifactNames })
  $badJobs = @($jobs.jobs | Where-Object {
      $_.conclusion -in @('failure', 'cancelled', 'timed_out', 'startup_failure', 'action_required')
    })

  $content = Get-Content -Raw -Path $planPath
  $content = $content -replace 'Checked at:.*', ('Checked at: ' + (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') + ' UTC')
  $content = $content -replace 'Run status:.*', ('Run status: ' + $run.status)
  $content = $content -replace 'Run conclusion:.*', ('Run conclusion: ' + ($(if ($null -eq $run.conclusion) { 'pending' } else { $run.conclusion })))
  $content = $content -replace 'Failed/cancelled/timed_out jobs observed:.*', ('Failed/cancelled/timed_out jobs observed: ' + $badJobs.Count)
  $content = $content -replace 'Missing required artifacts observed:.*', ('Missing required artifacts observed: ' + $missingArtifacts.Count)

  if ($run.status -eq 'completed') {
    $content = $content -replace '- \[ \] Consumer run 22002791381 is fully completed \(status = completed\)', '- [x] Consumer run 22002791381 is fully completed (status = completed)'
  }

  if ($run.conclusion -eq 'success') {
    $content = $content -replace '- \[ \] Consumer run 22002791381 conclusion = success', '- [x] Consumer run 22002791381 conclusion = success'
  } elseif ($run.status -eq 'completed' -and $run.conclusion -ne 'success') {
    $content = $content -replace '- \[x\] Consumer run 22002791381 conclusion = success', '- [ ] Consumer run 22002791381 conclusion = success'
  }

  if ($badJobs.Count -gt 0) {
    $content = $content -replace '- \[x\] No required CI job concluded with failure/cancelled/timed_out', '- [ ] No required CI job concluded with failure/cancelled/timed_out'
  }

  if ($missingArtifacts.Count -gt 0) {
    $content = $content -replace '- \[x\] Required packed library artifacts exist: lv_icon_x64\.lvlibp and lv_icon_x86\.lvlibp', '- [ ] Required packed library artifacts exist: lv_icon_x64.lvlibp and lv_icon_x86.lvlibp'
    $content = $content -replace '- \[x\] Conformance evidence artifacts exist \(full \+ linux \+ windows\)', '- [ ] Conformance evidence artifacts exist (full + linux + windows)'
  }

  Set-Content -Path $planPath -Value $content -Encoding utf8

  if ($run.status -eq 'completed') {
    [pscustomobject]@{
      run_id = $runId
      status = $run.status
      conclusion = $run.conclusion
      updated_at = $run.updated_at
      failed_or_cancelled = $badJobs.Count
      missing_required_artifacts = $missingArtifacts.Count
      plan_file = (Resolve-Path $planPath).Path
    } | ConvertTo-Json -Depth 4
    break
  }

  Start-Sleep -Seconds 30
}
