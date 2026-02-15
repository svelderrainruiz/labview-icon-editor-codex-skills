#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Assert-SourceProjectRemotes script contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:scriptPath = Join-Path $script:repoRoot 'scripts/Assert-SourceProjectRemotes.ps1'
        if (-not (Test-Path -LiteralPath $script:scriptPath -PathType Leaf)) {
            throw "Required script missing: $script:scriptPath"
        }

        $script:scriptContent = Get-Content -LiteralPath $script:scriptPath -Raw
    }

    It 'defines required parameters and deterministic upstream URL contract' {
        $script:scriptContent | Should -Match 'param\('
        $script:scriptContent | Should -Match '\$SourceProjectRoot'
        $script:scriptContent | Should -Match '\$UpstreamRepo'
        $script:scriptContent | Should -Match '\$OutputDirectory'
        $script:scriptContent | Should -Match '"https://github.com/\$UpstreamRepo\.git"'
    }

    It 'enforces non-interactive ls-remote connectivity and deterministic remote mutation flow' {
        $script:scriptContent | Should -Match 'remote get-url upstream'
        $script:scriptContent | Should -Match 'remote add upstream'
        $script:scriptContent | Should -Match 'remote set-url upstream'
        $script:scriptContent | Should -Match 'ls-remote upstream'
        $script:scriptContent | Should -Match 'GIT_TERMINAL_PROMPT'
        $script:scriptContent | Should -Match 'GCM_INTERACTIVE'
    }

    It 'emits deterministic diagnostics payloads and capture-then-fail semantics' {
        $script:scriptContent | Should -Match 'source-project-remotes\.status\.json'
        $script:scriptContent | Should -Match 'source-project-remotes\.result\.json'
        $script:scriptContent | Should -Match 'source-project-remotes\.log'
        $script:scriptContent | Should -Match 'Source project remote assertion failed:'
    }

    It 'writes failure diagnostics when source project root is missing' {
        $tempRoot = Join-Path $env:TEMP ("assert-source-remotes-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        try {
            $missingSourceRoot = Join-Path $tempRoot 'missing-source'
            $outputDirectory = Join-Path $tempRoot 'output'
            $failed = $false
            $thrownMessage = ''
            try {
                & $script:scriptPath `
                    -SourceProjectRoot $missingSourceRoot `
                    -UpstreamRepo 'svelderrainruiz/labview-icon-editor' `
                    -OutputDirectory $outputDirectory
            }
            catch {
                $failed = $true
                $thrownMessage = $_.Exception.Message
            }

            $failed | Should -BeTrue
            $thrownMessage | Should -Match 'Source project remote assertion failed:'
            $thrownMessage | Should -Match 'Source project root not found'
            Test-Path -LiteralPath (Join-Path $outputDirectory 'source-project-remotes.status.json') -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $outputDirectory 'source-project-remotes.result.json') -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $outputDirectory 'source-project-remotes.log') -PathType Leaf | Should -BeTrue
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot -PathType Container) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }
}
