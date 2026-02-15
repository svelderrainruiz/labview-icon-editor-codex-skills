param(
  [Parameter(Mandatory = $false)]
  [string]$WorkflowFile = 'windows-linux-vipm-package.yml',

  [Parameter(Mandatory = $false)]
  [string]$Branch,

  [Parameter(Mandatory = $false)]
  [string]$TestPath = './tests/*.Tests.ps1',

  [Parameter(Mandatory = $false)]
  [switch]$SkipLocalTests,

  [Parameter(Mandatory = $false)]
  [string[]]$WorkflowInput,

  [Parameter(Mandatory = $false)]
  [switch]$TriagePackageVipLinux,

  [Parameter(Mandatory = $false)]
  [string]$VipmCliUrl,

  [Parameter(Mandatory = $false)]
  [string]$VipmCliSha256,

  [Parameter(Mandatory = $false)]
  [string]$VipmCliArchiveType = 'tar.gz',

  [Parameter(Mandatory = $false)]
  [int]$PollSeconds = 20,

  [Parameter(Mandatory = $false)]
  [int]$CycleSleepSeconds = 60,

  [Parameter(Mandatory = $false)]
  [int]$MaxCycles = 0,

  [Parameter(Mandatory = $false)]
  [switch]$StopOnFailure,

  [Parameter(Mandatory = $false)]
  [string]$LogPath,

  [Parameter(Mandatory = $false)]
  [ValidateSet('auto', 'runner-cli', 'gh')]
  [string]$DispatchBackend = 'auto',

  [Parameter(Mandatory = $false)]
  [ValidateSet('auto', 'runner-cli', 'gh')]
  [string]$RunQueryBackend = 'auto',

  [Parameter(Mandatory = $false)]
  [string]$OwnerRepo = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-External {
  param(
    [Parameter(Mandatory)]
    [string]$FilePath,

    [Parameter(Mandatory)]
    [string[]]$Arguments
  )

  try {
    $output = & $FilePath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
  }
  catch {
    $output = @($_.Exception.Message)
    $exitCode = 127
  }

  return [pscustomobject]@{
    ExitCode = $exitCode
    Output = @($output)
  }
}

function Test-RunnerCliAvailability {
  $probe = Invoke-External -FilePath 'runner-cli' -Arguments @('--version')
  return [pscustomobject]@{
    available = ($probe.ExitCode -eq 0)
    exit_code = $probe.ExitCode
    output = @($probe.Output)
  }
}

function Resolve-OwnerRepo {
  param(
    [Parameter(Mandatory = $false)]
    [string]$Value
  )

  if (-not [string]::IsNullOrWhiteSpace($Value)) {
    return $Value.Trim()
  }

  if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_REPOSITORY)) {
    return [string]$env:GITHUB_REPOSITORY
  }

  try {
    $originUrl = (git remote get-url origin).Trim()
    if ($originUrl -match 'github\.com[:/](?<repo>[^/]+/[^/.]+?)(?:\.git)?$') {
      return [string]$Matches.repo
    }
  } catch {
  }

  throw "OwnerRepo was not provided and could not be inferred. Pass -OwnerRepo <owner/repo>."
}

function Invoke-WorkflowDispatch {
  param(
    [Parameter(Mandatory)]
    [ValidateSet('auto', 'runner-cli', 'gh')]
    [string]$Backend,

    [Parameter(Mandatory)]
    [string]$WorkflowFile,

    [Parameter(Mandatory)]
    [string]$Branch,

    [Parameter(Mandatory)]
    [string[]]$Inputs,

    [Parameter(Mandatory)]
    [bool]$RunnerCliAvailable
  )

  $runnerArgs = @('github', 'workflow', 'dispatch', '--workflow', $WorkflowFile, '--ref', $Branch)
  foreach ($pair in @($Inputs)) {
    $runnerArgs += @('--field', $pair)
  }

  $ghArgs = @('workflow', 'run', $WorkflowFile, '--ref', $Branch)
  foreach ($pair in @($Inputs)) {
    $ghArgs += @('-f', $pair)
  }

  $tryRunnerFirst = ($Backend -eq 'runner-cli') -or ($Backend -eq 'auto' -and $RunnerCliAvailable)
  if ($tryRunnerFirst) {
    if (-not $RunnerCliAvailable) {
      throw "Dispatch backend 'runner-cli' requested but runner-cli is not available."
    }

    $runnerDispatch = Invoke-External -FilePath 'runner-cli' -Arguments $runnerArgs
    if ($runnerDispatch.ExitCode -eq 0) {
      return [pscustomobject]@{
        method = 'runner-cli'
        exit_code = [int]$runnerDispatch.ExitCode
        output_preview = @($runnerDispatch.Output | Select-Object -First 12 | ForEach-Object { [string]$_ })
      }
    }

    if ($Backend -eq 'runner-cli') {
      $runnerOutput = ($runnerDispatch.Output -join "`n")
      throw "Workflow dispatch failed via runner-cli: $runnerOutput"
    }
  }

  if ($Backend -eq 'gh' -or $Backend -eq 'auto' -or ($Backend -eq 'auto' -and -not $RunnerCliAvailable)) {
    $ghDispatch = Invoke-External -FilePath 'gh' -Arguments $ghArgs
    if ($ghDispatch.ExitCode -ne 0) {
      $ghOutput = ($ghDispatch.Output -join "`n")
      throw "Workflow dispatch failed via gh: $ghOutput"
    }

    return [pscustomobject]@{
      method = 'gh'
      exit_code = [int]$ghDispatch.ExitCode
      output_preview = @($ghDispatch.Output | Select-Object -First 12 | ForEach-Object { [string]$_ })
    }
  }

  throw "Unsupported dispatch backend: $Backend"
}

