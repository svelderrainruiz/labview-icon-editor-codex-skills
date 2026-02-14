#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Invoke-PrepareVipbDiagnostics script contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:scriptPath = Join-Path $script:repoRoot 'scripts/Invoke-PrepareVipbDiagnostics.ps1'
        if (-not (Test-Path -LiteralPath $script:scriptPath -PathType Leaf)) {
            throw "Required script missing: $script:scriptPath"
        }

        $script:updateScriptPath = Join-Path $script:repoRoot 'scripts/Update-Vipb.DisplayInfo.ps1'
        $script:scriptContent = Get-Content -LiteralPath $script:scriptPath -Raw
    }

    It 'defines required parameters and diagnostics output contract markers' {
        $script:scriptContent | Should -Match 'param\('
        $script:scriptContent | Should -Match '\$RepoRoot'
        $script:scriptContent | Should -Match '\$VipbPath'
        $script:scriptContent | Should -Match '\$ReleaseNotesFile'
        $script:scriptContent | Should -Match '\$DisplayInformationJson'
        $script:scriptContent | Should -Match '\$OutputDirectory'
        $script:scriptContent | Should -Match '\$UpdateScriptPath'
        $script:scriptContent | Should -Match '\$ProfileResolutionPath'
        $script:scriptContent | Should -Match 'vipb\.before\.xml'
        $script:scriptContent | Should -Match 'vipb\.after\.xml'
        $script:scriptContent | Should -Match 'prepare-vipb\.status\.json'
        $script:scriptContent | Should -Match 'prepare-vipb\.error\.json'
        $script:scriptContent | Should -Match 'vipb-diagnostics\.json'
        $script:scriptContent | Should -Match 'vipb-diagnostics-summary\.md'
        $script:scriptContent | Should -Match 'display-information\.input\.json'
        $script:scriptContent | Should -Match 'profile-resolution\.input\.json'
    }

    It 'writes full diagnostics outputs on success path' {
        $tempRoot = Join-Path $env:TEMP ("vipb-diag-success-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        try {
            $repoRootPath = Join-Path $tempRoot 'repo'
            New-Item -Path $repoRootPath -ItemType Directory -Force | Out-Null
            '26.0' | Set-Content -LiteralPath (Join-Path $repoRootPath '.lvversion') -Encoding ASCII
            $vipbPath = Join-Path $tempRoot 'fixture.vipb'
            $releaseNotesPath = Join-Path $tempRoot 'release_notes.md'
            $outputDir = Join-Path $tempRoot 'output'
            $profileResolutionPath = Join-Path $tempRoot 'profile-resolution.json'

            @'
<VI_Package_Builder_Settings>
  <Library_General_Settings>
    <Library_Version>0.0.0.0</Library_Version>
    <Package_LabVIEW_Version>26.0 (64-bit)</Package_LabVIEW_Version>
    <Company_Name>old-company</Company_Name>
    <Product_Name>old-product</Product_Name>
  </Library_General_Settings>
  <Advanced_Settings>
    <Description>
      <One_Line_Description_Summary>old-summary</One_Line_Description_Summary>
      <Packager>old-packager</Packager>
      <URL>https://example.invalid</URL>
      <Copyright>old-copyright</Copyright>
      <Release_Notes>old-notes</Release_Notes>
      <Description>old-description</Description>
    </Description>
    <License_Agreement_Filepath>old-license</License_Agreement_Filepath>
    <Source_Files>
      <Exclusions>
        <Path>builds</Path>
      </Exclusions>
    </Source_Files>
  </Advanced_Settings>
</VI_Package_Builder_Settings>
'@ | Set-Content -LiteralPath $vipbPath -Encoding UTF8
            'release notes fixture' | Set-Content -LiteralPath $releaseNotesPath -Encoding UTF8

            $displayInfo = @{
                'Package Version' = @{
                    major = 0
                    minor = 1
                    patch = 0
                    build = 123
                }
                'Company Name' = 'fixture-company'
                'Product Name' = 'fixture-product'
                'Product Description Summary' = 'fixture-summary'
                'Product Description' = 'fixture-description'
                'Author Name (Person or Company)' = 'fixture-author'
                'Product Homepage (URL)' = 'https://github.com/example/repo'
                'Legal Copyright' = 'fixture-copyright'
                'Release Notes - Change Log' = 'release notes fixture'
            } | ConvertTo-Json -Depth 6 -Compress
            @'
{
  "selected_profile_id": "lv2026",
  "comparison_result": "match",
  "warning_required": false,
  "warning_message": "",
  "profile": {
    "lvversion_raw": "26.0",
    "expected_vipb_target": "26.0 (64-bit)"
  },
  "consumer": {
    "lvversion_raw": "26.0",
    "expected_vipb_target": "26.0 (64-bit)"
  }
}
'@ | Set-Content -LiteralPath $profileResolutionPath -Encoding UTF8

            & $script:scriptPath `
                -RepoRoot $repoRootPath `
                -VipbPath $vipbPath `
                -ReleaseNotesFile $releaseNotesPath `
                -DisplayInformationJson $displayInfo `
                -LabVIEWVersionYear 2026 `
                -LabVIEWMinorRevision 0 `
                -SupportedBitness '64' `
                -Major 0 `
                -Minor 1 `
                -Patch 0 `
                -Build 123 `
                -Commit 'abc123' `
                -OutputDirectory $outputDir `
                -SourceRepository 'example/repo' `
                -SourceRef 'refs/heads/main' `
                -SourceSha 'abc123' `
                -BuildRunId '111' `
                -BuildRunAttempt '1' `
                -ProfileResolutionPath $profileResolutionPath `
                -UpdateScriptPath $script:updateScriptPath

            foreach ($requiredFile in @(
                'NI Icon editor.vipb',
                'vipb.before.xml',
                'vipb.after.xml',
                'vipb.before.sha256',
                'vipb.after.sha256',
                'vipb-diff.json',
                'vipb-diff-summary.md',
                'vipb-diagnostics.json',
                'vipb-diagnostics-summary.md',
                'prepare-vipb.status.json',
                'prepare-vipb.log',
                'display-information.input.json',
                'profile-resolution.input.json'
            )) {
                Test-Path -LiteralPath (Join-Path $outputDir $requiredFile) -PathType Leaf | Should -BeTrue
            }

            $status = Get-Content -LiteralPath (Join-Path $outputDir 'prepare-vipb.status.json') -Raw | ConvertFrom-Json
            @('updated', 'no_changes') | Should -Contain ([string]$status.status)

            $diagnostics = Get-Content -LiteralPath (Join-Path $outputDir 'vipb-diagnostics.json') -Raw | ConvertFrom-Json
            [string]$diagnostics.status | Should -BeIn @('updated', 'no_changes')
            [int]$diagnostics.diff.changed_field_count | Should -BeGreaterOrEqual 0
            [int]$diagnostics.summary_format_version | Should -BeGreaterOrEqual 2
            [string]$diagnostics.version_authority.lvversion_raw | Should -Be '26.0'
            [string]$diagnostics.version_authority.expected_vipb_target | Should -Be '26.0 (64-bit)'
            [string]$diagnostics.version_authority.check_result | Should -Be 'pass'
            [string]$diagnostics.profile_advisory.profile_id | Should -Be 'lv2026'
            [string]$diagnostics.profile_advisory.comparison_result | Should -Be 'match'
            [bool]$diagnostics.profile_advisory.warning_emitted | Should -BeFalse

            $summary = Get-Content -LiteralPath (Join-Path $outputDir 'vipb-diagnostics-summary.md') -Raw
            $summary | Should -Match '## VIPB Diagnostics Suite'
            $summary | Should -Match '### Version Authority'
            $summary | Should -Match '### Target Preset Advisory'
            $summary | Should -Match '### Changed Fields Quick View'
            $summary | Should -Match '### File Inventory'
            $summary | Should -Match '\| Label \| Path \| Exists \| Size \(bytes\) \| SHA256 \|'
            $summary | Should -Match 'prepared_vipb'
            $summary | Should -Match 'vipb\.before\.xml'
            $summary | Should -Match 'vipb\.after\.xml'
            $summary | Should -Not -Match 'System\.Collections\.Specialized\.OrderedDictionary\.path'
            $summary | Should -Not -Match '(?m)^## VIPB Metadata Delta\s*$'
            $summary | Should -Match '### Field Delta'
            $summary | Should -Match 'Source project remains authoritative for VIPB target enforcement'
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot -PathType Container) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }

    It 'captures advisory mismatch metadata without failing when consumer authority still passes' {
        $tempRoot = Join-Path $env:TEMP ("vipb-diag-advisory-mismatch-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        try {
            $repoRootPath = Join-Path $tempRoot 'repo'
            New-Item -Path $repoRootPath -ItemType Directory -Force | Out-Null
            '26.0' | Set-Content -LiteralPath (Join-Path $repoRootPath '.lvversion') -Encoding ASCII

            $vipbPath = Join-Path $tempRoot 'fixture.vipb'
            $releaseNotesPath = Join-Path $tempRoot 'release_notes.md'
            $outputDir = Join-Path $tempRoot 'output'
            $profileResolutionPath = Join-Path $tempRoot 'profile-resolution.json'

            @'
<VI_Package_Builder_Settings>
  <Library_General_Settings>
    <Library_Version>0.0.0.0</Library_Version>
    <Package_LabVIEW_Version>26.0 (64-bit)</Package_LabVIEW_Version>
    <Company_Name>old-company</Company_Name>
    <Product_Name>old-product</Product_Name>
  </Library_General_Settings>
  <Advanced_Settings>
    <Description>
      <One_Line_Description_Summary>old-summary</One_Line_Description_Summary>
      <Packager>old-packager</Packager>
      <URL>https://example.invalid</URL>
      <Copyright>old-copyright</Copyright>
      <Release_Notes>old-notes</Release_Notes>
      <Description>old-description</Description>
    </Description>
    <License_Agreement_Filepath>old-license</License_Agreement_Filepath>
    <Source_Files>
      <Exclusions>
        <Path>builds</Path>
      </Exclusions>
    </Source_Files>
  </Advanced_Settings>
</VI_Package_Builder_Settings>
'@ | Set-Content -LiteralPath $vipbPath -Encoding UTF8
            'notes' | Set-Content -LiteralPath $releaseNotesPath -Encoding UTF8
            @'
{
  "selected_profile_id": "lv2025",
  "comparison_result": "mismatch",
  "warning_required": true,
  "warning_message": "Selected target preset differs from source project target. Source project remains authoritative.",
  "profile": {
    "lvversion_raw": "25.0",
    "expected_vipb_target": "25.0 (64-bit)"
  },
  "consumer": {
    "lvversion_raw": "26.0",
    "expected_vipb_target": "26.0 (64-bit)"
  }
}
'@ | Set-Content -LiteralPath $profileResolutionPath -Encoding UTF8

            $displayInfo = @{
                'Package Version' = @{
                    major = 0
                    minor = 1
                    patch = 0
                    build = 1
                }
                'Company Name' = 'fixture-company'
                'Product Name' = 'fixture-product'
                'Product Description Summary' = 'fixture-summary'
                'Product Description' = 'fixture-description'
                'Author Name (Person or Company)' = 'fixture-author'
                'Product Homepage (URL)' = 'https://github.com/example/repo'
                'Legal Copyright' = 'fixture-copyright'
                'Release Notes - Change Log' = 'notes'
            } | ConvertTo-Json -Depth 6 -Compress

            & $script:scriptPath `
                -RepoRoot $repoRootPath `
                -VipbPath $vipbPath `
                -ReleaseNotesFile $releaseNotesPath `
                -DisplayInformationJson $displayInfo `
                -LabVIEWVersionYear 2026 `
                -LabVIEWMinorRevision 0 `
                -SupportedBitness '64' `
                -Major 0 `
                -Minor 1 `
                -Patch 0 `
                -Build 1 `
                -Commit 'abc123' `
                -OutputDirectory $outputDir `
                -ProfileResolutionPath $profileResolutionPath `
                -UpdateScriptPath $script:updateScriptPath

            $LASTEXITCODE | Should -Be 0

            $status = Get-Content -LiteralPath (Join-Path $outputDir 'prepare-vipb.status.json') -Raw | ConvertFrom-Json
            [string]$status.status | Should -BeIn @('updated', 'no_changes')

            $diagnostics = Get-Content -LiteralPath (Join-Path $outputDir 'vipb-diagnostics.json') -Raw | ConvertFrom-Json
            [string]$diagnostics.profile_advisory.comparison_result | Should -Be 'mismatch'
            [bool]$diagnostics.profile_advisory.warning_emitted | Should -BeTrue
            [string]$diagnostics.profile_advisory.profile_expected_vipb_target | Should -Be '25.0 (64-bit)'
            [string]$diagnostics.profile_advisory.consumer_expected_vipb_target | Should -Be '26.0 (64-bit)'

            $summary = Get-Content -LiteralPath (Join-Path $outputDir 'vipb-diagnostics-summary.md') -Raw
            $summary | Should -Match '### Target Preset Advisory'
            $summary | Should -Match 'Comparison result: `mismatch`'
            $summary | Should -Match 'Warning emitted: `true`'
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot -PathType Container) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }

    It 'captures diagnostics and fails for missing VIPB input' {
        $tempRoot = Join-Path $env:TEMP ("vipb-diag-failure-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        try {
            $repoRootPath = Join-Path $tempRoot 'repo'
            New-Item -Path $repoRootPath -ItemType Directory -Force | Out-Null
            '26.0' | Set-Content -LiteralPath (Join-Path $repoRootPath '.lvversion') -Encoding ASCII
            $missingVipbPath = Join-Path $tempRoot 'missing.vipb'
            $releaseNotesPath = Join-Path $tempRoot 'release_notes.md'
            $outputDir = Join-Path $tempRoot 'output'
            'notes' | Set-Content -LiteralPath $releaseNotesPath -Encoding UTF8
            $displayInfo = @{
                'Package Version' = @{
                    major = 0
                    minor = 1
                    patch = 0
                    build = 1
                }
                'Company Name' = 'fixture-company'
                'Product Name' = 'fixture-product'
                'Product Description Summary' = 'fixture-summary'
                'Product Description' = 'fixture-description'
                'Author Name (Person or Company)' = 'fixture-author'
                'Product Homepage (URL)' = 'https://github.com/example/repo'
                'Legal Copyright' = 'fixture-copyright'
                'Release Notes - Change Log' = 'notes'
            } | ConvertTo-Json -Depth 6 -Compress

            $failed = $false
            try {
                & $script:scriptPath `
                    -RepoRoot $repoRootPath `
                    -VipbPath $missingVipbPath `
                    -ReleaseNotesFile $releaseNotesPath `
                    -DisplayInformationJson $displayInfo `
                    -LabVIEWVersionYear 2026 `
                    -LabVIEWMinorRevision 0 `
                    -SupportedBitness '64' `
                    -Major 0 `
                    -Minor 1 `
                    -Patch 0 `
                    -Build 1 `
                    -Commit 'abc123' `
                    -OutputDirectory $outputDir `
                    -UpdateScriptPath $script:updateScriptPath
            }
            catch {
                $failed = $true
            }

            $failed | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $outputDir 'prepare-vipb.status.json') -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $outputDir 'prepare-vipb.error.json') -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $outputDir 'vipb-diagnostics-summary.md') -PathType Leaf | Should -BeTrue

            $status = Get-Content -LiteralPath (Join-Path $outputDir 'prepare-vipb.status.json') -Raw | ConvertFrom-Json
            [string]$status.status | Should -Be 'failed'

            $errorPayload = Get-Content -LiteralPath (Join-Path $outputDir 'prepare-vipb.error.json') -Raw | ConvertFrom-Json
            [string]$errorPayload.message | Should -Match 'VIPB file not found'
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot -PathType Container) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }

    It 'captures diagnostics and normalizes mismatched VIPB target to .lvversion authority' {
        $tempRoot = Join-Path $env:TEMP ("vipb-diag-version-mismatch-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        try {
            $repoRootPath = Join-Path $tempRoot 'repo'
            New-Item -Path $repoRootPath -ItemType Directory -Force | Out-Null
            '26.0' | Set-Content -LiteralPath (Join-Path $repoRootPath '.lvversion') -Encoding ASCII

            $vipbPath = Join-Path $tempRoot 'fixture.vipb'
            $releaseNotesPath = Join-Path $tempRoot 'release_notes.md'
            $outputDir = Join-Path $tempRoot 'output'

            @'
<VI_Package_Builder_Settings>
  <Library_General_Settings>
    <Library_Version>0.0.0.0</Library_Version>
    <Package_LabVIEW_Version>20.0</Package_LabVIEW_Version>
    <Company_Name>old-company</Company_Name>
    <Product_Name>old-product</Product_Name>
  </Library_General_Settings>
  <Advanced_Settings>
    <Description>
      <One_Line_Description_Summary>old-summary</One_Line_Description_Summary>
      <Packager>old-packager</Packager>
      <URL>https://example.invalid</URL>
      <Copyright>old-copyright</Copyright>
      <Release_Notes>old-notes</Release_Notes>
      <Description>old-description</Description>
    </Description>
    <License_Agreement_Filepath>old-license</License_Agreement_Filepath>
    <Source_Files>
      <Exclusions>
        <Path>builds</Path>
      </Exclusions>
    </Source_Files>
  </Advanced_Settings>
</VI_Package_Builder_Settings>
'@ | Set-Content -LiteralPath $vipbPath -Encoding UTF8
            'notes' | Set-Content -LiteralPath $releaseNotesPath -Encoding UTF8

            $displayInfo = @{
                'Package Version' = @{
                    major = 0
                    minor = 1
                    patch = 0
                    build = 1
                }
                'Company Name' = 'fixture-company'
                'Product Name' = 'fixture-product'
                'Product Description Summary' = 'fixture-summary'
                'Product Description' = 'fixture-description'
                'Author Name (Person or Company)' = 'fixture-author'
                'Product Homepage (URL)' = 'https://github.com/example/repo'
                'Legal Copyright' = 'fixture-copyright'
                'Release Notes - Change Log' = 'notes'
            } | ConvertTo-Json -Depth 6 -Compress

            & $script:scriptPath `
                -RepoRoot $repoRootPath `
                -VipbPath $vipbPath `
                -ReleaseNotesFile $releaseNotesPath `
                -DisplayInformationJson $displayInfo `
                -LabVIEWVersionYear 2026 `
                -LabVIEWMinorRevision 0 `
                -SupportedBitness '64' `
                -Major 0 `
                -Minor 1 `
                -Patch 0 `
                -Build 1 `
                -Commit 'abc123' `
                -OutputDirectory $outputDir `
                -UpdateScriptPath $script:updateScriptPath

            $status = Get-Content -LiteralPath (Join-Path $outputDir 'prepare-vipb.status.json') -Raw | ConvertFrom-Json
            [string]$status.status | Should -Be 'updated'

            $diagnostics = Get-Content -LiteralPath (Join-Path $outputDir 'vipb-diagnostics.json') -Raw | ConvertFrom-Json
            [string]$diagnostics.version_authority.check_result | Should -Be 'pass'
            [string]$diagnostics.version_authority.expected_vipb_target | Should -Be '26.0 (64-bit)'
            [string]$diagnostics.version_authority.observed_vipb_target_before | Should -Be '20.0'
            [string]$diagnostics.version_authority.observed_vipb_target_after | Should -Be '26.0 (64-bit)'
            [string]$diagnostics.version_authority.observed_vipb_target | Should -Be '26.0 (64-bit)'
            [bool]$diagnostics.version_authority.input_mismatch | Should -BeTrue
            [bool]$diagnostics.version_authority.input_mismatch_normalized | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $outputDir 'prepare-vipb.error.json') -PathType Leaf | Should -BeFalse

            $summary = Get-Content -LiteralPath (Join-Path $outputDir 'vipb-diagnostics-summary.md') -Raw
            $summary | Should -Match '### Version Authority'
            $summary | Should -Match 'Authority check: `pass`'
            $summary | Should -Match 'Observed VIPB target \(before\): `20\.0`'
            $summary | Should -Match 'Observed VIPB target \(after\): `26\.0 \(64-bit\)`'
            $summary | Should -Match 'Input mismatch normalized: `true`'
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot -PathType Container) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }

    It 'captures diagnostics and fails when .lvversion is earlier than 20.0' {
        $tempRoot = Join-Path $env:TEMP ("vipb-diag-min-version-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        try {
            $repoRootPath = Join-Path $tempRoot 'repo'
            New-Item -Path $repoRootPath -ItemType Directory -Force | Out-Null
            '19.0' | Set-Content -LiteralPath (Join-Path $repoRootPath '.lvversion') -Encoding ASCII

            $vipbPath = Join-Path $tempRoot 'fixture.vipb'
            $releaseNotesPath = Join-Path $tempRoot 'release_notes.md'
            $outputDir = Join-Path $tempRoot 'output'

            @'
<VI_Package_Builder_Settings>
  <Library_General_Settings>
    <Library_Version>0.0.0.0</Library_Version>
    <Package_LabVIEW_Version>19.0 (64-bit)</Package_LabVIEW_Version>
    <Company_Name>old-company</Company_Name>
    <Product_Name>old-product</Product_Name>
  </Library_General_Settings>
  <Advanced_Settings>
    <Description>
      <One_Line_Description_Summary>old-summary</One_Line_Description_Summary>
      <Packager>old-packager</Packager>
      <URL>https://example.invalid</URL>
      <Copyright>old-copyright</Copyright>
      <Release_Notes>old-notes</Release_Notes>
      <Description>old-description</Description>
    </Description>
    <License_Agreement_Filepath>old-license</License_Agreement_Filepath>
    <Source_Files>
      <Exclusions>
        <Path>builds</Path>
      </Exclusions>
    </Source_Files>
  </Advanced_Settings>
</VI_Package_Builder_Settings>
'@ | Set-Content -LiteralPath $vipbPath -Encoding UTF8
            'notes' | Set-Content -LiteralPath $releaseNotesPath -Encoding UTF8

            $displayInfo = @{
                'Package Version' = @{
                    major = 0
                    minor = 1
                    patch = 0
                    build = 1
                }
                'Company Name' = 'fixture-company'
                'Product Name' = 'fixture-product'
                'Product Description Summary' = 'fixture-summary'
                'Product Description' = 'fixture-description'
                'Author Name (Person or Company)' = 'fixture-author'
                'Product Homepage (URL)' = 'https://github.com/example/repo'
                'Legal Copyright' = 'fixture-copyright'
                'Release Notes - Change Log' = 'notes'
            } | ConvertTo-Json -Depth 6 -Compress

            $failed = $false
            try {
                & $script:scriptPath `
                    -RepoRoot $repoRootPath `
                    -VipbPath $vipbPath `
                    -ReleaseNotesFile $releaseNotesPath `
                    -DisplayInformationJson $displayInfo `
                    -LabVIEWVersionYear 2019 `
                    -LabVIEWMinorRevision 0 `
                    -SupportedBitness '64' `
                    -Major 0 `
                    -Minor 1 `
                    -Patch 0 `
                    -Build 1 `
                    -Commit 'abc123' `
                    -OutputDirectory $outputDir `
                    -UpdateScriptPath $script:updateScriptPath
            }
            catch {
                $failed = $true
            }

            $failed | Should -BeTrue
            $status = Get-Content -LiteralPath (Join-Path $outputDir 'prepare-vipb.status.json') -Raw | ConvertFrom-Json
            [string]$status.status | Should -Be 'failed'

            $errorPayload = Get-Content -LiteralPath (Join-Path $outputDir 'prepare-vipb.error.json') -Raw | ConvertFrom-Json
            [string]$errorPayload.message | Should -Match 'Minimum supported LabVIEW version is 20\.0'
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot -PathType Container) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }
}
