#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Phase 3 governance scaffolding contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:governanceRoot = Join-Path $script:repoRoot 'docs/release-governance'

        if (-not (Test-Path -Path $script:governanceRoot -PathType Container)) {
            throw "Governance docs folder not found: $script:governanceRoot"
        }

        $script:promotionPath = Join-Path $script:governanceRoot 'promotion-policy.contract.json'
        $script:rollbackContractPath = Join-Path $script:governanceRoot 'rollback-trigger.contract.json'
        $script:rollbackRunbookPath = Join-Path $script:governanceRoot 'rollback-runbook.md'
        $script:provenanceChecklistPath = Join-Path $script:governanceRoot 'provenance-bundle-checklist.md'

        foreach ($path in @($script:promotionPath, $script:rollbackContractPath, $script:rollbackRunbookPath, $script:provenanceChecklistPath)) {
            if (-not (Test-Path -Path $path -PathType Leaf)) {
                throw "Phase 3 artifact missing: $path"
            }
        }

        $script:promotion = Get-Content -Raw -Path $script:promotionPath | ConvertFrom-Json -ErrorAction Stop
        $script:rollback = Get-Content -Raw -Path $script:rollbackContractPath | ConvertFrom-Json -ErrorAction Stop
        $script:runbook = Get-Content -Raw -Path $script:rollbackRunbookPath
        $script:checklist = Get-Content -Raw -Path $script:provenanceChecklistPath
    }

    It 'defines promotion lanes for canary and stable' {
        $script:promotion.lanes.name | Should -Contain 'canary'
        $script:promotion.lanes.name | Should -Contain 'stable'
    }

    It 'defines rollback triggers with required evidence fields' {
        $script:rollback.triggers.id | Should -Contain 'parity-gate-failure'
        $script:rollback.triggers.id | Should -Contain 'missing-provenance'
        $script:rollback.triggers.id | Should -Contain 'artifact-integrity-failure'

        foreach ($field in @('rollback reason', 'impacted release tag', 'replacement release tag', 'operator', 'timestamp_utc')) {
            $script:rollback.required_rollback_evidence | Should -Contain $field
        }
    }

    It 'includes rollback procedure and post-rollback validation sections' {
        $script:runbook | Should -Match '(?m)^## Rollback Procedure\s*$'
        $script:runbook | Should -Match '(?m)^## Post-Rollback Validation\s*$'
        $script:runbook | Should -Match '(?m)^## Escalation\s*$'
    }

    It 'includes required provenance bundle checklist fields' {
        foreach ($field in @(
            'skills_parity_gate_repo',
            'skills_parity_gate_run_url',
            'skills_parity_gate_run_id',
            'skills_parity_gate_run_attempt',
            'skills_parity_enforcement_profile',
            'consumer_repo',
            'consumer_ref',
            'consumer_sha',
            'consumer_sandbox_checked_sha',
            'consumer_sandbox_evidence_artifact',
            'consumer_parity_run_url',
            'consumer_parity_run_id',
            'consumer_parity_head_sha'
        )) {
            $script:checklist | Should -Match ([regex]::Escape($field))
        }
    }
}