function Invoke-WorkflowRunList {
  param(
    [Parameter(Mandatory)]
    [ValidateSet('auto', 'runner-cli', 'gh')]
    [string]$Backend,

    [Parameter(Mandatory)]
    [string]$WorkflowFile,

    [Parameter(Mandatory)]
    [string]$Branch,

    [Parameter(Mandatory)]
    [bool]$RunnerCliAvailable
  )

  $runnerArgs = @('github', 'run', 'list', '--workflow', $WorkflowFile, '--branch', $Branch, '--limit', '20', '--json')
  $ghArgs = @('run', 'list', '--workflow', $WorkflowFile, '--branch', $Branch, '--limit', '20', '--json', 'databaseId,url,status,conclusion,createdAt,headSha,event')

  $tryRunnerFirst = ($Backend -eq 'runner-cli') -or ($Backend -eq 'auto' -and $RunnerCliAvailable)
  if ($tryRunnerFirst) {
    if (-not $RunnerCliAvailable) {
      throw "Run-query backend 'runner-cli' requested but runner-cli is not available."
    }

    $runnerList = Invoke-External -FilePath 'runner-cli' -Arguments $runnerArgs
    if ($runnerList.ExitCode -eq 0) {
      try {
        $parsed = @(($runnerList.Output -join "`n") | ConvertFrom-Json)
        return [pscustomobject]@{
          backend = 'runner-cli'
          runs = @($parsed)
        }
      }
      catch {
        if ($Backend -eq 'runner-cli') {
          throw "Run list query via runner-cli returned non-JSON output."
        }
      }
    }
    elseif ($Backend -eq 'runner-cli') {
      $runnerOutput = ($runnerList.Output -join "`n")
      throw "Run list query failed via runner-cli: $runnerOutput"
    }
  }

  $ghList = Invoke-External -FilePath 'gh' -Arguments $ghArgs
  if ($ghList.ExitCode -ne 0) {
    return [pscustomobject]@{
      backend = 'gh'
      runs = @()
      exit_code = [int]$ghList.ExitCode
      output = @($ghList.Output)
    }
  }

  return [pscustomobject]@{
    backend = 'gh'
    runs = @(($ghList.Output -join "`n") | ConvertFrom-Json)
  }
}

function Write-CycleLog {
  param(
    [Parameter(Mandatory)]
    [hashtable]$Record
  )

  if ([string]::IsNullOrWhiteSpace($LogPath)) {
    return
  }

  $logDir = Split-Path -Path $LogPath -Parent
  if (-not [string]::IsNullOrWhiteSpace($logDir) -and -not (Test-Path -LiteralPath $logDir -PathType Container)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
  }

  $line = ($Record | ConvertTo-Json -Depth 8 -Compress)
  Add-Content -Path $LogPath -Value $line -Encoding utf8
}

function Get-NormalizedWorkflowInputs {
  param(
    [Parameter()]
    [AllowNull()]
    [object[]]$RawInputs
  )

  $result = @()

  foreach ($raw in @($RawInputs)) {
    if ($null -eq $raw) {
      continue
    }

    if ($raw -is [System.Array]) {
      foreach ($item in $raw) {
        if ($null -eq $item) {
          continue
        }

        $text = [string]$item
        if ([string]::IsNullOrWhiteSpace($text)) {
          continue
        }

        $candidate = $text.Trim().Trim('"').Trim("'")
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
          $result += $candidate
        }
      }

      continue
    }

    $rawText = [string]$raw
    if ([string]::IsNullOrWhiteSpace($rawText)) {
      continue
    }

    $parts = @($rawText -split ',')
    foreach ($part in $parts) {
      $candidate = $part.Trim().Trim('"').Trim("'")
      if (-not [string]::IsNullOrWhiteSpace($candidate)) {
        $result += $candidate
      }
    }
  }

  return @($result | Where-Object { $_ -like '*=*' })
}

