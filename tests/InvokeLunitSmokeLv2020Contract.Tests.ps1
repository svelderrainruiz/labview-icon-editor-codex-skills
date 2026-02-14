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
        $script:scriptContent | Should -Match 'ValidateSet\(''64''\)'
    }

    It 'contains canonical direct g-cli lunit command markers and diagnostics outputs' {
        $script:scriptContent | Should -Match '''--lv-ver'''
        $script:scriptContent | Should -Match '''--arch'''
        $script:scriptContent | Should -Match '''lunit'''
        $script:scriptContent | Should -Match '''-h'''
        $script:scriptContent | Should -Match '''-r'''
        $script:scriptContent | Should -Match 'continuing to run command gate'
        $script:scriptContent | Should -Not -Match 'g-cli LUnit help command failed with exit code'
        $script:scriptContent | Should -Match 'lunit-smoke\.status\.json'
        $script:scriptContent | Should -Match 'lunit-smoke\.result\.json'
        $script:scriptContent | Should -Match 'lunit-smoke\.log'
        $script:scriptContent | Should -Match 'lunit-report-64\.xml'
        $script:scriptContent | Should -Match 'lvversion_before_path = Join-Path \$workspaceDiagnosticsDirectory ''lvversion\.before'''
        $script:scriptContent | Should -Match 'lvversion_after_path = Join-Path \$workspaceDiagnosticsDirectory ''lvversion\.after'''
        $script:scriptContent | Should -Match 'Missing ''\.lvversion'' alongside'
    }

    It 'runs with mocked g-cli, emits diagnostics, enforces x64 path, and preserves source lvversion' {
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
  exit /b 0
)
echo Missing Parameters: report_path
exit /b 1
'@ | Set-Content -LiteralPath $mockGcliPath -Encoding ASCII
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
                'reports/lunit-report-64.xml',
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
            [int]$resultPayload.command_results.help_exit_code | Should -Be 1
            [int]$resultPayload.command_results.run_exit_code | Should -Be 0

            [string](Get-Content -LiteralPath (Join-Path $sourceRoot '.lvversion') -Raw).Trim() | Should -Be '26.0'
            [string](Get-Content -LiteralPath (Join-Path $outputDirectory 'workspace/lvversion.before') -Raw).Trim() | Should -Be '26.0'
            [string](Get-Content -LiteralPath (Join-Path $outputDirectory 'workspace/lvversion.after') -Raw).Trim() | Should -Be '20.0'
            [string](Get-Content -LiteralPath (Join-Path $outputDirectory 'lunit-smoke.log') -Raw) | Should -Match 'WARNING: g-cli LUnit help command exited with code 1; continuing to run command gate\.'

            $invocationLog = Get-Content -LiteralPath (Join-Path $binDir 'gcli-invocations.log') -Raw
            $invocationLog | Should -Match '--arch 64'
            $invocationLog | Should -Not -Match '--arch 32'
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
}
