#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Windows->Linux VIPM package workflow contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:workflowPath = Join-Path $script:repoRoot '.github/workflows/windows-linux-vipm-package.yml'
        $script:newManifestScriptPath = Join-Path $script:repoRoot 'scripts/New-PplBundleManifest.ps1'
        $script:consumeScriptPath = Join-Path $script:repoRoot 'scripts/Invoke-PplBundleConsume.ps1'

        foreach ($requiredPath in @($script:workflowPath, $script:newManifestScriptPath, $script:consumeScriptPath)) {
            if (-not (Test-Path -Path $requiredPath -PathType Leaf)) {
                throw "Required file missing: $requiredPath"
            }
        }

        $script:workflowContent = Get-Content -Raw -Path $script:workflowPath
    }

    It 'defines parallel Windows and Linux PPL producers plus Linux consumer job' {
        $script:workflowContent | Should -Match 'build-ppl-windows:'
        $script:workflowContent | Should -Match 'build-ppl-linux:'
        $script:workflowContent | Should -Match 'package-vip-linux:'
        $script:workflowContent | Should -Match 'needs:\s*\[build-ppl-windows,\s*build-ppl-linux\]'
        $script:workflowContent | Should -Match 'consumer_repo:'
        $script:workflowContent | Should -Match 'consumer_ref:'
        $script:workflowContent | Should -Match 'ppl_build_lane:'
    }

    It 'creates and uploads Windows and Linux PPL handoff bundles' {
        $script:workflowContent | Should -Match 'Checkout consumer repository'
        $script:workflowContent | Should -Match 'runlabview-windows\.ps1'
        $script:workflowContent | Should -Match 'runlabview-linux\.sh'
        $script:workflowContent | Should -Match 'Create Windows PPL handoff bundle'
        $script:workflowContent | Should -Match 'Create Linux PPL handoff bundle'
        $script:workflowContent | Should -Match 'scripts/New-PplBundleManifest\.ps1'
        $script:workflowContent | Should -Match 'Upload Windows PPL handoff artifact'
        $script:workflowContent | Should -Match 'Upload Linux PPL handoff artifact'
    }

    It 'runs linux parity scripts from a CRLF-safe temp copy inside containers' {
        $expectedSedNormalization = [regex]::Escape('sed -i ''s/\r$//'' "$script_file"')
        $script:workflowContent | Should -Match 'tmp_script_dir="\$\(mktemp -d\)"'
        $script:workflowContent | Should -Match 'cp -a "\$script_dir/\." "\$tmp_script_dir/"'
        $script:workflowContent | Should -Match $expectedSedNormalization
        $script:workflowContent | Should -Match '"\$tmp_script_dir/runlabview-linux\.sh"'
    }

    It 'verifies and consumes both PPL bundles on Linux before VIPM build' {
        $script:workflowContent | Should -Match 'Download Windows PPL handoff artifact'
        $script:workflowContent | Should -Match 'Download Linux PPL handoff artifact'
        $script:workflowContent | Should -Match 'scripts/Invoke-PplBundleConsume\.ps1'
        $script:workflowContent | Should -Match 'Verify and install Windows-built PPL for Linux packaging'
        $script:workflowContent | Should -Match 'Verify and install Linux-built PPL for Linux packaging'
        $script:workflowContent | Should -Match 'ExpectedSha256'
        $script:workflowContent | Should -Match 'vipm build'
    }

    It 'fails when vipm is unavailable and uploads package artifacts when present' {
        $script:workflowContent | Should -Match 'vipm is not available on PATH inside Linux image'
        $script:workflowContent | Should -Match 'vipm help preview \(first 20 lines\):'
        $script:workflowContent | Should -Match 'vipm help 2>&1 \|\| vipm --help 2>&1'
        $script:workflowContent | Should -Match 'Upload VI Package artifacts'
    }
}