function Get-VipmHelpPreviewEvidence {
  param(
    [Parameter(Mandatory)]
    [long]$RunId,

    [Parameter(Mandatory)]
    [string]$Conclusion
  )

  $source = if ($Conclusion -eq 'success') { '--log' } else { '--log-failed' }
  $logArgs = @('run', 'view', "$RunId", $source)
  $logResult = Invoke-External -FilePath 'gh' -Arguments $logArgs

  if ($logResult.ExitCode -ne 0) {
    return [ordered]@{
      observed = $false
      usage_line_observed = $false
      source = $source
      check_error = (($logResult.Output -join "`n").Trim())
    }
  }

  $logText = ($logResult.Output -join "`n")
  $previewObserved = $logText -match 'vipm help preview \(first 20 lines\):'
  $usageObserved = $logText -match '(?im)^\s*usage:\s+vipm\s+<command>' -or $logText -match '(?im)^\s*usage:\s+vipm\b'

  return [ordered]@{
    observed = $previewObserved
    usage_line_observed = $usageObserved
    source = $source
    check_error = $null
  }
}

function Resolve-DispatchedRunMeta {
  param(
    [Parameter(Mandatory)]
    [string]$WorkflowFile,

    [Parameter(Mandatory)]
    [string]$Branch,

    [Parameter(Mandatory)]
    [datetime]$StartedUtc,

    [Parameter()]
    [AllowNull()]
    [string]$ExpectedHeadSha,

    [Parameter(Mandatory)]
    [ValidateSet('auto', 'runner-cli', 'gh')]
    [string]$RunQueryBackend,

    [Parameter(Mandatory)]
    [bool]$RunnerCliAvailable,

    [Parameter(Mandatory)]
    [int]$PollSeconds
  )

  $attempt = 0
  $maxAttempts = 30
  while ($attempt -lt $maxAttempts) {
    $attempt += 1
    $listResult = Invoke-WorkflowRunList -Backend $RunQueryBackend -WorkflowFile $WorkflowFile -Branch $Branch -RunnerCliAvailable $RunnerCliAvailable
    if (@($listResult.runs).Count -gt 0) {
      $runs = @($listResult.runs)
      if ($runs.Count -gt 0) {
        $floorUtc = $StartedUtc.AddSeconds(-10)
        $candidates = @(
          $runs | Where-Object {
            $event = [string]$_.event
            $createdAtRaw = [string]$_.createdAt
            $headSha = [string]$_.headSha

            if ($event -ne 'workflow_dispatch') {
              return $false
            }

            $createdAt = $null
            try {
              $createdAt = [datetimeoffset]::Parse($createdAtRaw).UtcDateTime
            }
            catch {
              return $false
            }

            if ($createdAt -lt $floorUtc) {
              return $false
            }

            if (-not [string]::IsNullOrWhiteSpace($ExpectedHeadSha) -and $headSha -ne $ExpectedHeadSha) {
              return $false
            }

            return $true
          } | Sort-Object {[datetime]$_.createdAt} -Descending
        )

        if ($candidates.Count -gt 0) {
          return [ordered]@{
            run_id = [long]$candidates[0].databaseId
            url = [string]$candidates[0].url
            head_sha = [string]$candidates[0].headSha
          }
        }
      }
    }

    Start-Sleep -Seconds $PollSeconds
  }

  throw "Unable to correlate dispatched workflow run after $maxAttempts attempts."
}

$repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -Path $repoRoot
$OwnerRepo = Resolve-OwnerRepo -Value $OwnerRepo

if ([string]::IsNullOrWhiteSpace($Branch)) {
  $branchProbe = Invoke-External -FilePath 'git' -Arguments @('branch', '--show-current')
  if ($branchProbe.ExitCode -ne 0) {
    throw "Unable to resolve current git branch."
  }

  $Branch = ($branchProbe.Output -join "`n").Trim()
}

$ghProbe = Invoke-External -FilePath 'gh' -Arguments @('--version')
if ($ghProbe.ExitCode -ne 0) {
  throw "GitHub CLI (gh) is required on PATH."
}

