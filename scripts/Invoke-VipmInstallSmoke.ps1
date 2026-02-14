#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceProjectRoot,

    [Parameter(Mandatory = $true)]
    [string]$VipArtifactPath,

    [string]$ProjectName = 'lv_icon_editor.lvproj',

    [ValidateSet('32')]
    [string]$RequiredBitness = '32',

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [int]$CommandTimeoutSeconds = 900,
    [int]$WaitTimeoutSeconds = 120,
    [int]$WaitPollSeconds = 2,

    [string]$PackageToken,
    [string]$RunnerLabel = ''
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

    if ($TimeoutSeconds -lt 1) {
        throw 'Wait timeout must be at least 1 second.'
    }

    if ($PollSeconds -lt 1) {
        throw 'Wait poll interval must be at least 1 second.'
    }

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

function Invoke-VipmCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds
    )

    if ($TimeoutSeconds -lt 1) {
        throw 'Command timeout must be at least 1 second.'
    }

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
        }
        catch {
            Write-Verbose "Failed to terminate timed out vipm process: $($_.Exception.Message)"
        }
    }
    elseif (-not $process.HasExited) {
        $process.WaitForExit()
    }

    # Ensure stream readers are drained before we inspect output.
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

function Parse-PackageTokenFromVipb {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot
    )

    $vipbPath = Join-Path $SourceRoot 'Tooling/deployment/NI Icon editor.vipb'
    if (-not (Test-Path -LiteralPath $vipbPath -PathType Leaf)) {
        throw "Unable to determine package token from VIPB. Missing file '$vipbPath'."
    }

    [xml]$vipbXml = Get-Content -LiteralPath $vipbPath -Raw -ErrorAction Stop
    $token = [string]$vipbXml.VI_Package_Builder_Settings.Library_General_Settings.Product_Name
    $token = $token.Trim()
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "Unable to determine package token from VIPB '$vipbPath'. Expected non-empty Product_Name."
    }

    return [ordered]@{
        path = $vipbPath
        token = $token
    }
}

function Resolve-PackageIdFromVipPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VipPath
    )

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($VipPath)
    if ([string]::IsNullOrWhiteSpace($stem)) {
        throw "Unable to infer package identifier from VIP path '$VipPath'."
    }

    # Typical VIP name format: <package-id>-<major>.<minor>.<patch>.<build>.vip
    if ($stem -match '^(?<id>.+)-\d+\.\d+\.\d+\.\d+$') {
        $stem = [string]$Matches['id']
    }

    if ([string]::IsNullOrWhiteSpace($stem)) {
        throw "Inferred package identifier from VIP path '$VipPath' is empty."
    }

    return $stem.Trim()
}

