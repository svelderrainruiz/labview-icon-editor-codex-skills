#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Invoke-ContractTests script contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:scriptPath = Join-Path $script:repoRoot 'scripts/Invoke-ContractTests.ps1'

        if (-not (Test-Path -Path $script:scriptPath -PathType Leaf)) {
            throw "Required script missing: $script:scriptPath"
        }

        $script:scriptContent = Get-Content -Path $script:scriptPath -Raw
    }

    It 'defines TestPath and TestResultPath parameters' {
        $script:scriptContent | Should -Match '\[string\]\$TestPath\s*=\s*''\./tests/\*\.Tests\.ps1'''
        $script:scriptContent | Should -Match '\[string\]\$TestResultPath'
    }

    It 'uses explicit Pester configuration with configurable NUnit output path' {
        $script:scriptContent | Should -Match 'New-PesterConfiguration'
        $script:scriptContent | Should -Match '\$config\.TestResult\.Enabled\s*=\s*\$true'
        $script:scriptContent | Should -Match '\$config\.TestResult\.OutputFormat\s*=\s*''NUnitXml'''
        $script:scriptContent | Should -Match '\$config\.TestResult\.OutputPath\s*=\s*\$resolvedResultPath'
    }

    It 'does not rely on fixed repo-root testResults.xml path' {
        $script:scriptContent | Should -Not -Match '(?i)\.\/testResults\.xml'
        $script:scriptContent | Should -Match 'testResults-\$timestamp-\$PID-\$\(\[guid\]::NewGuid\(\)\.ToString\(''n''\)\)\.xml'
    }

    It 'writes results to explicit TestResultPath when provided' {
        $outputDir = Join-Path $env:TEMP ("invoke-contract-tests-" + [guid]::NewGuid().ToString('n'))
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        $resultPath = Join-Path $outputDir 'explicit-result.xml'

        & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:scriptPath -TestPath './tests/ManifestContract.Tests.ps1' -TestResultPath $resultPath
        $LASTEXITCODE | Should -Be 0
        (Test-Path -LiteralPath $resultPath -PathType Leaf) | Should -BeTrue
    }

    It 'prints default unique result path and does not use repo-root testResults.xml' {
        $output = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:scriptPath -TestPath './tests/ManifestContract.Tests.ps1' 2>&1
        $LASTEXITCODE | Should -Be 0

        $pathLine = @($output | Where-Object { $_ -match '^Pester NUnit XML path:\s*(.+)$' }) | Select-Object -Last 1
        $pathLine | Should -Not -BeNullOrEmpty

        $resolvedPath = ($pathLine -replace '^Pester NUnit XML path:\s*', '').Trim()
        (Test-Path -LiteralPath $resolvedPath -PathType Leaf) | Should -BeTrue
        [System.IO.Path]::GetFileName($resolvedPath) | Should -Not -Be 'testResults.xml'
    }
}
