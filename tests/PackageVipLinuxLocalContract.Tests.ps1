#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Local package-vip-linux helper contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:helperPath = Join-Path $script:repoRoot 'scripts/Invoke-PackageVipLinuxLocal.ps1'

        if (-not (Test-Path -Path $script:helperPath -PathType Leaf)) {
            throw "Helper script not found: $script:helperPath"
        }

        $script:helperContent = Get-Content -Raw -Path $script:helperPath
    }

    It 'exists under scripts with expected defaults' {
        $script:helperPath | Should -Match 'scripts[\\/]Invoke-PackageVipLinuxLocal\.ps1$'
        $script:helperContent | Should -Match '\[string\]\$LinuxLabviewImage\s*=\s*''nationalinstruments/labview:2026q1-linux-pwsh'''
        $script:helperContent | Should -Match '\[string\]\$VipmProjectPath\s*=\s*''consumer/Tooling/deployment/NI Icon editor\.vipb'''
    }

    It 'runs docker with workflow-aligned environment variables' {
        $script:helperContent | Should -Match 'VIPM_COMMUNITY_EDITION='
        $script:helperContent | Should -Match 'VIPM_PROJECT_PATH_IN_CONTAINER='
        $script:helperContent | Should -Match 'LINUX_LABVIEW_IMAGE='
        $script:helperContent | Should -Match "'bash',\s*'-lc'"
    }

    It 'emits actionable diagnostics when vipm is missing' {
        $script:helperContent | Should -Match 'vipm is not available on PATH inside Linux image'
        $script:helperContent | Should -Match 'PATH=\$PATH'
        $script:helperContent | Should -Match "vipm lookup: \$\(command -v vipm \|\| echo 'not-found'\)"
        $script:helperContent | Should -Match 'docker build --build-arg VIPM_CLI_URL=ARTIFACT_URL'
        $script:helperContent | Should -Match '--build-arg VIPM_CLI_SHA256=SHA256'
    }
}
