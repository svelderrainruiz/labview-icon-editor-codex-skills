#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Update-VipbDisplayInfo script contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:scriptPath = Join-Path $script:repoRoot 'scripts/Update-VipbDisplayInfo.ps1'

        if (-not (Test-Path -LiteralPath $script:scriptPath -PathType Leaf)) {
            throw "Required script missing: $script:scriptPath"
        }

        $script:scriptContent = Get-Content -LiteralPath $script:scriptPath -Raw
    }

    It 'defines required parameters and output contracts' {
        $script:scriptContent | Should -Match 'param\('
        $script:scriptContent | Should -Match '\$RepoRoot'
        $script:scriptContent | Should -Match '\$VipbPath'
        $script:scriptContent | Should -Match '\$ReleaseNotesFile'
        $script:scriptContent | Should -Match '\$DisplayInformationJson'
        $script:scriptContent | Should -Match '\$LabVIEWVersionYear'
        $script:scriptContent | Should -Match '\$LabVIEWMinorRevision'
        $script:scriptContent | Should -Match '\$SupportedBitness'
        $script:scriptContent | Should -Match '\$Major'
        $script:scriptContent | Should -Match '\$Minor'
        $script:scriptContent | Should -Match '\$Patch'
        $script:scriptContent | Should -Match '\$Build'
        $script:scriptContent | Should -Match '\$Commit'
        $script:scriptContent | Should -Match '\$DiffOutputPath'
        $script:scriptContent | Should -Match '\$SummaryMarkdownPath'
    }

    It 'contains deterministic vipb field mapping markers and exclusions contract' {
        $script:scriptContent | Should -Match 'Library_Version'
        $script:scriptContent | Should -Match 'Package_LabVIEW_Version'
        $script:scriptContent | Should -Match 'Company_Name'
        $script:scriptContent | Should -Match 'Product_Name'
        $script:scriptContent | Should -Match 'One_Line_Description_Summary'
        $script:scriptContent | Should -Match 'Packager'
        $script:scriptContent | Should -Match 'URL'
        $script:scriptContent | Should -Match 'Release_Notes'
        $script:scriptContent | Should -Match 'License_Agreement_Filepath'
        $script:scriptContent | Should -Match 'TestResults'
    }

    It 'uses bounded json serialization and avoids deep error payload dumps' {
        $script:scriptContent | Should -Match 'ConvertTo-Json -Depth 6'
        $script:scriptContent | Should -Not -Match 'ConvertTo-Json -Depth 10'
    }

    It 'writes diff json and summary markdown when run against a fixture vipb' {
        $tempRoot = Join-Path $env:TEMP ("vipb-update-test-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        try {
            $repoRootPath = Join-Path $tempRoot 'repo'
            New-Item -Path $repoRootPath -ItemType Directory -Force | Out-Null
            '26.0' | Set-Content -LiteralPath (Join-Path $repoRootPath '.lvversion') -Encoding ASCII
            $vipbPath = Join-Path $tempRoot 'fixture.vipb'
            $releaseNotesPath = Join-Path $tempRoot 'release_notes.md'
            $diffPath = Join-Path $tempRoot 'vipb-diff.json'
            $summaryPath = Join-Path $tempRoot 'vipb-diff-summary.md'

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

            "release notes fixture" | Set-Content -LiteralPath $releaseNotesPath -Encoding UTF8

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
                -DiffOutputPath $diffPath `
                -SummaryMarkdownPath $summaryPath

            Test-Path -LiteralPath $diffPath -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath $summaryPath -PathType Leaf | Should -BeTrue

            $diff = Get-Content -LiteralPath $diffPath -Raw | ConvertFrom-Json
            [int]$diff.changed_field_count | Should -BeGreaterThan 0
            @($diff.changed_fields) | Should -Contain 'Library_Version'
            @($diff.changed_fields) | Should -Contain 'Source_Files.Exclusions.Path'

            $summary = Get-Content -LiteralPath $summaryPath -Raw
            $summary | Should -Match '## VIPB Metadata Delta'
            $summary | Should -Match '\| Field \| Changed \| Before \| After \|'
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot -PathType Container) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }

    It 'fails when VIPB Package_LabVIEW_Version does not match authoritative .lvversion target' {
        $tempRoot = Join-Path $env:TEMP ("vipb-update-mismatch-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        try {
            $repoRootPath = Join-Path $tempRoot 'repo'
            New-Item -Path $repoRootPath -ItemType Directory -Force | Out-Null
            '26.0' | Set-Content -LiteralPath (Join-Path $repoRootPath '.lvversion') -Encoding ASCII

            $vipbPath = Join-Path $tempRoot 'fixture.vipb'
            $releaseNotesPath = Join-Path $tempRoot 'release_notes.md'
            $diffPath = Join-Path $tempRoot 'vipb-diff.json'
            $summaryPath = Join-Path $tempRoot 'vipb-diff-summary.md'

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
            'release notes fixture' | Set-Content -LiteralPath $releaseNotesPath -Encoding UTF8

            $displayInfo = [ordered]@{
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

            $thrownMessage = $null
            try {
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
                    -DiffOutputPath $diffPath `
                    -SummaryMarkdownPath $summaryPath
            }
            catch {
                $thrownMessage = $_.Exception.Message
            }

            $thrownMessage | Should -Match 'VIPB/.lvversion contract mismatch'
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot -PathType Container) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }

    It 'fails when provided LabVIEW version hint drifts from .lvversion' {
        $tempRoot = Join-Path $env:TEMP ("vipb-update-version-hint-mismatch-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        try {
            $repoRootPath = Join-Path $tempRoot 'repo'
            New-Item -Path $repoRootPath -ItemType Directory -Force | Out-Null
            '26.0' | Set-Content -LiteralPath (Join-Path $repoRootPath '.lvversion') -Encoding ASCII

            $vipbPath = Join-Path $tempRoot 'fixture.vipb'
            $releaseNotesPath = Join-Path $tempRoot 'release_notes.md'
            $diffPath = Join-Path $tempRoot 'vipb-diff.json'
            $summaryPath = Join-Path $tempRoot 'vipb-diff-summary.md'

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

            $displayInfo = [ordered]@{
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

            $thrownMessage = $null
            try {
                & $script:scriptPath `
                    -RepoRoot $repoRootPath `
                    -VipbPath $vipbPath `
                    -ReleaseNotesFile $releaseNotesPath `
                    -DisplayInformationJson $displayInfo `
                    -LabVIEWVersionYear 2025 `
                    -LabVIEWMinorRevision 0 `
                    -SupportedBitness '64' `
                    -Major 0 `
                    -Minor 1 `
                    -Patch 0 `
                    -Build 123 `
                    -DiffOutputPath $diffPath `
                    -SummaryMarkdownPath $summaryPath
            }
            catch {
                $thrownMessage = $_.Exception.Message
            }

            $thrownMessage | Should -Match 'LabVIEW version hint mismatch with \.lvversion'
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot -PathType Container) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }
}
