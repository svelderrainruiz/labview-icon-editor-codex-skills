#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceProjectRoot,

    [string]$ProjectName = 'lv_icon_editor.lvproj',

    [string]$VipbPath = 'Tooling/deployment/NI Icon editor.vipb',

    [Parameter(Mandatory = $true)]
    [ValidateRange(2000, 2100)]
    [int]$LabVIEWVersionYear,

    [ValidateSet('32', '64')]
    [string]$LabVIEWBitness = '64',

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [bool]$VipmCommunityEdition = $true,

    [ValidateRange(30, 7200)]
    [int]$CommandTimeoutSeconds = 900,

    [ValidateRange(1, 600)]
    [int]$WaitTimeoutSeconds = 120,

    [ValidateRange(1, 30)]
    [int]$WaitPollSeconds = 2,

    [switch]$EnforceLabVIEWProcessIsolation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:VipmExecutable = 'vipm'

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
        [int]$Depth = 12
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
        [string]$RawValue
    )

    if ($RawValue -notmatch '^(?<major>\d+)\.(?<minor>\d+)$') {
        throw ".lvversion value '$RawValue' is invalid. Expected numeric major.minor format (for example '26.0')."
    }

    $major = [int]$Matches['major']
    $minor = [int]$Matches['minor']
    if ($major -lt 20) {
        throw ".lvversion '$RawValue' is unsupported. Minimum supported LabVIEW version is 20.0."
    }

    return [ordered]@{
        raw = $RawValue
        major = $major
        minor = $minor
        year = [int](2000 + $major)
    }
}

function Test-IsTrueLike {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    return $Value.Trim().ToLowerInvariant() -in @('1', 'true', 'yes', 'on')
}

function Wait-ForIdleProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ProcessNames,
        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds,
        [Parameter(Mandatory = $true)]
        [int]$PollSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $active = @()
        foreach ($name in $ProcessNames) {
            $active += Get-Process -Name $name -ErrorAction SilentlyContinue
        }

        if (-not $active) {
            return
        }

        Start-Sleep -Seconds $PollSeconds
    }

    throw "Timed out waiting for processes to exit: $($ProcessNames -join ', ')"
}

function Get-LabVIEWInstallRoot {
    param(
        [Parameter(Mandatory = $true)]
        [int]$LabVIEWYear,
        [Parameter(Mandatory = $true)]
        [ValidateSet('32', '64')]
        [string]$Bitness
    )

    if ($Bitness -eq '32') {
        return "C:\Program Files (x86)\National Instruments\LabVIEW $LabVIEWYear"
    }

    return "C:\Program Files\National Instruments\LabVIEW $LabVIEWYear"
}

function Get-TargetLabVIEWProcesses {
    param(
        [Parameter(Mandatory = $true)]
        [int]$LabVIEWYear,
        [Parameter(Mandatory = $true)]
        [ValidateSet('32', '64')]
        [string]$Bitness
    )

    $installRoot = Get-LabVIEWInstallRoot -LabVIEWYear $LabVIEWYear -Bitness $Bitness
    $processes = @(Get-CimInstance Win32_Process -Filter "Name='LabVIEW.exe'" -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) {
        return @()
    }

    return @($processes | Where-Object {
            $_.ExecutablePath -and $_.ExecutablePath.StartsWith($installRoot, [System.StringComparison]::OrdinalIgnoreCase)
        })
}

function Get-VipmProcesses {
    return @(Get-Process -Name 'vipm' -ErrorAction SilentlyContinue)
}

