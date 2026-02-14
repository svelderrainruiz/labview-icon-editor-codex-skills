#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Invoke-VipmInstallSmoke contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:scriptPath = Join-Path $script:repoRoot 'scripts/Invoke-VipmInstallSmoke.ps1'
        if (-not (Test-Path -LiteralPath $script:scriptPath -PathType Leaf)) {
            throw "Required script missing: $script:scriptPath"
        }
        $script:scriptContent = Get-Content -LiteralPath $script:scriptPath -Raw
    }

    It 'defines x86 install interface and .lvversion authority markers' {
        $script:scriptContent | Should -Match 'param\('
        $script:scriptContent | Should -Match '\$SourceProjectRoot'
        $script:scriptContent | Should -Match '\$VipArtifactPath'
        $script:scriptContent | Should -Match '\$ProjectName'
        $script:scriptContent | Should -Match '\$RequiredBitness'
        $script:scriptContent | Should -Match '\$OutputDirectory'
        $script:scriptContent | Should -Match '\$PackageToken'
        $script:scriptContent | Should -Match "ValidateSet\('32'\)"
        $script:scriptContent | Should -Match "Missing '\.lvversion' alongside"
        $script:scriptContent | Should -Match 'Minimum supported LabVIEW version is 20\.0'
        $script:scriptContent | Should -Match 'Tooling/deployment/NI Icon editor\.vipb'
        $script:scriptContent | Should -Match 'Product_Name'
    }

    It 'contains required vipm command shape and diagnostics outputs' {
        $script:scriptContent | Should -Match 'System\.Diagnostics\.ProcessStartInfo'
        $script:scriptContent | Should -Match 'ArgumentList\.Add'
        $script:scriptContent | Should -Match '--labview-version'
        $script:scriptContent | Should -Match '--labview-bitness'
        $script:scriptContent | Should -Match 'install'
        $script:scriptContent | Should -Match 'list'
        $script:scriptContent | Should -Match 'uninstall'
        $script:scriptContent | Should -Match 'vipm-install\.status\.json'
        $script:scriptContent | Should -Match 'vipm-install\.result\.json'
        $script:scriptContent | Should -Match 'vipm-install\.log'
        $script:scriptContent | Should -Match 'help_path = Join-Path \$commandsDirectory ''help\.txt'''
        $script:scriptContent | Should -Match 'list_before_path = Join-Path \$commandsDirectory ''list-before\.txt'''
        $script:scriptContent | Should -Match 'install_path = Join-Path \$commandsDirectory ''install\.txt'''
        $script:scriptContent | Should -Match 'list_after_install_path = Join-Path \$commandsDirectory ''list-after-install\.txt'''
        $script:scriptContent | Should -Match 'uninstall_path = Join-Path \$commandsDirectory ''uninstall\.txt'''
        $script:scriptContent | Should -Match 'list_after_uninstall_path = Join-Path \$commandsDirectory ''list-after-uninstall\.txt'''
        $script:scriptContent | Should -Match 'if \(\$result\.status -ne ''passed''\)'
    }

    It 'runs with mocked vipm and emits deterministic x86 diagnostics' {
        $tempRoot = Join-Path $env:TEMP ("vipm-install-smoke-pass-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        $originalPath = $env:PATH
        $originalLogPath = $env:VIPM_TEST_LOG_PATH
        try {
            $sourceRoot = Join-Path $tempRoot 'consumer'
            $toolingDeployment = Join-Path $sourceRoot 'Tooling/deployment'
            $shimDir = Join-Path $tempRoot 'shim'
            $outputDirectory = Join-Path $tempRoot 'out'
            $artifactDirectory = Join-Path $tempRoot 'artifact'
            New-Item -Path $sourceRoot -ItemType Directory -Force | Out-Null
            New-Item -Path $toolingDeployment -ItemType Directory -Force | Out-Null
            New-Item -Path $shimDir -ItemType Directory -Force | Out-Null
            New-Item -Path $artifactDirectory -ItemType Directory -Force | Out-Null

            'dummy-project' | Set-Content -LiteralPath (Join-Path $sourceRoot 'lv_icon_editor.lvproj') -Encoding ASCII
            '26.0' | Set-Content -LiteralPath (Join-Path $sourceRoot '.lvversion') -Encoding ASCII
            @'
<VI_Package_Builder_Settings>
  <Library_General_Settings>
    <Product_Name>labview-icon-editor</Product_Name>
  </Library_General_Settings>
</VI_Package_Builder_Settings>
'@ | Set-Content -LiteralPath (Join-Path $toolingDeployment 'NI Icon editor.vipb') -Encoding UTF8

            $vipPath = Join-Path $artifactDirectory 'labview-icon-editor.vip'
            'dummy-vip' | Set-Content -LiteralPath $vipPath -Encoding ASCII

            $mockVipmPath = Join-Path $shimDir 'mock-vipm.ps1'
            @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

if (-not [string]::IsNullOrWhiteSpace($env:VIPM_TEST_LOG_PATH)) {
    Add-Content -LiteralPath $env:VIPM_TEST_LOG_PATH -Value ($Args -join ' ')
}

$statePath = $env:VIPM_TEST_STATE_PATH
if ([string]::IsNullOrWhiteSpace($statePath)) {
    $statePath = Join-Path $env:TEMP 'vipm-test-state.txt'
}

if ($Args.Count -eq 0) { exit 2 }
if ($Args[0] -eq 'activate') {
    Write-Output 'activated'
    exit 0
}
if ($Args[0] -eq 'help') {
    Write-Output 'help-ok'
    exit 0
}
if ($Args -contains 'list') {
    $state = if (Test-Path -LiteralPath $statePath) { (Get-Content -LiteralPath $statePath -Raw).Trim() } else { 'before' }
    if ($state -eq 'installed') {
        Write-Output 'Found 1 packages:'
        Write-Output '  labview-icon-editor (labview-icon-editor v0.0.0.1)'
    } else {
        Write-Output 'Found 0 packages:'
    }
    exit 0
}
if ($Args -contains 'install') {
    Set-Content -LiteralPath $statePath -Value 'installed'
    Write-Output 'install-ok'
    exit 0
}
if ($Args -contains 'uninstall') {
    Set-Content -LiteralPath $statePath -Value 'removed'
    Write-Output 'uninstall-ok'
    exit 0
}

Write-Error ('unexpected args: ' + ($Args -join ' '))
exit 9
'@ | Set-Content -LiteralPath $mockVipmPath -Encoding UTF8

            $mockVipmCmdPath = Join-Path $shimDir 'vipm.cmd'
            @'
@echo off
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0mock-vipm.ps1" %*
exit /b %errorlevel%
'@ | Set-Content -LiteralPath $mockVipmCmdPath -Encoding ASCII

            $env:VIPM_TEST_LOG_PATH = Join-Path $tempRoot 'vipm-invocations.log'
            Set-Content -LiteralPath $env:VIPM_TEST_LOG_PATH -Value '' -Encoding UTF8
            $env:VIPM_TEST_STATE_PATH = Join-Path $tempRoot 'vipm-state.txt'
            Set-Content -LiteralPath $env:VIPM_TEST_STATE_PATH -Value 'before' -Encoding UTF8
            $env:VIPM_COMMUNITY_EDITION = 'true'
            $env:PATH = "$shimDir;$originalPath"

            & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:scriptPath `
                -SourceProjectRoot $sourceRoot `
                -VipArtifactPath $vipPath `
                -RequiredBitness '32' `
                -OutputDirectory $outputDirectory `
                -RunnerLabel 'self-hosted-windows-lv2026x86' `
                -WaitTimeoutSeconds 3 `
                -WaitPollSeconds 1

            $LASTEXITCODE | Should -Be 0

            foreach ($requiredRelativePath in @(
                'vipm-install.status.json',
                'vipm-install.result.json',
                'vipm-install.log',
                'commands/help.txt',
                'commands/list-before.txt',
                'commands/install.txt',
                'commands/list-after-install.txt',
                'commands/uninstall.txt',
                'commands/list-after-uninstall.txt'
            )) {
                Test-Path -LiteralPath (Join-Path $outputDirectory $requiredRelativePath) -PathType Leaf | Should -BeTrue
            }

            $statusPayload = Get-Content -LiteralPath (Join-Path $outputDirectory 'vipm-install.status.json') -Raw | ConvertFrom-Json
            [string]$statusPayload.status | Should -Be 'passed'

            $resultPayload = Get-Content -LiteralPath (Join-Path $outputDirectory 'vipm-install.result.json') -Raw | ConvertFrom-Json
            [string]$resultPayload.status | Should -Be 'passed'
            [string]$resultPayload.required_bitness | Should -Be '32'
            [string]$resultPayload.source.lvversion_raw | Should -Be '26.0'
            [string]$resultPayload.source.labview_year | Should -Be '2026'
            [bool]$resultPayload.install_succeeded | Should -BeTrue
            [bool]$resultPayload.uninstall_succeeded | Should -BeTrue
            [string]$resultPayload.package.token | Should -Be 'labview-icon-editor'
            [string]$resultPayload.runner_label | Should -Be 'self-hosted-windows-lv2026x86'

            $invocations = Get-Content -LiteralPath $env:VIPM_TEST_LOG_PATH -Raw
            $invocations | Should -Match '--labview-version 2026'
            $invocations | Should -Match '--labview-bitness 32'
            $invocations | Should -Match 'install'
            $invocations | Should -Match 'uninstall'
        }
        finally {
            $env:PATH = $originalPath
            $env:VIPM_TEST_LOG_PATH = $originalLogPath
            $env:VIPM_TEST_STATE_PATH = $null
            $env:VIPM_COMMUNITY_EDITION = $null
            if (Test-Path -LiteralPath $tempRoot -PathType Container) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }

    It 'fails deterministically when sibling .lvversion is missing and still writes diagnostics' {
        $tempRoot = Join-Path $env:TEMP ("vipm-install-smoke-missing-lvversion-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        $originalPath = $env:PATH
        try {
            $sourceRoot = Join-Path $tempRoot 'consumer'
            $shimDir = Join-Path $tempRoot 'shim'
            $outputDirectory = Join-Path $tempRoot 'out'
            $artifactDirectory = Join-Path $tempRoot 'artifact'
            New-Item -Path $sourceRoot -ItemType Directory -Force | Out-Null
            New-Item -Path $shimDir -ItemType Directory -Force | Out-Null
            New-Item -Path $artifactDirectory -ItemType Directory -Force | Out-Null

            'dummy-project' | Set-Content -LiteralPath (Join-Path $sourceRoot 'lv_icon_editor.lvproj') -Encoding ASCII
            'dummy-vip' | Set-Content -LiteralPath (Join-Path $artifactDirectory 'labview-icon-editor.vip') -Encoding ASCII

            $mockVipmCmdPath = Join-Path $shimDir 'vipm.cmd'
            @'
@echo off
echo vipm
exit /b 0
'@ | Set-Content -LiteralPath $mockVipmCmdPath -Encoding ASCII

            $env:PATH = "$shimDir;$originalPath"

            $commandOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:scriptPath `
                -SourceProjectRoot $sourceRoot `
                -VipArtifactPath (Join-Path $artifactDirectory 'labview-icon-editor.vip') `
                -OutputDirectory $outputDirectory 2>&1

            $LASTEXITCODE | Should -Not -Be 0
            [string]($commandOutput -join [Environment]::NewLine) | Should -Match "Missing '.lvversion' alongside"

            Test-Path -LiteralPath (Join-Path $outputDirectory 'vipm-install.status.json') -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $outputDirectory 'vipm-install.result.json') -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $outputDirectory 'vipm-install.log') -PathType Leaf | Should -BeTrue

            $statusPayload = Get-Content -LiteralPath (Join-Path $outputDirectory 'vipm-install.status.json') -Raw | ConvertFrom-Json
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
