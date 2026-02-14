# Release Gates Contract (Agent View)

Last validated: 2026-02-14
Validation evidence: skills repo CI-coupled release flow

## Contract intent
Define deterministic GO/NO-GO release decisions using this repository's CI gate (`.github/workflows/ci.yml`) before publishing a skill-layer release.

## Gate inputs
From skills repo CI run metadata:
- run status
- run conclusion
- job conclusions
- artifact inventory
- source project SHA pin

## Required artifacts
- docker-contract-ppl-bundle-windows-x64-<run_id>
- docker-contract-ppl-bundle-linux-x64-<run_id>
- docker-contract-vip-package-self-hosted-<run_id>
- codex-skill-layer

## Release payload contract
Release publish must include these files:
- lvie-codex-skill-layer-installer.exe
- lvie-ppl-bundle-windows-x64.zip
- lvie-ppl-bundle-linux-x64.zip
- lvie-vip-package-self-hosted.zip
- release-provenance.json
- release-payload-manifest.json

## Job failure set
Any job with one of these conclusions fails the gate:
- failure
- cancelled
- timed_out
- startup_failure
- action_required

## Gate algorithm
1. Verify run status is completed.
2. Verify run conclusion is success.
3. Verify zero jobs in failure set.
4. Verify all required artifacts are present.
5. If all pass: GO; else: NO-GO.

## Dispatch policy
Only dispatch `.github/workflows/release-skill-layer.yml` when GO.

Required dispatch inputs:
- `release_tag` (example `v0.4.1`)
- `consumer_repo` (source project repo)
- `consumer_ref` (source project ref)
- `consumer_sha` (source project SHA)

Optional inputs:
- `labview_profile` (LabVIEW target preset id)
- `run_self_hosted` (deprecated compatibility input)
- `run_build_spec` (deprecated compatibility input)

## Self-hosted preflight policy
- Before declaring GO for runs that include self-hosted jobs, verify runner label availability:
  - `self-hosted-windows-lv2020x64`
  - `self-hosted-windows-lv2020x86`
- Self-hosted jobs enforce source-project remote hygiene with `Assert-SourceProjectRemotes.ps1`:
  - `upstream` must resolve to `https://github.com/<source-project-repo>.git`
  - non-interactive `git ls-remote upstream` must succeed
  - failures are hard-gate failures, not warnings.
- `run-lunit-smoke-lv2020x64` remains a strict gate:
  - LV2020 failure is blocking.
  - a diagnostic-only LV2026 x64 control probe may run on failure to improve root-cause clarity, but it does not change gate outcome.

## Provenance policy
Release notes must include CI and source-project provenance fields produced by `ci.yml` and `release-skill-layer`:
- `skills_ci_repo`
- `skills_ci_run_url`
- `skills_ci_run_id`
- `skills_ci_run_attempt`
- `source_project_repo`
- `source_project_ref`
- `source_project_sha`

## Auth boundary policy
- Git operations are independent of GitHub auth.
- Release dispatch and run querying require GitHub auth.
- Prefer short-lived token usage for automation.

## Operational commands
```powershell
gh api repos/svelderrainruiz/labview-icon-editor-codex-skills/actions/runs/<RUN_ID> --jq '{status, conclusion, head_sha, head_branch, run_attempt, updated_at}'
```

```powershell
gh api repos/svelderrainruiz/labview-icon-editor-codex-skills/actions/runs/<RUN_ID>/jobs --paginate --jq '.jobs[] | {name, status, conclusion}'
```

```powershell
gh api repos/svelderrainruiz/labview-icon-editor-codex-skills/actions/runs/<RUN_ID>/artifacts --jq '.artifacts[] | .name'
```

## Decision examples
- NO-GO example: CI gate fails in `build-x64-ppl-linux` and required artifacts are missing.
- GO example: `ci-gate` and `package` succeed and all required artifacts are present for publish.

