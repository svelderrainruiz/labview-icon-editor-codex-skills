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
    [string]$OutputDirectory,

    [string]$SourceRepository = $env:GITHUB_REPOSITORY,
    [string]$SourceRef = $env:GITHUB_REF,
    [string]$SourceSha = $env:GITHUB_SHA,
    [string]$BuildRunId = $env:GITHUB_RUN_ID,
    [string]$BuildRunAttempt = $env:GITHUB_RUN_ATTEMPT,

    [string]$UpdateScriptPath = 'scripts/Update-VipbDisplayInfo.ps1'
)

Set-StrictMode -Version Latest
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

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Get-FileSnapshotInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [ordered]@{
            path = $Path
            exists = $false
        }
    }

    $item = Get-Item -LiteralPath $Path
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    return [ordered]@{
        path = $Path
        exists = $true
        sha256 = $hash
        size_bytes = [int64]$item.Length
    }
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Value,
        [int]$Depth = 10
    )

    $parent = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        Ensure-Directory -Path $parent
    }
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-OptionalPropertyValue {
    param(
        [AllowNull()]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$PropertyName,
        [AllowNull()]
        [object]$DefaultValue = $null
    )

    if ($null -eq $Object) {
        return $DefaultValue
    }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($PropertyName)) {
            return $Object[$PropertyName]
        }

        return $DefaultValue
    }

    $property = $Object.PSObject.Properties[$PropertyName]
    if ($null -eq $property) {
        return $DefaultValue
    }

    return $property.Value
}

function Format-MarkdownCell {
    param(
        [AllowNull()]
        [string]$Value,
        [int]$MaxLength = 180
    )

    if ($null -eq $Value) {
        return ''
    }

    $normalized = $Value -replace "`r`n", "`n" -replace "`r", "`n"
    $normalized = $normalized.Replace('|', '\|')
    $normalized = $normalized -replace "`n", '<br/>'
    $normalized = $normalized.Replace('`', '\`')

    if ($normalized.Length -gt $MaxLength) {
        return $normalized.Substring(0, $MaxLength - 3) + '...'
    }

    return $normalized
}

function Get-DisplayPath {
    param(
        [AllowNull()]
        [string]$Path,
        [AllowNull()]
        [string]$BasePath
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    $resolvedPath = Resolve-FullPath -Path $Path
    if ([string]::IsNullOrWhiteSpace($BasePath)) {
        return $resolvedPath
    }

    $resolvedBasePath = Resolve-FullPath -Path $BasePath
    $relativePath = [System.IO.Path]::GetRelativePath($resolvedBasePath, $resolvedPath)
    $outsideBase = (
        $relativePath -eq '..' -or
        $relativePath.StartsWith('..' + [IO.Path]::DirectorySeparatorChar) -or
        $relativePath.StartsWith('..' + [IO.Path]::AltDirectorySeparatorChar)
    )
    if (-not $outsideBase) {
        return $relativePath.Replace('\', '/')
    }

    return $resolvedPath
}

function New-InventoryEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [AllowNull()]
        [object]$Info,
        [AllowNull()]
        [string]$BasePath
    )

    $rawPath = [string](Get-OptionalPropertyValue -Object $Info -PropertyName 'path' -DefaultValue '')
    $exists = [bool](Get-OptionalPropertyValue -Object $Info -PropertyName 'exists' -DefaultValue $false)
    $sha = [string](Get-OptionalPropertyValue -Object $Info -PropertyName 'sha256' -DefaultValue '')
    $size = Get-OptionalPropertyValue -Object $Info -PropertyName 'size_bytes' -DefaultValue $null
    $displayPath = Get-DisplayPath -Path $rawPath -BasePath $BasePath

    return [pscustomobject]@{
        label = $Label
        path = $displayPath
        exists = $exists
        size_bytes = $size
        sha256 = $sha
    }
}

