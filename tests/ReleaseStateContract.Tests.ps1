#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Release state Phase 2 contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:releaseStateSchemaPath = Join-Path $script:repoRoot 'schemas/release-state.schema.json'
        $script:dispatchResultSchemaPath = Join-Path $script:repoRoot 'schemas/dispatch-result.schema.json'
        $script:watcherPath = Join-Path $script:repoRoot 'scripts/Watch-RunAndUpdatePlan.ps1'
        $script:orchestratorPath = Join-Path $script:repoRoot 'scripts/Invoke-ReleaseOrchestrator.ps1'

        foreach ($path in @($script:releaseStateSchemaPath, $script:dispatchResultSchemaPath, $script:watcherPath, $script:orchestratorPath)) {
            if (-not (Test-Path -Path $path -PathType Leaf)) {
                throw "Required phase-2 artifact missing: $path"
            }
        }

        $script:releaseStateSchema = Get-Content -Raw -Path $script:releaseStateSchemaPath | ConvertFrom-Json -ErrorAction Stop
        $script:dispatchResultSchema = Get-Content -Raw -Path $script:dispatchResultSchemaPath | ConvertFrom-Json -ErrorAction Stop
        $script:watcherContent = Get-Content -Raw -Path $script:watcherPath
        $script:orchestratorContent = Get-Content -Raw -Path $script:orchestratorPath
    }

    It 'defines release-state schema with gate and go-eligibility fields' {
        $script:releaseStateSchema.required | Should -Contain 'gate'
        $script:releaseStateSchema.required | Should -Contain 'is_go_eligible'
        $script:releaseStateSchema.properties.PSObject.Properties.Name | Should -Contain 'required_artifacts'
        $script:releaseStateSchema.properties.PSObject.Properties.Name | Should -Contain 'missing_required_artifacts'
    }

    It 'defines dispatch-result schema for no-go, dry-run, and dispatched statuses' {
        $script:dispatchResultSchema.properties.status.enum | Should -Contain 'no-go'
        $script:dispatchResultSchema.properties.status.enum | Should -Contain 'go-dry-run'
        $script:dispatchResultSchema.properties.status.enum | Should -Contain 'dispatched'
        $script:dispatchResultSchema.properties.PSObject.Properties.Name | Should -Contain 'release_state_path'
    }

    It 'wires watcher script to optional StatePath emission' {
        $script:watcherContent | Should -Match '\[string\]\$StatePath'
        $script:watcherContent | Should -Match 'schema_version\s*=\s*''1\.0'''
        $script:watcherContent | Should -Match 'is_go_eligible\s*=\s*\$isGo'
    }

    It 'wires orchestrator to pass state path and emit dispatch result' {
        $script:orchestratorContent | Should -Match '-StatePath\s+\$releaseStatePath'
        $script:orchestratorContent | Should -Match 'dispatch-result-\{0\}\.json'
        $script:orchestratorContent | Should -Match 'Write-DispatchResult'
    }
}
