#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Skill layer manifest contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:manifestPath = Join-Path $script:repoRoot 'manifest.json'
        if (-not (Test-Path -Path $script:manifestPath -PathType Leaf)) {
            throw "Manifest not found: $script:manifestPath"
        }

        $script:manifest = Get-Content -Path $script:manifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
    }

    It 'contains vipm-cli-machine and linux-ppl-container-build modules and v0.4.1 version' {
        [string]$script:manifest.version | Should -Be '0.4.1'
        $script:manifest.modules.PSObject.Properties.Name | Should -Contain 'vipm-cli-machine'
        [string]$script:manifest.modules.'vipm-cli-machine'.path | Should -Be 'vipm-cli-machine'
        $script:manifest.modules.PSObject.Properties.Name | Should -Contain 'linux-ppl-container-build'
        [string]$script:manifest.modules.'linux-ppl-container-build'.path | Should -Be 'linux-ppl-container-build'
    }

    It 'has required_files entries that exist in the repository' {
        foreach ($relative in @($script:manifest.required_files)) {
            $fullPath = Join-Path $script:repoRoot ([string]$relative)
            Test-Path -Path $fullPath -PathType Leaf | Should -BeTrue -Because "required file '$relative' must exist"
        }
    }

    It 'has module paths that exist as directories' {
        foreach ($moduleName in $script:manifest.modules.PSObject.Properties.Name) {
            $module = $script:manifest.modules.$moduleName
            $modulePath = Join-Path $script:repoRoot ([string]$module.path)
            Test-Path -Path $modulePath -PathType Container | Should -BeTrue -Because "module path '$($module.path)' must exist"
        }
    }
}

