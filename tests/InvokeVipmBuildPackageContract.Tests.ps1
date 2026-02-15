#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Invoke-VipmBuildPackage contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:scriptPath = Join-Path $script:repoRoot 'scripts/Invoke-VipmBuildPackage.ps1'
        if (-not (Test-Path -LiteralPath $script:scriptPath -PathType Leaf)) {
            throw "Required script missing: $script:scriptPath"
        }
        $script:scriptContent = Get-Content -LiteralPath $script:scriptPath -Raw
    }

    It 'defines VIPM package-build interface and diagnostics contract' {
        $script:scriptContent | Should -Match 'param\('
        $script:scriptContent | Should -Match '\$SourceProjectRoot'
        $script:scriptContent | Should -Match '\$VipbPath'
        $script:scriptContent | Should -Match '\$LabVIEWVersionYear'
        $script:scriptContent | Should -Match '\$LabVIEWBitness'
        $script:scriptContent | Should -Match '\$OutputDirectory'
        $script:scriptContent | Should -Match '\$VipmCommunityEdition'
        $script:scriptContent | Should -Match '\$CommandTimeoutSeconds'
        $script:scriptContent | Should -Match '\$WaitTimeoutSeconds'
        $script:scriptContent | Should -Match '\$WaitPollSeconds'
        $script:scriptContent | Should -Match '\$EnforceLabVIEWProcessIsolation'
        $script:scriptContent | Should -Match "Required command 'vipm' not found on PATH\."
        $script:scriptContent | Should -Match 'Missing ''\.lvversion'' alongside'
        $script:scriptContent | Should -Match 'Minimum supported LabVIEW version is 20\.0'
        $script:scriptContent | Should -Match 'LabVIEW version mismatch'
        $script:scriptContent | Should -Match 'vipm-build\.status\.json'
        $script:scriptContent | Should -Match 'vipm-build\.result\.json'
        $script:scriptContent | Should -Match 'vipm-build\.log'
        $script:scriptContent | Should -Match 'help-build\.txt'
        $script:scriptContent | Should -Match 'build_path = Join-Path \$commandsDirectory ''build\.txt'''
        $script:scriptContent | Should -Match '--labview-version'
        $script:scriptContent | Should -Match '--labview-bitness'
        $script:scriptContent | Should -Match 'build'
        $script:scriptContent | Should -Match 'if \(\$result\.status -ne ''passed''\)'
    }

    It 'runs with mocked vipm and emits deterministic build diagnostics' {
        $tempRoot = Join-Path $env:TEMP ("vipm-build-package-pass-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        $originalPath = $env:PATH
        try {
            $sourceRoot = Join-Path $tempRoot 'consumer'
            $toolingDeployment = Join-Path $sourceRoot 'Tooling/deployment'
            $shimDir = Join-Path $tempRoot 'shim'
            $outputDirectory = Join-Path $tempRoot 'out'
            New-Item -Path $sourceRoot -ItemType Directory -Force | Out-Null
            New-Item -Path $toolingDeployment -ItemType Directory -Force | Out-Null
            New-Item -Path $shimDir -ItemType Directory -Force | Out-Null

            'dummy-project' | Set-Content -LiteralPath (Join-Path $sourceRoot 'lv_icon_editor.lvproj') -Encoding ASCII
            '26.0' | Set-Content -LiteralPath (Join-Path $sourceRoot '.lvversion') -Encoding ASCII
            'dummy-vipb' | Set-Content -LiteralPath (Join-Path $toolingDeployment 'NI Icon editor.vipb') -Encoding UTF8

            $mockVipmPath = Join-Path $shimDir 'mock-vipm.ps1'
            @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

if (-not [string]::IsNullOrWhiteSpace($env:VIPM_BUILD_TEST_LOG_PATH)) {
    Add-Content -LiteralPath $env:VIPM_BUILD_TEST_LOG_PATH -Value ($Args -join ' ')
}

if ($Args.Count -ge 2 -and $Args[0] -eq 'help' -and $Args[1] -eq 'build') {
    Write-Output 'Usage: build [OPTIONS] <BUILD_SPEC>'
    Write-Output 'Arguments: .vipb or .lvproj'
    exit 0
}

if ($Args.Count -ge 1 -and $Args[0] -eq 'activate') {
    Write-Output 'activate-ok'
    exit 0
}

$buildIndex = [Array]::IndexOf($Args, 'build')
if ($buildIndex -ge 0) {
    $outputDir = Join-Path $env:VIPM_BUILD_TEST_SOURCE_ROOT 'builds/VI Package'
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    $vipPath = Join-Path $outputDir 'labview-icon-editor-0.1.0.1.vip'
    'dummy-vip' | Set-Content -LiteralPath $vipPath -Encoding ASCII
    Write-Output ('built ' + $vipPath)
    exit 0
}

Write-Error ('unexpected args: ' + ($Args -join ' '))
exit 9
'@ | Set-Content -LiteralPath $mockVipmPath -Encoding UTF8

            $mockVipmCmdPath = Join-Path $shimDir 'vipm.cmd'
            @'
@echo off
pwsh -NoProfile -File "%~dp0mock-vipm.ps1" %*
exit /b %errorlevel%
'@ | Set-Content -LiteralPath $mockVipmCmdPath -Encoding ASCII

            $env:VIPM_BUILD_TEST_LOG_PATH = Join-Path $tempRoot 'vipm-build-invocations.log'
            Set-Content -LiteralPath $env:VIPM_BUILD_TEST_LOG_PATH -Value '' -Encoding UTF8
            $env:VIPM_BUILD_TEST_SOURCE_ROOT = $sourceRoot
            $env:VIPM_COMMUNITY_EDITION = 'true'
            $env:PATH = "$shimDir;$originalPath"

            & pwsh -NoProfile -File $script:scriptPath `
                -SourceProjectRoot $sourceRoot `
                -LabVIEWVersionYear 2026 `
                -LabVIEWBitness '64' `
                -OutputDirectory $outputDirectory `
                -VipmCommunityEdition:$true

            $LASTEXITCODE | Should -Be 0

            foreach ($requiredRelativePath in @(
                'vipm-build.status.json',
                'vipm-build.result.json',
                'vipm-build.log',
                'commands/help-build.txt',
                'commands/build.txt',
                'commands/activate.txt'
            )) {
                Test-Path -LiteralPath (Join-Path $outputDirectory $requiredRelativePath) -PathType Leaf | Should -BeTrue
            }

            $statusPayload = Get-Content -LiteralPath (Join-Path $outputDirectory 'vipm-build.status.json') -Raw | ConvertFrom-Json
            [string]$statusPayload.status | Should -Be 'passed'

            $resultPayload = Get-Content -LiteralPath (Join-Path $outputDirectory 'vipm-build.result.json') -Raw | ConvertFrom-Json
            [string]$resultPayload.status | Should -Be 'passed'
            [string]$resultPayload.target.bitness | Should -Be '64'
            [string]$resultPayload.source.lvversion_raw | Should -Be '26.0'
            [string]$resultPayload.source.lvversion_year | Should -Be '2026'
            [string]$resultPayload.artifact.vip_path | Should -Match '\.vip$'
            [string]$resultPayload.build.command | Should -Match '--labview-version'
            [string]$resultPayload.build.command | Should -Match '--labview-bitness'
            [string]$resultPayload.build.command | Should -Match 'build'

            $invocations = Get-Content -LiteralPath $env:VIPM_BUILD_TEST_LOG_PATH -Raw
            $invocations | Should -Match 'help build'
            $invocations | Should -Match '--labview-version 2026'
            $invocations | Should -Match '--labview-bitness 64'
            $invocations | Should -Match 'build'
        }
        finally {
            $env:PATH = $originalPath
            $env:VIPM_BUILD_TEST_LOG_PATH = $null
            $env:VIPM_BUILD_TEST_SOURCE_ROOT = $null
            $env:VIPM_COMMUNITY_EDITION = $null
            if (Test-Path -LiteralPath $tempRoot -PathType Container) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }

    It 'fails deterministically when sibling .lvversion is missing and still writes diagnostics' {
        $tempRoot = Join-Path $env:TEMP ("vipm-build-package-missing-lvversion-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        $originalPath = $env:PATH
        try {
            $sourceRoot = Join-Path $tempRoot 'consumer'
            $toolingDeployment = Join-Path $sourceRoot 'Tooling/deployment'
            $shimDir = Join-Path $tempRoot 'shim'
            $outputDirectory = Join-Path $tempRoot 'out'
            New-Item -Path $sourceRoot -ItemType Directory -Force | Out-Null
            New-Item -Path $toolingDeployment -ItemType Directory -Force | Out-Null
            New-Item -Path $shimDir -ItemType Directory -Force | Out-Null

            'dummy-project' | Set-Content -LiteralPath (Join-Path $sourceRoot 'lv_icon_editor.lvproj') -Encoding ASCII
            'dummy-vipb' | Set-Content -LiteralPath (Join-Path $toolingDeployment 'NI Icon editor.vipb') -Encoding UTF8

            $mockVipmCmdPath = Join-Path $shimDir 'vipm.cmd'
            @'
@echo off
echo vipm
exit /b 0
'@ | Set-Content -LiteralPath $mockVipmCmdPath -Encoding ASCII

            $env:PATH = "$shimDir;$originalPath"

            $commandOutput = & pwsh -NoProfile -File $script:scriptPath `
                -SourceProjectRoot $sourceRoot `
                -LabVIEWVersionYear 2026 `
                -OutputDirectory $outputDirectory 2>&1

            $LASTEXITCODE | Should -Not -Be 0
            [string]($commandOutput -join [Environment]::NewLine) | Should -Match "Missing '.lvversion' alongside"

            Test-Path -LiteralPath (Join-Path $outputDirectory 'vipm-build.status.json') -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $outputDirectory 'vipm-build.result.json') -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $outputDirectory 'vipm-build.log') -PathType Leaf | Should -BeTrue

            $statusPayload = Get-Content -LiteralPath (Join-Path $outputDirectory 'vipm-build.status.json') -Raw | ConvertFrom-Json
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
