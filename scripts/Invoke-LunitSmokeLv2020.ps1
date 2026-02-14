#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceProjectRoot,

    [string]$ProjectName = 'lv_icon_editor.lvproj',

    [ValidateRange(2000, 2100)]
    [int]$TargetLabVIEWVersion = 2020,

    [ValidateSet('64')]
    [string]$RequiredBitness = '64',

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [string]$OverrideLvversion = '20.0'
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

function Parse-LvversionValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RawValue,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if ($RawValue -notmatch '^(?<major>\d+)\.(?<minor>\d+)$') {
        throw "$Label value '$RawValue' is invalid. Expected numeric major.minor format (for example '20.0')."
    }

    $major = [int]$Matches['major']
    if ($major -lt 20) {
        throw "$Label '$RawValue' is unsupported. Minimum supported LabVIEW version is 20.0."
    }

    return [ordered]@{
        raw = $RawValue
        major = $major
        minor = [int]$Matches['minor']
    }
}

function New-QuotedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Args
    )

    return ($Args | ForEach-Object {
        if ($_ -match '\s') {
            '"' + $_.Replace('"', '\"') + '"'
        } else {
            $_
        }
    }) -join ' '
}

function Read-LunitReportSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReportPath
    )

    if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
        throw "LUnit report not found at '$ReportPath'."
    }

    try {
        [xml]$xml = Get-Content -LiteralPath $ReportPath -Raw -ErrorAction Stop
    }
    catch {
        throw "Failed to parse LUnit report '$ReportPath': $($_.Exception.Message)"
    }

    $testCases = $xml.SelectNodes('//testcase')
    if ($null -eq $testCases -or $testCases.Count -eq 0) {
        throw "No <testcase> entries found in LUnit report '$ReportPath'."
    }

    $failed = New-Object 'System.Collections.Generic.List[object]'
    $passedCount = 0
    $skippedCount = 0

    foreach ($case in $testCases) {
        $status = [string]$case.GetAttribute('status')
        if ([string]::IsNullOrWhiteSpace($status)) {
            $status = 'Skipped'
        }

        $failureNode = $case.SelectSingleNode('failure')
        if ($null -eq $failureNode) {
            $failureNode = $case.SelectSingleNode('error')
        }

        $normalizedStatus = $status.Trim().ToLowerInvariant()
        $isPassed = ($normalizedStatus -eq 'passed' -or $normalizedStatus -eq 'pass')
        $isSkipped = ($normalizedStatus -eq 'skipped' -or $normalizedStatus -eq 'skip')
        $isFailed = ($null -ne $failureNode) -or (-not $isPassed -and -not $isSkipped)

        if ($isPassed) {
            $passedCount++
        }
        elseif ($isSkipped) {
            $skippedCount++
        }

        if ($isFailed) {
            $failed.Add([ordered]@{
                classname = [string]$case.GetAttribute('classname')
                name = [string]$case.GetAttribute('name')
                status = $status
                failure_message = if ($null -ne $failureNode) { [string]$failureNode.GetAttribute('message') } else { '' }
            })
        }
    }

    return [ordered]@{
        total = [int]$testCases.Count
        passed = $passedCount
        skipped = $skippedCount
        failed = $failed.Count
        failed_cases = @($failed)
    }
}

$startedUtc = (Get-Date).ToUniversalTime()
$logLines = New-Object 'System.Collections.Generic.List[string]'
$workspaceRoot = $null
$result = [ordered]@{
    schema_version = 1
    status = 'failed'
    started_utc = $startedUtc.ToString('o')
    completed_utc = $null
    duration_seconds = $null
    target_labview_version = [string]$TargetLabVIEWVersion
    required_bitness = $RequiredBitness
    override_lvversion = $OverrideLvversion
    source = [ordered]@{
        project_root = ''
        project_path = ''
        project_relative_path = ''
        lvversion_path = ''
        lvversion_before = ''
    }
    workspace = [ordered]@{
        root = ''
        project_path = ''
        lvversion_path = ''
        lvversion_after = ''
    }
    commands = [ordered]@{
        help = ''
        run = ''
    }
    command_results = [ordered]@{
        help_exit_code = $null
        run_exit_code = $null
        help_output = ''
        run_output = ''
    }
    report = [ordered]@{
        path = ''
        total = $null
        passed = $null
        skipped = $null
        failed = $null
        failed_cases = @()
    }
    error = $null
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $entry = "[{0}] {1}" -f ((Get-Date).ToUniversalTime().ToString('o')), $Message
    $script:logLines.Add($entry)
    Write-Host $entry
}

