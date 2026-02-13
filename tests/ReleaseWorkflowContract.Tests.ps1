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

    It 'records skills parity gate evidence as primary release provenance' {
        $script:releaseContent | Should -Match 'skills_parity_gate_run_url:'
        $script:releaseContent | Should -Match 'skills_parity_gate_run_id:'
        $script:releaseContent | Should -Match 'skills_parity_gate_run_attempt:'
        $script:releaseContent | Should -Match 'skills_parity_enforcement_profile:'
        $script:releaseContent | Should -Match 'consumer_sandbox_checked_sha:'
        $script:releaseContent | Should -Match 'consumer_sandbox_evidence_artifact:'
        $script:releaseContent | Should -Match 'consumer_parity_run_url:'
        $script:releaseContent | Should -Match 'consumer_parity_run_id:'
        $script:releaseContent | Should -Match 'consumer_parity_head_sha:'
    }

    It 'packages vipm-cli-machine and linux-ppl-container-build modules in installer staging' {
        $script:releaseContent | Should -Match 'Copy-Item -Path "\$env:GITHUB_WORKSPACE/vipm-cli-machine" -Destination "\$staging/vipm-cli-machine" -Recurse -Force'
        $script:releaseContent | Should -Match 'Copy-Item -Path "\$env:GITHUB_WORKSPACE/linux-ppl-container-build" -Destination "\$staging/linux-ppl-container-build" -Recurse -Force'
    }

    It 'parity gate workflow validates required parity job names' {
        $script:parityContent | Should -Match 'Parity \(Linux Container\)'
        $script:parityContent | Should -Match 'Parity \(Self-Hosted Runner\)'
        $script:parityContent | Should -Match 'Parity \(Windows Container\)'
    }

    It 'parity gate workflow emits skills-run metadata outputs' {
        $script:parityContent | Should -Match 'consumer_sandbox_checked_sha:'
        $script:parityContent | Should -Match 'consumer_sandbox_evidence_artifact:'
        $script:parityContent | Should -Match 'gate_repo:'
        $script:parityContent | Should -Match 'gate_run_id:'
        $script:parityContent | Should -Match 'gate_run_url:'
        $script:parityContent | Should -Match 'gate_run_attempt:'
        $script:parityContent | Should -Match 'parity_enforcement_profile:'
    }

    It 'parity gate workflow adds sandbox preflight by cloned consumer sha' {
        $script:parityContent | Should -Match 'consumer-sandbox-preflight:'
        $script:parityContent | Should -Match 'Checkout consumer repository snapshot'
        $script:parityContent | Should -Match 'repository: \${{ inputs.consumer_repo }}'
        $script:parityContent | Should -Match 'ref: \${{ inputs.consumer_ref }}'
        $script:parityContent | Should -Match 'Sandbox preflight failed: checked out SHA'
        $script:parityContent | Should -Match 'missing \.lvversion'
        $script:parityContent | Should -Match 'Upload sandbox evidence artifact'
        $script:parityContent | Should -Match 'needs: \[consumer-sandbox-preflight\]'
    }

    It 'parity gate workflow applies upstream strict and fork container-only profiles' {
        $script:parityContent | Should -Match 'if \[\[ "\$PRECHECK_PROFILE" == "upstream-strict" \]\]'
        $script:parityContent | Should -Match 'parity_enforcement_profile="upstream-strict"'
        $script:parityContent | Should -Match 'parity_enforcement_profile="fork-container-only"'
        $script:parityContent | Should -Match 'if \[\[ "\$PRECHECK_PROFILE" == "fork-container-only" \]\]'
        $script:parityContent | Should -Match 'dispatch_run_self_hosted="false"'
    }
}