function Remove-MarkdownHeading {
    param(
        [AllowNull()]
        [string]$Markdown,
        [string]$Heading = '## VIPB Metadata Delta'
    )

    if ([string]::IsNullOrWhiteSpace($Markdown)) {
        return ''
    }

    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in ($Markdown -split "`r?`n")) {
        $lines.Add($line)
    }

    while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($lines[0])) {
        $lines.RemoveAt(0)
    }
    if ($lines.Count -gt 0 -and $lines[0].Trim() -eq $Heading) {
        $lines.RemoveAt(0)
    }
    while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($lines[0])) {
        $lines.RemoveAt(0)
    }

    return ($lines -join [Environment]::NewLine).TrimEnd()
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
    }
    else {
        $numeric
    }

    return [ordered]@{
        repo_root = $resolvedRepoRoot
        lvversion_path = $lvversionPath
        lvversion_raw = $rawValue
        lvversion_numeric = $numeric
        lvversion_year = $year
        lvversion_minor = $minor
        expected_vipb_target = $expectedVipbTarget
    }
}

function Get-VipbPackageLabVIEWVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VipbFilePath
    )

    if (-not (Test-Path -LiteralPath $VipbFilePath -PathType Leaf)) {
        return ''
    }

    [xml]$vipbXml = Get-Content -LiteralPath $VipbFilePath -Raw -ErrorAction Stop
    $rawValue = [string]$vipbXml.VI_Package_Builder_Settings.Library_General_Settings.Package_LabVIEW_Version
    if ($null -eq $rawValue) {
        return ''
    }

    return $rawValue.Trim()
}

$startedUtc = (Get-Date).ToUniversalTime()
$resolvedOutputDirectory = Resolve-FullPath -Path $OutputDirectory
Ensure-Directory -Path $resolvedOutputDirectory

$paths = [ordered]@{
    log_path = Join-Path $resolvedOutputDirectory 'prepare-vipb.log'
    status_path = Join-Path $resolvedOutputDirectory 'prepare-vipb.status.json'
    error_path = Join-Path $resolvedOutputDirectory 'prepare-vipb.error.json'
    diagnostics_path = Join-Path $resolvedOutputDirectory 'vipb-diagnostics.json'
    diagnostics_summary_path = Join-Path $resolvedOutputDirectory 'vipb-diagnostics-summary.md'
    diff_path = Join-Path $resolvedOutputDirectory 'vipb-diff.json'
    diff_summary_path = Join-Path $resolvedOutputDirectory 'vipb-diff-summary.md'
    display_info_input_path = Join-Path $resolvedOutputDirectory 'display-information.input.json'
    before_snapshot_path = Join-Path $resolvedOutputDirectory 'vipb.before.xml'
    after_snapshot_path = Join-Path $resolvedOutputDirectory 'vipb.after.xml'
    before_hash_path = Join-Path $resolvedOutputDirectory 'vipb.before.sha256'
    after_hash_path = Join-Path $resolvedOutputDirectory 'vipb.after.sha256'
    prepared_vipb_path = Join-Path $resolvedOutputDirectory 'NI Icon editor.vipb'
}

if (Test-Path -LiteralPath $paths.log_path -PathType Leaf) {
    Remove-Item -LiteralPath $paths.log_path -Force
}
New-Item -Path $paths.log_path -ItemType File -Force | Out-Null

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $line = "[{0}] {1}" -f ((Get-Date).ToUniversalTime().ToString('o')), $Message
    Add-Content -LiteralPath $paths.log_path -Value $line -Encoding UTF8
    Write-Host $line
}

$status = 'failed'
$errorPayload = $null
$diff = $null
$resolvedRepoRoot = $null
$resolvedVipbPath = $null
$resolvedReleaseNotesPath = $null
$resolvedUpdateScriptPath = $null
$versionAuthority = [ordered]@{
    repo_root = $null
    lvversion_path = $null
    lvversion_raw = $null
    lvversion_numeric = $null
    lvversion_year = $null
    lvversion_minor = $null
    expected_vipb_target = $null
    observed_vipb_target = $null
    check_result = 'unknown'
}

Write-Log "Starting VIPB diagnostics suite."

