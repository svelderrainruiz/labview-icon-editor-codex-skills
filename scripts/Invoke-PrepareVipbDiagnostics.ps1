#Requires -Version 7.0

[CmdletBinding()]
param(
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
$resolvedVipbPath = $null
$resolvedReleaseNotesPath = $null
$resolvedUpdateScriptPath = $null

Write-Log "Starting VIPB diagnostics suite."

try {
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
        vipb_path = $VipbPath
        release_notes_path = $ReleaseNotesFile
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

    $diagnosticsSummary = New-Object 'System.Collections.Generic.List[string]'
    $diagnosticsSummary.Add('## VIPB Diagnostics Suite')
    $diagnosticsSummary.Add('')
    $diagnosticsSummary.Add(('- Status: `{0}`' -f $status))
    $diagnosticsSummary.Add(('- Changed fields: `{0}` / `{1}`' -f $changedFieldCount, $touchedFieldCount))
    $diagnosticsSummary.Add(('- Duration seconds: `{0}`' -f $durationSeconds))
    $diagnosticsSummary.Add(('- Source: `{0}` @ `{1}`' -f $SourceRepository, $SourceSha))
    $diagnosticsSummary.Add(('- Workflow run: `{0}` attempt `{1}`' -f $BuildRunId, $BuildRunAttempt))
    $diagnosticsSummary.Add('')
    $diagnosticsSummary.Add('### File Inventory')
    $diagnosticsSummary.Add('')
    $diagnosticsSummary.Add('| File | Exists | Size (bytes) | SHA256 |')
    $diagnosticsSummary.Add('| --- | --- | --- | --- |')
    foreach ($entry in @(
        $preparedVipbInfo,
        $beforeSnapshotInfo,
        $afterSnapshotInfo,
        $diffInfo,
        $diffSummaryInfo,
        (Get-FileSnapshotInfo -Path $paths.diagnostics_path),
        (Get-FileSnapshotInfo -Path $paths.status_path),
        $errorInfo,
        (Get-FileSnapshotInfo -Path $paths.log_path),
        $displayInfoInput
    )) {
        $existsText = if ($entry.exists) { 'yes' } else { 'no' }
        $sizeText = if ($entry.Contains('size_bytes')) { [string]$entry.size_bytes } else { '' }
        $shaText = if ($entry.Contains('sha256')) { [string]$entry.sha256 } else { '' }
        $diagnosticsSummary.Add("| `$($entry.path)` | $existsText | $sizeText | $shaText |")
    }

    if (Test-Path -LiteralPath $paths.diff_summary_path -PathType Leaf) {
        $diagnosticsSummary.Add('')
        $diagnosticsSummary.Add('### Field Delta')
        $diagnosticsSummary.Add('')
        $diagnosticsSummary.Add((Get-Content -LiteralPath $paths.diff_summary_path -Raw))
    }

    if ($status -eq 'failed' -and $null -ne $errorPayload) {
        $diagnosticsSummary.Add('')
        $diagnosticsSummary.Add('### Failure')
        $diagnosticsSummary.Add('')
        $diagnosticsSummary.Add(('- Error type: `{0}`' -f $errorPayload.type))
        $diagnosticsSummary.Add(('- Message: `{0}`' -f $errorPayload.message))
        $diagnosticsSummary.Add(('- Error payload: `{0}`' -f $paths.error_path))
    }

    $diagnosticsSummary -join [Environment]::NewLine | Set-Content -LiteralPath $paths.diagnostics_summary_path -Encoding UTF8
    Write-Log ("Wrote diagnostics summary: {0}" -f $paths.diagnostics_summary_path)
    Write-Log ("Wrote diagnostics JSON: {0}" -f $paths.diagnostics_path)
    Write-Log ("Wrote status JSON: {0}" -f $paths.status_path)

    if ($status -eq 'failed') {
        throw "VIPB diagnostics suite failed. See '$($paths.error_path)' and '$($paths.log_path)'."
    }
}
