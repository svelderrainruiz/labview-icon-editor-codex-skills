#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Docker contract CI workflow contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:workflowPath = Join-Path $script:repoRoot '.github/workflows/docker-contract-ci.yml'

        if (-not (Test-Path -Path $script:workflowPath -PathType Leaf)) {
            throw "Required workflow missing: $script:workflowPath"
        }

        $script:workflowContent = Get-Content -Path $script:workflowPath -Raw
    }

    It 'checks out pinned consumer source and validates expected SHA' {
        $script:workflowContent | Should -Match 'CONSUMER_REPO:\s*svelderrainruiz/labview-icon-editor'
        $script:workflowContent | Should -Match 'CONSUMER_REF:\s*patch/456-2020-migration-branch-from-9e46ecf'
        $script:workflowContent | Should -Match 'CONSUMER_EXPECTED_SHA:\s*9e46ecf591bc36afca8ddf4ce688a5f58604a12a'
        $script:workflowContent | Should -Match 'Verify checked out consumer SHA'
        $script:workflowContent | Should -Match 'Consumer SHA mismatch'
    }

    It 'builds linux PPL using CRLF-safe parity script execution' {
        $expectedSedNormalization = [regex]::Escape('sed -i ''s/\r$//'' "$script_file"')
        $script:workflowContent | Should -Match 'Build Linux PPL in NI Linux container'
        $script:workflowContent | Should -Match 'tmp_script_dir="\$\(mktemp -d\)"'
        $script:workflowContent | Should -Match 'cp -a "\$script_dir/\." "\$tmp_script_dir/"'
        $script:workflowContent | Should -Match $expectedSedNormalization
        $script:workflowContent | Should -Match '"\$tmp_script_dir/runlabview-linux\.sh"'
        $script:workflowContent | Should -Match 'CONTAINER_PARITY_BUILD_SPEC=true'
    }

    It 'creates and uploads linux PPL bundle artifact with manifest' {
        $script:workflowContent | Should -Match 'Create Linux PPL bundle manifest'
        $script:workflowContent | Should -Match 'scripts/New-PplBundleManifest\.ps1'
        $script:workflowContent | Should -Match 'docker-contract-ppl-bundle-linux-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'if-no-files-found:\s*error'
    }
}