function Resolve-LabVIEWCliPort {
    param(
        [Parameter(Mandatory = $true)]
        [int]$LabVIEWYear,
        [Parameter(Mandatory = $true)]
        [ValidateSet('32', '64')]
        [string]$Bitness
    )

    $bitnessEnvName = "LVIE_LABVIEWCLI_PORT_{0}" -f $Bitness
    foreach ($envName in @($bitnessEnvName, 'LVIE_LABVIEWCLI_PORT')) {
        $value = [Environment]::GetEnvironmentVariable($envName)
        if (-not [string]::IsNullOrWhiteSpace($value) -and $value.Trim() -match '^\d+$') {
            return $value.Trim()
        }
    }

    $installRoot = Get-LabVIEWInstallRoot -LabVIEWYear $LabVIEWYear -Bitness $Bitness
    $iniPath = Join-Path $installRoot 'LabVIEW.ini'
    if (Test-Path -LiteralPath $iniPath -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $iniPath -ErrorAction SilentlyContinue) {
            if ($line -match '^\s*server\.tcp\.port\s*=\s*(\d+)\s*$') {
                return $Matches[1]
            }
        }
    }

    return '3363'
}

function Invoke-LabVIEWCliClose {
    param(
        [Parameter(Mandatory = $true)]
        [int]$LabVIEWYear,
        [Parameter(Mandatory = $true)]
        [ValidateSet('32', '64')]
        [string]$Bitness
    )

    $labviewCli = Get-Command -Name 'LabVIEWCLI' -ErrorAction SilentlyContinue
    if ($null -eq $labviewCli) {
        Write-Log "LabVIEWCLI not available on PATH; skipping graceful LabVIEW close attempt."
        return $false
    }

    $installRoot = Get-LabVIEWInstallRoot -LabVIEWYear $LabVIEWYear -Bitness $Bitness
    $labviewPath = Join-Path $installRoot 'LabVIEW.exe'
    $portNumber = Resolve-LabVIEWCliPort -LabVIEWYear $LabVIEWYear -Bitness $Bitness

    $args = @(
        '-LogToConsole', 'TRUE',
        '-OperationName', 'CloseLabVIEW',
        '-LabVIEWPath', $labviewPath,
        '-PortNumber', $portNumber
    )

    Write-Log ("Executing LabVIEWCLI close ({0}-bit, port {1})." -f $Bitness, $portNumber)
    $output = & LabVIEWCLI @args 2>&1
    $exitCode = $LASTEXITCODE
    foreach ($line in @($output)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
            Write-Log ([string]$line)
        }
    }

    if ($exitCode -ne 0) {
        Write-Log ("LabVIEWCLI CloseLabVIEW returned exit code {0}." -f $exitCode)
        return $false
    }

    return $true
}

