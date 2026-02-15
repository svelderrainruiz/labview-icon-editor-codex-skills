#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'LabVIEW parity workflow portability contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:workflowPath = Join-Path $script:repoRoot '.github/workflows/labview-parity.yml'
        if (-not (Test-Path -LiteralPath $script:workflowPath -PathType Leaf)) {
            throw "Workflow not found: $script:workflowPath"
        }

        $script:workflowContent = Get-Content -LiteralPath $script:workflowPath -Raw
    }

    It 'supports input-driven parity profile for dispatch and workflow_call' {
        $script:workflowContent | Should -Match 'parity_enforcement_profile:'
        $script:workflowContent | Should -Match 'workflow_dispatch:\s*[\s\S]*?parity_enforcement_profile:\s*[\s\S]*?default:\s*auto'
        $script:workflowContent | Should -Match 'workflow_call:\s*[\s\S]*?parity_enforcement_profile:\s*[\s\S]*?default:\s*auto'
        $script:workflowContent | Should -Match 'Expected strict\|container-only\|auto'
    }

    It 'removes owner-specific parity branching and maps auto via run_self_hosted' {
        $script:workflowContent | Should -Not -Match 'upstream-strict'
        $script:workflowContent | Should -Not -Match 'fork-container-only'
        $script:workflowContent | Should -Not -Match 'svelderrainruiz/labview-icon-editor'
        $script:workflowContent | Should -Match 'if \[\[ "\$requested_run_self_hosted" == "true"'
        $script:workflowContent | Should -Match 'parity_enforcement_profile="strict"'
        $script:workflowContent | Should -Match 'parity_enforcement_profile="container-only"'
    }

    It 'records selected profile in sandbox evidence payload' {
        $script:workflowContent | Should -Match 'parity_enforcement_profile_request'
        $script:workflowContent | Should -Match 'sandbox-contract-evidence\.json'
    }
}
