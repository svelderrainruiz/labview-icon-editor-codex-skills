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
  [string]$LogPath
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

  $output = & $FilePath @Arguments 2>&1
  $exitCode = $LASTEXITCODE

  return [pscustomobject]@{
    ExitCode = $exitCode
    Output = @($output)
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

$repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -Path $repoRoot

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
      run_id = $null
      url = $null
      status = $null
      conclusion = $null
      failed_jobs = @()
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

  $dispatchArgs = @('workflow', 'run', $WorkflowFile, '--ref', $Branch)
  foreach ($pair in $normalizedWorkflowInputs) {
    if ([string]::IsNullOrWhiteSpace($pair) -or -not $pair.Contains('=')) {
      throw "Invalid -WorkflowInput '$pair'. Expected format key=value."
    }

    $dispatchArgs += @('-f', $pair)
  }

  $dispatch = Invoke-External -FilePath 'gh' -Arguments $dispatchArgs
  if ($dispatch.ExitCode -ne 0) {
    $dispatchOutput = $dispatch.Output -join "`n"
    throw "Workflow dispatch failed: $dispatchOutput"
  }

  $record.workflow_run.dispatched = $true

  Start-Sleep -Seconds 5
  $latestArgs = @('run', 'list', '--workflow', $WorkflowFile, '--branch', $Branch, '--limit', '1', '--json', 'databaseId,url,status,conclusion,createdAt,headSha')
  $latest = Invoke-External -FilePath 'gh' -Arguments $latestArgs
  if ($latest.ExitCode -ne 0) {
    throw "Unable to resolve latest workflow run."
  }

  $latestJson = ($latest.Output -join "`n") | ConvertFrom-Json
  if (-not $latestJson -or $latestJson.Count -lt 1) {
    throw "No workflow run found after dispatch."
  }

  $runId = [long]$latestJson[0].databaseId
  $record.workflow_run.run_id = $runId
  $record.workflow_run.url = [string]$latestJson[0].url

  while ($true) {
    $runApi = Invoke-External -FilePath 'gh' -Arguments @('api', "repos/svelderrainruiz/labview-icon-editor-codex-skills/actions/runs/$runId")
    if ($runApi.ExitCode -ne 0) {
      Start-Sleep -Seconds $PollSeconds
      continue
    }

    $run = (($runApi.Output -join "`n") | ConvertFrom-Json)
    $record.workflow_run.status = [string]$run.status
    $record.workflow_run.conclusion = [string]$run.conclusion

    if ($run.status -eq 'completed') {
      $jobsApi = Invoke-External -FilePath 'gh' -Arguments @('api', "repos/svelderrainruiz/labview-icon-editor-codex-skills/actions/runs/$runId/jobs")
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

      break
    }

    Start-Sleep -Seconds $PollSeconds
  }

  $record.succeeded = ($record.workflow_run.conclusion -eq 'success' -and @($record.workflow_run.failed_jobs).Count -eq 0)
  $record.completed_utc = (Get-Date).ToUniversalTime().ToString('o')

  $summary = [pscustomobject]@{
    cycle = $record.cycle
    run_id = $record.workflow_run.run_id
    status = $record.workflow_run.status
    conclusion = $record.workflow_run.conclusion
    failed_jobs = @($record.workflow_run.failed_jobs).Count
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