function Stop-ProcessesById {
    param(
        [Parameter(Mandatory = $true)]
        [int[]]$ProcessIds,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    foreach ($processId in $ProcessIds) {
        try {
            Stop-Process -Id $processId -Force -ErrorAction Stop
            Write-Log ("Force-stopped {0} process PID {1}." -f $Label, $processId)
        } catch {
            Write-Log ("Failed to force-stop {0} process PID {1}: {2}" -f $Label, $processId, $_.Exception.Message)
        }
    }
}

function Ensure-ProcessIsolation {
    param(
        [Parameter(Mandatory = $true)]
        [int]$LabVIEWYear,
        [Parameter(Mandatory = $true)]
        [ValidateSet('32', '64')]
        [string]$Bitness,
        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds,
        [Parameter(Mandatory = $true)]
        [int]$PollSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $attemptedGracefulClose = $false
    while ((Get-Date) -lt $deadline) {
        $labviewProcesses = @(Get-TargetLabVIEWProcesses -LabVIEWYear $LabVIEWYear -Bitness $Bitness)
        $vipmProcesses = @(Get-VipmProcesses)
        if ($labviewProcesses.Count -eq 0 -and $vipmProcesses.Count -eq 0) {
            return
        }

        if (-not $attemptedGracefulClose -and $labviewProcesses.Count -gt 0) {
            Write-Log ("Detected running target LabVIEW process(es): {0}" -f (($labviewProcesses | ForEach-Object { $_.ProcessId }) -join ', '))
            [void](Invoke-LabVIEWCliClose -LabVIEWYear $LabVIEWYear -Bitness $Bitness)
            Start-Sleep -Seconds 2
            [void](Invoke-LabVIEWCliClose -LabVIEWYear $LabVIEWYear -Bitness $Bitness)
            Start-Sleep -Seconds 2
            $attemptedGracefulClose = $true
        }

        Start-Sleep -Seconds $PollSeconds
    }

    $labviewAfterWait = @(Get-TargetLabVIEWProcesses -LabVIEWYear $LabVIEWYear -Bitness $Bitness)
    $vipmAfterWait = @(Get-VipmProcesses)

    if ($labviewAfterWait.Count -gt 0) {
        Stop-ProcessesById -ProcessIds @($labviewAfterWait | ForEach-Object { [int]$_.ProcessId }) -Label 'LabVIEW'
    }
    if ($vipmAfterWait.Count -gt 0) {
        Stop-ProcessesById -ProcessIds @($vipmAfterWait | ForEach-Object { [int]$_.Id }) -Label 'VIPM'
    }

    Start-Sleep -Seconds ([Math]::Max(1, [Math]::Min(5, $PollSeconds)))
    $remainingLabview = @(Get-TargetLabVIEWProcesses -LabVIEWYear $LabVIEWYear -Bitness $Bitness)
    $remainingVipm = @(Get-VipmProcesses)
    if ($remainingLabview.Count -gt 0 -or $remainingVipm.Count -gt 0) {
        $remaining = New-Object 'System.Collections.Generic.List[string]'
        if ($remainingLabview.Count -gt 0) {
            $remaining.Add(("labview(pid={0})" -f (($remainingLabview | ForEach-Object { $_.ProcessId }) -join ',')))
        }
        if ($remainingVipm.Count -gt 0) {
            $remaining.Add(("vipm(pid={0})" -f (($remainingVipm | ForEach-Object { $_.Id }) -join ',')))
        }
        throw "Timed out waiting for processes to exit: $($remaining -join '; ')"
    }
}

function Invoke-VipmCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $script:VipmExecutable
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) {
        [void]$startInfo.ArgumentList.Add([string]$argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $null = $process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $completed = $process.WaitForExit($TimeoutSeconds * 1000)
    $timedOut = -not $completed

    if ($timedOut) {
        try {
            $process.Kill()
            $process.WaitForExit()
        } catch {
            Write-Verbose ("Failed to terminate timed out vipm process: {0}" -f $_.Exception.Message)
        }
    } elseif (-not $process.HasExited) {
        $process.WaitForExit()
    }

    if (-not $stdoutTask.IsCompleted) {
        $stdoutTask.Wait(5000)
    }
    if (-not $stderrTask.IsCompleted) {
        $stderrTask.Wait(5000)
    }

    return [ordered]@{
        exit_code = if ($timedOut) { 124 } else { [int]$process.ExitCode }
        timed_out = $timedOut
        stdout = [string]$stdoutTask.GetAwaiter().GetResult()
        stderr = [string]$stderrTask.GetAwaiter().GetResult()
    }
}

function Format-CommandText {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $rendered = $Arguments | ForEach-Object {
        if ($_ -match '\s') {
            '"' + $_.Replace('"', '\"') + '"'
        } else {
            $_
        }
    }
    return ('vipm ' + ($rendered -join ' '))
}

function Write-CommandTranscriptFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$CommandText,
        [Parameter(Mandatory = $true)]
        [hashtable]$Execution
    )

    $content = @(
        "command=$CommandText"
        "exit_code=$($Execution.exit_code)"
        "timed_out=$($Execution.timed_out)"
        '--- stdout ---'
        [string]$Execution.stdout
        '--- stderr ---'
        [string]$Execution.stderr
    ) -join [Environment]::NewLine

    Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

function Resolve-VipbPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [string]$Candidate
    )

    if ([System.IO.Path]::IsPathRooted($Candidate)) {
        return [System.IO.Path]::GetFullPath($Candidate)
    }

    $primary = Join-Path -Path $Root -ChildPath $Candidate
    if (Test-Path -LiteralPath $primary -PathType Leaf) {
        return [System.IO.Path]::GetFullPath($primary)
    }

    $secondary = $null
    if ($Candidate -match '^[\\/]*consumer[\\/]') {
        $trimmed = $Candidate -replace '^[\\/]*consumer[\\/]', ''
        $secondary = Join-Path -Path $Root -ChildPath $trimmed
        if (Test-Path -LiteralPath $secondary -PathType Leaf) {
            return [System.IO.Path]::GetFullPath($secondary)
        }
    }

    $attempted = @($primary)
    if (-not [string]::IsNullOrWhiteSpace($secondary)) {
        $attempted += $secondary
    }
    throw "VIPB file not found. Candidate '$Candidate'. Attempted: $($attempted -join '; ')"
}

