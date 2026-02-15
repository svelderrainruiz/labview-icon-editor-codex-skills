#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Invoke-LunitSmokeLv2020 script contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:scriptPath = Join-Path $script:repoRoot 'scripts/Invoke-LunitSmokeLv2020.ps1'
        if (-not (Test-Path -LiteralPath $script:scriptPath -PathType Leaf)) {
            throw "Required script missing: $script:scriptPath"
        }

        $script:scriptContent = Get-Content -LiteralPath $script:scriptPath -Raw
    }

    It 'defines required parameters and constrains smoke coverage to 64-bit only' {
        $script:scriptContent | Should -Match 'param\('
        $script:scriptContent | Should -Match '\$SourceProjectRoot'
        $script:scriptContent | Should -Match '\$ProjectName'
        $script:scriptContent | Should -Match '\$TargetLabVIEWVersion'
        $script:scriptContent | Should -Match '\$RequiredBitness'
        $script:scriptContent | Should -Match '\$OutputDirectory'
        $script:scriptContent | Should -Match '\$OverrideLvversion'
        $script:scriptContent | Should -Match '\$EnforceLabVIEWProcessIsolation'
        $script:scriptContent | Should -Match 'ValidateSet\(''64''\)'
    }

    It 'contains canonical direct g-cli lunit command markers and diagnostics outputs' {
        $script:scriptContent | Should -Match '''--lv-ver'''
        $script:scriptContent | Should -Match '''--arch'''
        $script:scriptContent | Should -Match '''lunit'''
        $script:scriptContent | Should -Match '''-r'''
        $script:scriptContent | Should -Not -Match '''-h'''
        $script:scriptContent | Should -Not -Match 'help_exit_code'
        $script:scriptContent | Should -Not -Match 'help_output'
        $script:scriptContent | Should -Match 'vipm_list_command'
        $script:scriptContent | Should -Match '''astemes_lib_lunit'''
        $script:scriptContent | Should -Match '''sas_workshops_lib_lunit_for_g_cli'''
        $script:scriptContent | Should -Match 'validation_outcome'
        $script:scriptContent | Should -Match 'parse-first strict gate'
        $script:scriptContent | Should -Match 'Invoke-Lv2026ControlProbe'
        $script:scriptContent | Should -Match 'diagnostic-only LV2026 control probe'
        $script:scriptContent | Should -Match 'control_probe'
        $script:scriptContent | Should -Match 'Ensure-LabVIEWProcessQuiescence'
        $script:scriptContent | Should -Match 'skipped_active_labview_processes'
        $script:scriptContent | Should -Match 'skipped_unable_to_clear_active_labview_processes'
        $script:scriptContent | Should -Match 'eligibleControlOutcomes = @\(''no_testcases'', ''failed_testcases''\)'
        $script:scriptContent | Should -Match 'lunit-smoke\.status\.json'
        $script:scriptContent | Should -Match 'lunit-smoke\.result\.json'
        $script:scriptContent | Should -Match 'lunit-smoke\.log'
        $script:scriptContent | Should -Match 'lunit-report-lv\{0\}-x\{1\}\.xml'
        $script:scriptContent | Should -Match 'lunit-report-lv2026-x64-control\.xml'
        $script:scriptContent | Should -Match 'lvversion_before_path = Join-Path \$workspaceDiagnosticsDirectory ''lvversion\.before'''
        $script:scriptContent | Should -Match 'lvversion_after_path = Join-Path \$workspaceDiagnosticsDirectory ''lvversion\.after'''
        $script:scriptContent | Should -Match 'Missing ''\.lvversion'' alongside'
    }

    It 'runs with mocked g-cli and vipm, emits diagnostics, enforces x64 path, and preserves source lvversion' {
        $runRuntime = -not [string]::IsNullOrWhiteSpace($env:RUN_LUNIT_SMOKE_RUNTIME_TEST) -and $env:RUN_LUNIT_SMOKE_RUNTIME_TEST.Trim().ToLowerInvariant() -in @('1', 'true', 'yes', 'on')
        if (-not $runRuntime) {
            Set-ItResult -Skipped -Because 'Set RUN_LUNIT_SMOKE_RUNTIME_TEST=true to run mocked LUnit runtime success path.'
            return
        }

        $tempRoot = Join-Path $env:TEMP ("lunit-smoke-success-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        $originalPath = $env:PATH
        try {
            $sourceRoot = Join-Path $tempRoot 'source'
            New-Item -Path $sourceRoot -ItemType Directory -Force | Out-Null
            '26.0' | Set-Content -LiteralPath (Join-Path $sourceRoot '.lvversion') -Encoding ASCII
            '@project' | Set-Content -LiteralPath (Join-Path $sourceRoot 'lv_icon_editor.lvproj') -Encoding ASCII

            $binDir = Join-Path $tempRoot 'bin'
            New-Item -Path $binDir -ItemType Directory -Force | Out-Null
            $mockGcliPath = Join-Path $binDir 'g-cli.cmd'
            @'
@echo off
setlocal EnableDelayedExpansion
set "reportPath="
set "arg1=%~1"
:parse
if "%~1"=="" goto parsed
if /I "%~1"=="-r" (
  set "reportPath=%~2"
)
shift
goto parse
:parsed
echo %*>>"%~dp0gcli-invocations.log"
if not "%reportPath%"=="" (
  for %%I in ("%reportPath%") do (
    if not exist "%%~dpI" mkdir "%%~dpI"
  )
  >"%reportPath%" echo ^<testsuite^>^<testcase name="Smoke" classname="LV2020" status="Passed" /^>^</testsuite^>
  exit /b 7
)
echo Missing Parameters: report_path
exit /b 1
'@ | Set-Content -LiteralPath $mockGcliPath -Encoding ASCII

            $mockVipmPath = Join-Path $binDir 'vipm.cmd'
            @'
@echo off
if /I "%~1"=="--labview-version" goto list
echo Unsupported mock invocation
exit /b 1
:list
echo Found 2 packages:
echo (astemes_lib_lunit v1.12.5.6)
echo (sas_workshops_lib_lunit_for_g_cli v1.2.0.83)
exit /b 0
'@ | Set-Content -LiteralPath $mockVipmPath -Encoding ASCII
            $env:PATH = "$binDir;$originalPath"

            $outputDirectory = Join-Path $tempRoot 'output'
            & $script:scriptPath `
                -SourceProjectRoot $sourceRoot `
                -OutputDirectory $outputDirectory `
                -TargetLabVIEWVersion 2020 `
                -RequiredBitness '64' `
                -OverrideLvversion '20.0'

            foreach ($requiredFile in @(
                'lunit-smoke.status.json',
                'lunit-smoke.result.json',
                'lunit-smoke.log',
                'reports/lunit-report-lv2020-x64.xml',
                'workspace/lvversion.before',
                'workspace/lvversion.after'
            )) {
                Test-Path -LiteralPath (Join-Path $outputDirectory $requiredFile) -PathType Leaf | Should -BeTrue
            }

            $statusPayload = Get-Content -LiteralPath (Join-Path $outputDirectory 'lunit-smoke.status.json') -Raw | ConvertFrom-Json
            [string]$statusPayload.status | Should -Be 'passed'

            $resultPayload = Get-Content -LiteralPath (Join-Path $outputDirectory 'lunit-smoke.result.json') -Raw | ConvertFrom-Json
            [string]$resultPayload.required_bitness | Should -Be '64'
            [string]$resultPayload.status | Should -Be 'passed'
            [string]$resultPayload.workspace.lvversion_after | Should -Be '20.0'
            [int]$resultPayload.command_results.run_exit_code | Should -Be 7
            [string]$resultPayload.report.validation_outcome | Should -Be 'passed'
            @($resultPayload.preflight.missing_package_ids).Count | Should -Be 0

            [string](Get-Content -LiteralPath (Join-Path $sourceRoot '.lvversion') -Raw).Trim() | Should -Be '26.0'
            [string](Get-Content -LiteralPath (Join-Path $outputDirectory 'workspace/lvversion.before') -Raw).Trim() | Should -Be '26.0'
            [string](Get-Content -LiteralPath (Join-Path $outputDirectory 'workspace/lvversion.after') -Raw).Trim() | Should -Be '20.0'
            [string](Get-Content -LiteralPath (Join-Path $outputDirectory 'lunit-smoke.log') -Raw) | Should -Match 'WARNING: g-cli LUnit run exited with code 7 but report validation passed; accepting parse-first strict gate\.'

            $invocationLog = Get-Content -LiteralPath (Join-Path $binDir 'gcli-invocations.log') -Raw
            $invocationLog | Should -Match '--arch 64'
            $invocationLog | Should -Not -Match '--arch 32'
            $invocationLog | Should -Not -Match '-h'
        }
        finally {
            $env:PATH = $originalPath
            if (Test-Path -LiteralPath $tempRoot -PathType Container) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }

    It 'fails deterministically when sibling .lvversion is missing and still writes diagnostics' {
        $tempRoot = Join-Path $env:TEMP ("lunit-smoke-missing-lvversion-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        $originalPath = $env:PATH
        try {
            $sourceRoot = Join-Path $tempRoot 'source'
            New-Item -Path $sourceRoot -ItemType Directory -Force | Out-Null
            '@project' | Set-Content -LiteralPath (Join-Path $sourceRoot 'lv_icon_editor.lvproj') -Encoding ASCII

            $binDir = Join-Path $tempRoot 'bin'
            New-Item -Path $binDir -ItemType Directory -Force | Out-Null
            '@echo off' | Set-Content -LiteralPath (Join-Path $binDir 'g-cli.cmd') -Encoding ASCII
            $env:PATH = "$binDir;$originalPath"

            $outputDirectory = Join-Path $tempRoot 'output'
            $failed = $false
            $thrownMessage = ''
            try {
                & $script:scriptPath `
                    -SourceProjectRoot $sourceRoot `
                    -OutputDirectory $outputDirectory `
                    -TargetLabVIEWVersion 2020 `
                    -RequiredBitness '64'
            }
            catch {
                $failed = $true
                $thrownMessage = $_.Exception.Message
            }

            $failed | Should -BeTrue
            $thrownMessage | Should -Match "Missing '.lvversion' alongside"
            Test-Path -LiteralPath (Join-Path $outputDirectory 'lunit-smoke.status.json') -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $outputDirectory 'lunit-smoke.result.json') -PathType Leaf | Should -BeTrue

            $statusPayload = Get-Content -LiteralPath (Join-Path $outputDirectory 'lunit-smoke.status.json') -Raw | ConvertFrom-Json
            [string]$statusPayload.status | Should -Be 'failed'
        }
        finally {
            $env:PATH = $originalPath
            if (Test-Path -LiteralPath $tempRoot -PathType Container) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }

    It 'runs diagnostic-only LV2026 control probe when LV2020 report validation fails and keeps gate strict' {
        $tempRoot = Join-Path $env:TEMP ("lunit-smoke-control-probe-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        $originalPath = $env:PATH
        try {
            $sourceRoot = Join-Path $tempRoot 'source'
            New-Item -Path $sourceRoot -ItemType Directory -Force | Out-Null
            '26.0' | Set-Content -LiteralPath (Join-Path $sourceRoot '.lvversion') -Encoding ASCII
            '@project' | Set-Content -LiteralPath (Join-Path $sourceRoot 'lv_icon_editor.lvproj') -Encoding ASCII

            $binDir = Join-Path $tempRoot 'bin'
            New-Item -Path $binDir -ItemType Directory -Force | Out-Null
            $mockGcliPath = Join-Path $binDir 'g-cli.cmd'
            @'
@echo off
setlocal EnableDelayedExpansion
set "reportPath="
set "lvver="
:parse
if "%~1"=="" goto parsed
if /I "%~1"=="--lv-ver" (
  set "lvver=%~2"
)
if /I "%~1"=="-r" (
  set "reportPath=%~2"
)
shift
goto parse
:parsed
echo %*>>"%~dp0gcli-invocations.log"
if "%reportPath%"=="" (
  echo Missing Parameters: report_path
  exit /b 1
)
for %%I in ("%reportPath%") do (
  if not exist "%%~dpI" mkdir "%%~dpI"
)
if "%lvver%"=="2020" (
  >"%reportPath%" echo ^<testsuites /^>
  echo LV2020 no testcases
  exit /b 23
)
>"%reportPath%" echo ^<testsuite^>^<testcase name="Control" classname="LV2026" status="Passed" /^>^</testsuite^>
echo LV2026 control probe passed
exit /b 0
'@ | Set-Content -LiteralPath $mockGcliPath -Encoding ASCII

            $mockVipmPath = Join-Path $binDir 'vipm.cmd'
            @'
@echo off
if /I "%~1"=="--labview-version" goto list
echo Unsupported mock invocation
exit /b 1
:list
echo Found 2 packages:
echo (astemes_lib_lunit v1.12.5.6)
echo (sas_workshops_lib_lunit_for_g_cli v1.2.0.83)
exit /b 0
'@ | Set-Content -LiteralPath $mockVipmPath -Encoding ASCII
            $env:PATH = "$binDir;$originalPath"

            $outputDirectory = Join-Path $tempRoot 'output'
            $thrownMessage = ''
            try {
                & $script:scriptPath `
                    -SourceProjectRoot $sourceRoot `
                    -OutputDirectory $outputDirectory `
                    -TargetLabVIEWVersion 2020 `
                    -RequiredBitness '64' `
                    -OverrideLvversion '20.0'
                throw 'Expected LV2020 strict gate failure, but script completed successfully.'
            }
            catch {
                $thrownMessage = $_.Exception.Message
            }

            $thrownMessage | Should -Match 'LabVIEW 2020 LUnit smoke gate failed'
            $thrownMessage | Should -Match 'no_testcases'
            Test-Path -LiteralPath (Join-Path $outputDirectory 'reports/lunit-report-lv2020-x64.xml') -PathType Leaf | Should -BeTrue

            $resultPayload = Get-Content -LiteralPath (Join-Path $outputDirectory 'lunit-smoke.result.json') -Raw | ConvertFrom-Json
            [string]$resultPayload.status | Should -Be 'failed'
            [string]$resultPayload.report.validation_outcome | Should -Be 'no_testcases'
            $controlStatus = [string]$resultPayload.control_probe.status
            if ($controlStatus -eq 'passed') {
                [bool]$resultPayload.control_probe.executed | Should -BeTrue
                [string]$resultPayload.control_probe.validation_outcome | Should -Be 'passed'
                [string]$resultPayload.control_probe.command | Should -Match '--lv-ver 2026'
                Test-Path -LiteralPath (Join-Path $outputDirectory 'reports/lunit-report-lv2026-x64-control.xml') -PathType Leaf | Should -BeTrue
            }
            else {
                $controlStatus | Should -Be 'not_run'
                [string]$resultPayload.control_probe.reason | Should -Be 'skipped_active_labview_processes'
            }

            [string](Get-Content -LiteralPath (Join-Path $sourceRoot '.lvversion') -Raw).Trim() | Should -Be '26.0'
        }
        finally {
            $env:PATH = $originalPath
            if (Test-Path -LiteralPath $tempRoot -PathType Container) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }
}
