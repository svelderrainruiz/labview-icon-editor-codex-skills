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

    It 'defines Windows producer and Linux consumer jobs' {
        $script:workflowContent | Should -Match 'build-ppl-windows:'
        $script:workflowContent | Should -Match 'package-vip-linux:'
        $script:workflowContent | Should -Match 'needs:\s*\[build-ppl-windows\]'
        $script:workflowContent | Should -Match 'consumer_repo:'
        $script:workflowContent | Should -Match 'consumer_ref:'
        $script:workflowContent | Should -Match 'ppl_build_lane:'
    }

    It 'creates and uploads a PPL handoff bundle from Windows' {
        $script:workflowContent | Should -Match 'Checkout consumer repository'
        $script:workflowContent | Should -Match 'runlabview-windows\.ps1'
        $script:workflowContent | Should -Match 'runlabview-linux\.sh'
        $script:workflowContent | Should -Match 'Create PPL handoff bundle'
        $script:workflowContent | Should -Match 'scripts/New-PplBundleManifest\.ps1'
        $script:workflowContent | Should -Match 'Upload PPL handoff artifact'
    }

    It 'verifies and consumes the Windows-built PPL on Linux before VIPM build' {
        $script:workflowContent | Should -Match 'scripts/Invoke-PplBundleConsume\.ps1'
        $script:workflowContent | Should -Match 'ExpectedSha256'
        $script:workflowContent | Should -Match 'vipm build'
    }

    It 'fails when vipm is unavailable and uploads package artifacts when present' {
        $script:workflowContent | Should -Match 'vipm is not available on PATH inside Linux image'
        $script:workflowContent | Should -Match 'Upload VI Package artifacts'
    }
}
