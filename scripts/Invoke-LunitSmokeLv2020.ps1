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
        failed_cases = @($failed.ToArray())
    }
}

function Get-ReportValidationOutcomeFromError {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($Message -like 'LUnit report not found*') {
        return 'report_missing'
    }
    if ($Message -like 'Failed to parse LUnit report*') {
        return 'report_malformed'
    }
    if ($Message -like 'No <testcase>*') {
        return 'no_testcases'
    }

    return 'report_validation_error'
}

function Get-VipmInstalledPackages {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VipmCommandPath,
        [Parameter(Mandatory = $true)]
        [string]$LabVIEWVersion,
        [Parameter(Mandatory = $true)]
        [string]$Bitness
    )

    $args = @('--labview-version', $LabVIEWVersion, '--labview-bitness', $Bitness, 'list', '--installed')
    $output = & $VipmCommandPath @args 2>&1
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    $outputText = (@($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)

    $packageIds = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in @($output | ForEach-Object { $_.ToString() })) {
        if ($line -match '\((?<id>[A-Za-z0-9_]+)\s+v[^\)]*\)') {
            $candidate = $Matches['id'].ToLowerInvariant()
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not $packageIds.Contains($candidate)) {
                $packageIds.Add($candidate) | Out-Null
            }
        }
    }

    return [ordered]@{
        command = 'vipm ' + (New-QuotedCommand -Args $args)
        exit_code = $exitCode
        output = $outputText
        package_ids = @($packageIds)
    }
}

