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
    }

    It 'defines ordered contract-tests then windows or linux build jobs plus release-notes and VIPB prep then self-hosted package jobs' {
        $script:workflowContent | Should -Match 'contract-tests:'
        $script:workflowContent | Should -Match 'build-ppl-windows:'
        $script:workflowContent | Should -Match 'build-ppl-linux:'
        $script:workflowContent | Should -Match 'gather-release-notes:'
        $script:workflowContent | Should -Match 'prepare-vipb-linux:'
        $script:workflowContent | Should -Match 'build-vip-self-hosted:'
        $script:workflowContent | Should -Match 'build-ppl-windows:\s*[\s\S]*?runs-on:\s*windows-latest'
        $script:workflowContent | Should -Match 'build-ppl-windows:\s*[\s\S]*?needs:\s*\[contract-tests\]'
        $script:workflowContent | Should -Match 'build-ppl-linux:\s*[\s\S]*?needs:\s*\[contract-tests,\s*build-ppl-windows\]'
        $script:workflowContent | Should -Match 'gather-release-notes:\s*[\s\S]*?runs-on:\s*ubuntu-latest'
        $script:workflowContent | Should -Match 'gather-release-notes:\s*[\s\S]*?needs:\s*\[contract-tests\]'
        $script:workflowContent | Should -Match 'prepare-vipb-linux:\s*[\s\S]*?runs-on:\s*ubuntu-latest'
        $script:workflowContent | Should -Match 'prepare-vipb-linux:\s*[\s\S]*?needs:\s*\[contract-tests,\s*gather-release-notes\]'
        $script:workflowContent | Should -Match 'build-vip-self-hosted:\s*[\s\S]*?runs-on:\s*\[self-hosted,\s*windows,\s*self-hosted-windows-lv\]'
        $script:workflowContent | Should -Match 'build-vip-self-hosted:\s*[\s\S]*?needs:\s*\[build-ppl-windows,\s*build-ppl-linux,\s*prepare-vipb-linux\]'
    }

    It 'defines pinned consumer source and shared windows or linux build constants' {
        $script:workflowContent | Should -Match 'CONSUMER_REPO:\s*svelderrainruiz/labview-icon-editor'
        $script:workflowContent | Should -Match 'CONSUMER_REF:\s*patch/456-2020-migration-branch-from-9e46ecf'
        $script:workflowContent | Should -Match 'CONSUMER_EXPECTED_SHA:\s*9e46ecf591bc36afca8ddf4ce688a5f58604a12a'
        $script:workflowContent | Should -Match 'WINDOWS_LABVIEW_IMAGE:\s*nationalinstruments/labview:2026q1-windows'
        $script:workflowContent | Should -Match 'LINUX_LABVIEW_IMAGE:\s*nationalinstruments/labview:2026q1-linux-pwsh'
        $script:workflowContent | Should -Match 'WINDOWS_PPL_OUTPUT_PATH:\s*consumer/resource/plugins/lv_icon\.windows\.lvlibp'
        $script:workflowContent | Should -Match 'LINUX_PPL_OUTPUT_PATH:\s*consumer/resource/plugins/lv_icon\.linux\.lvlibp'
    }

    It 'checks out consumer and validates expected SHA in PPL, release-notes, and VIPB prep jobs' {
        ([regex]::Matches($script:workflowContent, 'Checkout consumer repository')).Count | Should -BeGreaterOrEqual 4
        ([regex]::Matches($script:workflowContent, 'Verify checked out consumer SHA')).Count | Should -BeGreaterOrEqual 4
        $script:workflowContent | Should -Match 'Consumer SHA mismatch'
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

    It 'builds windows PPL in windows container and uploads windows bundle artifact' {
        $script:workflowContent | Should -Match 'Build Windows PPL in NI Windows container'
        $script:workflowContent | Should -Match 'runlabview-windows\.ps1'
        $script:workflowContent | Should -Match 'Create Windows PPL bundle manifest'
        $script:workflowContent | Should -Match 'Upload Windows raw PPL artifact'
        $script:workflowContent | Should -Match 'docker-contract-ppl-windows-raw-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'docker-contract-ppl-bundle-windows-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'Upload Windows PPL bundle artifact'
    }

    It 'builds linux PPL with CRLF-safe temp copy and uploads linux bundle artifact' {
        $expectedSedNormalization = [regex]::Escape('sed -i ''s/\r$//'' "$script_file"')
        $script:workflowContent | Should -Match 'Build Linux PPL in NI Linux container'
        $script:workflowContent | Should -Match 'tmp_script_dir="\$\(mktemp -d\)"'
        $script:workflowContent | Should -Match 'cp -a "\$script_dir/\." "\$tmp_script_dir/"'
        $script:workflowContent | Should -Match $expectedSedNormalization
        $script:workflowContent | Should -Match '"\$tmp_script_dir/runlabview-linux\.sh"'
        $script:workflowContent | Should -Match 'Create Linux PPL bundle manifest'
        $script:workflowContent | Should -Match 'Upload Linux raw PPL artifact'
        $script:workflowContent | Should -Match 'docker-contract-ppl-linux-raw-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'docker-contract-ppl-bundle-linux-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'Upload Linux PPL bundle artifact'
    }

    It 'runs VIPB diagnostics suite on linux and emits summary plus artifact' {
        $script:workflowContent | Should -Match 'prepare-vipb-linux:'
        $script:workflowContent | Should -Match 'Run VIPB diagnostics suite'
        $script:workflowContent | Should -Match 'continue-on-error:\s*true'
        $script:workflowContent | Should -Match 'scripts/Invoke-PrepareVipbDiagnostics\.ps1'
        $script:workflowContent | Should -Match '-RepoRoot \(Join-Path \$env:GITHUB_WORKSPACE ''consumer''\)'
        $script:workflowContent | Should -Match 'Publish VIPB diagnostics summary'
        $script:workflowContent | Should -Match 'GITHUB_STEP_SUMMARY'
        $script:workflowContent | Should -Match 'vipb-diagnostics-summary\.md'
        $script:workflowContent | Should -Match 'Upload prepared VIPB artifact'
        $script:workflowContent | Should -Match 'Upload prepared VIPB artifact\s*[\s\S]*?if:\s*always\(\)'
        $script:workflowContent | Should -Match 'docker-contract-vipb-prepared-linux-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'Fail if VIPB diagnostics suite failed'
        $script:workflowContent | Should -Match 'prepare-vipb\.status\.json'
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
        $script:workflowContent | Should -Match 'Download Windows PPL bundle artifact'
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
