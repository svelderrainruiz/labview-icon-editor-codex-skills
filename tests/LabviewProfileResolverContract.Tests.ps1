#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'LabVIEW profile resolver contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:scriptPath = Join-Path $script:repoRoot 'scripts/Resolve-LabviewProfile.ps1'
        $script:profilesRoot = Join-Path $script:repoRoot 'profiles/labview'
        $script:manifestPath = Join-Path $script:profilesRoot 'profiles.json'
        $script:defaultProfileLvversionPath = Join-Path $script:profilesRoot 'lv2026/.lvversion'
        $script:defaultProfileOverlayPath = Join-Path $script:profilesRoot 'lv2026/vipb-display-info.overlay.json'

        foreach ($requiredPath in @(
            $script:scriptPath,
            $script:manifestPath,
            $script:defaultProfileLvversionPath,
            $script:defaultProfileOverlayPath
        )) {
            if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
                throw "Required file missing: $requiredPath"
            }
        }

        $script:scriptContent = Get-Content -LiteralPath $script:scriptPath -Raw
    }

    It 'defines resolver interface and warning classification markers' {
        $script:scriptContent | Should -Match 'param\('
        $script:scriptContent | Should -Match '\$ProfilesRoot'
        $script:scriptContent | Should -Match '\$ProfileId'
        $script:scriptContent | Should -Match '\$ConsumerRepoRoot'
        $script:scriptContent | Should -Match '\$SupportedBitness'
        $script:scriptContent | Should -Match '\$OutputPath'
        $script:scriptContent | Should -Match 'comparison_result'
        $script:scriptContent | Should -Match '::warning title=LabVIEW profile advisory mismatch::'
    }

    It 'resolves default profile with match classification when consumer lvversion matches' {
        $tempRoot = Join-Path $env:TEMP ("labview-profile-match-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        try {
            $consumerRoot = Join-Path $tempRoot 'consumer'
            New-Item -Path $consumerRoot -ItemType Directory -Force | Out-Null
            '26.0' | Set-Content -LiteralPath (Join-Path $consumerRoot '.lvversion') -Encoding ASCII
            $outputPath = Join-Path $tempRoot 'profile-resolution.json'

            & pwsh -NoProfile -File $script:scriptPath `
                -ProfilesRoot $script:profilesRoot `
                -ConsumerRepoRoot $consumerRoot `
                -SupportedBitness '64' `
                -OutputPath $outputPath

            $LASTEXITCODE | Should -Be 0
            Test-Path -LiteralPath $outputPath -PathType Leaf | Should -BeTrue

            $resolution = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
            [string]$resolution.selected_profile_id | Should -Be 'lv2026'
            [string]$resolution.comparison_result | Should -Be 'match'
            [bool]$resolution.warning_required | Should -BeFalse
            [string]$resolution.profile.lvversion_raw | Should -Be '26.0'
            [string]$resolution.consumer.lvversion_raw | Should -Be '26.0'
            [string]$resolution.profile.expected_vipb_target | Should -Be '26.0 (64-bit)'
            [string]$resolution.consumer.expected_vipb_target | Should -Be '26.0 (64-bit)'
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot -PathType Container) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }

    It 'returns mismatch classification without failing when profile and consumer differ' {
        $tempRoot = Join-Path $env:TEMP ("labview-profile-mismatch-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        try {
            $consumerRoot = Join-Path $tempRoot 'consumer'
            New-Item -Path $consumerRoot -ItemType Directory -Force | Out-Null
            '25.0' | Set-Content -LiteralPath (Join-Path $consumerRoot '.lvversion') -Encoding ASCII
            $outputPath = Join-Path $tempRoot 'profile-resolution.json'

            & pwsh -NoProfile -File $script:scriptPath `
                -ProfilesRoot $script:profilesRoot `
                -ProfileId 'lv2026' `
                -ConsumerRepoRoot $consumerRoot `
                -SupportedBitness '64' `
                -OutputPath $outputPath

            $LASTEXITCODE | Should -Be 0
            $resolution = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
            [string]$resolution.comparison_result | Should -Be 'mismatch'
            [bool]$resolution.warning_required | Should -BeTrue
            [string]$resolution.warning_message | Should -Match 'Consumer remains authoritative'
            [string]$resolution.profile.expected_vipb_target | Should -Be '26.0 (64-bit)'
            [string]$resolution.consumer.expected_vipb_target | Should -Be '25.0 (64-bit)'
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot -PathType Container) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }

    It 'fails deterministically and writes invalid classification when profile assets are malformed' {
        $tempRoot = Join-Path $env:TEMP ("labview-profile-invalid-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        try {
            $profilesRoot = Join-Path $tempRoot 'profiles/labview'
            $profileDir = Join-Path $profilesRoot 'lv2026'
            New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
            @'
{
  "schema_version": 1,
  "profiles": [
    {
      "id": "lv2026",
      "display_name": "LabVIEW 2026",
      "lvversion": "26.0",
      "supported_bitness": ["64"],
      "default": true,
      "status": "active"
    }
  ]
}
'@ | Set-Content -LiteralPath (Join-Path $profilesRoot 'profiles.json') -Encoding UTF8
            '26.0' | Set-Content -LiteralPath (Join-Path $profileDir '.lvversion') -Encoding ASCII
            # Intentionally omit overlay file.

            $consumerRoot = Join-Path $tempRoot 'consumer'
            New-Item -Path $consumerRoot -ItemType Directory -Force | Out-Null
            '26.0' | Set-Content -LiteralPath (Join-Path $consumerRoot '.lvversion') -Encoding ASCII

            $outputPath = Join-Path $tempRoot 'profile-resolution.json'
            $commandOutput = & pwsh -NoProfile -File $script:scriptPath `
                -ProfilesRoot $profilesRoot `
                -ProfileId 'lv2026' `
                -ConsumerRepoRoot $consumerRoot `
                -SupportedBitness '64' `
                -OutputPath $outputPath 2>&1

            $LASTEXITCODE | Should -Not -Be 0
            [string]($commandOutput -join [Environment]::NewLine) | Should -Match 'overlay file not found'
            Test-Path -LiteralPath $outputPath -PathType Leaf | Should -BeTrue

            $resolution = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
            [string]$resolution.comparison_result | Should -Be 'invalid'
            [string]$resolution.error.message | Should -Match 'overlay file not found'
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot -PathType Container) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }
}
