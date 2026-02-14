#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'VIPM CLI community activation contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:probePath = Join-Path $script:repoRoot 'vipm-cli-machine/scripts/Invoke-VipmCliToolProbe.ps1'
        if (-not (Test-Path -Path $script:probePath -PathType Leaf)) {
            throw "Probe script missing: $script:probePath"
        }
    }

    BeforeEach {
        $script:originalPath = $env:PATH
        $env:VIPM_COMMUNITY_EDITION = $null
        $env:VIPM_TEST_FAIL_ACTIVATE = $null

        $script:shimDir = Join-Path $TestDrive 'shim'
        New-Item -Path $script:shimDir -ItemType Directory -Force | Out-Null
        $script:logPath = Join-Path $TestDrive 'vipm-invocations.log'
        Set-Content -Path $script:logPath -Value '' -Encoding utf8

        if ($IsWindows) {
            $shimPath = Join-Path $script:shimDir 'vipm.cmd'
            $shimContent = @"
@echo off
echo %*>>"%VIPM_TEST_LOG_PATH%"
if /I "%1"=="activate" (
  if "%VIPM_TEST_FAIL_ACTIVATE%"=="1" (
    echo activation failed 1>&2
    exit 23
  )
  exit /b 0
)
if /I "%1"=="about" (
  echo VIPM CLI
  exit /b 0
)
exit /b 0
"@
            Set-Content -Path $shimPath -Value $shimContent -Encoding ascii
        }
        else {
            $shimPath = Join-Path $script:shimDir 'vipm'
            $shimContent = @'
#!/usr/bin/env bash
echo "$*" >> "$VIPM_TEST_LOG_PATH"
if [[ "$1" == "activate" ]]; then
  if [[ "$VIPM_TEST_FAIL_ACTIVATE" == "1" ]]; then
    echo "activation failed" >&2
    exit 23
  fi
  exit 0
fi
if [[ "$1" == "about" ]]; then
  echo "VIPM CLI"
  exit 0
fi
exit 0
'@
            $normalized = $shimContent -replace "`r`n", "`n"
            [System.IO.File]::WriteAllText($shimPath, $normalized, [System.Text.UTF8Encoding]::new($false))
            & chmod +x $shimPath
        }

        $env:VIPM_TEST_LOG_PATH = $script:logPath
        $env:PATH = "$script:shimDir$([System.IO.Path]::PathSeparator)$($env:PATH)"
    }

    AfterEach {
        $env:PATH = $script:originalPath
        $env:VIPM_COMMUNITY_EDITION = $null
        $env:VIPM_TEST_FAIL_ACTIVATE = $null
        $env:VIPM_TEST_LOG_PATH = $null
    }

    It 'runs vipm activate before tool command when VIPM_COMMUNITY_EDITION=true' {
        $env:VIPM_COMMUNITY_EDITION = 'true'
        $jsonPath = Join-Path $TestDrive 'vipm-result.json'

        & $script:probePath -Tool about -Mode probe -LabVIEWVersion 2026 -SkipProcessWait -JsonOutputPath $jsonPath

        $lines = @(Get-Content -Path $script:logPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $lines.Count | Should -BeGreaterThan 1
        $lines[0] | Should -Match '^activate$'
        $lines[1] | Should -Match '^about$'

        $payload = Get-Content -Raw -Path $jsonPath | ConvertFrom-Json
        $payload.activation_attempted | Should -BeTrue
        $payload.activation_exit_code | Should -Be 0
    }

    It 'does not run vipm activate when VIPM_COMMUNITY_EDITION is not true-like' {
        $env:VIPM_COMMUNITY_EDITION = 'false'
        $jsonPath = Join-Path $TestDrive 'vipm-result-no-activate.json'

        & $script:probePath -Tool about -Mode probe -LabVIEWVersion 2026 -SkipProcessWait -JsonOutputPath $jsonPath

        $lines = @(Get-Content -Path $script:logPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $lines.Count | Should -Be 1
        $lines[0] | Should -Match '^about$'

        $payload = Get-Content -Raw -Path $jsonPath | ConvertFrom-Json
        $payload.activation_attempted | Should -BeFalse
    }

    It 'fails fast when community activation command fails' {
        $env:VIPM_COMMUNITY_EDITION = 'true'
        $env:VIPM_TEST_FAIL_ACTIVATE = '1'
        $jsonPath = Join-Path $TestDrive 'vipm-result-activation-fail.json'

        {
            & $script:probePath -Tool about -Mode probe -LabVIEWVersion 2026 -SkipProcessWait -JsonOutputPath $jsonPath
        } | Should -Throw '*VIPM activation failed*'

        $lines = @(Get-Content -Path $script:logPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $lines.Count | Should -Be 1
        $lines[0] | Should -Match '^activate$'
    }
}