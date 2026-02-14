#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Release workflow contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:releaseWorkflowPath = Join-Path $script:repoRoot '.github/workflows/release-skill-layer.yml'
        $script:ciWorkflowPath = Join-Path $script:repoRoot '.github/workflows/ci.yml'

        foreach ($path in @($script:releaseWorkflowPath, $script:ciWorkflowPath)) {
            if (-not (Test-Path -Path $path -PathType Leaf)) {
                throw "Required workflow missing: $path"
            }
        }

        $script:releaseContent = Get-Content -Path $script:releaseWorkflowPath -Raw
        $script:ciContent = Get-Content -Path $script:ciWorkflowPath -Raw
    }

    It 'keeps release workflow dispatch-only and CI-gated via reusable ci.yml' {
        $script:releaseContent | Should -Match 'on:\s*workflow_dispatch:'
        $script:releaseContent | Should -Match 'ci-gate:'
        $script:releaseContent | Should -Match 'uses:\s+\./\.github/workflows/ci\.yml'
        $script:releaseContent | Should -Match 'package:\s*\r?\n\s*needs:\s*\[ci-gate\]'
        $script:releaseContent | Should -Not -Match 'parity-gate:'
    }

    It 'keeps explicit source project pin inputs and compatibility inputs' {
        $script:releaseContent | Should -Match 'release_tag:'
        $script:releaseContent | Should -Match 'consumer_repo:'
        $script:releaseContent | Should -Match 'consumer_ref:'
        $script:releaseContent | Should -Match 'consumer_sha:'
        $script:releaseContent | Should -Match 'run_self_hosted:'
        $script:releaseContent | Should -Match 'run_build_spec:'
        $script:releaseContent | Should -Match '\(Deprecated\) retained for dispatch compatibility'
        $script:releaseContent | Should -Match 'labview_profile:'
    }

    It 'passes source project pin inputs into reusable CI gate' {
        $script:releaseContent | Should -Match 'source_project_repo:\s*\$\{\{ inputs\.consumer_repo \}\}'
        $script:releaseContent | Should -Match 'source_project_ref:\s*\$\{\{ inputs\.consumer_ref \}\}'
        $script:releaseContent | Should -Match 'source_project_sha:\s*\$\{\{ inputs\.consumer_sha \}\}'
        $script:releaseContent | Should -Match 'labview_profile:\s*\$\{\{ inputs\.labview_profile \}\}'
    }

    It 'packages vipm-cli-machine and linux-ppl-container-build modules in installer staging' {
        $script:releaseContent | Should -Match 'Copy-Item -Path "\$env:GITHUB_WORKSPACE/vipm-cli-machine" -Destination "\$staging/vipm-cli-machine" -Recurse -Force'
        $script:releaseContent | Should -Match 'Copy-Item -Path "\$env:GITHUB_WORKSPACE/linux-ppl-container-build" -Destination "\$staging/linux-ppl-container-build" -Recurse -Force'
    }

    It 'publishes release assets from CI artifacts plus installer' {
        $script:releaseContent | Should -Match 'publish-release-assets:'
        $script:releaseContent | Should -Match 'needs:\s*\[ci-gate,\s*package\]'
        $script:releaseContent | Should -Match 'Download installer artifact'
        $script:releaseContent | Should -Match 'pattern:\s*docker-contract-ppl-bundle-windows-x64-\*'
        $script:releaseContent | Should -Match 'pattern:\s*docker-contract-ppl-bundle-linux-x64-\*'
        $script:releaseContent | Should -Match 'pattern:\s*docker-contract-vip-package-self-hosted-\*'
        $script:releaseContent | Should -Match 'lvie-ppl-bundle-windows-x64\.zip'
        $script:releaseContent | Should -Match 'lvie-ppl-bundle-linux-x64\.zip'
        $script:releaseContent | Should -Match 'lvie-vip-package-self-hosted\.zip'
        $script:releaseContent | Should -Match 'release-provenance\.json'
        $script:releaseContent | Should -Match 'release-payload-manifest\.json'
        $script:releaseContent | Should -Match 'New-ReleasePayloadManifest\.ps1'
        $script:releaseContent | Should -Match 'schemas/release-payload-contract\.schema\.json'
        $script:releaseContent | Should -Match 'gh release upload'
        $script:releaseContent | Should -Match 'gh release create'
    }

    It 'records CI-based release provenance fields in release notes content' {
        $script:releaseContent | Should -Match 'skills_ci_repo:'
        $script:releaseContent | Should -Match 'skills_ci_run_url:'
        $script:releaseContent | Should -Match 'skills_ci_run_id:'
        $script:releaseContent | Should -Match 'skills_ci_run_attempt:'
        $script:releaseContent | Should -Match 'source_project_repo:'
        $script:releaseContent | Should -Match 'source_project_ref:'
        $script:releaseContent | Should -Match 'source_project_sha:'
    }

    It 'exposes reusable ci.yml source project override inputs' {
        $script:ciContent | Should -Match 'workflow_call:'
        $script:ciContent | Should -Match 'source_project_repo:'
        $script:ciContent | Should -Match 'source_project_ref:'
        $script:ciContent | Should -Match 'source_project_sha:'
        $script:ciContent | Should -Match 'labview_profile:'
    }
}