function Get-FirstNonEmptyLine {
    param(
        [AllowNull()]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    $line = ($Text -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
    if ($null -eq $line) {
        return ''
    }

    return [string]$line
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

function Format-CommandText {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $rendered = $Arguments | ForEach-Object {
        if ($_ -match '\s') {
            '"' + $_.Replace('"', '\"') + '"'
        }
        else {
            $_
        }
    }
    return ('vipm ' + ($rendered -join ' '))
}

function Test-OutputContainsAnyMarker {
    param(
        [AllowNull()]
        [string]$Text,
        [Parameter(Mandatory = $true)]
        [string[]]$Markers
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    foreach ($marker in $Markers) {
        if ([string]::IsNullOrWhiteSpace($marker)) {
            continue
        }
        if ($Text -match [Regex]::Escape($marker)) {
            return $true
        }
    }

    return $false
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
    status_path = Join-Path $resolvedOutputDirectory 'vipm-install.status.json'
    result_path = Join-Path $resolvedOutputDirectory 'vipm-install.result.json'
    log_path = Join-Path $resolvedOutputDirectory 'vipm-install.log'
    help_path = Join-Path $commandsDirectory 'help.txt'
    list_before_path = Join-Path $commandsDirectory 'list-before.txt'
    install_path = Join-Path $commandsDirectory 'install.txt'
    list_after_install_path = Join-Path $commandsDirectory 'list-after-install.txt'
    uninstall_path = Join-Path $commandsDirectory 'uninstall.txt'
    list_after_uninstall_path = Join-Path $commandsDirectory 'list-after-uninstall.txt'
}

$result = [ordered]@{
    schema_version = 1
    status = 'failed'
    started_utc = $startedUtc.ToString('o')
    completed_utc = $null
    duration_seconds = $null
    required_bitness = $RequiredBitness
    runner_label = $RunnerLabel
    source = [ordered]@{
        project_root = ''
        project_path = ''
        project_relative_path = ''
        lvversion_path = ''
        lvversion_raw = ''
        labview_year = $null
        vipb_path = ''
    }
    vip = [ordered]@{
        path = ''
        size_bytes = $null
        sha256 = ''
    }
    package = [ordered]@{
        token_source = ''
        token = ''
        markers = @()
    }
    activation = [ordered]@{
        attempted = $false
        enabled = $false
        exit_code = $null
        timed_out = $false
        stderr_preview = ''
    }
    command_timeout_seconds = $CommandTimeoutSeconds
    process_wait = [ordered]@{
        attempted = $true
        succeeded = $false
        warning = ''
    }
    commands = @()
    install_succeeded = $false
    uninstall_succeeded = $false
    error = $null
}

$statusPayload = [ordered]@{
    status = 'failed'
    reason = ''
    generated_utc = $null
    result_path = $paths.result_path
    log_path = $paths.log_path
}

function Invoke-TrackedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $commandText = Format-CommandText -Arguments $Arguments
    Write-Log ("Executing {0}: {1}" -f $Name, $commandText)
    $execution = Invoke-VipmCommand -Arguments $Arguments -TimeoutSeconds $CommandTimeoutSeconds
    Write-CommandTranscriptFile -Path $OutputPath -CommandText $commandText -Execution $execution

    $record = [ordered]@{
        name = $Name
        command = $commandText
        exit_code = [int]$execution.exit_code
        timed_out = [bool]$execution.timed_out
        stdout_preview = Get-FirstNonEmptyLine -Text ([string]$execution.stdout)
        stderr_preview = Get-FirstNonEmptyLine -Text ([string]$execution.stderr)
        output_path = $OutputPath
    }
    $script:result.commands += $record

    if ([bool]$execution.timed_out) {
        throw "VIPM command '$Name' timed out after $CommandTimeoutSeconds second(s)."
    }
    if ([int]$execution.exit_code -ne 0) {
        $line = Get-FirstNonEmptyLine -Text ([string]$execution.stderr)
        if ([string]::IsNullOrWhiteSpace($line)) {
            $line = Get-FirstNonEmptyLine -Text ([string]$execution.stdout)
        }
        if ([string]::IsNullOrWhiteSpace($line)) {
            $line = "vipm exited with code $($execution.exit_code)."
        }
        throw "VIPM command '$Name' failed: $line"
    }

    return $execution
}

try {
    Write-Log "Starting VIPM install smoke gate."

    $resolvedSourceRoot = Resolve-FullPath -Path $SourceProjectRoot
    if (-not (Test-Path -LiteralPath $resolvedSourceRoot -PathType Container)) {
        throw "Source project root not found: $resolvedSourceRoot"
    }
    $result.source.project_root = $resolvedSourceRoot

    $vipmCommand = Get-Command -Name 'vipm' -ErrorAction SilentlyContinue
    if ($null -eq $vipmCommand) {
        throw "Command 'vipm' was not found on PATH."
    }
    $script:VipmExecutable = [string]$vipmCommand.Source
    Write-Log ("Resolved vipm command: {0}" -f $vipmCommand.Source)

    $projectCandidates = @(Get-ChildItem -Path $resolvedSourceRoot -Recurse -File -Filter $ProjectName)
    if ($projectCandidates.Count -eq 0) {
        throw "Unable to locate '$ProjectName' under '$resolvedSourceRoot'."
    }
    if ($projectCandidates.Count -gt 1) {
        $candidateList = ($projectCandidates | ForEach-Object { $_.FullName }) -join '; '
        throw "Expected exactly one '$ProjectName' under '$resolvedSourceRoot', found $($projectCandidates.Count): $candidateList"
    }

    $resolvedProjectPath = $projectCandidates[0].FullName
    $result.source.project_path = $resolvedProjectPath
    $result.source.project_relative_path = [System.IO.Path]::GetRelativePath($resolvedSourceRoot, $resolvedProjectPath)

    $projectDirectory = Split-Path -Path $resolvedProjectPath -Parent
    $lvversionPath = Join-Path $projectDirectory '.lvversion'
    if (-not (Test-Path -LiteralPath $lvversionPath -PathType Leaf)) {
        throw "Missing '.lvversion' alongside '$ProjectName'. Expected: '$lvversionPath'."
    }
    $result.source.lvversion_path = $lvversionPath

    $lvversionRaw = (Get-Content -LiteralPath $lvversionPath -Raw -ErrorAction Stop).Trim()
    $lvInfo = Parse-LvversionValue -RawValue $lvversionRaw
    $result.source.lvversion_raw = $lvInfo.raw
    $result.source.labview_year = [int]$lvInfo.year
    Write-Log ("Resolved LabVIEW year from .lvversion: {0}" -f $lvInfo.year)

    $resolvedVipPath = Resolve-FullPath -Path $VipArtifactPath
    if (-not (Test-Path -LiteralPath $resolvedVipPath -PathType Leaf)) {
        throw "VIP artifact not found: $resolvedVipPath"
    }
    $vipItem = Get-Item -LiteralPath $resolvedVipPath
    $result.vip.path = $resolvedVipPath
    $result.vip.size_bytes = [int64]$vipItem.Length
    $result.vip.sha256 = (Get-FileHash -LiteralPath $resolvedVipPath -Algorithm SHA256).Hash.ToLowerInvariant()

    $vipbToken = Parse-PackageTokenFromVipb -SourceRoot $resolvedSourceRoot
    $result.source.vipb_path = $vipbToken.path

    $vipPathToken = Resolve-PackageIdFromVipPath -VipPath $resolvedVipPath
    if (-not [string]::IsNullOrWhiteSpace($PackageToken)) {
        $result.package.token_source = 'parameter'
        $result.package.token = $PackageToken.Trim()
    }
    else {
        $result.package.token_source = 'vip_filename'
        $result.package.token = $vipPathToken
    }
    if ([string]::IsNullOrWhiteSpace([string]$result.package.token)) {
        throw 'Package uninstall token is empty.'
    }
    $result.package.markers = @($result.package.token, $vipPathToken, [string]$vipbToken.token) |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
        Select-Object -Unique

    try {
        Wait-ForIdleProcess -ProcessNames @('vipm', 'labview') -TimeoutSeconds $WaitTimeoutSeconds -PollSeconds $WaitPollSeconds
        $result.process_wait.succeeded = $true
    }
    catch {
        $result.process_wait.warning = $_.Exception.Message
        Write-Log ("WARNING: {0}. Continuing with VIPM smoke commands." -f $_.Exception.Message)
    }

    $activationEnabled = Test-IsTrueLike -Value $env:VIPM_COMMUNITY_EDITION
    $result.activation.enabled = $activationEnabled
    if ($activationEnabled) {
        $result.activation.attempted = $true
        $activationExecution = Invoke-VipmCommand -Arguments @('activate') -TimeoutSeconds $CommandTimeoutSeconds
        $result.activation.exit_code = [int]$activationExecution.exit_code
        $result.activation.timed_out = [bool]$activationExecution.timed_out
        $result.activation.stderr_preview = Get-FirstNonEmptyLine -Text ([string]$activationExecution.stderr)
        if ([bool]$activationExecution.timed_out) {
            throw "VIPM activation timed out after $CommandTimeoutSeconds second(s)."
        }
        if ([int]$activationExecution.exit_code -ne 0) {
            $line = Get-FirstNonEmptyLine -Text ([string]$activationExecution.stderr)
            if ([string]::IsNullOrWhiteSpace($line)) {
                $line = Get-FirstNonEmptyLine -Text ([string]$activationExecution.stdout)
            }
            if ([string]::IsNullOrWhiteSpace($line)) {
                $line = "vipm activate exited with code $($activationExecution.exit_code)."
            }
            throw "VIPM activation failed: $line"
        }
    }

    $labviewYear = [string]$lvInfo.year
    $commonArgs = @('--labview-version', $labviewYear, '--labview-bitness', $RequiredBitness)

    $helpInstallFailed = $false
    try {
        Invoke-TrackedCommand -Name 'help-install' -OutputPath $paths.help_path -Arguments @('help', 'install') | Out-Null
    }
    catch {
        $helpInstallFailed = $true
        Write-Log ("WARNING: vipm help install failed; falling back to vipm help. {0}" -f $_.Exception.Message)
    }
    if ($helpInstallFailed) {
        Invoke-TrackedCommand -Name 'help' -OutputPath $paths.help_path -Arguments @('help') | Out-Null
    }

    Invoke-TrackedCommand -Name 'list-before' -OutputPath $paths.list_before_path -Arguments ($commonArgs + @('list', '--installed')) | Out-Null
    Invoke-TrackedCommand -Name 'install' -OutputPath $paths.install_path -Arguments ($commonArgs + @('install', $resolvedVipPath)) | Out-Null
    $result.install_succeeded = $true

    $listAfterInstallExecution = Invoke-TrackedCommand -Name 'list-after-install' -OutputPath $paths.list_after_install_path -Arguments ($commonArgs + @('list', '--installed'))
    if (-not (Test-OutputContainsAnyMarker -Text ([string]$listAfterInstallExecution.stdout) -Markers @($result.package.markers))) {
        throw "Installed package marker not found in post-install package list. Markers: $($result.package.markers -join ', ')"
    }

    Invoke-TrackedCommand -Name 'uninstall' -OutputPath $paths.uninstall_path -Arguments ($commonArgs + @('uninstall', [string]$result.package.token)) | Out-Null
    $result.uninstall_succeeded = $true

    $listAfterUninstallExecution = Invoke-TrackedCommand -Name 'list-after-uninstall' -OutputPath $paths.list_after_uninstall_path -Arguments ($commonArgs + @('list', '--installed'))
    if (Test-OutputContainsAnyMarker -Text ([string]$listAfterUninstallExecution.stdout) -Markers @($result.package.markers)) {
        throw "Package marker still present after uninstall; cleanup failed. Markers: $($result.package.markers -join ', ')"
    }

    $result.status = 'passed'
    $statusPayload.status = 'passed'
    Write-Log 'VIPM install smoke gate completed successfully.'
}
catch {
    $reason = $_.Exception.Message
    $result.status = 'failed'
    $result.error = [ordered]@{
        type = $_.Exception.GetType().FullName
        message = $reason
    }
    $statusPayload.status = 'failed'
    $statusPayload.reason = $reason
    Write-Log ("ERROR: {0}" -f $reason)
}
finally {
    $completedUtc = (Get-Date).ToUniversalTime()
    $result.completed_utc = $completedUtc.ToString('o')
    $result.duration_seconds = [math]::Round(($completedUtc - $startedUtc).TotalSeconds, 3)
    $statusPayload.generated_utc = $completedUtc.ToString('o')

    Write-JsonFile -Path $paths.result_path -Value $result -Depth 14
    Write-JsonFile -Path $paths.status_path -Value $statusPayload -Depth 8
    Set-Content -LiteralPath $paths.log_path -Value (@($logLines) -join [Environment]::NewLine) -Encoding UTF8
}

if ($result.status -ne 'passed') {
    $reason = if (-not [string]::IsNullOrWhiteSpace([string]$statusPayload.reason)) {
        [string]$statusPayload.reason
    }
    else {
        'unknown failure'
    }
    throw "VIPM install smoke gate failed: $reason. See '$($paths.result_path)' and '$($paths.log_path)'."
}
