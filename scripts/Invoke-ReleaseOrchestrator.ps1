param(
  [Parameter(Mandatory = $true)]
  [long]$RunId,

  [Parameter(Mandatory = $true)]
  [string]$PlanPath,

  [Parameter(Mandatory = $false)]
  [string]$OwnerRepo = 'svelderrainruiz/labview-icon-editor',

  [Parameter(Mandatory = $false)]
  [string]$SkillRepo,

  [Parameter(Mandatory = $false)]
  [string]$ReleaseTag,

  [Parameter(Mandatory = $false)]
  [bool]$RunSelfHosted = $true,

  [Parameter(Mandatory = $false)]
  [bool]$RunBuildSpec = $true,

  [Parameter(Mandatory = $false)]
  [int]$PollSeconds = 30,

  [Parameter(Mandatory = $false)]
  [string]$OutputDir,

  [Parameter(Mandatory = $false)]
  [string]$GitHubToken,

  [Parameter(Mandatory = $false)]
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Get-RunSnapshot {
  param(
    [string]$Repo,
    [long]$Id
  )

  $headers = @{ 'User-Agent' = 'codex-orchestrator' }
  $run = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/actions/runs/$Id" -Headers $headers
  $jobs = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/actions/runs/$Id/jobs?per_page=100" -Headers $headers
  $artifacts = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/actions/runs/$Id/artifacts?per_page=100" -Headers $headers

  [pscustomobject]@{
    run = $run
    jobs = $jobs
    artifacts = $artifacts
  }
}

function Update-PlanDispatchSection {
  param(
    [string]$Path,
    [string]$Tag,
    [bool]$Dispatched,
    [string]$StatePath,
    [string]$DispatchPath
  )

  if (-not (Test-Path -Path $Path -PathType Leaf)) {
    return
  }

  $content = Get-Content -Raw -Path $Path
  $content = $content -replace '- release_tag: TODO \(set next semver tag, example: v0\.4\.1\)', ('- release_tag: ' + $Tag)
  $content = $content -replace '- \[ \] Choose and record release_tag: .*', ('- [x] Choose and record release_tag: ' + $Tag)

  if (-not [string]::IsNullOrWhiteSpace($StatePath)) {
    $content = $content -replace '- release_state_json:.*', ('- release_state_json: ' + (Convert-ToPlanPath -PathValue $StatePath))
  }

  if (-not [string]::IsNullOrWhiteSpace($DispatchPath)) {
    $content = $content -replace '- dispatch_result_json:.*', ('- dispatch_result_json: ' + (Convert-ToPlanPath -PathValue $DispatchPath))
  }

  if ($Dispatched) {
    $content = $content -replace '- \[ \] Trigger release-skill-layer with prefilled inputs above', '- [x] Trigger release-skill-layer with prefilled inputs above'
  }

  Set-Content -Path $Path -Value $content -Encoding utf8
}

function Convert-ToPlanPath {
  param(
    [string]$PathValue
  )

  if ([string]::IsNullOrWhiteSpace($PathValue)) {
    return $PathValue
  }

  try {
    $repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
    $resolvedPath = $PathValue

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
      $resolvedPath = (Resolve-Path -Path $PathValue).Path
    } else {
      $candidate = Join-Path $repoRoot $PathValue
      if (Test-Path -Path $candidate) {
        $resolvedPath = (Resolve-Path -Path $candidate).Path
      } else {
        $resolvedPath = $candidate
      }
    }

    return [System.IO.Path]::GetRelativePath($repoRoot, $resolvedPath).Replace('\\', '/')
  } catch {
    return $PathValue
  }
}

function Get-SkillRepo {
  if ($SkillRepo) {
    return $SkillRepo
  }

  if ($env:GITHUB_REPOSITORY) {
    return $env:GITHUB_REPOSITORY
  }

  try {
    $remote = (git remote get-url origin).Trim()
    if ($remote -match 'github\.com[:/](?<repo>[^/]+/[^/.]+)(\.git)?$') {
      return $Matches.repo
    }
  } catch {
  }

  throw 'SkillRepo was not provided and could not be inferred. Pass -SkillRepo <owner/repo>.'
}

function Get-OrchestratorRef {
  try {
    $branch = (git rev-parse --abbrev-ref HEAD).Trim()
    if ([string]::IsNullOrWhiteSpace($branch) -or $branch -eq 'HEAD') {
      return 'main'
    }
    return $branch
  } catch {
    return 'main'
  }
}