function Invoke-Lv2026ControlProbe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GcliCommandPath,
        [Parameter(Mandatory = $true)]
        [string]$SourceProjectRoot,
        [Parameter(Mandatory = $true)]
        [string]$ProjectRelativePath,
        [Parameter(Mandatory = $true)]
        [string]$SourceLvversionRaw,
        [Parameter(Mandatory = $true)]
        [string]$ReportPath
    )

    $control = [ordered]@{
        executed = $true
        status = 'failed'
        reason = ''
        target_labview_version = '2026'
        required_bitness = '64'
        active_labview_processes = @()
        workspace_root = ''
        report_path = $ReportPath
        command = ''
        run_exit_code = $null
        run_output = ''
        validation_outcome = 'not_validated'
        total = $null
        passed = $null
        skipped = $null
        failed = $null
        failed_cases = @()
        error = $null
    }

    $controlWorkspaceRoot = $null
    try {
        if (-not (Test-Path -LiteralPath $SourceProjectRoot -PathType Container)) {
            throw "Source project root not found for LV2026 control probe: '$SourceProjectRoot'."
        }

        $reportDirectory = Split-Path -Path $ReportPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($reportDirectory)) {
            Ensure-Directory -Path $reportDirectory
        }

        $workspaceParent = if (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
            $env:RUNNER_TEMP
        }
        elseif (-not [string]::IsNullOrWhiteSpace($env:TEMP)) {
            $env:TEMP
        }
        else {
            [System.IO.Path]::GetTempPath()
        }

        $controlWorkspaceRoot = Join-Path $workspaceParent ("lunit-smoke-lv2026-control-{0}" -f [guid]::NewGuid().ToString('N'))
        Ensure-Directory -Path $controlWorkspaceRoot
        $control.workspace_root = $controlWorkspaceRoot

        foreach ($entry in (Get-ChildItem -LiteralPath $SourceProjectRoot -Force)) {
            Copy-Item -LiteralPath $entry.FullName -Destination $controlWorkspaceRoot -Recurse -Force
        }

        $workspaceProjectPath = Join-Path $controlWorkspaceRoot $ProjectRelativePath
        if (-not (Test-Path -LiteralPath $workspaceProjectPath -PathType Leaf)) {
            throw "LV2026 control probe workspace project copy missing at '$workspaceProjectPath'."
        }

        $workspaceLvversionPath = Join-Path (Split-Path -Path $workspaceProjectPath -Parent) '.lvversion'
        if (-not (Test-Path -LiteralPath $workspaceLvversionPath -PathType Leaf)) {
            throw "LV2026 control probe workspace .lvversion missing at '$workspaceLvversionPath'."
        }
        Set-Content -LiteralPath $workspaceLvversionPath -Value $SourceLvversionRaw -Encoding ASCII

        $probeArgs = @('--lv-ver', '2026', '--arch', '64', 'lunit', '--', '-r', $ReportPath, $workspaceProjectPath)
        $control.command = 'g-cli ' + (New-QuotedCommand -Args $probeArgs)
        Write-Log ("Executing diagnostic-only LV2026 control probe command: {0}" -f $control.command)
        $probeOutput = & $GcliCommandPath @probeArgs 2>&1
        $probeExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
        $control.run_exit_code = $probeExitCode
        $control.run_output = (@($probeOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)

        try {
            $probeReportSummary = Read-LunitReportSummary -ReportPath $ReportPath
            $control.validation_outcome = 'parsed'
        }
        catch {
            $probeValidationOutcome = Get-ReportValidationOutcomeFromError -Message $_.Exception.Message
            $control.validation_outcome = $probeValidationOutcome
            throw ("LV2026 control probe report validation failed ({0}): {1} (run exit code {2})." -f $probeValidationOutcome, $_.Exception.Message, $probeExitCode)
        }

        $control.total = [int]$probeReportSummary.total
        $control.passed = [int]$probeReportSummary.passed
        $control.skipped = [int]$probeReportSummary.skipped
        $control.failed = [int]$probeReportSummary.failed
        $control.failed_cases = @($probeReportSummary.failed_cases)
        if ([int]$probeReportSummary.failed -gt 0) {
            $control.validation_outcome = 'failed_testcases'
            throw ("LV2026 control probe report validation failed (failed_testcases): report contains {0} failing test(s) (run exit code {1})." -f $probeReportSummary.failed, $probeExitCode)
        }
        $control.validation_outcome = 'passed'

        if ($probeExitCode -ne 0) {
            Write-Log ("WARNING: LV2026 control probe exited with code {0} but report validation passed; keeping diagnostic probe status as passed." -f $probeExitCode)
        }

        $control.status = 'passed'
        $control.reason = 'control_probe_passed'
    }
    catch {
        $control.status = 'failed'
        $control.reason = $_.Exception.Message
        $control.error = [ordered]@{
            type = $_.Exception.GetType().FullName
            message = $_.Exception.Message
        }
    }
    finally {
        if (-not [string]::IsNullOrWhiteSpace($controlWorkspaceRoot) -and (Test-Path -LiteralPath $controlWorkspaceRoot -PathType Container)) {
            try {
                Remove-Item -LiteralPath $controlWorkspaceRoot -Recurse -Force
                Write-Log ("Cleaned LV2026 control probe workspace: {0}" -f $controlWorkspaceRoot)
            }
            catch {
                Write-Log ("WARNING: failed to clean LV2026 control probe workspace '{0}': {1}" -f $controlWorkspaceRoot, $_.Exception.Message)
            }
        }
    }

    return $control
}

