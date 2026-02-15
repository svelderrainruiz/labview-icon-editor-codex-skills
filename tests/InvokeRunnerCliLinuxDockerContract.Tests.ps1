#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Invoke-RunnerCliLinuxDocker contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:scriptPath = Join-Path $script:repoRoot 'scripts/Invoke-RunnerCliLinuxDocker.ps1'

        if (-not (Test-Path -LiteralPath $script:scriptPath -PathType Leaf)) {
            throw "Required script missing: $script:scriptPath"
        }

        $script:scriptContent = Get-Content -LiteralPath $script:scriptPath -Raw
    }

    It 'defines required parameters and deterministic defaults' {
        $script:scriptContent | Should -Match '\[string\]\$SourceProjectRoot'
        $script:scriptContent | Should -Match '\[string\]\$OutputDirectory'
        $script:scriptContent | Should -Match '\[string\]\$DockerfilePath\s*=\s*''docker/runner-cli-linux-ci\.Dockerfile'''
        $script:scriptContent | Should -Match '\[string\]\$LockFilePath\s*=\s*''docker/runner-cli-linux-ci\.lock\.json'''
        $script:scriptContent | Should -Match '\[string\]\$Runtime\s*=\s*''linux-x64'''
    }

    It 'enforces lock-file contract and deterministic docker build args' {
        $script:scriptContent | Should -Match 'Lock file.*missing ''dotnet_sdk_image'''
        $script:scriptContent | Should -Match 'Lock file.*missing ''pylavi'' object'
        $script:scriptContent | Should -Match 'pylavi\.name, pylavi\.version, pylavi\.url, and pylavi\.sha256'
        $script:scriptContent | Should -Match 'pylavi\.sha256 must be lowercase 64-char hex'
        $script:scriptContent | Should -Match 'DOTNET_SDK_IMAGE='
        $script:scriptContent | Should -Match 'PYLAVI_URL='
        $script:scriptContent | Should -Match 'PYLAVI_SHA256='
    }

    It 'runs runner-cli build pipeline in container with copy-to-workspace model' {
        $script:scriptContent | Should -Match 'Runner CLI project not found'
        $script:scriptContent | Should -Match 'Runner CLI test project not found'
        $script:scriptContent | Should -Match 'Convert-ToDockerHostPath'
        $script:scriptContent | Should -Match '--mount'
        $script:scriptContent | Should -Match 'type=bind,source='
        $script:scriptContent | Should -Match 'cp -a /source/\. /workspace/src/'
        $script:scriptContent | Should -Match 'dotnet test RunnerCli.Tests/RunnerCli.Tests.csproj'
        $script:scriptContent | Should -Match 'dotnet publish RunnerCli/RunnerCli.csproj'
        $script:scriptContent | Should -Match '--runtime __RUNTIME__'
    }

    It 'captures diagnostics payloads and fails after writing them on error' {
        foreach ($fileName in @(
            'runner-cli-linux-docker.status.json',
            'runner-cli-linux-docker.result.json',
            'runner-cli-linux-docker.log',
            'runner-cli-linux-docker.stdout.txt',
            'runner-cli-linux-docker.stderr.txt'
        )) {
            $escaped = [regex]::Escape($fileName)
            $script:scriptContent | Should -Match $escaped
        }

        $script:scriptContent | Should -Match 'Write-JsonFile -Path \$resultPath'
        $script:scriptContent | Should -Match 'Write-JsonFile -Path \$statusPath'
        $script:scriptContent | Should -Match 'throw "runner-cli Linux Docker validation failed:'
    }

    It 'writes failure diagnostics for missing source root before exiting non-zero' {
        $tempRoot = Join-Path $env:TEMP ('invoke-runner-cli-linux-docker-contract-' + [guid]::NewGuid().ToString('n'))
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        $outputDir = Join-Path $tempRoot 'out'
        $missingSource = Join-Path $tempRoot 'missing-source'

        $null = & pwsh -NoProfile -File $script:scriptPath -SourceProjectRoot $missingSource -OutputDirectory $outputDir 2>&1
        $LASTEXITCODE | Should -Not -Be 0

        $statusPath = Join-Path $outputDir 'runner-cli-linux-docker.status.json'
        $resultPath = Join-Path $outputDir 'runner-cli-linux-docker.result.json'
        $logPath = Join-Path $outputDir 'runner-cli-linux-docker.log'

        (Test-Path -LiteralPath $statusPath -PathType Leaf) | Should -BeTrue
        (Test-Path -LiteralPath $resultPath -PathType Leaf) | Should -BeTrue
        (Test-Path -LiteralPath $logPath -PathType Leaf) | Should -BeTrue

        $status = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
        [string]$status.status | Should -Be 'failed'
        [string]$status.reason | Should -Match 'Source project root not found'
    }
}
