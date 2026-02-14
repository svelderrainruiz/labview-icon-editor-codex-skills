#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'VIPM help output local docker contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:helperPath = Join-Path $script:repoRoot 'scripts/Invoke-PackageVipLinuxLocal.ps1'

        if (-not (Test-Path -Path $script:helperPath -PathType Leaf)) {
            throw "Helper script not found: $script:helperPath"
        }
    }

    It 'prints vipm help output when a vipm-capable image is provided' {
        $runDockerVipmHelpTest = -not [string]::IsNullOrWhiteSpace($env:RUN_DOCKER_VIPM_HELP_TEST) -and $env:RUN_DOCKER_VIPM_HELP_TEST.Trim().ToLowerInvariant() -in @('1', 'true', 'yes', 'on')
        if (-not $runDockerVipmHelpTest) {
            Set-ItResult -Skipped -Because 'Set RUN_DOCKER_VIPM_HELP_TEST=true to run local docker vipm help test.'
            return
        }

        if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'Docker CLI is not available on PATH.'
            return
        }

        $testRoot = Join-Path $script:repoRoot 'artifacts/tmp-vipm-help-local-test'
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

        $dockerfilePath = Join-Path $testRoot 'Dockerfile'
        $dockerfile = @'
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y bash coreutils sed && rm -rf /var/lib/apt/lists/*
RUN printf '#!/usr/bin/env bash\nset -euo pipefail\ncmd="${1:-}"\ncase "$cmd" in\n  help|--help|"")\n    echo "VIPM CLI"\n    echo "Usage: vipm <command> [options]"\n    echo "Commands: help, activate, build"\n    ;;\n  activate)\n    echo "VIPM activate ok"\n    ;;\n  build)\n    target="${2:-}"\n    echo "VIPM build for ${target}"\n    mkdir -p /workspace/build\n    touch /workspace/build/mock.vip\n    ;;\n  *)\n    echo "unknown command: $cmd" >&2\n    exit 2\n    ;;\nesac\n' > /usr/local/bin/vipm
RUN chmod +x /usr/local/bin/vipm
'@
        Set-Content -Path $dockerfilePath -Value $dockerfile -Encoding utf8

        $imageTag = "local/vipm-help-test:$PID"
        $buildOutput = & docker build -t $imageTag -f $dockerfilePath $testRoot 2>&1
        if ($LASTEXITCODE -ne 0) {
            $details = $buildOutput -join [Environment]::NewLine
            throw "Failed to build local vipm test image. $details"
        }

        try {
            $consumerRoot = Join-Path $testRoot 'consumer'
            New-Item -ItemType Directory -Path (Join-Path $consumerRoot 'Tooling/deployment') -Force | Out-Null
            Set-Content -Path (Join-Path $consumerRoot 'Tooling/deployment/NI Icon editor.vipb') -Value 'stub-vipb' -Encoding ascii

            $consumerRelative = [IO.Path]::GetRelativePath($script:repoRoot, $consumerRoot).Replace('\\', '/')
            $vipbRelative = "$consumerRelative/Tooling/deployment/NI Icon editor.vipb"

            $output = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:helperPath `
                -LinuxLabviewImage $imageTag `
                -ConsumerPath $consumerRelative `
                -VipmProjectPath $vipbRelative 2>&1 | Out-String

            if ($LASTEXITCODE -ne 0) {
                throw "Helper exited with code $LASTEXITCODE. Output: $output"
            }

            $output | Should -Match 'vipm help preview \(first 20 lines\):'
            $output | Should -Match 'Usage:\s+vipm\s+<command>'
        }
        finally {
            & docker image rm -f $imageTag *> $null
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
