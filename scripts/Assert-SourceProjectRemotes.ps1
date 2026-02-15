#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceProjectRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$UpstreamRepo,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
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
        [int]$Depth = 8
    )

    $parent = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        Ensure-Directory -Path $parent
    }

    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

$startedUtc = (Get-Date).ToUniversalTime()
$logLines = New-Object 'System.Collections.Generic.List[string]'
$result = [ordered]@{
    schema_version = 1
    status = 'failed'
    started_utc = $startedUtc.ToString('o')
    completed_utc = $null
    duration_seconds = $null
    source_project_root = ''
    upstream_repo = $UpstreamRepo
    expected_upstream_url = ''
    upstream_url_before = ''
    upstream_url_after = ''
    action_taken = ''
    ls_remote_command = ''
    ls_remote_exit_code = $null
    ls_remote_output = ''
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
$statusPath = Join-Path $resolvedOutputDirectory 'source-project-remotes.status.json'
$resultPath = Join-Path $resolvedOutputDirectory 'source-project-remotes.result.json'
$logPath = Join-Path $resolvedOutputDirectory 'source-project-remotes.log'

$statusPayload = [ordered]@{
    status = 'failed'
    reason = ''
    generated_utc = $null
}

try {
    $gitCommand = Get-Command -Name 'git' -ErrorAction SilentlyContinue
    if ($null -eq $gitCommand) {
        throw "Required command 'git' not found on PATH."
    }

    $resolvedSourceProjectRoot = Resolve-FullPath -Path $SourceProjectRoot
    if (-not (Test-Path -LiteralPath $resolvedSourceProjectRoot -PathType Container)) {
        throw "Source project root not found: '$resolvedSourceProjectRoot'."
    }
    $result.source_project_root = $resolvedSourceProjectRoot

    & $gitCommand.Source -C $resolvedSourceProjectRoot rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Source project root '$resolvedSourceProjectRoot' is not a git repository."
    }

    $expectedUpstreamUrl = "https://github.com/$UpstreamRepo.git"
    $result.expected_upstream_url = $expectedUpstreamUrl

    $upstreamUrlBefore = ''
    $upstreamUrlRaw = & $gitCommand.Source -C $resolvedSourceProjectRoot remote get-url upstream 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($upstreamUrlRaw)) {
        $upstreamUrlBefore = $upstreamUrlRaw.Trim()
    }
    $result.upstream_url_before = $upstreamUrlBefore

    if ([string]::IsNullOrWhiteSpace($upstreamUrlBefore)) {
        Write-Log ("Adding missing 'upstream' remote: {0}" -f $expectedUpstreamUrl)
        & $gitCommand.Source -C $resolvedSourceProjectRoot remote add upstream $expectedUpstreamUrl
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to add 'upstream' remote to '$resolvedSourceProjectRoot'."
        }
        $result.action_taken = 'added_upstream'
    }
    elseif ($upstreamUrlBefore -ne $expectedUpstreamUrl) {
        Write-Log ("Updating 'upstream' remote from '{0}' to '{1}'." -f $upstreamUrlBefore, $expectedUpstreamUrl)
        & $gitCommand.Source -C $resolvedSourceProjectRoot remote set-url upstream $expectedUpstreamUrl
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to update 'upstream' remote URL for '$resolvedSourceProjectRoot'."
        }
        $result.action_taken = 'updated_upstream_url'
    }
    else {
        $result.action_taken = 'unchanged'
    }

    $upstreamUrlAfterRaw = & $gitCommand.Source -C $resolvedSourceProjectRoot remote get-url upstream 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($upstreamUrlAfterRaw)) {
        throw "Unable to resolve 'upstream' remote URL after configuration."
    }
    $result.upstream_url_after = $upstreamUrlAfterRaw.Trim()

    $result.ls_remote_command = 'git ls-remote upstream'
    $previousPrompt = $env:GIT_TERMINAL_PROMPT
    $previousGcm = $env:GCM_INTERACTIVE
    $env:GIT_TERMINAL_PROMPT = '0'
    $env:GCM_INTERACTIVE = 'Never'
    try {
        $lsRemoteOutput = & $gitCommand.Source -C $resolvedSourceProjectRoot ls-remote upstream 2>&1
        $lsRemoteExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    }
    finally {
        if ($null -eq $previousPrompt) {
            Remove-Item Env:\GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue
        }
        else {
            $env:GIT_TERMINAL_PROMPT = $previousPrompt
        }

        if ($null -eq $previousGcm) {
            Remove-Item Env:\GCM_INTERACTIVE -ErrorAction SilentlyContinue
        }
        else {
            $env:GCM_INTERACTIVE = $previousGcm
        }
    }

    $result.ls_remote_exit_code = $lsRemoteExitCode
    $result.ls_remote_output = (@($lsRemoteOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)
    if ($lsRemoteExitCode -ne 0) {
        $firstErrorLine = ''
        $firstOutputLine = @($lsRemoteOutput | ForEach-Object { $_.ToString() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) | Select-Object -First 1
        if ($null -ne $firstOutputLine) {
            $firstErrorLine = [string]$firstOutputLine
        }
        throw ("Unable to reach source project 'upstream' remote non-interactively. Repo: '{0}'. Upstream URL: '{1}'. Check network/credentials and verify with 'git -C ""{0}"" ls-remote upstream'. Details: {2}" -f $resolvedSourceProjectRoot, $result.upstream_url_after, $firstErrorLine)
    }

    $result.status = 'passed'
    $statusPayload.status = 'passed'
    Write-Log ("Source project 'upstream' remote is configured and reachable: {0}" -f $result.upstream_url_after)
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
    $completedUtc = (Get-Date).ToUniversalTime()
    $result.completed_utc = $completedUtc.ToString('o')
    $result.duration_seconds = [math]::Round(($completedUtc - $startedUtc).TotalSeconds, 3)
    $statusPayload.generated_utc = $completedUtc.ToString('o')

    Write-JsonFile -Path $resultPath -Value $result -Depth 10
    Write-JsonFile -Path $statusPath -Value $statusPayload -Depth 6
    Set-Content -LiteralPath $logPath -Value (@($logLines) -join [Environment]::NewLine) -Encoding UTF8
}

if ($result.status -ne 'passed') {
    $reason = if (-not [string]::IsNullOrWhiteSpace([string]$statusPayload.reason)) {
        [string]$statusPayload.reason
    }
    else {
        'unknown failure'
    }
    throw "Source project remote assertion failed: $reason. See '$resultPath' and '$logPath'."
}
