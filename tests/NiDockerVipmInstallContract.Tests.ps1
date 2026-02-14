#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'NI Dockerfile VIPM install contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:dockerfilePath = Join-Path $script:repoRoot 'docker/ni-lv-pwsh.Dockerfile'
        if (-not (Test-Path -Path $script:dockerfilePath -PathType Leaf)) {
            throw "Dockerfile not found: $script:dockerfilePath"
        }

        $script:dockerfile = Get-Content -Raw -Path $script:dockerfilePath
    }

    It 'defines deterministic VIPM build args' {
        $script:dockerfile | Should -Match 'ARG\s+VIPM_CLI_URL='
        $script:dockerfile | Should -Match 'ARG\s+VIPM_CLI_SHA256='
        $script:dockerfile | Should -Match 'ARG\s+VIPM_CLI_ARCHIVE_TYPE=tar\.gz'
    }

    It 'requires URL and SHA256 together' {
        $script:dockerfile | Should -Match 'Both VIPM_CLI_URL and VIPM_CLI_SHA256 must be provided together\.'
    }

    It 'verifies archive checksum before extraction' {
        $script:dockerfile | Should -Match 'sha256sum\s+-c\s+-'
    }

    It 'installs vipm executable to /usr/local/bin/vipm' {
        $script:dockerfile | Should -Match 'install\s+-m\s+0755\s+"\$\{vipm_candidate\}"\s+/usr/local/bin/vipm'
    }
}
