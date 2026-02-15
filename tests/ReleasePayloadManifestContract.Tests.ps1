#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Release payload manifest contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:schemaPath = Join-Path $script:repoRoot 'schemas/release-payload-contract.schema.json'
        $script:generatorPath = Join-Path $script:repoRoot 'scripts/New-ReleasePayloadManifest.ps1'

        foreach ($path in @($script:schemaPath, $script:generatorPath)) {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "Required release payload contract file missing: $path"
            }
        }

        $script:schema = Get-Content -LiteralPath $script:schemaPath -Raw | ConvertFrom-Json -ErrorAction Stop
    }

    It 'defines required top-level fields and category enum in schema' {
        @($script:schema.required) | Should -Contain 'schema_version'
        @($script:schema.required) | Should -Contain 'generated_utc'
        @($script:schema.required) | Should -Contain 'release_tag'
        @($script:schema.required) | Should -Contain 'source_project'
        @($script:schema.required) | Should -Contain 'skills_ci_run'
        @($script:schema.required) | Should -Contain 'assets'
        [bool]$script:schema.additionalProperties | Should -BeFalse

        $categories = @($script:schema.properties.assets.items.properties.category.enum)
        foreach ($category in @(
            'installer',
            'ppl_bundle_windows_x64',
            'ppl_bundle_linux_x64',
            'vip_package_self_hosted',
            'provenance'
        )) {
            $categories | Should -Contain $category
        }
    }

    It 'generates a schema-valid release payload manifest with required assets' {
        $tempRoot = Join-Path $env:TEMP ("release-payload-manifest-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        try {
            $requiredFiles = @(
                'lvie-codex-skill-layer-installer.exe',
                'lvie-ppl-bundle-windows-x64.zip',
                'lvie-ppl-bundle-linux-x64.zip',
                'lvie-vip-package-self-hosted.zip',
                'release-provenance.json'
            )
            foreach ($name in $requiredFiles) {
                $path = Join-Path $tempRoot $name
                Set-Content -LiteralPath $path -Value "fixture-$name" -Encoding UTF8
            }

            & $script:generatorPath `
                -ReleaseTag 'v0.1.0' `
                -StageDirectory $tempRoot `
                -SourceProjectRepo 'svelderrainruiz/labview-icon-editor' `
                -SourceProjectRef 'main' `
                -SourceProjectSha '1234567890abcdef' `
                -CiRepository 'svelderrainruiz/labview-icon-editor-codex-skills' `
                -CiRunId '100' `
                -CiRunAttempt '1' `
                -CiRunUrl 'https://github.com/svelderrainruiz/labview-icon-editor-codex-skills/actions/runs/100' `
                -OutputPath (Join-Path $tempRoot 'release-payload-manifest.json') `
                -SchemaPath $script:schemaPath

            $manifestPath = Join-Path $tempRoot 'release-payload-manifest.json'
            Test-Path -LiteralPath $manifestPath -PathType Leaf | Should -BeTrue

            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
            [string]$manifest.schema_version | Should -Be '1.0'
            [string]$manifest.release_tag | Should -Be 'v0.1.0'
            @($manifest.assets).Count | Should -Be 5
            foreach ($category in @(
                'installer',
                'ppl_bundle_windows_x64',
                'ppl_bundle_linux_x64',
                'vip_package_self_hosted',
                'provenance'
            )) {
                @($manifest.assets.category) | Should -Contain $category
            }
            foreach ($asset in @($manifest.assets)) {
                [string]$asset.sha256 | Should -Match '^[a-f0-9]{64}$'
                [int64]$asset.size_bytes | Should -BeGreaterOrEqual 0
            }
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot -PathType Container) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }

    It 'fails when a required staged release asset is missing' {
        $tempRoot = Join-Path $env:TEMP ("release-payload-missing-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        try {
            $requiredFiles = @(
                'lvie-codex-skill-layer-installer.exe',
                'lvie-ppl-bundle-windows-x64.zip',
                'lvie-ppl-bundle-linux-x64.zip',
                'release-provenance.json'
            )
            foreach ($name in $requiredFiles) {
                $path = Join-Path $tempRoot $name
                Set-Content -LiteralPath $path -Value "fixture-$name" -Encoding UTF8
            }

            $failed = $false
            $errorMessage = ''
            try {
                & $script:generatorPath `
                    -ReleaseTag 'v0.1.0' `
                    -StageDirectory $tempRoot `
                    -SourceProjectRepo 'svelderrainruiz/labview-icon-editor' `
                    -SourceProjectRef 'main' `
                    -SourceProjectSha '1234567890abcdef' `
                    -CiRepository 'svelderrainruiz/labview-icon-editor-codex-skills' `
                    -CiRunId '100' `
                    -CiRunAttempt '1' `
                    -CiRunUrl 'https://github.com/svelderrainruiz/labview-icon-editor-codex-skills/actions/runs/100' `
                    -SchemaPath $script:schemaPath
            }
            catch {
                $failed = $true
                $errorMessage = $_.Exception.Message
            }

            $failed | Should -BeTrue
            $errorMessage | Should -Match 'Required staged release asset missing'
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot -PathType Container) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }
}
