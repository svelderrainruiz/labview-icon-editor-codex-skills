#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Docker contract CI workflow contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:workflowPath = Join-Path $script:repoRoot '.github/workflows/docker-contract-ci.yml'

        if (-not (Test-Path -Path $script:workflowPath -PathType Leaf)) {
            throw "Required workflow missing: $script:workflowPath"
        }

        $script:workflowContent = Get-Content -Path $script:workflowPath -Raw
    }

    It 'defines ordered contract-tests then windows then linux PPL jobs' {
        $script:workflowContent | Should -Match 'contract-tests:'
        $script:workflowContent | Should -Match 'build-ppl-windows:'
        $script:workflowContent | Should -Match 'build-ppl-linux:'
        $script:workflowContent | Should -Match 'build-ppl-windows:\s*[\s\S]*?runs-on:\s*windows-latest'
        $script:workflowContent | Should -Match 'build-ppl-windows:\s*[\s\S]*?needs:\s*\[contract-tests\]'
        $script:workflowContent | Should -Match 'build-ppl-linux:\s*[\s\S]*?needs:\s*\[contract-tests,\s*build-ppl-windows\]'
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

    It 'checks out consumer and validates expected SHA in both PPL build jobs' {
        ([regex]::Matches($script:workflowContent, 'Checkout consumer repository')).Count | Should -BeGreaterOrEqual 2
        ([regex]::Matches($script:workflowContent, 'Verify checked out consumer SHA')).Count | Should -BeGreaterOrEqual 2
        $script:workflowContent | Should -Match 'Consumer SHA mismatch'
    }

    It 'builds windows PPL in windows container and uploads windows bundle artifact' {
        $script:workflowContent | Should -Match 'Build Windows PPL in NI Windows container'
        $script:workflowContent | Should -Match 'runlabview-windows\.ps1'
        $script:workflowContent | Should -Match 'Create Windows PPL bundle manifest'
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
        $script:workflowContent | Should -Match 'docker-contract-ppl-bundle-linux-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'Upload Linux PPL bundle artifact'
    }

    It 'creates manifests for both windows and linux bundles' {
        ([regex]::Matches($script:workflowContent, 'scripts/New-PplBundleManifest\.ps1')).Count | Should -BeGreaterOrEqual 2
    }
}
