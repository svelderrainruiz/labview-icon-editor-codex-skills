#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Release workflow contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:releaseWorkflowPath = Join-Path $script:repoRoot '.github/workflows/release-skill-layer.yml'
        $script:parityWorkflowPath = Join-Path $script:repoRoot '.github/workflows/labview-parity.yml'

        foreach ($path in @($script:releaseWorkflowPath, $script:parityWorkflowPath)) {
            if (-not (Test-Path -Path $path -PathType Leaf)) {
                throw "Required workflow missing: $path"
            }
        }

        $script:releaseContent = Get-Content -Path $script:releaseWorkflowPath -Raw
        $script:parityContent = Get-Content -Path $script:parityWorkflowPath -Raw
    }

    It 'keeps release workflow as dispatch-only and parity-gated' {
        $script:releaseContent | Should -Match 'on:\s*workflow_dispatch:'
        $script:releaseContent | Should -Match 'parity-gate:'
        $script:releaseContent | Should -Match 'uses:\s+\./\.github/workflows/labview-parity\.yml'
        $script:releaseContent | Should -Match 'package:\s*\r?\n\s*needs:\s*\[parity-gate\]'
    }

    It 'requires deterministic consumer gate inputs' {
        $script:releaseContent | Should -Match 'release_tag:'
        $script:releaseContent | Should -Match 'consumer_repo:'
        $script:releaseContent | Should -Match 'consumer_ref:'
        $script:releaseContent | Should -Match 'consumer_sha:'
    }

    It 'packages vipm-cli-machine module in installer staging' {
        $script:releaseContent | Should -Match 'Copy-Item -Path "\$env:GITHUB_WORKSPACE/vipm-cli-machine" -Destination "\$staging/vipm-cli-machine" -Recurse -Force'
    }

    It 'parity gate workflow validates required parity job names' {
        $script:parityContent | Should -Match 'Parity \(Linux Container\)'
        $script:parityContent | Should -Match 'Parity \(Self-Hosted Runner\)'
        $script:parityContent | Should -Match 'Parity \(Windows Container\)'
    }
}

