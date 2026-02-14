#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$ProfilesRoot = 'profiles/labview',

    [string]$ProfileId,

    [Parameter(Mandatory = $true)]
    [string]$ConsumerRepoRoot,

    [ValidateSet('32', '64')]
    [string]$SupportedBitness = '64',

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
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

function Get-FileSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ''
    }

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Resolve-LvversionInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$ContextLabel
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$ContextLabel .lvversion not found: $Path"
    }

    $rawValue = (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop).Trim()
    if ($rawValue -notmatch '^(?<major>\d+)\.(?<minor>\d+)$') {
        throw "$ContextLabel .lvversion value '$rawValue' is invalid. Expected numeric major.minor format (for example '26.0')."
    }

    $major = [int]$Matches['major']
    $minor = [int]$Matches['minor']
    $year = 2000 + $major
    $numeric = "{0}.{1}" -f $major, $minor

    return [ordered]@{
        path = $Path
        raw = $rawValue
        numeric = $numeric
        year = $year
        minor = $minor
        sha256 = Get-FileSha256 -Path $Path
    }
}

function Get-ExpectedVipbTarget {
    param(
        [Parameter(Mandatory = $true)]
        [string]$NumericVersion,
        [Parameter(Mandatory = $true)]
        [ValidateSet('32', '64')]
        [string]$Bitness
    )

    if ($Bitness -eq '64') {
        return "{0} (64-bit)" -f $NumericVersion
    }

    return $NumericVersion
}

function Write-ResolutionJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [object]$Payload
    )

    Ensure-ParentDirectory -Path $Path
    $Payload | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$resolvedOutputPath = Resolve-FullPath -Path $OutputPath