$startedUtc = (Get-Date).ToUniversalTime()
$logLines = New-Object 'System.Collections.Generic.List[string]'

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
$commandsDirectory = Join-Path $resolvedOutputDirectory 'commands'
Ensure-Directory -Path $commandsDirectory

$paths = [ordered]@{
    status_path = Join-Path $resolvedOutputDirectory 'vipm-build.status.json'
    result_path = Join-Path $resolvedOutputDirectory 'vipm-build.result.json'
    log_path = Join-Path $resolvedOutputDirectory 'vipm-build.log'
    help_build_path = Join-Path $commandsDirectory 'help-build.txt'
    activate_path = Join-Path $commandsDirectory 'activate.txt'
    build_path = Join-Path $commandsDirectory 'build.txt'
}

$result = [ordered]@{
    schema_version = 1
    status = 'failed'
    started_utc = $startedUtc.ToString('o')
    completed_utc = $null
    duration_seconds = $null
    source = [ordered]@{
        project_root = ''
        project_path = ''
        lvversion_path = ''
        lvversion_raw = ''
        lvversion_year = $null
        vipb_path = ''
    }
    target = [ordered]@{
        labview_year_requested = $LabVIEWVersionYear
        labview_year_from_lvversion = $null
        bitness = $LabVIEWBitness
    }
    preflight = [ordered]@{
        vipm_command = ''
        help_build_command = ''
        help_build_exit_code = $null
        help_build_supports_vipb = $false
        process_isolation_enabled = $EnforceLabVIEWProcessIsolation.IsPresent
        process_isolation_succeeded = $false
    }
    activation = [ordered]@{
        attempted = $false
        enabled = $false
        command = ''
        exit_code = $null
        timed_out = $false
        stderr_preview = ''
    }
    build = [ordered]@{
        command = ''
        exit_code = $null
        timed_out = $false
        stdout_preview = ''
        stderr_preview = ''
    }
    artifact = [ordered]@{
        vip_path = ''
        size_bytes = $null
        sha256 = ''
    }
    diagnostics = [ordered]@{
        output_directory = $resolvedOutputDirectory
        log_path = $paths.log_path
    }
    error = $null
}

$statusPayload = [ordered]@{
    status = 'failed'
    reason = ''
    generated_utc = ''
    result_path = $paths.result_path
    log_path = $paths.log_path
}

