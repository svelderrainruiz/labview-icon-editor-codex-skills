#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Agent docs contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:agentsRoot = Join-Path $script:repoRoot 'docs/agents'

        if (-not (Test-Path -Path $script:agentsRoot -PathType Container)) {
            throw "Agents docs folder not found: $script:agentsRoot"
        }

        $script:requiredDocs = @(
            'quickstart.md',
            'release-gates.md',
            'ci-catalog.md',
            'change-log.md'
        )

        $script:docs = @{}
        foreach ($fileName in $script:requiredDocs) {
            $path = Join-Path $script:agentsRoot $fileName
            if (-not (Test-Path -Path $path -PathType Leaf)) {
                throw "Required agent doc missing: $path"
            }

            $script:docs[$fileName] = Get-Content -Raw -Path $path
        }
    }

    It 'contains all required docs in docs/agents' {
        foreach ($fileName in $script:requiredDocs) {
            $path = Join-Path $script:agentsRoot $fileName
            Test-Path -Path $path -PathType Leaf | Should -BeTrue -Because "required doc '$fileName' must exist"
        }
    }

    It 'includes Last validated metadata in quickstart, release-gates, and ci-catalog' {
        foreach ($fileName in @('quickstart.md', 'release-gates.md', 'ci-catalog.md')) {
            [string]$script:docs[$fileName] | Should -Match '(?m)^Last validated:\s+\d{4}-\d{2}-\d{2}\s*$'
        }
    }

    It 'documents required release artifacts in release-gates contract' {
        $content = [string]$script:docs['release-gates.md']

        foreach ($artifact in @(
            'docker-contract-ppl-bundle-windows-x64-<run_id>',
            'docker-contract-ppl-bundle-linux-x64-<run_id>',
            'docker-contract-vip-package-self-hosted-<run_id>',
            'codex-skill-layer',
            'release-payload-manifest.json'
        )) {
            $content | Should -Match ([regex]::Escape($artifact))
        }
    }

    It 'documents required gate sections in release-gates' {
        $content = [string]$script:docs['release-gates.md']
        $content | Should -Match '(?m)^## Gate algorithm\s*$'
        $content | Should -Match '(?m)^## Dispatch policy\s*$'
        $content | Should -Match '(?m)^## Auth boundary policy\s*$'
        $content | Should -Match '(?m)^## Provenance policy\s*$'
    }

    It 'keeps quickstart command snippets for status, jobs, and artifacts queries' {
        $content = [string]$script:docs['quickstart.md']
        $content | Should -Match 'actions/runs/<RUN_ID>\s+--jq'
        $content | Should -Match 'actions/runs/<RUN_ID>/jobs'
        $content | Should -Match 'actions/runs/<RUN_ID>/artifacts'
    }

    It 'documents self-hosted runner label and source remote triage guidance' {
        $quickstart = [string]$script:docs['quickstart.md']
        $releaseGates = [string]$script:docs['release-gates.md']

        $quickstart | Should -Match 'actions/runners'
        $quickstart | Should -Match 'self-hosted-windows-lv2020x64'
        $quickstart | Should -Match 'Assert-SourceProjectRemotes\.ps1'
        $quickstart | Should -Match 'no deterministic `g-cli \.\.\. lunit -- -h` preflight'
        $quickstart | Should -Match 'diagnostic-only LV2026 x64 control probe'
        $quickstart | Should -Match '-EnforceLabVIEWProcessIsolation'
        $quickstart | Should -Match 'skipped_unable_to_clear_active_labview_processes'
        $quickstart | Should -Match 'LV2020 remains strict'
        $releaseGates | Should -Match '## Self-hosted preflight policy'
        $releaseGates | Should -Match 'Assert-SourceProjectRemotes\.ps1'
        $releaseGates | Should -Match 'git ls-remote upstream'
        $releaseGates | Should -Match 'diagnostic-only LV2026 x64 control probe'
        $releaseGates | Should -Match '-EnforceLabVIEWProcessIsolation'
    }
}

