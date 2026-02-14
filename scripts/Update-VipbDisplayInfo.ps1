#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $true)]
    [string]$VipbPath,

    [Parameter(Mandatory = $true)]
    [string]$ReleaseNotesFile,

    [Parameter(Mandatory = $true)]
    [string]$DisplayInformationJson,

    [Parameter(Mandatory = $true)]
    [ValidateRange(2000, 2100)]
    [int]$LabVIEWVersionYear,

    [ValidateRange(0, 99)]
    [int]$LabVIEWMinorRevision = 0,

    [ValidateSet('32', '64')]
    [string]$SupportedBitness = '64',

    [Parameter(Mandatory = $true)]
    [int]$Major,

    [Parameter(Mandatory = $true)]
    [int]$Minor,

    [Parameter(Mandatory = $true)]
    [int]$Patch,

    [Parameter(Mandatory = $true)]
    [int]$Build,

    [string]$Commit,

    [Parameter(Mandatory = $true)]
    [string]$DiffOutputPath,

    [Parameter(Mandatory = $true)]
    [string]$SummaryMarkdownPath
)

$ErrorActionPreference = 'Stop'

function Resolve-FullPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location).Path -ChildPath $Path))
}

function Ensure-ParentDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $parent = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -Path $parent -ItemType Directory -Force | Out-Null
    }
}

function Format-MarkdownCell {
    param(
        [AllowNull()]
        [string]$Value,
        [int]$MaxLength = 140
    )

    if ($null -eq $Value) {
        return ''
    }

    $normalized = $Value -replace "`r`n", "`n" -replace "`r", "`n"
    $normalized = [string]$normalized.Replace([string]'|', [string]'\|')
    $normalized = $normalized -replace "`n", '<br/>'

    if ($normalized.Length -gt $MaxLength) {
        return $normalized.Substring(0, $MaxLength - 3) + '...'
    }

    return $normalized
}

function Add-FieldChange {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Changes,
        [Parameter(Mandatory = $true)]
        [string]$Field,
        [AllowNull()]
        [string]$PreviousValue,
        [AllowNull()]
        [string]$CurrentValue
    )

    $changed = -not [string]::Equals($PreviousValue, $CurrentValue, [System.StringComparison]::Ordinal)
    $Changes.Add([pscustomobject]@{
        field    = $Field
        previous = $PreviousValue
        current  = $CurrentValue
        changed  = $changed
    })
}

function Set-OrCreateElementText {
    param(
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlDocument]$Document,
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlNode]$ParentNode,
        [Parameter(Mandatory = $true)]
        [string]$ElementName,
        [AllowNull()]
        [string]$Value
    )

    $element = $ParentNode.SelectSingleNode($ElementName)
    if ($null -eq $element) {
        $element = $Document.CreateElement($ElementName)
        [void]$ParentNode.AppendChild($element)
    }

    $previous = [string]$element.InnerText
    $element.InnerText = [string]$Value
    return [pscustomobject]@{
        previous = $previous
        current  = [string]$element.InnerText
    }
}

function Resolve-LvversionAuthorityInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRootPath,
        [Parameter(Mandatory = $true)]
        [ValidateSet('32', '64')]
        [string]$Bitness
    )

    $resolvedRepoRoot = Resolve-FullPath -Path $RepoRootPath
    if (-not (Test-Path -LiteralPath $resolvedRepoRoot -PathType Container)) {
        throw "RepoRoot directory not found: $resolvedRepoRoot"
    }

    $lvversionPath = Join-Path -Path $resolvedRepoRoot -ChildPath '.lvversion'
    if (-not (Test-Path -LiteralPath $lvversionPath -PathType Leaf)) {
        throw ".lvversion not found at $lvversionPath"
    }

    $rawValue = (Get-Content -LiteralPath $lvversionPath -Raw -ErrorAction Stop).Trim()
    if ($rawValue -notmatch '^(?<major>\d+)\.(?<minor>\d+)$') {
        throw ".lvversion value '$rawValue' is invalid. Expected numeric major.minor format (for example '26.0')."
    }

    $major = [int]$Matches['major']
    $minor = [int]$Matches['minor']
    $year = 2000 + $major
    $numeric = "{0}.{1}" -f $major, $minor
    $expectedVipbTarget = if ($Bitness -eq '64') {
        "{0} (64-bit)" -f $numeric
    } else {
        $numeric
    }

    return [pscustomobject]@{
        RepoRoot = $resolvedRepoRoot
        LvversionPath = $lvversionPath
        Raw = $rawValue
        Numeric = $numeric
        Year = $year
        MinorRevision = $minor
        ExpectedVipbTarget = $expectedVipbTarget
    }
}

