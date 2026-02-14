#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Docker contract CI workflow contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:workflowPath = Join-Path $script:repoRoot '.github/workflows/ci.yml'

        if (-not (Test-Path -Path $script:workflowPath -PathType Leaf)) {
            throw "Required workflow missing: $script:workflowPath"
        }

        $script:workflowContent = Get-Content -Path $script:workflowPath -Raw
    }

    It 'defines CI Pipeline workflow name and trigger path' {
        $script:workflowContent | Should -Match 'name:\s*CI Pipeline'
        $script:workflowContent | Should -Match '\.github/workflows/ci\.yml'
        $script:workflowContent | Should -Match '''profiles/\*\*'''
    }

    It 'supports reusable workflow_call with source project override inputs' {
        $script:workflowContent | Should -Match 'workflow_call:'
        $script:workflowContent | Should -Match 'source_project_repo:'
        $script:workflowContent | Should -Match 'source_project_ref:'
        $script:workflowContent | Should -Match 'source_project_sha:'
        $script:workflowContent | Should -Match 'workflow_call:\s*[\s\S]*?labview_profile:'
        $script:workflowContent | Should -Match 'CONSUMER_REPO:\s*\$\{\{\s*inputs\.source_project_repo'
        $script:workflowContent | Should -Match 'CONSUMER_REF:\s*\$\{\{\s*inputs\.source_project_ref'
        $script:workflowContent | Should -Match 'CONSUMER_EXPECTED_SHA:\s*\$\{\{\s*inputs\.source_project_sha'
    }

    It 'defines ordered contract-tests then windows or linux build jobs plus release-notes, profile resolution, and VIPB prep then self-hosted package jobs' {
        $script:workflowContent | Should -Match 'contract-tests:'
        $script:workflowContent | Should -Match 'build-x64-ppl-windows:'
        $script:workflowContent | Should -Match 'build-x64-ppl-linux:'
        $script:workflowContent | Should -Match 'gather-release-notes:'
        $script:workflowContent | Should -Match 'resolve-labview-profile:'
        $script:workflowContent | Should -Match 'prepare-vipb-linux:'
        $script:workflowContent | Should -Match 'build-vip-self-hosted:'
        $script:workflowContent | Should -Match 'build-x64-ppl-windows:\s*[\s\S]*?runs-on:\s*windows-latest'
        $script:workflowContent | Should -Match 'build-x64-ppl-windows:\s*[\s\S]*?needs:\s*\[contract-tests\]'
        $script:workflowContent | Should -Match 'build-x64-ppl-linux:\s*[\s\S]*?needs:\s*\[contract-tests,\s*build-x64-ppl-windows\]'
        $script:workflowContent | Should -Match 'gather-release-notes:\s*[\s\S]*?runs-on:\s*ubuntu-latest'
        $script:workflowContent | Should -Match 'gather-release-notes:\s*[\s\S]*?needs:\s*\[contract-tests\]'
        $script:workflowContent | Should -Match 'resolve-labview-profile:\s*[\s\S]*?runs-on:\s*ubuntu-latest'
        $script:workflowContent | Should -Match 'resolve-labview-profile:\s*[\s\S]*?needs:\s*\[contract-tests\]'
        $script:workflowContent | Should -Match 'prepare-vipb-linux:\s*[\s\S]*?runs-on:\s*ubuntu-latest'
        $script:workflowContent | Should -Match 'prepare-vipb-linux:\s*[\s\S]*?needs:\s*\[contract-tests,\s*gather-release-notes,\s*resolve-labview-profile\]'
        $script:workflowContent | Should -Match 'build-vip-self-hosted:\s*[\s\S]*?runs-on:\s*\[self-hosted,\s*windows,\s*self-hosted-windows-lv\]'
        $script:workflowContent | Should -Match 'build-vip-self-hosted:\s*[\s\S]*?needs:\s*\[build-x64-ppl-windows,\s*build-x64-ppl-linux,\s*prepare-vipb-linux\]'
    }

    It 'defines pinned source-project defaults and shared windows or linux build constants' {
        $script:workflowContent | Should -Match 'CONSUMER_REPO:\s*\$\{\{\s*inputs\.source_project_repo\s*\|\|\s*''svelderrainruiz/labview-icon-editor'''
        $script:workflowContent | Should -Match 'CONSUMER_REF:\s*\$\{\{\s*inputs\.source_project_ref\s*\|\|\s*''patch/456-2020-migration-branch-from-9e46ecf'''
        $script:workflowContent | Should -Match 'CONSUMER_EXPECTED_SHA:\s*\$\{\{\s*inputs\.source_project_sha\s*\|\|\s*''9e46ecf591bc36afca8ddf4ce688a5f58604a12a'''
        $script:workflowContent | Should -Match 'WINDOWS_LABVIEW_IMAGE:\s*nationalinstruments/labview:2026q1-windows'
        $script:workflowContent | Should -Match 'LINUX_LABVIEW_IMAGE:\s*nationalinstruments/labview:2026q1-linux-pwsh'
        $script:workflowContent | Should -Match 'WINDOWS_PPL_OUTPUT_PATH:\s*consumer/resource/plugins/lv_icon\.windows\.lvlibp'
        $script:workflowContent | Should -Match 'LINUX_PPL_OUTPUT_PATH:\s*consumer/resource/plugins/lv_icon\.linux\.lvlibp'
        $script:workflowContent | Should -Match 'LABVIEW_PROFILES_ROOT:\s*profiles/labview'
        $script:workflowContent | Should -Match 'DEFAULT_LABVIEW_PROFILE:\s*\$\{\{\s*inputs\.labview_profile\s*\|\|\s*''lv2026'''
    }

    It 'defines workflow_dispatch LabVIEW profile selector input' {
        $script:workflowContent | Should -Match 'workflow_dispatch:\s*[\s\S]*?inputs:'
        $script:workflowContent | Should -Match 'workflow_dispatch:\s*[\s\S]*?labview_profile:'
        $script:workflowContent | Should -Match 'labview_profile:\s*[\s\S]*?default:\s*''lv2026'''
    }

    It 'checks out consumer and validates expected SHA in PPL, release-notes, and VIPB prep jobs' {
        ([regex]::Matches($script:workflowContent, 'Checkout source project repository')).Count | Should -BeGreaterOrEqual 4
        ([regex]::Matches($script:workflowContent, 'Verify checked out source project SHA')).Count | Should -BeGreaterOrEqual 4
        $script:workflowContent | Should -Match 'Source project SHA mismatch'
    }

    It 'gathers release notes in a dedicated artifact job for VIPB prep consumption' {
        $script:workflowContent | Should -Match 'gather-release-notes:'
        $script:workflowContent | Should -Match 'Gather release notes artifact content'
        $script:workflowContent | Should -Match 'Upload release notes artifact'
        $script:workflowContent | Should -Match 'docker-contract-release-notes-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'Download release notes artifact'
        $script:workflowContent | Should -Match 'Install gathered release notes for VIPB preparation'
        $script:workflowContent | Should -Match 'release_notes\.md'
    }

    It 'resolves repo-owned LabVIEW target preset advisory and uploads resolution artifact' {
        $script:workflowContent | Should -Match 'resolve-labview-profile:'
        $script:workflowContent | Should -Match 'Resolve selected LabVIEW target preset id'
        $script:workflowContent | Should -Match 'scripts/Resolve-LabviewProfile\.ps1'
        $script:workflowContent | Should -Match '::warning title=LabVIEW target preset advisory mismatch::'
        $script:workflowContent | Should -Match '## LabVIEW Target Preset Advisory'
        $script:workflowContent | Should -Match 'Upload LabVIEW profile resolution artifact'
        $script:workflowContent | Should -Match 'docker-contract-labview-profile-resolution-\$\{\{\s*github\.run_id\s*\}\}'
    }

    It 'builds windows x64 PPL in windows container and uploads windows x64 bundle artifact' {
        $script:workflowContent | Should -Match 'Build Windows x64 PPL in NI Windows container'
        $script:workflowContent | Should -Match 'runlabview-windows\.ps1'
        $script:workflowContent | Should -Match 'Create Windows x64 PPL bundle manifest'
        $script:workflowContent | Should -Match 'Upload Windows raw x64 PPL artifact'
        $script:workflowContent | Should -Match 'docker-contract-ppl-windows-raw-x64-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'docker-contract-ppl-bundle-windows-x64-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'Upload Windows x64 PPL bundle artifact'
    }

    It 'builds linux x64 PPL with CRLF-safe temp copy and uploads linux x64 bundle artifact' {
        $expectedSedNormalization = [regex]::Escape('sed -i ''s/\r$//'' "$script_file"')
        $script:workflowContent | Should -Match 'Build Linux x64 PPL in NI Linux container'
        $script:workflowContent | Should -Match 'tmp_script_dir="\$\(mktemp -d\)"'
        $script:workflowContent | Should -Match 'cp -a "\$script_dir/\." "\$tmp_script_dir/"'
        $script:workflowContent | Should -Match $expectedSedNormalization
        $script:workflowContent | Should -Match '"\$tmp_script_dir/runlabview-linux\.sh"'
        $script:workflowContent | Should -Match 'Create Linux x64 PPL bundle manifest'
        $script:workflowContent | Should -Match 'Upload Linux raw x64 PPL artifact'
        $script:workflowContent | Should -Match 'docker-contract-ppl-linux-raw-x64-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'docker-contract-ppl-bundle-linux-x64-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'Upload Linux x64 PPL bundle artifact'
    }

    It 'runs VIPB diagnostics suite on linux and emits summary plus artifact' {
        $script:workflowContent | Should -Match 'prepare-vipb-linux:'
        $script:workflowContent | Should -Match 'Download LabVIEW target preset resolution artifact'
        $script:workflowContent | Should -Match 'docker-contract-labview-profile-resolution-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'Run VIPB diagnostics suite'
        $script:workflowContent | Should -Match 'continue-on-error:\s*true'
        $script:workflowContent | Should -Match 'scripts/Invoke-PrepareVipbDiagnostics\.ps1'
        $script:workflowContent | Should -Match '-RepoRoot \(Join-Path \$env:GITHUB_WORKSPACE ''consumer''\)'
        $script:workflowContent | Should -Match '-ProfileResolutionPath \(Join-Path \$env:RUNNER_TEMP ''labview-profile-resolution/profile-resolution\.json''\)'
        $script:workflowContent | Should -Match 'Publish VIPB diagnostics summary'
        $script:workflowContent | Should -Match 'GITHUB_STEP_SUMMARY'
        $script:workflowContent | Should -Match 'vipb-diagnostics-summary\.md'
        $script:workflowContent | Should -Match 'Upload prepared VIPB artifact'
        $script:workflowContent | Should -Match 'Upload prepared VIPB artifact\s*[\s\S]*?if:\s*always\(\)'
        $script:workflowContent | Should -Match 'docker-contract-vipb-prepared-linux-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'Fail if VIPB diagnostics suite failed'
        $script:workflowContent | Should -Match 'prepare-vipb\.status\.json'
        $script:workflowContent | Should -Match '::error title=VIPB diagnostics failed::'
        $script:workflowContent | Should -Match '::group::VIPB diagnostics failure context'
        $script:workflowContent | Should -Match 'prepare-vipb\.error\.json'
        $script:workflowContent | Should -Match 'vipb-diagnostics-summary\.md'
        $script:workflowContent | Should -Match 'status failed but error payload missing/unparseable'
    }

    It 'creates manifests for both windows and linux bundles' {
        ([regex]::Matches($script:workflowContent, 'scripts/New-PplBundleManifest\.ps1')).Count | Should -BeGreaterOrEqual 2
    }

    It 'defines self-hosted native package version constants using 0.1.0 baseline' {
        $script:workflowContent | Should -Match 'build-vip-self-hosted:\s*[\s\S]*?VERSION_MAJOR:\s*''0'''
        $script:workflowContent | Should -Match 'build-vip-self-hosted:\s*[\s\S]*?VERSION_MINOR:\s*''1'''
        $script:workflowContent | Should -Match 'build-vip-self-hosted:\s*[\s\S]*?VERSION_PATCH:\s*''0'''
        $script:workflowContent | Should -Match 'build-vip-self-hosted:\s*[\s\S]*?LVIE_RUNNER_CLI_SKIP_BUILD:\s*''1'''
        $script:workflowContent | Should -Match 'build-vip-self-hosted:\s*[\s\S]*?LVIE_RUNNER_CLI_SKIP_DOWNLOAD:\s*''1'''
    }

    It 'bootstraps worktree context in self-hosted lane' {
        $script:workflowContent | Should -Match 'Bootstrap worktree guard context'
        $script:workflowContent | Should -Match 'LVIE_WORKTREE_ROOT='
        $script:workflowContent | Should -Match 'LVIE_SKIP_WORKTREE_ROOT_CHECK=1'
    }

    It 'consumes windows x64 PPL and linux-prepared VIPB, then only builds native x86 in self-hosted lane' {
        $script:workflowContent | Should -Match 'Download Windows x64 PPL bundle artifact'
        $script:workflowContent | Should -Match 'Download prepared VIPB artifact'
        $script:workflowContent | Should -Match 'actions/download-artifact@v4'
        $script:workflowContent | Should -Match 'Consume prepared VIPB from Linux artifact'
        $script:workflowContent | Should -Match 'docker-contract-vipb-prepared-linux-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'NI Icon editor\.vipb'
        $script:workflowContent | Should -Match 'Consume Windows-built x64 PPL bundle'
        $script:workflowContent | Should -Match 'Invoke-PplBundleConsume\.ps1'
        $script:workflowContent | Should -Match 'lv_icon_x64\.lvlibp'
        $script:workflowContent | Should -Match 'Build native 32-bit PPL'
        $script:workflowContent | Should -Not -Match 'Build native 64-bit PPL'
        $script:workflowContent | Should -Not -Match 'Modify VIPB display info \(LV 64-bit\)'
        $script:workflowContent | Should -Match '-SupportedBitness 32'
        $script:workflowContent | Should -Match 'lv_icon_x86\.lvlibp'
    }

    It 'stamps 0.1.0 version in native build calls and uploads self-hosted VIP artifact' {
        $script:workflowContent | Should -Match 'BuildProjectSpec\.ps1'
        $script:workflowContent | Should -Match 'Upload consumed VIPB \(post-mortem\)'
        $script:workflowContent | Should -Match 'docker-contract-vipb-modified-self-hosted-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'Invoke-VipBuild\.ps1'
        $script:workflowContent | Should -Match '-Major \$env:VERSION_MAJOR'
        $script:workflowContent | Should -Match '-Minor \$env:VERSION_MINOR'
        $script:workflowContent | Should -Match '-Patch \$env:VERSION_PATCH'
        $script:workflowContent | Should -Match 'docker-contract-vip-package-self-hosted-\$\{\{\s*github\.run_id\s*\}\}'
    }
}