try {
    $resolvedRepoRoot = Resolve-FullPath -Path $RepoRoot
    $resolvedVipbPath = Resolve-FullPath -Path $VipbPath
    $resolvedReleaseNotesPath = Resolve-FullPath -Path $ReleaseNotesFile
    $resolvedUpdateScriptPath = Resolve-FullPath -Path $UpdateScriptPath

    if (-not (Test-Path -LiteralPath $resolvedVipbPath -PathType Leaf)) {
        throw "VIPB file not found: $resolvedVipbPath"
    }
    if (-not (Test-Path -LiteralPath $resolvedReleaseNotesPath -PathType Leaf)) {
        throw "Release notes file not found: $resolvedReleaseNotesPath"
    }
    if (-not (Test-Path -LiteralPath $resolvedUpdateScriptPath -PathType Leaf)) {
        throw "Update script not found: $resolvedUpdateScriptPath"
    }

    $versionAuthority = Resolve-LvversionAuthorityInfo -RepoRootPath $resolvedRepoRoot -Bitness $SupportedBitness
    $versionAuthority.observed_vipb_target = Get-VipbPackageLabVIEWVersion -VipbFilePath $resolvedVipbPath
    $versionAuthority.check_result = if (
        [string]::Equals(
            [string]$versionAuthority.observed_vipb_target,
            [string]$versionAuthority.expected_vipb_target,
            [System.StringComparison]::Ordinal
        )
    ) {
        'pass'
    }
    else {
        'fail'
    }

    $displayInfoRaw = [string]$DisplayInformationJson
    if ([string]::IsNullOrWhiteSpace($displayInfoRaw)) {
        throw "DisplayInformationJson is empty."
    }

    # Persist raw input exactly as provided for reproducibility.
    Set-Content -LiteralPath $paths.display_info_input_path -Value $displayInfoRaw -Encoding UTF8
    $null = $displayInfoRaw | ConvertFrom-Json -ErrorAction Stop

    Copy-Item -LiteralPath $resolvedVipbPath -Destination $paths.before_snapshot_path -Force
    $beforeInfo = Get-FileSnapshotInfo -Path $paths.before_snapshot_path
    if ($beforeInfo.exists) {
        Set-Content -LiteralPath $paths.before_hash_path -Value $beforeInfo.sha256 -Encoding ASCII
    }
    Write-Log ("Captured pre-update snapshot: {0}" -f $paths.before_snapshot_path)

    $updateArguments = @(
        '-NoProfile',
        '-File', $resolvedUpdateScriptPath,
        '-RepoRoot', $resolvedRepoRoot,
        '-VipbPath', $resolvedVipbPath,
        '-ReleaseNotesFile', $resolvedReleaseNotesPath,
        '-DisplayInformationJson', $displayInfoRaw,
        '-LabVIEWVersionYear', [string]$LabVIEWVersionYear,
        '-LabVIEWMinorRevision', [string]$LabVIEWMinorRevision,
        '-SupportedBitness', $SupportedBitness,
        '-Major', [string]$Major,
        '-Minor', [string]$Minor,
        '-Patch', [string]$Patch,
        '-Build', [string]$Build,
        '-DiffOutputPath', $paths.diff_path,
        '-SummaryMarkdownPath', $paths.diff_summary_path
    )
    if (-not [string]::IsNullOrWhiteSpace($Commit)) {
        $updateArguments += @('-Commit', $Commit)
    }

    $updateOutput = & pwsh @updateArguments 2>&1
    foreach ($line in @($updateOutput)) {
        Write-Log ([string]$line)
    }
    if ($LASTEXITCODE -ne 0) {
        $updateFailurePatterns = @(
            'VIPB/.lvversion contract mismatch',
            'LabVIEW version hint mismatch with \.lvversion',
            '\.lvversion not found'
        )
        $failureDetail = @($updateOutput | ForEach-Object { [string]$_ } | Where-Object {
            $candidate = $_
            foreach ($pattern in $updateFailurePatterns) {
                if ($candidate -match $pattern) {
                    return $true
                }
            }
            return $false
        } | Select-Object -Last 1)

        if ($failureDetail.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($failureDetail[0])) {
            throw "Update-VipbDisplayInfo.ps1 failed with exit code $LASTEXITCODE. $($failureDetail[0])"
        }

        throw "Update-VipbDisplayInfo.ps1 failed with exit code $LASTEXITCODE."
    }

    Copy-Item -LiteralPath $resolvedVipbPath -Destination $paths.after_snapshot_path -Force
    $afterInfo = Get-FileSnapshotInfo -Path $paths.after_snapshot_path
    if ($afterInfo.exists) {
        Set-Content -LiteralPath $paths.after_hash_path -Value $afterInfo.sha256 -Encoding ASCII
    }
    Copy-Item -LiteralPath $resolvedVipbPath -Destination $paths.prepared_vipb_path -Force
    Write-Log ("Captured post-update snapshot: {0}" -f $paths.after_snapshot_path)
    Write-Log ("Prepared VIPB path: {0}" -f $paths.prepared_vipb_path)

    if (Test-Path -LiteralPath $paths.diff_path -PathType Leaf) {
        $diff = Get-Content -LiteralPath $paths.diff_path -Raw | ConvertFrom-Json
    } else {
        throw "Expected diff output was not produced: $($paths.diff_path)"
    }

    $changedCount = 0
    if ($null -ne $diff -and $null -ne $diff.changed_field_count) {
        $changedCount = [int]$diff.changed_field_count
    }
    $status = if ($changedCount -gt 0) { 'updated' } else { 'no_changes' }
    Write-Log ("VIPB diagnostics status resolved to '{0}'." -f $status)
}
catch {
    $status = 'failed'
    $errorPayload = [ordered]@{
        error = 'VIPB diagnostics suite failed.'
        type = $_.Exception.GetType().FullName
        message = $_.Exception.Message
        line = $_.InvocationInfo.ScriptLineNumber
        column = $_.InvocationInfo.OffsetInLine
        repo_root = $RepoRoot
        vipb_path = $VipbPath
        release_notes_path = $ReleaseNotesFile
        version_authority_check = $versionAuthority.check_result
    }
    Write-Log ("ERROR: {0}" -f $errorPayload.message)
}
finally {
    $completedUtc = (Get-Date).ToUniversalTime()
    $durationSeconds = [math]::Round(($completedUtc - $startedUtc).TotalSeconds, 3)

    $beforeSnapshotInfo = Get-FileSnapshotInfo -Path $paths.before_snapshot_path
    $afterSnapshotInfo = Get-FileSnapshotInfo -Path $paths.after_snapshot_path
    $preparedVipbInfo = Get-FileSnapshotInfo -Path $paths.prepared_vipb_path
    $diffInfo = Get-FileSnapshotInfo -Path $paths.diff_path
    $diffSummaryInfo = Get-FileSnapshotInfo -Path $paths.diff_summary_path
    $displayInfoInput = Get-FileSnapshotInfo -Path $paths.display_info_input_path

    if ($status -eq 'failed' -and $null -ne $errorPayload) {
        Write-JsonFile -Path $paths.error_path -Value $errorPayload -Depth 6
    }
    $errorInfo = Get-FileSnapshotInfo -Path $paths.error_path

    $changedFields = @()
    $changedFieldCount = 0
    $touchedFieldCount = 0
    if ($null -ne $diff) {
        if ($null -ne $diff.changed_fields) {
            $changedFields = @($diff.changed_fields)
        }
        if ($null -ne $diff.changed_field_count) {
            $changedFieldCount = [int]$diff.changed_field_count
        }
        if ($null -ne $diff.touched_field_count) {
            $touchedFieldCount = [int]$diff.touched_field_count
        }
    }

    $statusPayload = [ordered]@{
        status = $status
        timestamp_utc = $completedUtc.ToString('o')
        diagnostics_path = $paths.diagnostics_path
        summary_path = $paths.diagnostics_summary_path
        error_path = if ($status -eq 'failed') { $paths.error_path } else { $null }
    }
    Write-JsonFile -Path $paths.status_path -Value $statusPayload -Depth 6
    $statusInfo = Get-FileSnapshotInfo -Path $paths.status_path

    $diagnostics = [ordered]@{
        summary_format_version = 2
        status = $status
        started_utc = $startedUtc.ToString('o')
        completed_utc = $completedUtc.ToString('o')
        duration_seconds = $durationSeconds
        source = [ordered]@{
            repository = $SourceRepository
            ref = $SourceRef
            sha = $SourceSha
        }
        workflow = [ordered]@{
            run_id = $BuildRunId
            run_attempt = $BuildRunAttempt
        }
        labview = [ordered]@{
            year = [string]$LabVIEWVersionYear
            minor_revision = [string]$LabVIEWMinorRevision
            bitness = $SupportedBitness
        }
        version_authority = $versionAuthority
        package_version = [ordered]@{
            major = $Major
            minor = $Minor
            patch = $Patch
            build = $Build
            commit = $Commit
        }
        diff = [ordered]@{
            changed_field_count = $changedFieldCount
            touched_field_count = $touchedFieldCount
            changed_fields = $changedFields
            diff_path = $paths.diff_path
            diff_summary_path = $paths.diff_summary_path
        }
        outputs = [ordered]@{
            prepared_vipb = $preparedVipbInfo
            vipb_before = $beforeSnapshotInfo
            vipb_after = $afterSnapshotInfo
            diff_json = $diffInfo
            diff_summary_markdown = $diffSummaryInfo
            display_information_input = $displayInfoInput
            status_json = $statusInfo
            error_json = $errorInfo
            log_file = (Get-FileSnapshotInfo -Path $paths.log_path)
        }
        tooling = [ordered]@{
            pwsh_version = $PSVersionTable.PSVersion.ToString()
            platform = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
            update_script_path = $resolvedUpdateScriptPath
        }
        error = $errorPayload
    }

    Write-JsonFile -Path $paths.diagnostics_path -Value $diagnostics -Depth 12

    $workspaceRoot = if (
        -not [string]::IsNullOrWhiteSpace($env:GITHUB_WORKSPACE) -and
        (Test-Path -LiteralPath $env:GITHUB_WORKSPACE -PathType Container)
    ) {
        Resolve-FullPath -Path $env:GITHUB_WORKSPACE
    }
    else {
        Resolve-FullPath -Path (Join-Path $PSScriptRoot '..')
    }

    $inventoryEntries = @(
        (New-InventoryEntry -Label 'prepared_vipb' -Info $preparedVipbInfo -BasePath $workspaceRoot),
        (New-InventoryEntry -Label 'vipb_before' -Info $beforeSnapshotInfo -BasePath $workspaceRoot),
        (New-InventoryEntry -Label 'vipb_after' -Info $afterSnapshotInfo -BasePath $workspaceRoot),
        (New-InventoryEntry -Label 'diff_json' -Info $diffInfo -BasePath $workspaceRoot),
        (New-InventoryEntry -Label 'diff_summary_markdown' -Info $diffSummaryInfo -BasePath $workspaceRoot),
        (New-InventoryEntry -Label 'diagnostics_json' -Info (Get-FileSnapshotInfo -Path $paths.diagnostics_path) -BasePath $workspaceRoot),
        (New-InventoryEntry -Label 'status_json' -Info $statusInfo -BasePath $workspaceRoot),
        (New-InventoryEntry -Label 'error_json' -Info $errorInfo -BasePath $workspaceRoot),
        (New-InventoryEntry -Label 'log_file' -Info (Get-FileSnapshotInfo -Path $paths.log_path) -BasePath $workspaceRoot),
        (New-InventoryEntry -Label 'display_information_input' -Info $displayInfoInput -BasePath $workspaceRoot)
    )

    $diagnosticsSummary = New-Object 'System.Collections.Generic.List[string]'
    $diagnosticsSummary.Add('## VIPB Diagnostics Suite')
    $diagnosticsSummary.Add('')
    $diagnosticsSummary.Add(('- Status: `{0}`' -f $status))
    $diagnosticsSummary.Add(('- Changed fields: `{0}` / `{1}`' -f $changedFieldCount, $touchedFieldCount))
    $diagnosticsSummary.Add(('- Duration seconds: `{0}`' -f $durationSeconds))
    $diagnosticsSummary.Add(('- Source: `{0}` @ `{1}`' -f $SourceRepository, $SourceSha))
    $diagnosticsSummary.Add(('- Workflow run: `{0}` attempt `{1}`' -f $BuildRunId, $BuildRunAttempt))
    $diagnosticsSummary.Add('')
    $diagnosticsSummary.Add('### Version Authority')
    $diagnosticsSummary.Add('')
    $diagnosticsSummary.Add(('- Repo root: `{0}`' -f (Format-MarkdownCell -Value (Get-DisplayPath -Path ([string]$versionAuthority.repo_root) -BasePath $workspaceRoot) -MaxLength 260)))
    $diagnosticsSummary.Add(('- .lvversion path: `{0}`' -f (Format-MarkdownCell -Value (Get-DisplayPath -Path ([string]$versionAuthority.lvversion_path) -BasePath $workspaceRoot) -MaxLength 260)))
    $diagnosticsSummary.Add(('- .lvversion raw: `{0}`' -f (Format-MarkdownCell -Value ([string]$versionAuthority.lvversion_raw) -MaxLength 60)))
    $diagnosticsSummary.Add(('- Expected VIPB target: `{0}`' -f (Format-MarkdownCell -Value ([string]$versionAuthority.expected_vipb_target) -MaxLength 120)))
    $diagnosticsSummary.Add(('- Observed VIPB target: `{0}`' -f (Format-MarkdownCell -Value ([string]$versionAuthority.observed_vipb_target) -MaxLength 120)))
    $diagnosticsSummary.Add(('- Authority check: `{0}`' -f (Format-MarkdownCell -Value ([string]$versionAuthority.check_result) -MaxLength 20)))
    $diagnosticsSummary.Add('')
    $diagnosticsSummary.Add('### Changed Fields Quick View')
    $diagnosticsSummary.Add('')
    if ($changedFields.Count -gt 0) {
        foreach ($field in $changedFields) {
            $fieldText = Format-MarkdownCell -Value ([string]$field) -MaxLength 120
            $diagnosticsSummary.Add(('- `{0}`' -f $fieldText))
        }
    }
    else {
        $diagnosticsSummary.Add('- none')
    }
    $diagnosticsSummary.Add('')
    $diagnosticsSummary.Add('### File Inventory')
    $diagnosticsSummary.Add('')
    $diagnosticsSummary.Add('| Label | Path | Exists | Size (bytes) | SHA256 |')
    $diagnosticsSummary.Add('| --- | --- | --- | --- | --- |')
    foreach ($entry in $inventoryEntries) {
        $labelText = Format-MarkdownCell -Value ([string]$entry.label) -MaxLength 80
        $pathText = Format-MarkdownCell -Value ([string]$entry.path) -MaxLength 260
        $existsText = if ($entry.exists) { 'yes' } else { 'no' }
        $sizeText = if ($null -ne $entry.size_bytes) { [string]$entry.size_bytes } else { '' }
        $shaText = if (-not [string]::IsNullOrWhiteSpace([string]$entry.sha256)) {
            Format-MarkdownCell -Value ([string]$entry.sha256) -MaxLength 80
        }
        else {
            ''
        }
        $diagnosticsSummary.Add("| $labelText | $pathText | $existsText | $sizeText | $shaText |")
    }

    if (Test-Path -LiteralPath $paths.diff_summary_path -PathType Leaf) {
        $fieldDeltaContent = Remove-MarkdownHeading -Markdown (Get-Content -LiteralPath $paths.diff_summary_path -Raw)
        if (-not [string]::IsNullOrWhiteSpace($fieldDeltaContent)) {
            $diagnosticsSummary.Add('')
            $diagnosticsSummary.Add('### Field Delta')
            $diagnosticsSummary.Add('')
            $diagnosticsSummary.Add($fieldDeltaContent)
        }
    }

    if ($status -eq 'failed' -and $null -ne $errorPayload) {
        $errorPayloadPath = Get-DisplayPath -Path $paths.error_path -BasePath $workspaceRoot
        $diagnosticsSummary.Add('')
        $diagnosticsSummary.Add('### Failure')
        $diagnosticsSummary.Add('')
        $diagnosticsSummary.Add(('- Error type: `{0}`' -f $errorPayload.type))
        $diagnosticsSummary.Add(('- Message: `{0}`' -f (Format-MarkdownCell -Value $errorPayload.message -MaxLength 260)))
        $diagnosticsSummary.Add(('- Error payload: `{0}`' -f (Format-MarkdownCell -Value $errorPayloadPath -MaxLength 260)))
    }

    $diagnosticsSummary -join [Environment]::NewLine | Set-Content -LiteralPath $paths.diagnostics_summary_path -Encoding UTF8
    Write-Log ("Wrote diagnostics summary: {0}" -f $paths.diagnostics_summary_path)
    Write-Log ("Wrote diagnostics JSON: {0}" -f $paths.diagnostics_path)
    Write-Log ("Wrote status JSON: {0}" -f $paths.status_path)

    if ($status -eq 'failed') {
        throw "VIPB diagnostics suite failed. See '$($paths.error_path)' and '$($paths.log_path)'."
    }
}
