# Release Gates Contract (Agent View)

Last validated: 2026-02-15
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

## Advisory artifacts (non-gating)
- docker-contract-pylavi-source-project-<run_id> (diagnostic source-project pylavi validation)
- docker-contract-runner-cli-linux-x64-<run_id> (diagnostic runner-cli Linux Docker build/test/publish)

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

Advisory lane during rollout:
- `validate-pylavi-docker-source-project` is intentionally non-gating.
- Its artifact `docker-contract-pylavi-source-project-<run_id>` is for diagnostics and triage only, not GO/NO-GO.

## Dispatch policy
- Auto path: `.github/workflows/release-skill-layer.yml` runs on `push` to `main`.
- Manual path: `workflow_dispatch` remains available for explicit overrides and reruns.
- Resolve/publish only when GO.

Dispatch inputs:
- `release_tag` (optional override; default is `v<manifest.version>`)
- `consumer_repo` (optional source project repo override)
- `consumer_ref` (optional source project ref override)
- `consumer_sha` (optional source project SHA override)

Optional inputs:
- `labview_profile` (LabVIEW target preset id)
- `source_labview_version_override` (optional effective `.lvversion` override; format `major.minor`, minimum `20.0`)
- `run_lv2020_edge_smoke` (optional non-gating LV2020 edge smoke diagnostics)
- `run_self_hosted` (deprecated compatibility input)
- `run_build_spec` (deprecated compatibility input)

## Auto-release policy
- Auto-release is version-gated:
  - derive tag from `manifest.json` as `v<manifest.version>`.
  - if tag already exists, skip deterministically with `skip_reason=tag_exists`.
- Resolver source-target chain:
  - workflow inputs (manual dispatch),
  - repository variables (`LVIE_SOURCE_PROJECT_REPO`, `LVIE_SOURCE_PROJECT_REF`, `LVIE_SOURCE_PROJECT_SHA`, `LVIE_LABVIEW_PROFILE`),
  - deterministic fallback for repo/ref (`<owner>/labview-icon-editor`, `main`).
- Strict pin remains mandatory:
  - if `consumer_sha`/`LVIE_SOURCE_PROJECT_SHA` is missing or invalid, release resolves to deterministic failure (no publish).
- Manual dispatch may override resolved defaults when needed.

## Fork bootstrap policy
- One-time bootstrap script:
  - `scripts/Initialize-ForkPortability.ps1`
- Writes/updates repository variable contract:
  - `LVIE_SOURCE_PROJECT_REPO`
  - `LVIE_SOURCE_PROJECT_REF`
  - `LVIE_SOURCE_PROJECT_SHA`
  - `LVIE_LABVIEW_PROFILE`
  - `LVIE_PARITY_ENFORCEMENT_PROFILE`
- Deterministic SHA rotation:
  - use `-RefreshSourceSha` on the bootstrap script.

## Self-hosted preflight policy
- Before declaring GO for runs that include self-hosted jobs, verify runner label availability:
  - `self-hosted-windows-lv<YYYY>x64`
  - `self-hosted-windows-lv<YYYY>x86`
  - where `<YYYY>` is resolved from source project `.lvversion`.
- Self-hosted jobs enforce source-project remote hygiene with `Assert-SourceProjectRemotes.ps1`:
  - `upstream` must resolve to `https://github.com/<source-project-repo>.git`
  - non-interactive `git ls-remote upstream` must succeed
  - failures are hard-gate failures, not warnings.
- `run-lunit-smoke-x64` remains a strict gate:
  - execution target year is resolved from effective LabVIEW target selection.
  - when `source_labview_version_override` is provided, it must be `major.minor` and `>=20.0`, and becomes the effective CI target.
  - when override is not provided, observed source project `.lvversion` is used.
  - LV2020 failure is blocking.
  - a diagnostic-only LV2026 x64 control probe may run on comparable failures (`no_testcases` / `failed_testcases`) to improve root-cause clarity, but it does not change gate outcome.
  - CI enforces process isolation (`-EnforceLabVIEWProcessIsolation`) and clears active LabVIEW processes before LV2020 run and before control probe.
  - if active LabVIEW processes cannot be cleared, control probe is skipped with reason `skipped_unable_to_clear_active_labview_processes`.
  - `-AllowNoTestcasesWhenControlProbePasses` is only used by optional `run-lunit-smoke-lv2020x64-edge`.
- VIP package build path uses VIPM CLI:
  - self-hosted package lane runs `Invoke-VipmBuildPackage.ps1`
  - this lane builds the `.vip` via `vipm build` against the effective `.lvversion` target year (x64)
  - g-cli is limited to LUnit smoke only.
- optional non-gating LV2020 edge smoke:
  - enabled via `run_lv2020_edge_smoke: true`
  - runs in `run-lunit-smoke-lv2020x64-edge`
  - intended for deferred edge-case diagnostics and does not block required gates.
- Runner PowerShell policy baseline:
  - one-time setup per runner account: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force`
  - verify with `Get-ExecutionPolicy -List`
  - CI auto-corrects and emits diagnostics with `Initialize-RunnerPowerShellPolicy.ps1`; unresolved non-compliance is hard-fail.
  - `-ExecutionPolicy Bypass` is not allowed in governed CI/docs/script command paths.

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
gh api repos/<owner>/labview-icon-editor-codex-skills/actions/runs/<RUN_ID> --jq '{status, conclusion, head_sha, head_branch, run_attempt, updated_at}'
```

```powershell
gh api repos/<owner>/labview-icon-editor-codex-skills/actions/runs/<RUN_ID>/jobs --paginate --jq '.jobs[] | {name, status, conclusion}'
```

```powershell
gh api repos/<owner>/labview-icon-editor-codex-skills/actions/runs/<RUN_ID>/artifacts --jq '.artifacts[] | .name'
```

## Decision examples
- NO-GO example: CI gate fails in `build-x64-ppl-linux` and required artifacts are missing.
- GO example: `ci-gate` and `package` succeed and all required artifacts are present for publish.