$resolvedOutputDirectory = Resolve-FullPath -Path $OutputDirectory
Ensure-Directory -Path $resolvedOutputDirectory
$reportsDirectory = Join-Path $resolvedOutputDirectory 'reports'
$workspaceDiagnosticsDirectory = Join-Path $resolvedOutputDirectory 'workspace'
Ensure-Directory -Path $reportsDirectory
Ensure-Directory -Path $workspaceDiagnosticsDirectory

$paths = [ordered]@{
    status_path = Join-Path $resolvedOutputDirectory 'lunit-smoke.status.json'
    result_path = Join-Path $resolvedOutputDirectory 'lunit-smoke.result.json'
    log_path = Join-Path $resolvedOutputDirectory 'lunit-smoke.log'
    report_path = Join-Path $reportsDirectory 'lunit-report-64.xml'
    lvversion_before_path = Join-Path $workspaceDiagnosticsDirectory 'lvversion.before'
    lvversion_after_path = Join-Path $workspaceDiagnosticsDirectory 'lvversion.after'
}

$statusPayload = [ordered]@{
    status = 'failed'
    reason = ''
    generated_utc = $null
    report_path = $paths.report_path
}

try {
    Write-Log "Starting LabVIEW 2020 LUnit smoke gate (bitness: $RequiredBitness)."

    $resolvedSourceProjectRoot = Resolve-FullPath -Path $SourceProjectRoot
    if (-not (Test-Path -LiteralPath $resolvedSourceProjectRoot -PathType Container)) {
        throw "Source project root not found: $resolvedSourceProjectRoot"
    }
    $result.source.project_root = $resolvedSourceProjectRoot

    $gcliCommand = Get-Command -Name 'g-cli' -ErrorAction SilentlyContinue
    if ($null -eq $gcliCommand) {
        throw "Required command 'g-cli' not found on PATH."
    }
    Write-Log ("Resolved g-cli command: {0}" -f $gcliCommand.Source)

    $projectCandidates = @(Get-ChildItem -Path $resolvedSourceProjectRoot -Recurse -File -Filter $ProjectName)
    if ($projectCandidates.Count -eq 0) {
        throw "Unable to locate '$ProjectName' under '$resolvedSourceProjectRoot'."
    }
    if ($projectCandidates.Count -gt 1) {
        $candidatesList = ($projectCandidates | ForEach-Object { $_.FullName }) -join '; '
        throw "Expected exactly one '$ProjectName' under '$resolvedSourceProjectRoot', found $($projectCandidates.Count): $candidatesList"
    }

    $resolvedProjectPath = $projectCandidates[0].FullName
    $result.source.project_path = $resolvedProjectPath
    $result.source.project_relative_path = [System.IO.Path]::GetRelativePath($resolvedSourceProjectRoot, $resolvedProjectPath)
    Write-Log ("Resolved source project: {0}" -f $resolvedProjectPath)

    $projectDirectory = Split-Path -Path $resolvedProjectPath -Parent
    $sourceLvversionPath = Join-Path $projectDirectory '.lvversion'
    if (-not (Test-Path -LiteralPath $sourceLvversionPath -PathType Leaf)) {
        throw "Missing '.lvversion' alongside '$ProjectName'. Expected: '$sourceLvversionPath'."
    }
    $result.source.lvversion_path = $sourceLvversionPath

    $sourceLvversionRaw = (Get-Content -LiteralPath $sourceLvversionPath -Raw -ErrorAction Stop).Trim()
    [void](Parse-LvversionValue -RawValue $sourceLvversionRaw -Label '.lvversion')
    $result.source.lvversion_before = $sourceLvversionRaw
    Set-Content -LiteralPath $paths.lvversion_before_path -Value $sourceLvversionRaw -Encoding ASCII

    [void](Parse-LvversionValue -RawValue $OverrideLvversion -Label 'OverrideLvversion')

    $workspaceParent = if (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
        $env:RUNNER_TEMP
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:TEMP)) {
        $env:TEMP
    }
    else {
        $resolvedOutputDirectory
    }
    $workspaceRoot = Join-Path $workspaceParent ("lunit-smoke-lv2020-{0}" -f [guid]::NewGuid().ToString('N'))
    Ensure-Directory -Path $workspaceRoot
    $result.workspace.root = $workspaceRoot

    foreach ($entry in (Get-ChildItem -LiteralPath $resolvedSourceProjectRoot -Force)) {
        Copy-Item -LiteralPath $entry.FullName -Destination $workspaceRoot -Recurse -Force
    }

    $workspaceProjectPath = Join-Path $workspaceRoot $result.source.project_relative_path
    if (-not (Test-Path -LiteralPath $workspaceProjectPath -PathType Leaf)) {
        throw "Workspace project copy missing at '$workspaceProjectPath'."
    }
    $result.workspace.project_path = $workspaceProjectPath

    $workspaceLvversionPath = Join-Path (Split-Path -Path $workspaceProjectPath -Parent) '.lvversion'
    if (-not (Test-Path -LiteralPath $workspaceLvversionPath -PathType Leaf)) {
        throw "Workspace '.lvversion' missing at '$workspaceLvversionPath'."
    }
    Set-Content -LiteralPath $workspaceLvversionPath -Value $OverrideLvversion -Encoding ASCII
    $result.workspace.lvversion_path = $workspaceLvversionPath
    $result.workspace.lvversion_after = $OverrideLvversion
    Set-Content -LiteralPath $paths.lvversion_after_path -Value $OverrideLvversion -Encoding ASCII

    $reportPath = $paths.report_path
    $result.report.path = $reportPath

    $helpArgs = @('--lv-ver', [string]$TargetLabVIEWVersion, '--arch', $RequiredBitness, 'lunit', '--', '-h')
    $runArgs = @('--lv-ver', [string]$TargetLabVIEWVersion, '--arch', $RequiredBitness, 'lunit', '--', '-r', $reportPath, $workspaceProjectPath)
    $result.commands.help = 'g-cli ' + (New-QuotedCommand -Args $helpArgs)
    $result.commands.run = 'g-cli ' + (New-QuotedCommand -Args $runArgs)

    Write-Log ("Executing help command: {0}" -f $result.commands.help)
    $helpOutput = & $gcliCommand.Source @helpArgs 2>&1
    $helpExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    $result.command_results.help_exit_code = $helpExitCode
    $result.command_results.help_output = (@($helpOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)
    if ($helpExitCode -ne 0) {
        Write-Log ("WARNING: g-cli LUnit help command exited with code {0}; continuing to run command gate." -f $helpExitCode)
    }

    Write-Log ("Executing run command: {0}" -f $result.commands.run)
    $runOutput = & $gcliCommand.Source @runArgs 2>&1
    $runExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    $result.command_results.run_exit_code = $runExitCode
    $result.command_results.run_output = (@($runOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)
    if ($runExitCode -ne 0) {
        throw "g-cli LUnit run command failed with exit code $runExitCode."
    }

    $reportSummary = Read-LunitReportSummary -ReportPath $reportPath
    $result.report.total = [int]$reportSummary.total
    $result.report.passed = [int]$reportSummary.passed
    $result.report.skipped = [int]$reportSummary.skipped
    $result.report.failed = [int]$reportSummary.failed
    $result.report.failed_cases = @($reportSummary.failed_cases)
    if ([int]$reportSummary.failed -gt 0) {
        throw "LUnit report contains $($reportSummary.failed) failing test(s)."
    }

    $result.status = 'passed'
    $statusPayload.status = 'passed'
    Write-Log "LabVIEW 2020 LUnit smoke gate completed successfully."
}
catch {
    $errorMessage = $_.Exception.Message
    $result.status = 'failed'
    $result.error = [ordered]@{
        type = $_.Exception.GetType().FullName
        message = $errorMessage
    }
    $statusPayload.status = 'failed'
    $statusPayload.reason = $errorMessage
    Write-Log ("ERROR: {0}" -f $errorMessage)
}
finally {
    if (-not [string]::IsNullOrWhiteSpace($workspaceRoot) -and (Test-Path -LiteralPath $workspaceRoot -PathType Container)) {
        try {
            Remove-Item -LiteralPath $workspaceRoot -Recurse -Force
            Write-Log ("Cleaned temporary workspace: {0}" -f $workspaceRoot)
        }
        catch {
            Write-Log ("WARNING: failed to clean workspace '{0}': {1}" -f $workspaceRoot, $_.Exception.Message)
        }
    }

    $completedUtc = (Get-Date).ToUniversalTime()
    $result.completed_utc = $completedUtc.ToString('o')
    $result.duration_seconds = [math]::Round(($completedUtc - $startedUtc).TotalSeconds, 3)
    $statusPayload.generated_utc = $completedUtc.ToString('o')

    Write-JsonFile -Path $paths.result_path -Value $result -Depth 12
    Write-JsonFile -Path $paths.status_path -Value $statusPayload -Depth 6
    Set-Content -LiteralPath $paths.log_path -Value (@($logLines) -join [Environment]::NewLine) -Encoding UTF8
}

if ($result.status -ne 'passed') {
    $reason = if (-not [string]::IsNullOrWhiteSpace([string]$statusPayload.reason)) {
        [string]$statusPayload.reason
    }
    else {
        'unknown failure'
    }
    throw "LabVIEW 2020 LUnit smoke gate failed: $reason. See '$($paths.result_path)' and '$($paths.log_path)'."
}
