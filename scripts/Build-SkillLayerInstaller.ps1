#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PayloadRoot,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [string]$InstallRoot = 'C:\Users\Public\lvie\codex-skill-layer\current',

    [Parameter(Mandatory = $false)]
    [string]$NsisScriptPath,

    [Parameter(Mandatory = $false)]
    [string]$MakensisPath
)

$ErrorActionPreference = 'Stop'

function Resolve-MakensisPath {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Override
    )

    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        if (-not (Test-Path -LiteralPath $Override -PathType Leaf)) {
            throw "makensis not found at override path: $Override"
        }
        return (Resolve-Path -LiteralPath $Override).Path
    }

    $cmd = Get-Command makensis -ErrorAction SilentlyContinue
    if ($cmd -and -not [string]::IsNullOrWhiteSpace($cmd.Source)) {
        return $cmd.Source
    }

    foreach ($candidate in @(
        'C:\Program Files (x86)\NSIS\makensis.exe',
        'C:\Program Files\NSIS\makensis.exe'
    )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    throw 'makensis was not found. Install NSIS or pass -MakensisPath.'
}

$resolvedPayloadRoot = (Resolve-Path -LiteralPath $PayloadRoot).Path
if (-not (Test-Path -LiteralPath $resolvedPayloadRoot -PathType Container)) {
    throw "Payload root not found: $resolvedPayloadRoot"
}

$resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDir)) {
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
}

$resolvedScriptPath = if ([string]::IsNullOrWhiteSpace($NsisScriptPath)) {
    Join-Path (Split-Path -Parent $PSScriptRoot) 'nsis\skill-layer-installer.nsi'
} else {
    [System.IO.Path]::GetFullPath($NsisScriptPath)
}

if (-not (Test-Path -LiteralPath $resolvedScriptPath -PathType Leaf)) {
    throw "NSIS script not found: $resolvedScriptPath"
}

$makensis = Resolve-MakensisPath -Override $MakensisPath

$args = @(
    '/V3',
    ("/DOUT_FILE=$resolvedOutputPath"),
    ("/DPAYLOAD_DIR=$resolvedPayloadRoot"),
    ("/DINSTALL_ROOT=$InstallRoot"),
    $resolvedScriptPath
)

& $makensis @args
if ($LASTEXITCODE -ne 0) {
    throw "makensis failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path -LiteralPath $resolvedOutputPath -PathType Leaf)) {
    throw "Installer output not found at $resolvedOutputPath"
}

Write-Output $resolvedOutputPath
