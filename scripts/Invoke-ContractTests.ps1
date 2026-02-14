param(
  [Parameter(Mandatory = $false)]
  [string]$TestPath = './tests/*.Tests.ps1',

  [Parameter(Mandatory = $false)]
  [string]$TestResultPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function New-UniqueTestResultPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$BaseDirectory
  )

  $timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
  $name = "testResults-$timestamp-$PID-$([guid]::NewGuid().ToString('n')).xml"
  return Join-Path $BaseDirectory $name
}

function Resolve-ResultPath {
  param(
    [string]$RequestedPath
  )

  if ([string]::IsNullOrWhiteSpace($RequestedPath)) {
    $baseRoot = if (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
      $env:RUNNER_TEMP
    } elseif (-not [string]::IsNullOrWhiteSpace($env:TEMP)) {
      $env:TEMP
    } else {
      [System.IO.Path]::GetTempPath()
    }

    $resultsDir = Join-Path $baseRoot 'pester-results'
    if (-not (Test-Path -LiteralPath $resultsDir -PathType Container)) {
      New-Item -Path $resultsDir -ItemType Directory -Force | Out-Null
    }

    return New-UniqueTestResultPath -BaseDirectory $resultsDir
  }

  $resolvedPath = $RequestedPath
  if (-not [System.IO.Path]::IsPathRooted($resolvedPath)) {
    $resolvedPath = Join-Path (Get-Location) $resolvedPath
  }
  $resolvedPath = [System.IO.Path]::GetFullPath($resolvedPath)

  $parent = Split-Path -Path $resolvedPath -Parent
  if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -Path $parent -ItemType Directory -Force | Out-Null
  }

  return $resolvedPath
}

function Test-ExclusiveFileAccess {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $true
  }

  try {
    $handle = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    $handle.Close()
    return $true
  } catch {
    return $false
  }
}

$minimum = [version]'5.0.0'
$installed = Get-Module -ListAvailable -Name Pester |
  Sort-Object Version -Descending |
  Select-Object -First 1

if (-not $installed -or $installed.Version -lt $minimum) {
  Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
  Install-Module -Name Pester -Scope CurrentUser -Force -SkipPublisherCheck -MinimumVersion $minimum
}

Import-Module Pester -MinimumVersion 5.0.0

$resolvedResultPath = Resolve-ResultPath -RequestedPath $TestResultPath
if (-not (Test-ExclusiveFileAccess -Path $resolvedResultPath)) {
  $fallbackName = '{0}-{1}{2}' -f [System.IO.Path]::GetFileNameWithoutExtension($resolvedResultPath), ([guid]::NewGuid().ToString('n')), [System.IO.Path]::GetExtension($resolvedResultPath)
  $resolvedResultPath = Join-Path (Split-Path -Path $resolvedResultPath -Parent) $fallbackName
  Write-Warning "Requested NUnit XML path is locked/unwritable. Falling back to '$resolvedResultPath'."
}

$config = New-PesterConfiguration
$config.Run.Path = $TestPath
$config.Run.PassThru = $true
$config.Output.CIFormat = 'Auto'
$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = 'NUnitXml'
$config.TestResult.OutputPath = $resolvedResultPath

$result = Invoke-Pester -Configuration $config

Write-Host "Pester NUnit XML path: $resolvedResultPath"

if ($null -eq $result) {
  throw "Invoke-Pester did not return a result object. Result path: $resolvedResultPath"
}

$failedCount = [int]$result.FailedCount
if ($failedCount -gt 0) {
  throw "Contract tests failed ($failedCount failed). Result file: $resolvedResultPath"
}