$runnerCliProbe = Test-RunnerCliAvailability
if ($DispatchBackend -eq 'runner-cli' -and -not $runnerCliProbe.available) {
  throw "Dispatch backend 'runner-cli' requested but runner-cli is not available on PATH."
}

if ($RunQueryBackend -eq 'runner-cli' -and -not $runnerCliProbe.available) {
  throw "Run-query backend 'runner-cli' requested but runner-cli is not available on PATH."
}

$authProbe = Invoke-External -FilePath 'gh' -Arguments @('auth', 'status')
if ($authProbe.ExitCode -ne 0) {
  throw "GitHub CLI is not authenticated. Run 'gh auth login'."
}

$normalizedWorkflowInputs = Get-NormalizedWorkflowInputs -RawInputs $WorkflowInput
if ($TriagePackageVipLinux.IsPresent) {
  $triageInputs = @(
    'ppl_build_lane=linux-container',
    'labview_community_edition=true',
    'linux_labview_image=nationalinstruments/labview:2026q1-linux',
    "windows_build_command=New-Item -ItemType Directory -Path 'consumer/resource/plugins' -Force | Out-Null; Set-Content -Path 'consumer/resource/plugins/lv_icon.lvlibp' -Value 'stub-ppl' -Encoding ascii",
    "linux_build_command=New-Item -ItemType Directory -Path 'consumer/resource/plugins' -Force | Out-Null; Set-Content -Path 'consumer/resource/plugins/lv_icon.lvlibp' -Value 'stub-linux-ppl' -Encoding ascii"
  )

  $normalizedWorkflowInputs += $triageInputs
}

if ((-not [string]::IsNullOrWhiteSpace($VipmCliUrl)) -xor (-not [string]::IsNullOrWhiteSpace($VipmCliSha256))) {
  throw "-VipmCliUrl and -VipmCliSha256 must be provided together."
}

if (-not [string]::IsNullOrWhiteSpace($VipmCliUrl)) {
  $normalizedWorkflowInputs += @(
    "vipm_cli_url=$VipmCliUrl",
    "vipm_cli_sha256=$VipmCliSha256",
    "vipm_cli_archive_type=$VipmCliArchiveType"
  )
}

$normalizedWorkflowInputs = @(
  $normalizedWorkflowInputs |
    Group-Object -AsHashTable -AsString |
    ForEach-Object { $_.Keys } |
    Sort-Object
)

$hasConsumerRefInput = @($normalizedWorkflowInputs | Where-Object {
  $entry = [string]$_
  if (-not $entry.Contains('=')) {
    return $false
  }

  $key = ($entry -split '=', 2)[0].Trim().ToLowerInvariant()
  return $key -eq 'consumer_ref'
}).Count -gt 0

if (-not $hasConsumerRefInput) {
  $normalizedWorkflowInputs += 'consumer_ref=develop'
}

