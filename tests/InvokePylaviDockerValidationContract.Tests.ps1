#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Invoke-PylaviDockerValidation contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:scriptPath = Join-Path $script:repoRoot 'scripts/Invoke-PylaviDockerValidation.ps1'

        if (-not (Test-Path -LiteralPath $script:scriptPath -PathType Leaf)) {
            throw "Required script missing: $script:scriptPath"
        }

        $script:scriptContent = Get-Content -LiteralPath $script:scriptPath -Raw
    }

    It 'defines required parameters and deterministic defaults' {
        $script:scriptContent | Should -Match '\[string\]\$SourceProjectRoot'
        $script:scriptContent | Should -Match '\[string\]\$OutputDirectory'
        $script:scriptContent | Should -Match '\[string\]\$DockerfilePath\s*=\s*''docker/pylavi-ci\.Dockerfile'''
        $script:scriptContent | Should -Match '\[string\]\$LockFilePath\s*=\s*''docker/pylavi\.lock\.json'''
        $script:scriptContent | Should -Match '\[string\]\$PylaviConfigPath\s*=\s*''consumer/Tooling/pylavi/vi-validate\.yml'''
    }

    It 'enforces lock-file URL and sha256 contract for deterministic image build' {
        $script:scriptContent | Should -Match 'Lock file.*missing ''package'' object'
        $script:scriptContent | Should -Match 'package\.name, package\.version, package\.url, and package\.sha256'
        $script:scriptContent | Should -Match 'package\.sha256 must be lowercase 64-char hex'
        $script:scriptContent | Should -Match 'PYLAVI_URL='
        $script:scriptContent | Should -Match 'PYLAVI_SHA256='
        $script:scriptContent | Should -Match 'docker_build_command'
        $script:scriptContent | Should -Match 'Building deterministic pylavi image'
    }

    It 'resolves source project contract and runs vi_validate against source root' {
        $script:scriptContent | Should -Match "Expected exactly one 'lv_icon_editor\.lvproj'"
        $script:scriptContent | Should -Match "Missing '\.lvversion' alongside"
        $script:scriptContent | Should -Match 'Configured pylavi config path'
        $script:scriptContent | Should -Match 'Convert-ToDockerHostPath'
        $script:scriptContent | Should -Match '--mount'
        $script:scriptContent | Should -Match 'type=bind,source='
        $script:scriptContent | Should -Match 'docker_mount_spec'
        $script:scriptContent | Should -Match "-replace '\\\\', '/'"
        $script:scriptContent | Should -Match 'vi_validate'
        $script:scriptContent | Should -Match '--config'
        $script:scriptContent | Should -Match '-p'
        $script:scriptContent | Should -Match '/source'
    }

    It 'captures diagnostics payloads and fails after writing them on error' {
        foreach ($fileName in @(
            'pylavi-docker.status.json',
            'pylavi-docker.result.json',
            'pylavi-docker.log',
            'vi-validate.stdout.txt',
            'vi-validate.stderr.txt'
        )) {
            $escaped = [regex]::Escape($fileName)
            $script:scriptContent | Should -Match $escaped
        }

        $script:scriptContent | Should -Match 'catch \{' 
        $script:scriptContent | Should -Match 'finally \{' 
        $script:scriptContent | Should -Match 'Write-JsonFile -Path \$resultPath'
        $script:scriptContent | Should -Match 'Write-JsonFile -Path \$statusPath'
        $script:scriptContent | Should -Match 'throw "pylavi Docker validation failed:'
    }

    It 'writes failure diagnostics for missing source root before exiting non-zero' {
        $tempRoot = Join-Path $env:TEMP ('invoke-pylavi-docker-contract-' + [guid]::NewGuid().ToString('n'))
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        $outputDir = Join-Path $tempRoot 'out'
        $missingSource = Join-Path $tempRoot 'missing-source'

        $output = & pwsh -NoProfile -File $script:scriptPath -SourceProjectRoot $missingSource -OutputDirectory $outputDir 2>&1
        $LASTEXITCODE | Should -Not -Be 0

        $statusPath = Join-Path $outputDir 'pylavi-docker.status.json'
        $resultPath = Join-Path $outputDir 'pylavi-docker.result.json'
        $logPath = Join-Path $outputDir 'pylavi-docker.log'

        (Test-Path -LiteralPath $statusPath -PathType Leaf) | Should -BeTrue
        (Test-Path -LiteralPath $resultPath -PathType Leaf) | Should -BeTrue
        (Test-Path -LiteralPath $logPath -PathType Leaf) | Should -BeTrue

        $status = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
        [string]$status.status | Should -Be 'failed'
        [string]$status.reason | Should -Match 'Source project root not found'
    }
}