function Dispatch-ReleaseWorkflow {
  param(
    [string]$Repo,
    [string]$Ref,
    [string]$Tag,
    [string]$ConsumerRepo,
    [string]$ConsumerRef,
    [string]$ConsumerSha,
    [bool]$DispatchRunSelfHosted,
    [bool]$DispatchRunBuildSpec,
    [string]$TokenOverride
  )

  $gh = Get-Command gh -ErrorAction SilentlyContinue
  if ($gh) {
    & gh workflow run release-skill-layer.yml `
      --repo $Repo `
      --ref $Ref `
      -f "release_tag=$Tag" `
      -f "consumer_repo=$ConsumerRepo" `
      -f "consumer_ref=$ConsumerRef" `
      -f "consumer_sha=$ConsumerSha" `
      -f "run_self_hosted=$($DispatchRunSelfHosted.ToString().ToLowerInvariant())" `
      -f "run_build_spec=$($DispatchRunBuildSpec.ToString().ToLowerInvariant())"

    if ($LASTEXITCODE -eq 0) {
      return [pscustomobject]@{ method = 'gh'; dispatched = $true }
    }
  }

  $token = if ($TokenOverride) { $TokenOverride } elseif ($env:GH_TOKEN) { $env:GH_TOKEN } elseif ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } else { $null }
  if ([string]::IsNullOrWhiteSpace($token)) {
    throw 'Dispatch failed: no GH_TOKEN or GITHUB_TOKEN available and gh workflow dispatch failed/unavailable.'
  }

  $headers = @{
    Authorization = "Bearer $token"
    Accept = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent' = 'codex-orchestrator'
  }

  $body = @{
    ref = $Ref
    inputs = @{
      release_tag = $Tag
      consumer_repo = $ConsumerRepo
      consumer_ref = $ConsumerRef
      consumer_sha = $ConsumerSha
      run_self_hosted = $DispatchRunSelfHosted.ToString().ToLowerInvariant()
      run_build_spec = $DispatchRunBuildSpec.ToString().ToLowerInvariant()
    }
  } | ConvertTo-Json -Depth 5

  Invoke-RestMethod -Method Post -Uri "https://api.github.com/repos/$Repo/actions/workflows/release-skill-layer.yml/dispatches" -Headers $headers -Body $body -ContentType 'application/json'
  return [pscustomobject]@{ method = 'rest'; dispatched = $true }
}

function Write-DispatchResult {
  param(
    [string]$Path,
    [string]$Status,
    [long]$Run,
    [string]$Tag,
    [string]$Owner,
    [string]$Plan,
    [string]$State,
    [string]$Method,
    [string]$Skill,
    [string]$Workflow,
    [string]$ConsumerRef,
    [string]$ConsumerSha
  )

  $payload = [pscustomobject]@{
    schema_version = '1.0'
    generated_utc = (Get-Date).ToUniversalTime().ToString('o')
    status = $Status
    method = $Method
    run_id = $Run
    release_tag = $Tag
    owner_repo = $Owner
    consumer_ref = $ConsumerRef
    consumer_sha = $ConsumerSha
    skill_repo = $Skill
    workflow_ref = $Workflow
    plan_path = $Plan
    release_state_path = $State
  }

  $payload | ConvertTo-Json -Depth 8 | Set-Content -Path $Path -Encoding utf8
}

if (-not (Test-Path -Path $PlanPath -PathType Leaf)) {
  throw "Plan file not found: $PlanPath"
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $OutputDir = Join-Path (Join-Path $PSScriptRoot '..') 'artifacts/release-state'
}

if (-not (Test-Path -Path $OutputDir -PathType Container)) {
  New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
}

$releaseStatePath = Join-Path $OutputDir ("release-state-{0}.json" -f $RunId)
$dispatchResultPath = Join-Path $OutputDir ("dispatch-result-{0}.json" -f $RunId)

$watcherPath = Join-Path $PSScriptRoot 'Watch-RunAndUpdatePlan.ps1'
if (-not (Test-Path -Path $watcherPath -PathType Leaf)) {
  throw "Watcher script not found: $watcherPath"
}

& $watcherPath -RunId $RunId -PlanPath $PlanPath -OwnerRepo $OwnerRepo -StatePath $releaseStatePath -PollSeconds $PollSeconds | Out-Null

$snapshot = Get-RunSnapshot -Repo $OwnerRepo -Id $RunId
$requiredArtifacts = @(
  'lv_icon_x64.lvlibp',
  'lv_icon_x86.lvlibp',
  'conformance-full',
  'core-conformance-linux-evidence',
  'core-conformance-windows-evidence'
)

$artifactNames = @($snapshot.artifacts.artifacts | ForEach-Object { $_.name })
$missingArtifacts = @($requiredArtifacts | Where-Object { $_ -notin $artifactNames })
$badJobs = @($snapshot.jobs.jobs | Where-Object {
    $_.conclusion -in @('failure', 'cancelled', 'timed_out', 'startup_failure', 'action_required')
  })

