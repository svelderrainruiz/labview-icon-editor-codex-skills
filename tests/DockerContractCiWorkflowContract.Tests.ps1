#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Docker contract CI workflow contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:workflowPath = Join-Path $script:repoRoot '.github/workflows/ci.yml'

        if (-not (Test-Path -Path $script:workflowPath -PathType Leaf)) {
            throw "Required workflow missing: $script:workflowPath"
        }

        $script:workflowContent = Get-Content -Path $script:workflowPath -Raw
    }

    It 'defines CI Pipeline workflow name and unfiltered pull_request trigger' {
        $script:workflowContent | Should -Match 'name:\s*CI Pipeline'
        $script:workflowContent | Should -Match 'pull_request:'
        $script:workflowContent | Should -Not -Match 'pull_request:\s*[\s\S]*?paths:'
    }

    It 'supports reusable workflow_call with source project override inputs' {
        $script:workflowContent | Should -Match 'workflow_call:'
        $script:workflowContent | Should -Match 'source_project_repo:'
        $script:workflowContent | Should -Match 'source_project_ref:'
        $script:workflowContent | Should -Match 'source_project_sha:'
        $script:workflowContent | Should -Match 'workflow_call:\s*[\s\S]*?labview_profile:'
        $script:workflowContent | Should -Match 'workflow_call:\s*[\s\S]*?source_labview_version_override:'
        $script:workflowContent | Should -Match 'workflow_call:\s*[\s\S]*?run_lv2020_edge_smoke:'
        $script:workflowContent | Should -Match 'CONSUMER_REPO:\s*\$\{\{\s*inputs\.source_project_repo'
        $script:workflowContent | Should -Match 'CONSUMER_REF:\s*\$\{\{\s*inputs\.source_project_ref'
        $script:workflowContent | Should -Match 'CONSUMER_EXPECTED_SHA:\s*\$\{\{\s*inputs\.source_project_sha'
        $script:workflowContent | Should -Match 'SOURCE_LVVERSION_OVERRIDE:\s*\$\{\{\s*inputs\.source_labview_version_override'
        $script:workflowContent | Should -Match 'RUN_LV2020_EDGE_SMOKE:\s*\$\{\{\s*inputs\.run_lv2020_edge_smoke'
    }

    It 'defines ordered docker-ci then non-gating pylavi/runner-cli lanes, then lunit smoke, windows or linux build jobs plus release-notes/profile/VIPB prep then self-hosted package, install, and final gate jobs' {
        $script:workflowContent | Should -Match 'docker-ci:'
        $script:workflowContent | Should -Not -Match 'contract-tests:'
        $script:workflowContent | Should -Match 'validate-pylavi-docker-source-project:'
        $script:workflowContent | Should -Match 'build-runner-cli-linux-docker:'
        $script:workflowContent | Should -Match 'run-lunit-smoke-x64:'
        $script:workflowContent | Should -Match 'run-lunit-smoke-lv2020x64-edge:'
        $script:workflowContent | Should -Match 'build-x64-ppl-windows:'
        $script:workflowContent | Should -Match 'build-x64-ppl-linux:'
        $script:workflowContent | Should -Match 'gather-release-notes:'
        $script:workflowContent | Should -Match 'resolve-labview-profile:'
        $script:workflowContent | Should -Match 'prepare-vipb-linux:'
        $script:workflowContent | Should -Match 'build-vip-self-hosted:'
        $script:workflowContent | Should -Match 'install-vip-x86-self-hosted:'
        $script:workflowContent | Should -Match 'ci-self-hosted-final-gate:'
        $script:workflowContent | Should -Match 'resolve-source-target:'
        $script:workflowContent | Should -Match 'resolve-source-target:\s*[\s\S]*?needs:\s*\[docker-ci\]'
        $script:workflowContent | Should -Match 'resolve-source-target:\s*[\s\S]*?Strict pin is required'
        $script:workflowContent | Should -Match 'resolve-source-target:\s*[\s\S]*?LVIE_SOURCE_PROJECT_REPO'
        $script:workflowContent | Should -Match 'validate-pylavi-docker-source-project:\s*[\s\S]*?needs:\s*\[docker-ci,\s*resolve-source-target\]'
        $script:workflowContent | Should -Match 'validate-pylavi-docker-source-project:\s*[\s\S]*?continue-on-error:\s*true'
        $script:workflowContent | Should -Match 'validate-pylavi-docker-source-project:\s*[\s\S]*?Run deterministic pylavi Docker validation'
        $script:workflowContent | Should -Match 'docker-contract-pylavi-source-project-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'build-runner-cli-linux-docker:\s*[\s\S]*?needs:\s*\[docker-ci,\s*resolve-source-target\]'
        $script:workflowContent | Should -Match 'build-runner-cli-linux-docker:\s*[\s\S]*?continue-on-error:\s*true'
        $script:workflowContent | Should -Match 'build-runner-cli-linux-docker:\s*[\s\S]*?Build runner-cli in deterministic Linux Docker lane'
        $script:workflowContent | Should -Match 'docker-contract-runner-cli-linux-x64-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'run-lunit-smoke-x64:\s*[\s\S]*?runs-on:\s*(\[\s*self-hosted,\s*windows,\s*\$\{\{\s*needs\.resolve-labview-profile\.outputs\.source_runner_label_x64\s*\}\}\s*\]|(?:\r?\n\s*-\s*self-hosted\r?\n\s*-\s*windows\r?\n\s*-\s*\$\{\{\s*needs\.resolve-labview-profile\.outputs\.source_runner_label_x64\s*\}\}))'
        $script:workflowContent | Should -Match 'run-lunit-smoke-x64:\s*[\s\S]*?needs:\s*\[docker-ci,\s*resolve-source-target,\s*resolve-labview-profile\]'
        $script:workflowContent | Should -Match 'run-lunit-smoke-lv2020x64-edge:\s*[\s\S]*?if:\s*\$\{\{\s*inputs\.run_lv2020_edge_smoke == true \|\| inputs\.run_lv2020_edge_smoke == ''true'''
        $script:workflowContent | Should -Match 'run-lunit-smoke-lv2020x64-edge:\s*[\s\S]*?needs:\s*\[docker-ci,\s*resolve-source-target\]'
        $script:workflowContent | Should -Match 'build-x64-ppl-windows:\s*[\s\S]*?runs-on:\s*windows-latest'
        $script:workflowContent | Should -Match 'build-x64-ppl-windows:\s*[\s\S]*?needs:\s*\[docker-ci,\s*resolve-source-target\]'
        $script:workflowContent | Should -Match 'build-x64-ppl-linux:\s*[\s\S]*?needs:\s*\[docker-ci,\s*resolve-source-target,\s*build-x64-ppl-windows\]'
        $script:workflowContent | Should -Match 'gather-release-notes:\s*[\s\S]*?runs-on:\s*ubuntu-latest'
        $script:workflowContent | Should -Match 'gather-release-notes:\s*[\s\S]*?needs:\s*\[docker-ci,\s*resolve-source-target\]'
        $script:workflowContent | Should -Match 'resolve-labview-profile:\s*[\s\S]*?runs-on:\s*ubuntu-latest'
        $script:workflowContent | Should -Match 'resolve-labview-profile:\s*[\s\S]*?needs:\s*\[docker-ci,\s*resolve-source-target\]'
        $script:workflowContent | Should -Match 'prepare-vipb-linux:\s*[\s\S]*?runs-on:\s*ubuntu-latest'
        $script:workflowContent | Should -Match 'prepare-vipb-linux:\s*[\s\S]*?needs:\s*\[docker-ci,\s*resolve-source-target,\s*gather-release-notes,\s*resolve-labview-profile\]'
        $script:workflowContent | Should -Match 'build-vip-self-hosted:\s*[\s\S]*?runs-on:\s*(\[\s*self-hosted,\s*windows,\s*\$\{\{\s*needs\.resolve-labview-profile\.outputs\.source_runner_label_x64\s*\}\},\s*\$\{\{\s*needs\.resolve-labview-profile\.outputs\.source_runner_label_x86\s*\}\}\s*\]|(?:\r?\n\s*-\s*self-hosted\r?\n\s*-\s*windows\r?\n\s*-\s*\$\{\{\s*needs\.resolve-labview-profile\.outputs\.source_runner_label_x64\s*\}\}\r?\n\s*-\s*\$\{\{\s*needs\.resolve-labview-profile\.outputs\.source_runner_label_x86\s*\}\}))'
        $script:workflowContent | Should -Match 'build-vip-self-hosted:\s*[\s\S]*?needs:\s*\[resolve-source-target,\s*build-x64-ppl-windows,\s*build-x64-ppl-linux,\s*prepare-vipb-linux,\s*run-lunit-smoke-x64,\s*resolve-labview-profile\]'
        $script:workflowContent | Should -Not -Match 'build-vip-self-hosted:\s*[\s\S]*?needs:\s*\[[^\]]*run-lunit-smoke-lv2020x64-edge'
        $script:workflowContent | Should -Match 'install-vip-x86-self-hosted:\s*[\s\S]*?needs:\s*\[resolve-source-target,\s*build-vip-self-hosted,\s*resolve-labview-profile\]'
        $script:workflowContent | Should -Match 'ci-self-hosted-final-gate:\s*[\s\S]*?needs:\s*\[build-vip-self-hosted,\s*install-vip-x86-self-hosted\]'
    }

    It 'defines portability source-target resolution chain and shared windows or linux build constants' {
        $script:workflowContent | Should -Match 'CONSUMER_REPO:\s*\$\{\{\s*inputs\.source_project_repo\s*\|\|\s*vars\.LVIE_SOURCE_PROJECT_REPO\s*\|\|\s*format\(''\{0\}/labview-icon-editor'',\s*github\.repository_owner\)\s*\}\}'
        $script:workflowContent | Should -Match 'CONSUMER_REF:\s*\$\{\{\s*inputs\.source_project_ref\s*\|\|\s*vars\.LVIE_SOURCE_PROJECT_REF\s*\|\|\s*''main''\s*\}\}'
        $script:workflowContent | Should -Match 'CONSUMER_EXPECTED_SHA:\s*\$\{\{\s*inputs\.source_project_sha\s*\|\|\s*vars\.LVIE_SOURCE_PROJECT_SHA\s*\|\|\s*''''\s*\}\}'
        $script:workflowContent | Should -Match 'PARITY_ENFORCEMENT_PROFILE:\s*\$\{\{\s*vars\.LVIE_PARITY_ENFORCEMENT_PROFILE\s*\|\|\s*''auto''\s*\}\}'
        $script:workflowContent | Should -Match 'WINDOWS_LABVIEW_IMAGE:\s*nationalinstruments/labview:2026q1-windows'
        $script:workflowContent | Should -Match 'LINUX_LABVIEW_IMAGE:\s*nationalinstruments/labview:2026q1-linux-pwsh'
        $script:workflowContent | Should -Match 'WINDOWS_PPL_OUTPUT_PATH:\s*consumer/resource/plugins/lv_icon\.windows\.lvlibp'
        $script:workflowContent | Should -Match 'LINUX_PPL_OUTPUT_PATH:\s*consumer/resource/plugins/lv_icon\.linux\.lvlibp'
        $script:workflowContent | Should -Match 'LABVIEW_PROFILES_ROOT:\s*profiles/labview'
        $script:workflowContent | Should -Match 'DEFAULT_LABVIEW_PROFILE:\s*\$\{\{\s*inputs\.labview_profile\s*\|\|\s*vars\.LVIE_LABVIEW_PROFILE\s*\|\|\s*''lv2026'''
    }

    It 'defines workflow_dispatch LabVIEW profile selector input' {
        $script:workflowContent | Should -Match 'workflow_dispatch:\s*[\s\S]*?inputs:'
        $script:workflowContent | Should -Match 'workflow_dispatch:\s*[\s\S]*?source_project_repo:'
        $script:workflowContent | Should -Match 'workflow_dispatch:\s*[\s\S]*?source_project_ref:'
        $script:workflowContent | Should -Match 'workflow_dispatch:\s*[\s\S]*?source_project_sha:'
        $script:workflowContent | Should -Match 'workflow_dispatch:\s*[\s\S]*?labview_profile:'
        $script:workflowContent | Should -Match 'labview_profile:\s*[\s\S]*?default:\s*''lv2026'''
        $script:workflowContent | Should -Match 'workflow_dispatch:\s*[\s\S]*?source_labview_version_override:'
        $script:workflowContent | Should -Match 'workflow_dispatch:\s*[\s\S]*?run_lv2020_edge_smoke:'
        $script:workflowContent | Should -Match 'run_lv2020_edge_smoke:\s*[\s\S]*?default:\s*false'
    }

    It 'checks out consumer and validates expected SHA in PPL, release-notes, and VIPB prep jobs' {
        ([regex]::Matches($script:workflowContent, 'Checkout source project repository')).Count | Should -BeGreaterOrEqual 4
        ([regex]::Matches($script:workflowContent, 'Verify checked out source project SHA')).Count | Should -BeGreaterOrEqual 4
        $script:workflowContent | Should -Match 'Source project SHA mismatch'
    }

    It 'gathers release notes in a dedicated artifact job for VIPB prep consumption' {
        $script:workflowContent | Should -Match 'gather-release-notes:'
        $script:workflowContent | Should -Match 'Gather release notes artifact content'
        $script:workflowContent | Should -Match 'Upload release notes artifact'
        $script:workflowContent | Should -Match 'docker-contract-release-notes-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'Download release notes artifact'
        $script:workflowContent | Should -Match 'Install gathered release notes for VIPB preparation'
        $script:workflowContent | Should -Match 'release_notes\.md'
    }

    It 'resolves repo-owned LabVIEW target preset advisory, derives source-version runner labels, and uploads resolution artifact' {
        $script:workflowContent | Should -Match 'resolve-labview-profile:'
        $script:workflowContent | Should -Match 'resolve-labview-profile:\s*[\s\S]*?outputs:'
        $script:workflowContent | Should -Match 'source_labview_year:\s*\$\{\{\s*steps\.source-labels\.outputs\.source_labview_year\s*\}\}'
        $script:workflowContent | Should -Match 'source_runner_label_x86:\s*\$\{\{\s*steps\.source-labels\.outputs\.source_runner_label_x86\s*\}\}'
        $script:workflowContent | Should -Match 'source_runner_label_x64:\s*\$\{\{\s*steps\.source-labels\.outputs\.source_runner_label_x64\s*\}\}'
        $script:workflowContent | Should -Match 'effective_lvversion_raw:\s*\$\{\{\s*steps\.source-labels\.outputs\.effective_lvversion_raw\s*\}\}'
        $script:workflowContent | Should -Match 'effective_labview_year:\s*\$\{\{\s*steps\.source-labels\.outputs\.effective_labview_year\s*\}\}'
        $script:workflowContent | Should -Match 'observed_source_lvversion_raw:\s*\$\{\{\s*steps\.source-labels\.outputs\.observed_source_lvversion_raw\s*\}\}'
        $script:workflowContent | Should -Match 'override_active:\s*\$\{\{\s*steps\.source-labels\.outputs\.override_active\s*\}\}'
        $script:workflowContent | Should -Match 'Resolve selected LabVIEW target preset id'
        $script:workflowContent | Should -Match 'scripts/Resolve-LabviewProfile\.ps1'
        $script:workflowContent | Should -Match 'Resolve source project runner labels from \.lvversion'
        $script:workflowContent | Should -Match 'source_labview_version_override'
        $script:workflowContent | Should -Match 'self-hosted-windows-lv\$\{yearValue\}x86'
        $script:workflowContent | Should -Match '::warning title=LabVIEW target preset advisory mismatch::'
        $script:workflowContent | Should -Match '::warning title=Source project LabVIEW override active::'
        $script:workflowContent | Should -Match '## LabVIEW Target Preset Advisory'
        $script:workflowContent | Should -Match 'Upload LabVIEW profile resolution artifact'
        $script:workflowContent | Should -Match 'docker-contract-labview-profile-resolution-\$\{\{\s*github\.run_id\s*\}\}'
    }

    It 'builds windows x64 PPL in windows container and uploads windows x64 bundle artifact' {
        $script:workflowContent | Should -Match 'Validate Windows container parity assets'
        $script:workflowContent | Should -Match 'Get-ChildItem -Path \$consumerRoot -Recurse -File -Filter ''lv_icon_editor\.lvproj'''
        $script:workflowContent | Should -Match 'Missing ''\.lvversion'' alongside ''lv_icon_editor\.lvproj'''
        $script:workflowContent | Should -Match 'Minimum supported LabVIEW version is 20\.0'
        $script:workflowContent | Should -Match 'WINDOWS_PROJECT_RELATIVE_PATH='
        $script:workflowContent | Should -Match 'WINDOWS_PROJECT_CONTAINER_PATH='
        $script:workflowContent | Should -Match 'Build Windows x64 PPL in NI Windows container'
        $script:workflowContent | Should -Match 'LVIE_PROJECT_RELATIVE_PATH=\$projectRelativePath'
        $script:workflowContent | Should -Match 'PROJECT_PATH_REL=\$projectRelativePath'
        $script:workflowContent | Should -Match 'LVIE_PROJECT_PATH=\$projectContainerPath'
        $script:workflowContent | Should -Match 'PROJECT_PATH=\$projectContainerPath'
        $script:workflowContent | Should -Match 'runlabview-windows\.ps1'
        $script:workflowContent | Should -Match 'Create Windows x64 PPL bundle manifest'
        $script:workflowContent | Should -Match 'Upload Windows raw x64 PPL artifact'
        $script:workflowContent | Should -Match 'docker-contract-ppl-windows-raw-x64-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'docker-contract-ppl-bundle-windows-x64-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'Upload Windows x64 PPL bundle artifact'
    }

    It 'builds linux x64 PPL with CRLF-safe temp copy and uploads linux x64 bundle artifact' {
        $expectedSedNormalization = [regex]::Escape('sed -i ''s/\r$//'' "$script_file"')
        $script:workflowContent | Should -Match 'Build Linux x64 PPL in NI Linux container'
        $script:workflowContent | Should -Match 'tmp_script_dir="\$\(mktemp -d\)"'
        $script:workflowContent | Should -Match 'cp -a "\$script_dir/\." "\$tmp_script_dir/"'
        $script:workflowContent | Should -Match $expectedSedNormalization
        $script:workflowContent | Should -Match '"\$tmp_script_dir/runlabview-linux\.sh"'
        $script:workflowContent | Should -Match 'Create Linux x64 PPL bundle manifest'
        $script:workflowContent | Should -Match 'Upload Linux raw x64 PPL artifact'
        $script:workflowContent | Should -Match 'docker-contract-ppl-linux-raw-x64-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'docker-contract-ppl-bundle-linux-x64-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'Upload Linux x64 PPL bundle artifact'
    }

    It 'runs native LabVIEW lunit smoke gate in x64 with source-version target and uploads diagnostics artifact' {
        $runLunitBlockMatch = [regex]::Match($script:workflowContent, 'run-lunit-smoke-x64:\s*[\s\S]*?run-lunit-smoke-lv2020x64-edge:', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $runLunitBlockMatch.Success | Should -BeTrue
        $runLunitBlock = $runLunitBlockMatch.Value

        $script:workflowContent | Should -Match 'run-lunit-smoke-x64:'
        $script:workflowContent | Should -Match 'Run native LabVIEW LUnit smoke \(x64, source-version target\)'
        $script:workflowContent | Should -Match 'scripts/Invoke-LunitSmokeLv2020\.ps1'
        $script:workflowContent | Should -Not -Match 'Resolve LUnit smoke execution target'
        $script:workflowContent | Should -Match '-TargetLabVIEWVersion \$\{\{\s*needs\.resolve-labview-profile\.outputs\.effective_labview_year\s*\}\}'
        $script:workflowContent | Should -Match '-OverrideLvversion ''\$\{\{\s*needs\.resolve-labview-profile\.outputs\.effective_lvversion_raw\s*\}\}'''
        $script:workflowContent | Should -Match '-RequiredBitness ''64'''
        $script:workflowContent | Should -Match '-EnforceLabVIEWProcessIsolation'
        $runLunitBlock | Should -Not -Match '-AllowNoTestcasesWhenControlProbePasses'
        $runLunitBlock | Should -Not -Match '-RequiredBitness ''32'''
        $script:workflowContent | Should -Match 'Publish LabVIEW 2020 LUnit smoke summary'
        $script:workflowContent | Should -Match 'Effective \.lvversion'
        $script:workflowContent | Should -Match 'Observed source \.lvversion'
        $script:workflowContent | Should -Match 'Override active'
        $script:workflowContent | Should -Match 'lunit-report-lv\{0\}-x64\.xml'
        $script:workflowContent | Should -Match 'lunit-report-lv2026-x64-control\.xml'
        $script:workflowContent | Should -Match 'LV2026 Comparative Control Probe \(diagnostic only\)'
        $script:workflowContent | Should -Not -Match '\("- Bitness: `64`"\)'
        $script:workflowContent | Should -Match 'Upload LabVIEW 2020 LUnit smoke artifact'
        $script:workflowContent | Should -Match 'docker-contract-lunit-smoke-lv2020-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'Upload LabVIEW 2020 LUnit smoke artifact\s*[\s\S]*?if:\s*always\(\)'
    }

    It 'defines optional non-gating LV2020 x64 edge smoke diagnostics job' {
        $edgeJobBlockMatch = [regex]::Match($script:workflowContent, 'run-lunit-smoke-lv2020x64-edge:\s*[\s\S]*?build-x64-ppl-windows:', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $edgeJobBlockMatch.Success | Should -BeTrue
        $edgeJobBlock = $edgeJobBlockMatch.Value

        $script:workflowContent | Should -Match 'run-lunit-smoke-lv2020x64-edge:'
        $script:workflowContent | Should -Match 'Run optional LV2020 x64 edge smoke \(non-gating\)'
        $script:workflowContent | Should -Match 'run-lunit-smoke-lv2020x64-edge:\s*[\s\S]*?-TargetLabVIEWVersion 2020'
        $script:workflowContent | Should -Match 'run-lunit-smoke-lv2020x64-edge:\s*[\s\S]*?-OverrideLvversion ''20\.0'''
        $edgeJobBlock | Should -Match '-AllowNoTestcasesWhenControlProbePasses'
        $script:workflowContent | Should -Match 'run-lunit-smoke-lv2020x64-edge:\s*[\s\S]*?continue-on-error:\s*true'
        $script:workflowContent | Should -Match 'docker-contract-lunit-smoke-lv2020-edge-\$\{\{\s*github\.run_id\s*\}\}'
    }

    It 'keeps the LabVIEW 2020 smoke summary PowerShell block parse-safe' {
        $summaryStepMatch = [regex]::Match(
            $script:workflowContent,
            '- name: Publish LabVIEW 2020 LUnit smoke summary[\s\S]*?run:\s*\|\s*(?<script>[\s\S]*?)\r?\n\s*- name: Upload LabVIEW 2020 LUnit smoke artifact',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )
        $summaryStepMatch.Success | Should -BeTrue

        $summaryScript = $summaryStepMatch.Groups['script'].Value
        $summaryScript | Should -Not -Match '\("- Bitness: `64`"\)'

        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($summaryScript, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
    }

    It 'keeps the pylavi Docker summary PowerShell block parse-safe' {
        $summaryStepMatch = [regex]::Match(
            $script:workflowContent,
            '- name: Publish pylavi Docker validation summary[\s\S]*?run:\s*\|\s*(?<script>[\s\S]*?)\r?\n\s*- name: Upload pylavi Docker validation artifact',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )
        $summaryStepMatch.Success | Should -BeTrue

        $summaryScript = $summaryStepMatch.Groups['script'].Value
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($summaryScript, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
    }

    It 'keeps the runner-cli Docker summary PowerShell block parse-safe' {
        $summaryStepMatch = [regex]::Match(
            $script:workflowContent,
            '- name: Publish runner-cli Linux Docker summary[\s\S]*?run:\s*\|\s*(?<script>[\s\S]*?)\r?\n\s*- name: Upload runner-cli Linux Docker artifact',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )
        $summaryStepMatch.Success | Should -BeTrue

        $summaryScript = $summaryStepMatch.Groups['script'].Value
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($summaryScript, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
    }

    It 'does not use inline if expressions inside -f format calls in workflow scripts' {
        $script:workflowContent | Should -Not -Match '-f\s+\(if\s+\('
    }

    It 'asserts source project remotes in each self-hosted job before consumer-script execution' {
        $script:workflowContent | Should -Match 'run-lunit-smoke-x64:\s*[\s\S]*?Assert source project remotes'
        $script:workflowContent | Should -Match 'build-vip-self-hosted:\s*[\s\S]*?Assert source project remotes'
        $script:workflowContent | Should -Match 'install-vip-x86-self-hosted:\s*[\s\S]*?Assert source project remotes'
        $script:workflowContent | Should -Match 'scripts/Assert-SourceProjectRemotes\.ps1'
        $script:workflowContent | Should -Match '-UpstreamRepo \$env:CONSUMER_REPO'
        $script:workflowContent | Should -Match 'source-project-remotes\.result\.json'
    }

    It 'keeps all source-project-remotes summary blocks parse-safe' {
        $script:workflowContent | Should -Not -Match '\("- Upstream repo: `\{0\}`"'

        $summaryBlockMatches = [regex]::Matches(
            $script:workflowContent,
            '- name: Assert source project remotes[\s\S]*?run:\s*\|\s*(?<script>[\s\S]*?)\r?\n\s*- name:',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )
        $summaryBlockMatches.Count | Should -BeGreaterOrEqual 3

        foreach ($match in $summaryBlockMatches) {
            $summaryScript = $match.Groups['script'].Value
            $tokens = $null
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseInput($summaryScript, [ref]$tokens, [ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }

    It 'runs VIPB diagnostics suite on linux and emits summary plus artifact' {
        $script:workflowContent | Should -Match 'prepare-vipb-linux:'
        $script:workflowContent | Should -Match 'Apply effective \.lvversion for VIPB prep'
        $script:workflowContent | Should -Match 'Download LabVIEW target preset resolution artifact'
        $script:workflowContent | Should -Match 'docker-contract-labview-profile-resolution-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'Run VIPB diagnostics suite'
        $script:workflowContent | Should -Match 'continue-on-error:\s*true'
        $script:workflowContent | Should -Match 'scripts/Invoke-PrepareVipbDiagnostics\.ps1'
        $script:workflowContent | Should -Match '-RepoRoot \(Join-Path \$env:GITHUB_WORKSPACE ''consumer''\)'
        $script:workflowContent | Should -Match '-ProfileResolutionPath \(Join-Path \$env:RUNNER_TEMP ''labview-profile-resolution/profile-resolution\.json''\)'
        $script:workflowContent | Should -Match 'Publish VIPB diagnostics summary'
        $script:workflowContent | Should -Match 'GITHUB_STEP_SUMMARY'
        $script:workflowContent | Should -Match 'vipb-diagnostics-summary\.md'
        $script:workflowContent | Should -Match 'Upload prepared VIPB artifact'
        $script:workflowContent | Should -Match 'Upload prepared VIPB artifact\s*[\s\S]*?if:\s*always\(\)'
        $script:workflowContent | Should -Match 'docker-contract-vipb-prepared-linux-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'Fail if VIPB diagnostics suite failed'
        $script:workflowContent | Should -Match 'prepare-vipb\.status\.json'
        $script:workflowContent | Should -Match '::error title=VIPB diagnostics failed::'
        $script:workflowContent | Should -Match '::group::VIPB diagnostics failure context'
        $script:workflowContent | Should -Match 'prepare-vipb\.error\.json'
        $script:workflowContent | Should -Match 'vipb-diagnostics-summary\.md'
        $script:workflowContent | Should -Match 'status failed but error payload missing/unparseable'
    }

    It 'creates manifests for both windows and linux bundles' {
        ([regex]::Matches($script:workflowContent, 'scripts/New-PplBundleManifest\.ps1')).Count | Should -BeGreaterOrEqual 2
    }

    It 'defines self-hosted native package version constants using 0.1.0 baseline' {
        $script:workflowContent | Should -Match 'build-vip-self-hosted:\s*[\s\S]*?VERSION_MAJOR:\s*''0'''
        $script:workflowContent | Should -Match 'build-vip-self-hosted:\s*[\s\S]*?VERSION_MINOR:\s*''1'''
        $script:workflowContent | Should -Match 'build-vip-self-hosted:\s*[\s\S]*?VERSION_PATCH:\s*''0'''
        $script:workflowContent | Should -Match 'build-vip-self-hosted:\s*[\s\S]*?LVIE_RUNNER_CLI_SKIP_BUILD:\s*''1'''
        $script:workflowContent | Should -Match 'build-vip-self-hosted:\s*[\s\S]*?LVIE_RUNNER_CLI_SKIP_DOWNLOAD:\s*''1'''
    }

    It 'bootstraps worktree context in self-hosted lane' {
        $script:workflowContent | Should -Match 'Bootstrap worktree guard context'
        $script:workflowContent | Should -Match 'LVIE_WORKTREE_ROOT='
        $script:workflowContent | Should -Match 'LVIE_SKIP_WORKTREE_ROOT_CHECK=1'
    }

    It 'consumes windows x64 PPL and linux-prepared VIPB, then only builds native x86 in self-hosted lane' {
        $script:workflowContent | Should -Match 'Apply effective \.lvversion for self-hosted build'
        $script:workflowContent | Should -Match 'Download Windows x64 PPL bundle artifact'
        $script:workflowContent | Should -Match 'Download prepared VIPB artifact'
        $script:workflowContent | Should -Match 'actions/download-artifact@v4'
        $script:workflowContent | Should -Match 'Consume prepared VIPB from Linux artifact'
        $script:workflowContent | Should -Match 'docker-contract-vipb-prepared-linux-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'NI Icon editor\.vipb'
        $script:workflowContent | Should -Match 'Consume Windows-built x64 PPL bundle'
        $script:workflowContent | Should -Match 'Invoke-PplBundleConsume\.ps1'
        $script:workflowContent | Should -Match 'lv_icon_x64\.lvlibp'
        $script:workflowContent | Should -Match 'Build native 32-bit PPL'
        $script:workflowContent | Should -Not -Match 'Build native 64-bit PPL'
        $script:workflowContent | Should -Not -Match 'Modify VIPB display info \(LV 64-bit\)'
        $script:workflowContent | Should -Match '-SupportedBitness 32'
        $script:workflowContent | Should -Match 'lv_icon_x86\.lvlibp'
    }

    It 'stamps 0.1.0 version in native build calls and uploads self-hosted VIP artifact' {
        $script:workflowContent | Should -Match 'BuildProjectSpec\.ps1'
        $script:workflowContent | Should -Match 'Upload consumed VIPB \(post-mortem\)'
        $script:workflowContent | Should -Match 'docker-contract-vipb-modified-self-hosted-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'Invoke-VipmBuildPackage\.ps1'
        $script:workflowContent | Should -Match 'Required command ''vipm'' not found on PATH for self-hosted packaging lane'
        $script:workflowContent | Should -Not -Match 'Required command ''g-cli'' not found on PATH for self-hosted packaging lane'
        $script:workflowContent | Should -Match '-Major \$env:VERSION_MAJOR'
        $script:workflowContent | Should -Match '-Minor \$env:VERSION_MINOR'
        $script:workflowContent | Should -Match '-Patch \$env:VERSION_PATCH'
        $script:workflowContent | Should -Match 'Upload VIPM package build diagnostics artifact'
        $script:workflowContent | Should -Match 'docker-contract-vipm-build-self-hosted-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'docker-contract-vip-package-self-hosted-\$\{\{\s*github\.run_id\s*\}\}'
    }

    It 'runs post-package VIPM install smoke on dynamic x86 runner label and uploads diagnostics artifact' {
        $script:workflowContent | Should -Match 'install-vip-x86-self-hosted:'
        $script:workflowContent | Should -Match 'install-vip-x86-self-hosted:\s*[\s\S]*?runs-on:\s*(\[\s*self-hosted,\s*windows,\s*\$\{\{\s*needs\.resolve-labview-profile\.outputs\.source_runner_label_x86\s*\}\}\s*\]|(?:\r?\n\s*-\s*self-hosted\r?\n\s*-\s*windows\r?\n\s*-\s*\$\{\{\s*needs\.resolve-labview-profile\.outputs\.source_runner_label_x86\s*\}\}))'
        $script:workflowContent | Should -Match 'Download self-hosted VI Package artifact'
        $script:workflowContent | Should -Match 'docker-contract-vip-package-self-hosted-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'Resolve VI Package artifact path'
        $script:workflowContent | Should -Match 'Apply effective \.lvversion for x86 install smoke'
        $script:workflowContent | Should -Match 'Run VIPM install smoke \(x86, \.lvversion-driven\)'
        $script:workflowContent | Should -Match 'scripts/Invoke-VipmInstallSmoke\.ps1'
        $script:workflowContent | Should -Match '-RequiredBitness ''32'''
        $script:workflowContent | Should -Match 'Publish VIPM install smoke summary'
        $script:workflowContent | Should -Match 'Upload VIPM install smoke diagnostics artifact'
        $script:workflowContent | Should -Match 'docker-contract-vipm-install-x86-\$\{\{\s*github\.run_id\s*\}\}'
        $script:workflowContent | Should -Match 'Upload VIPM install smoke diagnostics artifact\s*[\s\S]*?if:\s*always\(\)'
    }

    It 'defines final self-hosted gate that depends on package build and x86 VIPM install smoke' {
        $script:workflowContent | Should -Match 'ci-self-hosted-final-gate:'
        $script:workflowContent | Should -Match 'ci-self-hosted-final-gate:\s*[\s\S]*?needs:\s*\[build-vip-self-hosted,\s*install-vip-x86-self-hosted\]'
        $script:workflowContent | Should -Match 'Final self-hosted CI gate'
    }
}

