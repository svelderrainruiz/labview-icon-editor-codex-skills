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

$canonicalScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'Update-Vipb.DisplayInfo.ps1'
if (-not (Test-Path -LiteralPath $canonicalScriptPath -PathType Leaf)) {
    throw "Canonical script not found: $canonicalScriptPath"
}

Write-Warning "'scripts/Update-VipbDisplayInfo.ps1' is deprecated. Use 'scripts/Update-Vipb.DisplayInfo.ps1'."

& $canonicalScriptPath @PSBoundParameters
