#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Fork portability bootstrap contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:scriptPath = Join-Path $script:repoRoot 'scripts/Initialize-ForkPortability.ps1'
        if (-not (Test-Path -LiteralPath $script:scriptPath -PathType Leaf)) {
            throw "Bootstrap script missing: $script:scriptPath"
        }

        $script:scriptContent = Get-Content -LiteralPath $script:scriptPath -Raw
    }

    It 'defines required parameters for skills repo and source target with refresh mode' {
        $script:scriptContent | Should -Match '\[string\]\$SkillsRepo'
        $script:scriptContent | Should -Match '\[string\]\$SourceProjectRepo'
        $script:scriptContent | Should -Match '\[string\]\$SourceProjectRef'
        $script:scriptContent | Should -Match '\[switch\]\$RefreshSourceSha'
        $script:scriptContent | Should -Match '\[string\]\$LabviewProfile'
        $script:scriptContent | Should -Match '\[string\]\$ParityEnforcementProfile'
        $script:scriptContent | Should -Match '\[string\]\$OutputPath'
    }

    It 'writes required portability variables through gh api contract' {
        foreach ($variableName in @(
            'LVIE_SOURCE_PROJECT_REPO',
            'LVIE_SOURCE_PROJECT_REF',
            'LVIE_SOURCE_PROJECT_SHA',
            'LVIE_LABVIEW_PROFILE',
            'LVIE_PARITY_ENFORCEMENT_PROFILE'
        )) {
            $script:scriptContent | Should -Match ([regex]::Escape($variableName))
        }

        $script:scriptContent | Should -Match 'repos/\$Repository/actions/variables/\$Name'
        $script:scriptContent | Should -Match "api',\s*'-X',\s*'PATCH'"
        $script:scriptContent | Should -Match "api',\s*'-X',\s*'POST'"
    }

    It 'enforces strict resolved SHA pin and emits deterministic result payload' {
        $script:scriptContent | Should -Match "SourceProjectRepo is required"
        $script:scriptContent | Should -Match "SourceProjectRef is required"
        $script:scriptContent | Should -Match 'repos/\$sourceProjectRepoId/commits/\$encodedRef'
        $script:scriptContent | Should -Match '\^\[0-9a-f\]\{40\}\$'
        $script:scriptContent | Should -Match 'portability-bootstrap\.result\.json'
        $script:scriptContent | Should -Match 'schema_version'
        $script:scriptContent | Should -Match "status = 'success'"
    }
}
