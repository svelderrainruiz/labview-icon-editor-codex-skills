#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Release dual PPL VIPM workflow contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:workflowPath = Join-Path $script:repoRoot '.github/workflows/release-dual-ppl-vipm-package.yml'

        if (-not (Test-Path -Path $script:workflowPath -PathType Leaf)) {
            throw "Required workflow missing: $script:workflowPath"
        }

        $script:workflowContent = Get-Content -Path $script:workflowPath -Raw
    }

    It 'defines parallel producer jobs and linux package consumer job' {
        $script:workflowContent | Should -Match 'pull_request:'
        $script:workflowContent | Should -Match 'branches:\s*\r?\n\s*-\s*main'
        $script:workflowContent | Should -Match 'build-ppl-windows:'
        $script:workflowContent | Should -Match 'build-ppl-linux:'
        $script:workflowContent | Should -Match 'package-vip-linux:'
        $script:workflowContent | Should -Match 'needs:\s*\[build-ppl-windows,\s*build-ppl-linux\]'
    }

    It 'runs linux parity scripts from a CRLF-safe temp copy inside containers' {
        $expectedSedNormalization = [regex]::Escape('sed -i ''s/\r$//'' "$script_file"')
        $script:workflowContent | Should -Match 'runlabview-linux\.sh'
        $script:workflowContent | Should -Match 'tmp_script_dir="\$\(mktemp -d\)"'
        $script:workflowContent | Should -Match 'cp -a "\$script_dir/\." "\$tmp_script_dir/"'
        $script:workflowContent | Should -Match $expectedSedNormalization
        $script:workflowContent | Should -Match '"\$tmp_script_dir/runlabview-linux\.sh"'
    }
}