try {
    $resolvedSourceRoot = Resolve-FullPath -Path $SourceProjectRoot
    if (-not (Test-Path -LiteralPath $resolvedSourceRoot -PathType Container)) {
        throw "SourceProjectRoot not found: '$resolvedSourceRoot'."
    }
    $result.source.project_root = $resolvedSourceRoot

    $projectCandidates = @(Get-ChildItem -Path $resolvedSourceRoot -Recurse -File -Filter $ProjectName -ErrorAction Stop)
    if ($projectCandidates.Count -ne 1) {
        $candidateList = ($projectCandidates | ForEach-Object { $_.FullName }) -join '; '
        throw "Expected exactly one '$ProjectName' under '$resolvedSourceRoot', found $($projectCandidates.Count). Candidates: $candidateList"
    }

    $projectPath = $projectCandidates[0].FullName
    $result.source.project_path = $projectPath
    $projectDirectory = Split-Path -Path $projectPath -Parent

    $lvversionPath = Join-Path $projectDirectory '.lvversion'
    if (-not (Test-Path -LiteralPath $lvversionPath -PathType Leaf)) {
        throw "Missing '.lvversion' alongside '$ProjectName' at '$projectDirectory'."
    }
    $result.source.lvversion_path = $lvversionPath

    $lvversionRaw = (Get-Content -LiteralPath $lvversionPath -Raw -ErrorAction Stop).Trim()
    $lvversionInfo = Parse-LvversionValue -RawValue $lvversionRaw
    $result.source.lvversion_raw = [string]$lvversionInfo.raw
    $result.source.lvversion_year = [int]$lvversionInfo.year
    $result.target.labview_year_from_lvversion = [int]$lvversionInfo.year

    if ([int]$lvversionInfo.year -ne [int]$LabVIEWVersionYear) {
        throw "LabVIEW version mismatch: requested year '$LabVIEWVersionYear' does not match authoritative .lvversion '$($lvversionInfo.raw)' (year '$($lvversionInfo.year)')."
    }

    $resolvedVipbPath = Resolve-VipbPath -Root $resolvedSourceRoot -Candidate $VipbPath
    $result.source.vipb_path = $resolvedVipbPath

    $vipmCommand = Get-Command -Name 'vipm' -ErrorAction SilentlyContinue
    if ($null -eq $vipmCommand) {
        throw "Required command 'vipm' not found on PATH."
    }
    $script:VipmExecutable = [string]$vipmCommand.Source
    $result.preflight.vipm_command = [string]$vipmCommand.Source
    Write-Log ("Resolved vipm command: {0}" -f $script:VipmExecutable)

    $helpBuildArgs = @('help', 'build')
    $result.preflight.help_build_command = Format-CommandText -Arguments $helpBuildArgs
    $helpBuildExecution = Invoke-VipmCommand -Arguments $helpBuildArgs -TimeoutSeconds ([Math]::Min($CommandTimeoutSeconds, 120))
    $result.preflight.help_build_exit_code = [int]$helpBuildExecution.exit_code
    Write-CommandTranscriptFile -Path $paths.help_build_path -CommandText $result.preflight.help_build_command -Execution $helpBuildExecution
    $helpCombined = [string]$helpBuildExecution.stdout + [Environment]::NewLine + [string]$helpBuildExecution.stderr
    $supportsVipb = [int]$helpBuildExecution.exit_code -eq 0 -and $helpCombined -match '\.vipb'
    $result.preflight.help_build_supports_vipb = $supportsVipb
    if (-not $supportsVipb) {
        throw "VIPM build preflight failed. 'vipm help build' did not confirm .vipb support."
    }

    if ($EnforceLabVIEWProcessIsolation.IsPresent) {
        Write-Log ("Waiting for isolated tooling state before build: labview({0}-bit) + vipm (timeout={1}s)." -f $LabVIEWBitness, $WaitTimeoutSeconds)
        Ensure-ProcessIsolation -LabVIEWYear $LabVIEWVersionYear -Bitness $LabVIEWBitness -TimeoutSeconds $WaitTimeoutSeconds -PollSeconds $WaitPollSeconds
        $result.preflight.process_isolation_succeeded = $true
    } else {
        $result.preflight.process_isolation_succeeded = $true
    }

    $activationEnabled = $VipmCommunityEdition -or (Test-IsTrueLike -Value $env:VIPM_COMMUNITY_EDITION)
    $result.activation.enabled = $activationEnabled
    if ($activationEnabled) {
        $activateArgs = @('activate')
        $result.activation.attempted = $true
        $result.activation.command = Format-CommandText -Arguments $activateArgs
        $activateExecution = Invoke-VipmCommand -Arguments $activateArgs -TimeoutSeconds $CommandTimeoutSeconds
        $result.activation.exit_code = [int]$activateExecution.exit_code
        $result.activation.timed_out = [bool]$activateExecution.timed_out
        $result.activation.stderr_preview = ([string]$activateExecution.stderr).Trim() | Select-Object -First 1
        Write-CommandTranscriptFile -Path $paths.activate_path -CommandText $result.activation.command -Execution $activateExecution
        if ([int]$activateExecution.exit_code -ne 0) {
            throw "vipm activate failed with exit code $($activateExecution.exit_code)."
        }
    }

    $buildStartUtc = (Get-Date).ToUniversalTime()
    $buildArgs = @(
        '--labview-version', $LabVIEWVersionYear.ToString(),
        '--labview-bitness', $LabVIEWBitness,
        'build', $resolvedVipbPath
    )
    $result.build.command = Format-CommandText -Arguments $buildArgs
    $buildExecution = Invoke-VipmCommand -Arguments $buildArgs -TimeoutSeconds $CommandTimeoutSeconds
    $result.build.exit_code = [int]$buildExecution.exit_code
    $result.build.timed_out = [bool]$buildExecution.timed_out
    $result.build.stdout_preview = (([string]$buildExecution.stdout).Trim() -split "`r?`n" | Select-Object -First 5) -join [Environment]::NewLine
    $result.build.stderr_preview = (([string]$buildExecution.stderr).Trim() -split "`r?`n" | Select-Object -First 5) -join [Environment]::NewLine
    Write-CommandTranscriptFile -Path $paths.build_path -CommandText $result.build.command -Execution $buildExecution
    if ([int]$buildExecution.exit_code -ne 0) {
        throw "vipm build failed with exit code $($buildExecution.exit_code)."
    }

    $vipCandidates = @(Get-ChildItem -Path $resolvedSourceRoot -Recurse -File -Filter '*.vip' -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)
    $freshCandidates = @($vipCandidates | Where-Object { $_.LastWriteTimeUtc -ge $buildStartUtc.AddSeconds(-2) })
    if ($freshCandidates.Count -eq 0) {
        throw "vipm build reported success but no newly-produced .vip artifact was found under '$resolvedSourceRoot'."
    }

    $vipArtifact = $freshCandidates[0]
    $result.artifact.vip_path = $vipArtifact.FullName
    $result.artifact.size_bytes = [int64]$vipArtifact.Length
    $result.artifact.sha256 = (Get-FileHash -LiteralPath $vipArtifact.FullName -Algorithm SHA256).Hash.ToLowerInvariant()

    $result.status = 'passed'
    $statusPayload.status = 'passed'
    $statusPayload.reason = 'ok'
}
catch {
    $result.status = 'failed'
    $result.error = [ordered]@{
        type = $_.Exception.GetType().FullName
        message = $_.Exception.Message
    }
    $statusPayload.status = 'failed'
    $statusPayload.reason = $_.Exception.Message
    Write-Log ("ERROR: {0}" -f $_.Exception.Message)
}
finally {
    $completedUtc = (Get-Date).ToUniversalTime()
    $durationSeconds = [Math]::Round(($completedUtc - $startedUtc).TotalSeconds, 3)
    $result.completed_utc = $completedUtc.ToString('o')
    $result.duration_seconds = $durationSeconds
    $statusPayload.generated_utc = $completedUtc.ToString('o')
    Set-Content -LiteralPath $paths.log_path -Value ($logLines -join [Environment]::NewLine) -Encoding UTF8
    Write-JsonFile -Path $paths.result_path -Value $result
    Write-JsonFile -Path $paths.status_path -Value $statusPayload
}

if ($result.status -ne 'passed') {
    throw "VIPM package build failed: $($statusPayload.reason). See '$($paths.result_path)' and '$($paths.log_path)'."
}
