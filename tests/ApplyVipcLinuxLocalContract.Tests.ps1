#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Local apply VIPC Linux helper contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:helperPath = Join-Path $script:repoRoot 'scripts/Invoke-ApplyVipcLinuxLocal.ps1'

        if (-not (Test-Path -Path $script:helperPath -PathType Leaf)) {
            throw "Helper script not found: $script:helperPath"
        }

        $script:helperContent = Get-Content -Raw -Path $script:helperPath
    }

    It 'exists under scripts with expected defaults' {
        $script:helperPath | Should -Match 'scripts[\\/]Invoke-ApplyVipcLinuxLocal\.ps1$'
        $script:helperContent | Should -Match '\[string\]\$LinuxLabviewImage\s*=\s*''nationalinstruments/labview:2026q1-linux-pwsh'''
        $script:helperContent | Should -Match '\[string\]\$VipcPath\s*=\s*''consumer/\.github/actions/apply-vipc/runner_dependencies\.vipc'''
        $script:helperContent | Should -Match '\[ValidateSet\(''64''\)\]\s*\[string\]\$Bitness\s*=\s*''64'''
    }

    It 'guards paired vipm cli url and sha inputs' {
        $script:helperContent | Should -Match 'VipmCliUrl and VipmCliSha256 must be provided together'
    }

    It 'builds fallback image with deterministic vipm cli build args' {
        $script:helperContent | Should -Match 'docker-build-vipm-capable'
        $script:helperContent | Should -Match '--build-arg'',\s*"VIPM_CLI_URL='
        $script:helperContent | Should -Match '--build-arg'',\s*"VIPM_CLI_SHA256='
        $script:helperContent | Should -Match '--build-arg'',\s*"VIPM_CLI_ARCHIVE_TYPE='
        $script:helperContent | Should -Match 'docker/ni-lv-pwsh\.Dockerfile'
    }

    It 'runs vipm install with explicit LabVIEW version and bitness against runner_dependencies.vipc' {
        $script:helperContent | Should -Match 'vipm --labview-version "\$LABVIEW_YEAR" --labview-bitness "\$LABVIEW_BITNESS" install "\$VIPC_PATH_IN_CONTAINER"'
        $script:helperContent | Should -Match 'runner_dependencies\.vipc'
    }

    It 'writes deterministic diagnostics and captures failure before exiting non-zero' {
        $script:helperContent | Should -Match 'vipm-apply\.log'
        $script:helperContent | Should -Match 'vipm-apply\.result\.json'
        $script:helperContent | Should -Match 'catch \{[\s\S]*Write-Log "ERROR:'
        $script:helperContent | Should -Match 'finally \{[\s\S]*ConvertTo-Json[\s\S]*Set-Content'
        $script:helperContent | Should -Match 'if \(\$scriptExitCode -ne 0\) \{\s*exit \$scriptExitCode'
    }

    It 'supports optional local runtime exercise behind env-gated opt-in' {
        $runRuntime = -not [string]::IsNullOrWhiteSpace($env:RUN_DOCKER_VIPM_VIPC_APPLY_TEST) -and $env:RUN_DOCKER_VIPM_VIPC_APPLY_TEST.Trim().ToLowerInvariant() -in @('1', 'true', 'yes', 'on')
        if (-not $runRuntime) {
            Set-ItResult -Skipped -Because 'Set RUN_DOCKER_VIPM_VIPC_APPLY_TEST=true to run local docker VIPC apply exercise.'
            return
        }

        if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'Docker CLI is not available on PATH.'
            return
        }

        if ([string]::IsNullOrWhiteSpace($env:VIPM_CLI_URL) -or [string]::IsNullOrWhiteSpace($env:VIPM_CLI_SHA256)) {
            Set-ItResult -Skipped -Because 'VIPM_CLI_URL and VIPM_CLI_SHA256 are required for runtime exercise.'
            return
        }

        $outputRoot = Join-Path $script:repoRoot ("artifacts/tmp-apply-vipc-runtime-{0}" -f $PID)
        try {
            $output = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:helperPath `
                -VipmCliUrl $env:VIPM_CLI_URL `
                -VipmCliSha256 $env:VIPM_CLI_SHA256 `
                -OutputDirectory $outputRoot 2>&1 | Out-String

            if ($LASTEXITCODE -ne 0) {
                throw "Runtime exercise failed with code $LASTEXITCODE. Output: $output"
            }

            Test-Path -LiteralPath (Join-Path $outputRoot 'vipm-apply.log') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $outputRoot 'vipm-apply.result.json') | Should -BeTrue
        }
        finally {
            Remove-Item -LiteralPath $outputRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