$startedUtc = (Get-Date).ToUniversalTime()
$logLines = New-Object 'System.Collections.Generic.List[string]'
$workspaceRoot = $null
$runPhaseStarted = $false
$resolvedSourceProjectRoot = ''
$gcliCommandPath = ''
$sourceLvversionRaw = ''
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
    preflight = [ordered]@{
        vipm_command = ''
        vipm_list_command = ''
        vipm_list_exit_code = $null
        vipm_list_output = ''
        required_package_ids = @(
            'astemes_lib_lunit',
            'sas_workshops_lib_lunit_for_g_cli'
        )
        installed_package_ids = @()
        missing_package_ids = @()
    }
    commands = [ordered]@{
        run = ''
    }
    command_results = [ordered]@{
        run_exit_code = $null
        run_output = ''
    }
    report = [ordered]@{
        path = ''
        validation_outcome = ''
        total = $null
        passed = $null
        skipped = $null
        failed = $null
        failed_cases = @()
    }
    control_probe = [ordered]@{
        executed = $false
        status = 'not_run'
        reason = 'not_triggered'
        target_labview_version = '2026'
        required_bitness = '64'
        active_labview_processes = @()
        workspace_root = ''
        report_path = ''
        command = ''
        run_exit_code = $null
        run_output = ''
        validation_outcome = 'not_run'
        total = $null
        passed = $null
        skipped = $null
        failed = $null
        failed_cases = @()
        error = $null
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
    control_report_path = Join-Path $reportsDirectory 'lunit-report-2026-control.xml'
    lvversion_before_path = Join-Path $workspaceDiagnosticsDirectory 'lvversion.before'
    lvversion_after_path = Join-Path $workspaceDiagnosticsDirectory 'lvversion.after'
}
$result.control_probe.report_path = $paths.control_report_path

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
    $gcliCommandPath = $gcliCommand.Source
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
    $result.report.validation_outcome = 'not_validated'

    $runArgs = @('--lv-ver', [string]$TargetLabVIEWVersion, '--arch', $RequiredBitness, 'lunit', '--', '-r', $reportPath, $workspaceProjectPath)
    $result.commands.run = 'g-cli ' + (New-QuotedCommand -Args $runArgs)

    $vipmCommand = Get-Command -Name 'vipm' -ErrorAction SilentlyContinue
    if ($null -eq $vipmCommand) {
        throw "Required command 'vipm' not found on PATH."
    }
    $result.preflight.vipm_command = $vipmCommand.Source
    Write-Log ("Resolved vipm command: {0}" -f $vipmCommand.Source)

    $vipmPackages = Get-VipmInstalledPackages -VipmCommandPath $vipmCommand.Source -LabVIEWVersion ([string]$TargetLabVIEWVersion) -Bitness $RequiredBitness
    $result.preflight.vipm_list_command = [string]$vipmPackages.command
    $result.preflight.vipm_list_exit_code = [int]$vipmPackages.exit_code
    $result.preflight.vipm_list_output = [string]$vipmPackages.output
    if ([int]$vipmPackages.exit_code -ne 0) {
        throw ("VIPM package preflight failed: unable to query installed packages for LabVIEW {0} ({1}-bit). Command '{2}' exited with code {3}." -f $TargetLabVIEWVersion, $RequiredBitness, $result.preflight.vipm_list_command, $result.preflight.vipm_list_exit_code)
    }

    $installedPackageIds = @($vipmPackages.package_ids | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique)
    $result.preflight.installed_package_ids = $installedPackageIds
    $missingPackageIds = @($result.preflight.required_package_ids | Where-Object { $installedPackageIds -notcontains $_.ToLowerInvariant() })
    $result.preflight.missing_package_ids = $missingPackageIds
    if ($missingPackageIds.Count -gt 0) {
        $missingList = ($missingPackageIds -join ', ')
        throw ("VIPM package preflight failed: missing required package IDs for LabVIEW {0} ({1}-bit): {2}. Apply .github/actions/apply-vipc/runner_dependencies.vipc." -f $TargetLabVIEWVersion, $RequiredBitness, $missingList)
    }

    $runPhaseStarted = $true
    Write-Log ("Executing run command: {0}" -f $result.commands.run)
    $runOutput = & $gcliCommand.Source @runArgs 2>&1
    $runExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    $result.command_results.run_exit_code = $runExitCode
    $result.command_results.run_output = (@($runOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)

    try {
        $reportSummary = Read-LunitReportSummary -ReportPath $reportPath
        $result.report.validation_outcome = 'parsed'
    }
    catch {
        $validationOutcome = Get-ReportValidationOutcomeFromError -Message $_.Exception.Message
        $result.report.validation_outcome = $validationOutcome
        throw ("LUnit report validation failed ({0}): {1} (run exit code {2})." -f $validationOutcome, $_.Exception.Message, $runExitCode)
    }

    $result.report.total = [int]$reportSummary.total
    $result.report.passed = [int]$reportSummary.passed
    $result.report.skipped = [int]$reportSummary.skipped
    $result.report.failed = [int]$reportSummary.failed
    $result.report.failed_cases = @($reportSummary.failed_cases)
    if ([int]$reportSummary.failed -gt 0) {
        $result.report.validation_outcome = 'failed_testcases'
        throw ("LUnit report validation failed (failed_testcases): report contains {0} failing test(s) (run exit code {1})." -f $reportSummary.failed, $runExitCode)
    }
    $result.report.validation_outcome = 'passed'

    if ($runExitCode -ne 0) {
        Write-Log ("WARNING: g-cli LUnit run exited with code {0} but report validation passed; accepting parse-first strict gate." -f $runExitCode)
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

    if ($runPhaseStarted -and -not [string]::IsNullOrWhiteSpace($gcliCommandPath) -and -not [string]::IsNullOrWhiteSpace($resolvedSourceProjectRoot) -and -not [string]::IsNullOrWhiteSpace([string]$result.source.project_relative_path)) {
        $primaryValidationOutcome = [string]$result.report.validation_outcome
        if ([string]::IsNullOrWhiteSpace($primaryValidationOutcome)) {
            $primaryValidationOutcome = 'unknown'
        }

        $eligibleControlOutcomes = @('no_testcases', 'failed_testcases')
        if ($eligibleControlOutcomes -notcontains $primaryValidationOutcome) {
            $result.control_probe.reason = "skipped_for_primary_outcome_$primaryValidationOutcome"
            Write-Log ("Skipping LV2026 control probe because LV2020 validation outcome '{0}' is not in eligible set: {1}." -f $primaryValidationOutcome, ($eligibleControlOutcomes -join ', '))
        }
        else {
            $activeLabVIEWProcessNames = @()
            try {
                $activeLabVIEWProcessNames = @(
                    Get-Process -ErrorAction SilentlyContinue |
                    Where-Object { $_.ProcessName -match '(?i)labview' } |
                    Select-Object -ExpandProperty ProcessName -Unique |
                    Sort-Object
                )
            }
            catch {
                Write-Log ("WARNING: Unable to enumerate LabVIEW processes before control probe: {0}" -f $_.Exception.Message)
            }

            $result.control_probe.active_labview_processes = @($activeLabVIEWProcessNames)
            if ($activeLabVIEWProcessNames.Count -gt 0) {
                $result.control_probe.reason = 'skipped_active_labview_processes'
                Write-Log ("Skipping LV2026 control probe because active LabVIEW processes were detected: {0}" -f ($activeLabVIEWProcessNames -join ', '))
            }
            else {
                Write-Log 'LV2020 run/report path failed; running diagnostic-only LV2026 control probe.'
                $result.control_probe = Invoke-Lv2026ControlProbe `
                    -GcliCommandPath $gcliCommandPath `
                    -SourceProjectRoot $resolvedSourceProjectRoot `
                    -ProjectRelativePath ([string]$result.source.project_relative_path) `
                    -SourceLvversionRaw $sourceLvversionRaw `
                    -ReportPath $paths.control_report_path

                if ([string]$result.control_probe.status -eq 'passed') {
                    Write-Log 'LV2026 control probe passed. LV2020 failure is likely version-specific compatibility/discovery.'
                }
                else {
                    Write-Log ("LV2026 control probe failed: {0}" -f [string]$result.control_probe.reason)
                }
            }
        }
    }
    elseif (-not $runPhaseStarted) {
        $result.control_probe.reason = 'run_phase_not_reached'
    }
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
