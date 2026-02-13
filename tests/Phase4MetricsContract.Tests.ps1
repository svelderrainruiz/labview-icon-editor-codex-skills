#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Phase 4 metrics scaffold contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:governanceRoot = Join-Path $script:repoRoot 'docs/release-governance'
        $script:metricsContractPath = Join-Path $script:governanceRoot 'metrics-loop.contract.json'
        $script:metricsRunbookPath = Join-Path $script:governanceRoot 'metrics-review-runbook.md'
        $script:metricsSchemaPath = Join-Path $script:repoRoot 'schemas/release-metrics.schema.json'
        $script:metricsScriptPath = Join-Path $script:repoRoot 'scripts/Invoke-ReleaseMetricsSnapshot.ps1'

        foreach ($path in @($script:metricsContractPath, $script:metricsRunbookPath, $script:metricsSchemaPath, $script:metricsScriptPath)) {
            if (-not (Test-Path -Path $path -PathType Leaf)) {
                throw "Phase 4 artifact missing: $path"
            }
        }

        $script:metricsContract = Get-Content -Raw -Path $script:metricsContractPath | ConvertFrom-Json -ErrorAction Stop
        $script:metricsSchema = Get-Content -Raw -Path $script:metricsSchemaPath | ConvertFrom-Json -ErrorAction Stop
        $script:metricsRunbook = Get-Content -Raw -Path $script:metricsRunbookPath
        $script:metricsScript = Get-Content -Raw -Path $script:metricsScriptPath
    }

    It 'defines required metrics and gate outcomes in the contract' {
        $script:metricsContract.required_metrics | Should -Contain 'gate_outcome'
        $script:metricsContract.required_metrics | Should -Contain 'rollback_triggered'
        $script:metricsContract.required_metrics | Should -Contain 'missing_required_artifact_count'
        $script:metricsContract.gate_outcomes | Should -Contain 'go'
        $script:metricsContract.gate_outcomes | Should -Contain 'no-go'
    }

    It 'defines release metrics schema fields for gate and failures' {
        $script:metricsSchema.required | Should -Contain 'gate_outcome'
        $script:metricsSchema.required | Should -Contain 'failed_job_count'
        $script:metricsSchema.required | Should -Contain 'top_failure_causes'
        $script:metricsSchema.properties.PSObject.Properties.Name | Should -Contain 'rollback_triggered'
    }

    It 'includes review and improvement sections in the runbook' {
        $script:metricsRunbook | Should -Match '(?m)^## Collection\s*$'
        $script:metricsRunbook | Should -Match '(?m)^## Weekly Review\s*$'
        $script:metricsRunbook | Should -Match '(?m)^## Continuous Improvement Actions\s*$'
    }

    It 'wires collection script to emit release-metrics JSON snapshots' {
        $script:metricsScript | Should -Match 'release-metrics-\{0\}\.json'
        $script:metricsScript | Should -Match 'schema_version\s*=\s*''1\.0'''
        $script:metricsScript | Should -Match 'gate_outcome\s*=\s*\$gateOutcome'
    }
}