try {
    $authorityInfo = Resolve-LvversionAuthorityInfo -RepoRootPath $RepoRoot -Bitness $SupportedBitness

    if ($LabVIEWVersionYear -ne $authorityInfo.Year -or $LabVIEWMinorRevision -ne $authorityInfo.MinorRevision) {
        throw (
            "LabVIEW version hint mismatch with .lvversion. Provided '{0}.{1}' but .lvversion '{2}' resolves to '{3}.{4}'." -f
            $LabVIEWVersionYear, $LabVIEWMinorRevision, $authorityInfo.Raw, $authorityInfo.Year, $authorityInfo.MinorRevision
        )
    }

    $resolvedVipbPath = Resolve-FullPath -Path $VipbPath
    if (-not (Test-Path -LiteralPath $resolvedVipbPath -PathType Leaf)) {
        throw "VIPB file not found: $resolvedVipbPath"
    }

    $resolvedReleaseNotesPath = Resolve-FullPath -Path $ReleaseNotesFile
    if (-not (Test-Path -LiteralPath $resolvedReleaseNotesPath -PathType Leaf)) {
        throw "Release notes file not found: $resolvedReleaseNotesPath"
    }

    $resolvedDiffOutputPath = Resolve-FullPath -Path $DiffOutputPath
    $resolvedSummaryPath = Resolve-FullPath -Path $SummaryMarkdownPath
    Ensure-ParentDirectory -Path $resolvedDiffOutputPath
    Ensure-ParentDirectory -Path $resolvedSummaryPath

    try {
        $displayInfo = $DisplayInformationJson | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "DisplayInformationJson is not valid JSON."
    }

    $releaseNotes = Get-Content -LiteralPath $resolvedReleaseNotesPath -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($releaseNotes)) {
        $releaseNotes = [string]$displayInfo.'Release Notes - Change Log'
    }
    if ($null -eq $releaseNotes) {
        $releaseNotes = ''
    }

    $allowedFields = @(
        'Package Version',
        'Company Name',
        'Product Name',
        'Product Description Summary',
        'Product Description',
        'Author Name (Person or Company)',
        'Product Homepage (URL)',
        'Legal Copyright',
        'Release Notes - Change Log',
        'License Agreement Name'
    )

    $requiredFields = @(
        'Company Name',
        'Product Name',
        'Product Description Summary',
        'Product Description'
    )

    $providedFields = @($displayInfo.PSObject.Properties.Name)
    $unexpected = @($providedFields | Where-Object { $_ -notin $allowedFields })
    if ($unexpected.Count -gt 0) {
        throw ("DisplayInformationJson contains unsupported fields: {0}" -f ($unexpected -join ', '))
    }

    $missingRequired = @($requiredFields | Where-Object {
        [string]::IsNullOrWhiteSpace([string]$displayInfo.PSObject.Properties[$_].Value)
    })
    if ($missingRequired.Count -gt 0) {
        throw ("DisplayInformationJson is missing required fields: {0}" -f ($missingRequired -join ', '))
    }

    [xml]$vipbXml = Get-Content -LiteralPath $resolvedVipbPath -Raw -ErrorAction Stop
    $vipbXml.PreserveWhitespace = $true

    $generalSettings = $vipbXml.VI_Package_Builder_Settings.Library_General_Settings
    $advancedSettings = $vipbXml.VI_Package_Builder_Settings.Advanced_Settings
    $descriptionSettings = $advancedSettings.Description
    if ($null -eq $generalSettings -or $null -eq $advancedSettings -or $null -eq $descriptionSettings) {
        throw "VIPB file is missing expected sections: Library_General_Settings and Advanced_Settings/Description."
    }

    $currentVipbTarget = [string]$generalSettings.Package_LabVIEW_Version
    if (-not [string]::Equals($currentVipbTarget, $authorityInfo.ExpectedVipbTarget, [System.StringComparison]::Ordinal)) {
        throw (
            "VIPB/.lvversion contract mismatch. VIPB Package_LabVIEW_Version '{0}' does not match .lvversion target '{1}' from '{2}'." -f
            $currentVipbTarget, $authorityInfo.ExpectedVipbTarget, $authorityInfo.LvversionPath
        )
    }

    $changes = New-Object 'System.Collections.Generic.List[object]'

    $libraryVersionValue = "{0}.{1}.{2}.{3}" -f $Major, $Minor, $Patch, $Build
    $packageLabVIEWVersion = $authorityInfo.ExpectedVipbTarget

    $descriptionValue = [string]$displayInfo.'Product Description'
    if (-not [string]::IsNullOrWhiteSpace($Commit)) {
        $descriptionValue = "{0}`n`nCommit: {1}" -f $descriptionValue, $Commit
    }

    $mappedUpdates = @(
        @{ Parent = $generalSettings; Element = 'Library_Version'; Field = 'Library_Version'; Value = $libraryVersionValue },
        @{ Parent = $generalSettings; Element = 'Package_LabVIEW_Version'; Field = 'Package_LabVIEW_Version'; Value = $packageLabVIEWVersion },
        @{ Parent = $generalSettings; Element = 'Company_Name'; Field = 'Company_Name'; Value = [string]$displayInfo.'Company Name' },
        @{ Parent = $generalSettings; Element = 'Product_Name'; Field = 'Product_Name'; Value = [string]$displayInfo.'Product Name' },
        @{ Parent = $descriptionSettings; Element = 'One_Line_Description_Summary'; Field = 'One_Line_Description_Summary'; Value = [string]$displayInfo.'Product Description Summary' },
        @{ Parent = $descriptionSettings; Element = 'Packager'; Field = 'Packager'; Value = [string]$displayInfo.'Author Name (Person or Company)' },
        @{ Parent = $descriptionSettings; Element = 'URL'; Field = 'URL'; Value = [string]$displayInfo.'Product Homepage (URL)' },
        @{ Parent = $descriptionSettings; Element = 'Copyright'; Field = 'Copyright'; Value = [string]$displayInfo.'Legal Copyright' },
        @{ Parent = $descriptionSettings; Element = 'Release_Notes'; Field = 'Release_Notes'; Value = [string]$releaseNotes },
        @{ Parent = $descriptionSettings; Element = 'Description'; Field = 'Description'; Value = $descriptionValue },
        @{ Parent = $advancedSettings; Element = 'License_Agreement_Filepath'; Field = 'License_Agreement_Filepath'; Value = '' }
    )

    foreach ($update in $mappedUpdates) {
        $result = Set-OrCreateElementText `
            -Document $vipbXml `
            -ParentNode $update.Parent `
            -ElementName $update.Element `
            -Value $update.Value
        Add-FieldChange -Changes $changes -Field $update.Field -PreviousValue $result.previous -CurrentValue $result.current
    }

    $sourceFilesNode = $advancedSettings.SelectSingleNode('Source_Files')
    if ($null -eq $sourceFilesNode) {
        $sourceFilesNode = $vipbXml.CreateElement('Source_Files')
        [void]$advancedSettings.AppendChild($sourceFilesNode)
    }

    $beforePaths = @($sourceFilesNode.SelectNodes('Exclusions/Path') | ForEach-Object { [string]$_.InnerText })
    $hasTestResultsExclusion = $beforePaths -contains 'TestResults'
    if (-not $hasTestResultsExclusion) {
        $exclusionNode = $vipbXml.CreateElement('Exclusions')
        $pathNode = $vipbXml.CreateElement('Path')
        $pathNode.InnerText = 'TestResults'
        [void]$exclusionNode.AppendChild($pathNode)
        [void]$sourceFilesNode.AppendChild($exclusionNode)
    }
    $afterPaths = @($sourceFilesNode.SelectNodes('Exclusions/Path') | ForEach-Object { [string]$_.InnerText })
    Add-FieldChange `
        -Changes $changes `
        -Field 'Source_Files.Exclusions.Path' `
        -PreviousValue ($beforePaths -join '; ') `
        -CurrentValue ($afterPaths -join '; ')

    $writerSettings = New-Object System.Xml.XmlWriterSettings
    $writerSettings.Indent = $true
    $writerSettings.IndentChars = '  '
    $writerSettings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
    $writerSettings.NewLineChars = "`n"
    $writer = [System.Xml.XmlWriter]::Create($resolvedVipbPath, $writerSettings)
    $vipbXml.Save($writer)
    $writer.Close()

    $fieldEntries = $changes.ToArray()
    $changedEntries = @($fieldEntries | Where-Object { $_.changed })

    $diff = [ordered]@{
        vipb_path           = $resolvedVipbPath
        timestamp_utc       = (Get-Date).ToUniversalTime().ToString('o')
        touched_field_count = $fieldEntries.Count
        changed_field_count = $changedEntries.Count
        changed_fields      = @($changedEntries | ForEach-Object { $_.field })
        fields              = $fieldEntries
    }
    $diff | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resolvedDiffOutputPath -Encoding UTF8

    $status = if ($changedEntries.Count -gt 0) {
        'VIPB metadata updated'
    } else {
        'VIPB metadata no changes'
    }

    $summaryLines = New-Object 'System.Collections.Generic.List[string]'
    $summaryLines.Add('## VIPB Metadata Delta')
    $summaryLines.Add('')
    $summaryLines.Add(("- Status: {0}" -f $status))
    $summaryLines.Add(("- Changed fields: {0} / {1}" -f $changedEntries.Count, $fieldEntries.Count))
    $summaryLines.Add(('- VIPB path: `{0}`' -f $resolvedVipbPath))
    $summaryLines.Add('')
    $summaryLines.Add('| Field | Changed | Before | After |')
    $summaryLines.Add('| --- | --- | --- | --- |')
    foreach ($entry in $fieldEntries) {
        $changedCell = if ($entry.changed) { 'yes' } else { 'no' }
        $fieldCell = Format-MarkdownCell -Value ([string]$entry.field)
        $beforeCell = Format-MarkdownCell -Value ([string]$entry.previous)
        $afterCell = Format-MarkdownCell -Value ([string]$entry.current)
        $summaryLines.Add("| $fieldCell | $changedCell | $beforeCell | $afterCell |")
    }
    $summaryLines -join [Environment]::NewLine | Set-Content -LiteralPath $resolvedSummaryPath -Encoding UTF8

    Write-Host ("VIPB metadata status: {0}" -f $status)
    Write-Host ("VIPB diff JSON: {0}" -f $resolvedDiffOutputPath)
    Write-Host ("VIPB summary markdown: {0}" -f $resolvedSummaryPath)
}
catch {
    $errorPayload = [ordered]@{
        error               = 'Failed to update VIPB metadata.'
        type                = $_.Exception.GetType().FullName
        message             = $_.Exception.Message
        line                = $_.InvocationInfo.ScriptLineNumber
        column              = $_.InvocationInfo.OffsetInLine
        repo_root           = $RepoRoot
        vipb_path           = $VipbPath
        diff_output_path    = $DiffOutputPath
        summary_output_path = $SummaryMarkdownPath
    }
    Write-Error ($errorPayload | ConvertTo-Json -Depth 4)
    exit 1
}