$isCompleted = $snapshot.run.status -eq 'completed'
$isSuccess = $snapshot.run.conclusion -eq 'success'
$hasNoBadJobs = $badJobs.Count -eq 0
$hasRequiredArtifacts = $missingArtifacts.Count -eq 0
$isGo = $isCompleted -and $isSuccess -and $hasNoBadJobs -and $hasRequiredArtifacts

if (-not $ReleaseTag) {
  $manifestPath = Join-Path (Join-Path $PSScriptRoot '..') 'manifest.json'
  if (-not (Test-Path -Path $manifestPath -PathType Leaf)) {
    throw "manifest.json not found: $manifestPath"
  }
  $manifest = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json
  $ReleaseTag = "v$($manifest.version)"
}

Update-PlanDispatchSection -Path $PlanPath -Tag $ReleaseTag -Dispatched:$false -StatePath $releaseStatePath -DispatchPath $dispatchResultPath

if (-not $isGo) {
  $noGoPayload = [pscustomobject]@{
    status = 'no-go'
    run_id = $RunId
    run_status = $snapshot.run.status
    run_conclusion = $snapshot.run.conclusion
    bad_job_count = $badJobs.Count
    missing_required_artifacts = $missingArtifacts
    plan_path = (Resolve-Path $PlanPath).Path
    release_tag = $ReleaseTag
    release_state_path = $releaseStatePath
    dispatch_result_path = $dispatchResultPath
  }

  Write-DispatchResult -Path $dispatchResultPath -Status 'no-go' -Run $RunId -Tag $ReleaseTag -Owner $OwnerRepo -Plan (Resolve-Path $PlanPath).Path -State $releaseStatePath -Method $null -Skill $null -Workflow $null -ConsumerRef $snapshot.run.head_branch -ConsumerSha $snapshot.run.head_sha

  $noGoPayload | ConvertTo-Json -Depth 6
  exit 2
}

$skillRepoResolved = Get-SkillRepo
$orchestratorRef = Get-OrchestratorRef

if ($DryRun) {
  $dryPayload = [pscustomobject]@{
    status = 'go-dry-run'
    run_id = $RunId
    release_tag = $ReleaseTag
    skill_repo = $skillRepoResolved
    workflow_ref = $orchestratorRef
    consumer_repo = $OwnerRepo
    consumer_ref = $snapshot.run.head_branch
    consumer_sha = $snapshot.run.head_sha
    plan_path = (Resolve-Path $PlanPath).Path
    release_state_path = $releaseStatePath
    dispatch_result_path = $dispatchResultPath
  }

  Write-DispatchResult -Path $dispatchResultPath -Status 'go-dry-run' -Run $RunId -Tag $ReleaseTag -Owner $OwnerRepo -Plan (Resolve-Path $PlanPath).Path -State $releaseStatePath -Method $null -Skill $skillRepoResolved -Workflow $orchestratorRef -ConsumerRef $snapshot.run.head_branch -ConsumerSha $snapshot.run.head_sha

  $dryPayload | ConvertTo-Json -Depth 6
  exit 0
}

$dispatchResult = Dispatch-ReleaseWorkflow `
  -Repo $skillRepoResolved `
  -Ref $orchestratorRef `
  -Tag $ReleaseTag `
  -ConsumerRepo $OwnerRepo `
  -ConsumerRef $snapshot.run.head_branch `
  -ConsumerSha $snapshot.run.head_sha `
  -DispatchRunSelfHosted:$RunSelfHosted `
  -DispatchRunBuildSpec:$RunBuildSpec `
  -TokenOverride $GitHubToken

Update-PlanDispatchSection -Path $PlanPath -Tag $ReleaseTag -Dispatched:$true -StatePath $releaseStatePath -DispatchPath $dispatchResultPath

$dispatchPayload = [pscustomobject]@{
  status = 'dispatched'
  method = $dispatchResult.method
  run_id = $RunId
  release_tag = $ReleaseTag
  skill_repo = $skillRepoResolved
  workflow_ref = $orchestratorRef
  consumer_repo = $OwnerRepo
  consumer_ref = $snapshot.run.head_branch
  consumer_sha = $snapshot.run.head_sha
  plan_path = (Resolve-Path $PlanPath).Path
  release_state_path = $releaseStatePath
  dispatch_result_path = $dispatchResultPath
}

Write-DispatchResult -Path $dispatchResultPath -Status 'dispatched' -Run $RunId -Tag $ReleaseTag -Owner $OwnerRepo -Plan (Resolve-Path $PlanPath).Path -State $releaseStatePath -Method $dispatchResult.method -Skill $skillRepoResolved -Workflow $orchestratorRef -ConsumerRef $snapshot.run.head_branch -ConsumerSha $snapshot.run.head_sha

$dispatchPayload | ConvertTo-Json -Depth 6