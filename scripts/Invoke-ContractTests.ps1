param(
  [Parameter(Mandatory = $false)]
  [string]$TestPath = './tests/*.Tests.ps1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$minimum = [version]'5.0.0'
$installed = Get-Module -ListAvailable -Name Pester |
  Sort-Object Version -Descending |
  Select-Object -First 1

if (-not $installed -or $installed.Version -lt $minimum) {
  Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
  Install-Module -Name Pester -Scope CurrentUser -Force -SkipPublisherCheck -MinimumVersion $minimum
}

Import-Module Pester -MinimumVersion 5.0.0
Invoke-Pester -Path $TestPath -CI