$cycle = 0
while ($true) {
  $cycle += 1
  $startedUtc = (Get-Date).ToUniversalTime()
  Write-Host "=== Autonomous CI cycle $cycle started at $($startedUtc.ToString('o')) ==="

  $record = [ordered]@{
    cycle = $cycle
    started_utc = $startedUtc.ToString('o')
    branch = $Branch
    workflow = $WorkflowFile
    local_tests = [ordered]@{
      skipped = $SkipLocalTests.IsPresent
      passed = $null
      exit_code = $null
    }
    workflow_run = [ordered]@{
      dispatched = $false
      dispatch_response = [ordered]@{
        exit_code = $null
        output_preview = @()
      }
      run_id = $null
      url = $null
      status = $null
      conclusion = $null
      failed_jobs = @()
      vipm_help_preview = [ordered]@{
        observed = $false
        usage_line_observed = $false
        source = $null
        check_error = $null
      }
    }
    succeeded = $false
  }

  if (-not $SkipLocalTests.IsPresent) {
    $testResult = Invoke-External -FilePath 'pwsh' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', './scripts/Invoke-ContractTests.ps1', '-TestPath', $TestPath)
    $record.local_tests.exit_code = $testResult.ExitCode
    $record.local_tests.passed = ($testResult.ExitCode -eq 0)

    if ($testResult.ExitCode -ne 0) {
      Write-Host "Local contract tests failed (exit $($testResult.ExitCode))."
      Write-CycleLog -Record $record

      if ($StopOnFailure.IsPresent) {
        throw "Stopping because local tests failed in cycle $cycle."
      }

      if ($MaxCycles -gt 0 -and $cycle -ge $MaxCycles) {
        break
      }

      Start-Sleep -Seconds $CycleSleepSeconds
      continue
    }
  }

  $headProbe = Invoke-External -FilePath 'git' -Arguments @('rev-parse', 'HEAD')
  $expectedHeadSha = if ($headProbe.ExitCode -eq 0) { (($headProbe.Output -join "`n").Trim()) } else { '' }
  foreach ($pair in $normalizedWorkflowInputs) {
    if ([string]::IsNullOrWhiteSpace($pair) -or -not $pair.Contains('=')) {
      throw "Invalid -WorkflowInput '$pair'. Expected format key=value."
    }
  }

  $dispatch = Invoke-WorkflowDispatch -Backend $DispatchBackend -WorkflowFile $WorkflowFile -Branch $Branch -Inputs $normalizedWorkflowInputs -RunnerCliAvailable ([bool]$runnerCliProbe.available)
  $record.workflow_run.dispatch_response.exit_code = [int]$dispatch.exit_code
  $record.workflow_run.dispatch_response.output_preview = @($dispatch.output_preview)
  $record.workflow_run.dispatch_response.method = [string]$dispatch.method

  $record.workflow_run.dispatched = $true
  $record.workflow_run.head_sha_expected = $expectedHeadSha

  $resolvedRunMeta = Resolve-DispatchedRunMeta -WorkflowFile $WorkflowFile -Branch $Branch -StartedUtc $startedUtc -ExpectedHeadSha $expectedHeadSha -RunQueryBackend $RunQueryBackend -RunnerCliAvailable ([bool]$runnerCliProbe.available) -PollSeconds $PollSeconds
  $runId = [long]$resolvedRunMeta.run_id
  $record.workflow_run.run_id = $runId
  $record.workflow_run.url = [string]$resolvedRunMeta.url
  $record.workflow_run.head_sha_actual = [string]$resolvedRunMeta.head_sha

  while ($true) {
    $runApi = Invoke-External -FilePath 'gh' -Arguments @('api', "repos/$OwnerRepo/actions/runs/$runId")
    if ($runApi.ExitCode -ne 0) {
      Start-Sleep -Seconds $PollSeconds
      continue
    }

    $run = (($runApi.Output -join "`n") | ConvertFrom-Json)
    $record.workflow_run.status = [string]$run.status
    $record.workflow_run.conclusion = [string]$run.conclusion

    if ($run.status -eq 'completed') {
      $jobsApi = Invoke-External -FilePath 'gh' -Arguments @('api', "repos/$OwnerRepo/actions/runs/$runId/jobs")
      if ($jobsApi.ExitCode -eq 0) {
        $jobs = (($jobsApi.Output -join "`n") | ConvertFrom-Json)
        $record.workflow_run.failed_jobs = @(
          $jobs.jobs |
            Where-Object { $_.conclusion -in @('failure', 'cancelled', 'timed_out', 'startup_failure', 'action_required') } |
            ForEach-Object {
              [ordered]@{
                name = $_.name
                conclusion = $_.conclusion
                url = $_.html_url
              }
            }
        )
      }

      $record.workflow_run.vipm_help_preview = Get-VipmHelpPreviewEvidence -RunId $runId -Conclusion ([string]$run.conclusion)

      break
    }

    Start-Sleep -Seconds $PollSeconds
  }

  $record.succeeded = ($record.workflow_run.conclusion -eq 'success' -and @($record.workflow_run.failed_jobs).Count -eq 0)
  $record.completed_utc = (Get-Date).ToUniversalTime().ToString('o')

  $summary = [pscustomobject]@{
    cycle = $record.cycle
    run_id = $record.workflow_run.run_id
    dispatch_exit_code = $record.workflow_run.dispatch_response.exit_code
    status = $record.workflow_run.status
    conclusion = $record.workflow_run.conclusion
    failed_jobs = @($record.workflow_run.failed_jobs).Count
    vipm_help_observed = [bool]$record.workflow_run.vipm_help_preview.observed
    vipm_help_usage_line_observed = [bool]$record.workflow_run.vipm_help_preview.usage_line_observed
    run_url = $record.workflow_run.url
  }
  $summary | ConvertTo-Json -Depth 4

  Write-CycleLog -Record $record

  if ($StopOnFailure.IsPresent -and -not $record.succeeded) {
    throw "Stopping because workflow run $($record.workflow_run.run_id) ended with conclusion '$($record.workflow_run.conclusion)'."
  }

  if ($MaxCycles -gt 0 -and $cycle -ge $MaxCycles) {
    break
  }

  Start-Sleep -Seconds $CycleSleepSeconds
}
