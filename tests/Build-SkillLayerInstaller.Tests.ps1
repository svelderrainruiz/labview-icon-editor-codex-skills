#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Build-SkillLayerInstaller script' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:scriptPath = Join-Path $script:repoRoot 'scripts/Build-SkillLayerInstaller.ps1'
        if (-not (Test-Path -Path $script:scriptPath -PathType Leaf)) {
            throw "Script not found: $script:scriptPath"
        }
    }

    It 'fails fast when NSIS root is missing' {
        $payloadRoot = Join-Path $TestDrive 'payload'
        New-Item -Path $payloadRoot -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $payloadRoot 'manifest.json') -Value '{"name":"fixture"}' -Encoding utf8
        Set-Content -Path (Join-Path $payloadRoot 'LICENSE') -Value '0BSD' -Encoding utf8

        $outputPath = Join-Path $TestDrive 'skill-layer-installer.exe'
        {
            & $script:scriptPath -PayloadRoot $payloadRoot -OutputPath $outputPath -NsisRoot 'C:\__missing__\NSIS'
        } | Should -Throw '*Required NSIS binary not found*'
    }

    It 'builds installer when NSIS root is valid' -Skip:(-not (Test-Path 'C:\Program Files (x86)\NSIS\makensis.exe')) {
        $payloadRoot = Join-Path $TestDrive 'payload-valid'
        New-Item -Path $payloadRoot -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $payloadRoot 'manifest.json') -Value '{"name":"fixture"}' -Encoding utf8
        Set-Content -Path (Join-Path $payloadRoot 'LICENSE') -Value '0BSD' -Encoding utf8

        $outputPath = Join-Path $TestDrive 'skill-layer-installer-valid.exe'
        $result = & $script:scriptPath -PayloadRoot $payloadRoot -OutputPath $outputPath -NsisRoot 'C:\Program Files (x86)\NSIS'

        (Test-Path -Path $outputPath -PathType Leaf) | Should -BeTrue
        ([string]($result | Out-String)) | Should -Match ([regex]::Escape($outputPath))
    }
}
