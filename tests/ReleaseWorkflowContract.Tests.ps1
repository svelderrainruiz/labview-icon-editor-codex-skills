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

    It 'supports push-to-main auto release and workflow_dispatch overrides via resolver plus reusable CI gate' {
        $script:releaseContent | Should -Match 'on:\s*[\s\S]*?push:\s*[\s\S]*?branches:\s*[\s\S]*?- main'
        $script:releaseContent | Should -Match 'on:\s*[\s\S]*?workflow_dispatch:'
        $script:releaseContent | Should -Match 'resolve-release-context:'
        $script:releaseContent | Should -Match 'should_release:\s*\$\{\{\s*steps\.resolve\.outputs\.should_release\s*\}\}'
        $script:releaseContent | Should -Match 'skip_reason:\s*\$\{\{\s*steps\.resolve\.outputs\.skip_reason\s*\}\}'
        $script:releaseContent | Should -Match 'ci-gate:'
        $script:releaseContent | Should -Match 'ci-gate:\s*[\s\S]*?needs:\s*\[resolve-release-context\]'
        $script:releaseContent | Should -Match "ci-gate:\s*[\s\S]*?if:\s*\$\{\{\s*needs\.resolve-release-context\.outputs\.should_release == 'true'\s*\}\}"
        $script:releaseContent | Should -Match 'uses:\s+\./\.github/workflows/ci\.yml'
        $script:releaseContent | Should -Match 'package:\s*[\s\S]*?needs:\s*\[resolve-release-context,\s*ci-gate\]'
        $script:releaseContent | Should -Match "package:\s*[\s\S]*?if:\s*\$\{\{\s*needs\.resolve-release-context\.outputs\.should_release == 'true'\s*\}\}"
        $script:releaseContent | Should -Match 'publish-release-assets:\s*[\s\S]*?needs:\s*\[resolve-release-context,\s*ci-gate,\s*package\]'
        $script:releaseContent | Should -Match "publish-release-assets:\s*[\s\S]*?if:\s*\$\{\{\s*needs\.resolve-release-context\.outputs\.should_release == 'true'\s*\}\}"
        $script:releaseContent | Should -Match 'release-skipped:'
        $script:releaseContent | Should -Match "release-skipped:\s*[\s\S]*?if:\s*\$\{\{\s*needs\.resolve-release-context\.outputs\.should_release != 'true'\s*\}\}"
        $script:releaseContent | Should -Not -Match 'parity-gate:'
    }

    It 'keeps explicit source project pin inputs, variable-ready dispatch defaults, and compatibility inputs' {
        $script:releaseContent | Should -Match 'release_tag:'
        $script:releaseContent | Should -Match 'consumer_repo:'
        $script:releaseContent | Should -Match 'consumer_ref:'
        $script:releaseContent | Should -Match 'consumer_sha:'
        $script:releaseContent | Should -Match 'consumer_repo:\s*[\s\S]*?required:\s*false'
        $script:releaseContent | Should -Match "consumer_repo:\s*[\s\S]*?default:\s*''"
        $script:releaseContent | Should -Match 'consumer_ref:\s*[\s\S]*?required:\s*false'
        $script:releaseContent | Should -Match "consumer_ref:\s*[\s\S]*?default:\s*''"
        $script:releaseContent | Should -Match 'consumer_sha:\s*[\s\S]*?required:\s*false'
        $script:releaseContent | Should -Match "consumer_sha:\s*[\s\S]*?default:\s*''"
        $script:releaseContent | Should -Match 'run_self_hosted:'
        $script:releaseContent | Should -Match 'run_build_spec:'
        $script:releaseContent | Should -Match '\(Deprecated\) retained for dispatch compatibility'
        $script:releaseContent | Should -Match 'labview_profile:'
        $script:releaseContent | Should -Match 'source_labview_version_override:'
        $script:releaseContent | Should -Match 'run_lv2020_edge_smoke:'
    }

    It 'resolves source project target from inputs then repository variables with strict SHA requirement' {
        $script:releaseContent | Should -Match 'VAR_SOURCE_PROJECT_REPO:\s*\$\{\{\s*vars\.LVIE_SOURCE_PROJECT_REPO'
        $script:releaseContent | Should -Match 'VAR_SOURCE_PROJECT_REF:\s*\$\{\{\s*vars\.LVIE_SOURCE_PROJECT_REF'
        $script:releaseContent | Should -Match 'VAR_SOURCE_PROJECT_SHA:\s*\$\{\{\s*vars\.LVIE_SOURCE_PROJECT_SHA'
        $script:releaseContent | Should -Match 'VAR_LABVIEW_PROFILE:\s*\$\{\{\s*vars\.LVIE_LABVIEW_PROFILE'
        $script:releaseContent | Should -Match '\{0\}/labview-icon-editor''\s*-f\s*\[string\]\$env:GITHUB_REPOSITORY_OWNER'
        $script:releaseContent | Should -Match 'Strict pin is required; set workflow input ''consumer_sha'' or repository variable ''LVIE_SOURCE_PROJECT_SHA'''
        $script:releaseContent | Should -Not -Match 'Get-CiDefaultValue'
    }

    It 'passes source project pin values into reusable CI gate via resolver outputs' {
        $script:releaseContent | Should -Match 'source_project_repo:\s*\$\{\{\s*needs\.resolve-release-context\.outputs\.consumer_repo\s*\}\}'
        $script:releaseContent | Should -Match 'source_project_ref:\s*\$\{\{\s*needs\.resolve-release-context\.outputs\.consumer_ref\s*\}\}'
        $script:releaseContent | Should -Match 'source_project_sha:\s*\$\{\{\s*needs\.resolve-release-context\.outputs\.consumer_sha\s*\}\}'
        $script:releaseContent | Should -Match 'labview_profile:\s*\$\{\{\s*needs\.resolve-release-context\.outputs\.labview_profile\s*\}\}'
        $script:releaseContent | Should -Match 'source_labview_version_override:\s*\$\{\{\s*needs\.resolve-release-context\.outputs\.source_labview_version_override\s*\}\}'
        $script:releaseContent | Should -Match 'run_lv2020_edge_smoke:\s*\$\{\{\s*needs\.resolve-release-context\.outputs\.run_lv2020_edge_smoke\s*\}\}'
    }

    It 'implements version-gated auto-release skip when tag already exists on push' {
        $script:releaseContent | Should -Match 'if\s*\(\$isPushMain -and \$tagExists\)\s*\{\s*\$shouldRelease = ''false''\s*\r?\n\s*\$skipReason = ''tag_exists'''
        $script:releaseContent | Should -Match 'repos/\$env:GITHUB_REPOSITORY/git/ref/tags/'
        $script:releaseContent | Should -Match '\$tagProbeExitCode = \$LASTEXITCODE'
        $script:releaseContent | Should -Match '\$global:LASTEXITCODE = 0'
        $script:releaseContent | Should -Match "release-skipped:\s*[\s\S]*?if:\s*\$\{\{\s*needs\.resolve-release-context\.outputs\.should_release != 'true'\s*\}\}"
    }

    It 'packages vipm-cli-machine and linux-ppl-container-build modules in installer staging' {
        $script:releaseContent | Should -Match 'Copy-Item -Path "\$env:GITHUB_WORKSPACE/vipm-cli-machine" -Destination "\$staging/vipm-cli-machine" -Recurse -Force'
        $script:releaseContent | Should -Match 'Copy-Item -Path "\$env:GITHUB_WORKSPACE/linux-ppl-container-build" -Destination "\$staging/linux-ppl-container-build" -Recurse -Force'
    }

    It 'publishes release assets from CI artifacts plus installer' {
        $script:releaseContent | Should -Match 'publish-release-assets:'
        $script:releaseContent | Should -Match 'needs:\s*\[resolve-release-context,\s*ci-gate,\s*package\]'
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

    It 'exposes reusable ci.yml source project override inputs and portability variable chain' {
        $script:ciContent | Should -Match 'workflow_call:'
        $script:ciContent | Should -Match 'source_project_repo:'
        $script:ciContent | Should -Match 'source_project_ref:'
        $script:ciContent | Should -Match 'source_project_sha:'
        $script:ciContent | Should -Match 'labview_profile:'
        $script:ciContent | Should -Match 'source_labview_version_override:'
        $script:ciContent | Should -Match 'run_lv2020_edge_smoke:'
        $script:ciContent | Should -Match 'vars\.LVIE_SOURCE_PROJECT_REPO'
        $script:ciContent | Should -Match 'vars\.LVIE_SOURCE_PROJECT_REF'
        $script:ciContent | Should -Match 'vars\.LVIE_SOURCE_PROJECT_SHA'
        $script:ciContent | Should -Match 'format\(''\{0\}/labview-icon-editor'',\s*github\.repository_owner\)'
    }
}

