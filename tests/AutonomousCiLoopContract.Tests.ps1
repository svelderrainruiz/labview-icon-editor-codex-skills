#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Autonomous CI loop contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:loopPath = Join-Path $script:repoRoot 'scripts/Invoke-AutonomousCiLoop.ps1'

        if (-not (Test-Path -Path $script:loopPath -PathType Leaf)) {
            throw "Autonomous loop script not found: $script:loopPath"
        }

        $script:loopContent = Get-Content -Raw -Path $script:loopPath
    }

    It 'includes robust dispatched-run correlation helper' {
        $script:loopContent | Should -Match 'function\s+Resolve-DispatchedRunMeta'
        $script:loopContent | Should -Match "--limit',\s*'20'"
        $script:loopContent | Should -Match '\$event\s*-ne\s*''workflow_dispatch'''
    }

    It 'records expected and actual run head SHA in cycle logs' {
        $script:loopContent | Should -Match 'head_sha_expected'
        $script:loopContent | Should -Match 'head_sha_actual'
        $script:loopContent | Should -Match 'record\.workflow_run\.head_sha_expected'
        $script:loopContent | Should -Match 'record\.workflow_run\.head_sha_actual'
    }

    It 'defaults consumer_ref to develop when input is not explicitly provided' {
        $script:loopContent | Should -Match 'hasConsumerRefInput'
        $script:loopContent | Should -Match '\$key\s*-eq\s*''consumer_ref'''
        $script:loopContent | Should -Match '\$normalizedWorkflowInputs\s*\+=\s*''consumer_ref=develop'''
    }
}