try {
    $resolvedProfilesRoot = Resolve-FullPath -Path $ProfilesRoot
    if (-not (Test-Path -LiteralPath $resolvedProfilesRoot -PathType Container)) {
        throw "Profiles root not found: $resolvedProfilesRoot"
    }

    $manifestPath = Join-Path -Path $resolvedProfilesRoot -ChildPath 'profiles.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Profiles manifest not found: $manifestPath"
    }

    $manifestRaw = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop
    try {
        $manifest = $manifestRaw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Profiles manifest JSON is invalid: $manifestPath"
    }

    $profiles = @($manifest.profiles)
    if ($profiles.Count -eq 0) {
        throw "Profiles manifest '$manifestPath' does not define any profiles."
    }

    $defaultProfiles = @($profiles | Where-Object {
        [bool](Get-OptionalPropertyValue -Object $_ -PropertyName 'default' -DefaultValue $false)
    })
    if ($defaultProfiles.Count -ne 1) {
        throw "Profiles manifest must define exactly one default profile. Found $($defaultProfiles.Count)."
    }

    $selectedProfileId = if ([string]::IsNullOrWhiteSpace($ProfileId)) {
        [string](Get-OptionalPropertyValue -Object $defaultProfiles[0] -PropertyName 'id' -DefaultValue '')
    } else {
        $ProfileId.Trim()
    }
    if ([string]::IsNullOrWhiteSpace($selectedProfileId)) {
        throw 'Selected profile id is empty.'
    }

    $selectedProfiles = @($profiles | Where-Object {
        [string]::Equals(
            [string](Get-OptionalPropertyValue -Object $_ -PropertyName 'id' -DefaultValue ''),
            $selectedProfileId,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    })
    if ($selectedProfiles.Count -ne 1) {
        $knownIds = @($profiles | ForEach-Object {
            [string](Get-OptionalPropertyValue -Object $_ -PropertyName 'id' -DefaultValue '')
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        throw "Profile '$selectedProfileId' not found. Known profiles: $($knownIds -join ', ')."
    }
    $selectedProfile = $selectedProfiles[0]

    $selectedProfileFolderName = [string](Get-OptionalPropertyValue -Object $selectedProfile -PropertyName 'id' -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace($selectedProfileFolderName)) {
        throw 'Selected profile entry is missing required field: id.'
    }

    $profileDirectory = Join-Path -Path $resolvedProfilesRoot -ChildPath $selectedProfileFolderName
    if (-not (Test-Path -LiteralPath $profileDirectory -PathType Container)) {
        throw "Profile directory not found: $profileDirectory"
    }

    $profileLvversionPath = Join-Path -Path $profileDirectory -ChildPath '.lvversion'
    $profileLvversion = Resolve-LvversionInfo -Path $profileLvversionPath -ContextLabel "Profile '$selectedProfileFolderName'"

    $manifestLvversion = [string](Get-OptionalPropertyValue -Object $selectedProfile -PropertyName 'lvversion' -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace($manifestLvversion)) {
        throw "Profile '$selectedProfileFolderName' is missing required manifest field 'lvversion'."
    }
    if (-not [string]::Equals($manifestLvversion, [string]$profileLvversion.raw, [System.StringComparison]::Ordinal)) {
        throw (
            "Profile '$selectedProfileFolderName' manifest lvversion '$manifestLvversion' does not match profile .lvversion '$($profileLvversion.raw)'."
        )
    }

    $overlayPath = Join-Path -Path $profileDirectory -ChildPath 'vipb-display-info.overlay.json'
    if (-not (Test-Path -LiteralPath $overlayPath -PathType Leaf)) {
        throw "Profile '$selectedProfileFolderName' overlay file not found: $overlayPath"
    }
    $overlayRaw = Get-Content -LiteralPath $overlayPath -Raw -ErrorAction Stop
    try {
        $overlayData = $overlayRaw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Profile '$selectedProfileFolderName' overlay JSON is invalid: $overlayPath"
    }

    $resolvedConsumerRepoRoot = Resolve-FullPath -Path $ConsumerRepoRoot
    if (-not (Test-Path -LiteralPath $resolvedConsumerRepoRoot -PathType Container)) {
        throw "Consumer repo root not found: $resolvedConsumerRepoRoot"
    }

    $consumerLvversionPath = Join-Path -Path $resolvedConsumerRepoRoot -ChildPath '.lvversion'
    $consumerLvversion = Resolve-LvversionInfo -Path $consumerLvversionPath -ContextLabel 'Consumer'

    $profileExpectedTarget = Get-ExpectedVipbTarget -NumericVersion ([string]$profileLvversion.numeric) -Bitness $SupportedBitness
    $consumerExpectedTarget = Get-ExpectedVipbTarget -NumericVersion ([string]$consumerLvversion.numeric) -Bitness $SupportedBitness
    $comparisonResult = if (
        [string]::Equals($profileExpectedTarget, $consumerExpectedTarget, [System.StringComparison]::Ordinal)
    ) {
        'match'
    } else {
        'mismatch'
    }

    $warningMessage = if ($comparisonResult -eq 'mismatch') {
        "Selected profile '$selectedProfileId' targets '$profileExpectedTarget' while consumer .lvversion targets '$consumerExpectedTarget'. Consumer remains authoritative."
    } else {
        ''
    }

    $resolution = [ordered]@{
        schema_version = 1
        generated_utc = (Get-Date).ToUniversalTime().ToString('o')
        selected_profile_id = $selectedProfileId
        supported_bitness = $SupportedBitness
        comparison_result = $comparisonResult
        warning_required = ($comparisonResult -eq 'mismatch')
        warning_message = $warningMessage
        manifest = [ordered]@{
            path = $manifestPath
            sha256 = Get-FileSha256 -Path $manifestPath
            schema_version = (Get-OptionalPropertyValue -Object $manifest -PropertyName 'schema_version' -DefaultValue $null)
            default_profile_id = [string](Get-OptionalPropertyValue -Object $defaultProfiles[0] -PropertyName 'id' -DefaultValue '')
            profiles_count = $profiles.Count
        }
        profile = [ordered]@{
            id = $selectedProfileFolderName
            display_name = [string](Get-OptionalPropertyValue -Object $selectedProfile -PropertyName 'display_name' -DefaultValue '')
            status = [string](Get-OptionalPropertyValue -Object $selectedProfile -PropertyName 'status' -DefaultValue '')
            manifest_lvversion_raw = $manifestLvversion
            profile_root = $profileDirectory
            lvversion_path = $profileLvversion.path
            lvversion_raw = $profileLvversion.raw
            lvversion_numeric = $profileLvversion.numeric
            lvversion_year = $profileLvversion.year
            lvversion_minor = $profileLvversion.minor
            expected_vipb_target = $profileExpectedTarget
            supported_bitness = @(Get-OptionalPropertyValue -Object $selectedProfile -PropertyName 'supported_bitness' -DefaultValue @())
            lvversion_sha256 = $profileLvversion.sha256
            overlay_path = $overlayPath
            overlay_sha256 = Get-FileSha256 -Path $overlayPath
            overlay_data = $overlayData
        }
        consumer = [ordered]@{
            repo_root = $resolvedConsumerRepoRoot
            lvversion_path = $consumerLvversion.path
            lvversion_raw = $consumerLvversion.raw
            lvversion_numeric = $consumerLvversion.numeric
            lvversion_year = $consumerLvversion.year
            lvversion_minor = $consumerLvversion.minor
            expected_vipb_target = $consumerExpectedTarget
            lvversion_sha256 = $consumerLvversion.sha256
        }
    }

    Write-ResolutionJson -Path $resolvedOutputPath -Payload $resolution

    if ($comparisonResult -eq 'mismatch') {
        Write-Host ("::warning title=LabVIEW profile advisory mismatch::{0}" -f $warningMessage)
    }
    Write-Host ("LabVIEW profile resolution written: {0}" -f $resolvedOutputPath)
    Write-Host ("Selected profile: {0}" -f $selectedProfileId)
    Write-Host ("Comparison result: {0}" -f $comparisonResult)
}
catch {
    $errorMessage = $_.Exception.Message
    $fallbackResolution = [ordered]@{
        schema_version = 1
        generated_utc = (Get-Date).ToUniversalTime().ToString('o')
        selected_profile_id = $ProfileId
        supported_bitness = $SupportedBitness
        comparison_result = 'invalid'
        warning_required = $false
        warning_message = ''
        error = [ordered]@{
            type = $_.Exception.GetType().FullName
            message = $errorMessage
        }
    }

    try {
        Write-ResolutionJson -Path $resolvedOutputPath -Payload $fallbackResolution
    } catch {
        Write-Warning ("Failed to write invalid profile resolution payload to '{0}': {1}" -f $resolvedOutputPath, $_.Exception.Message)
    }

    Write-Error $errorMessage
    exit 1
}
