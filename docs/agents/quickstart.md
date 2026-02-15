# Agent Quickstart (labview-icon-editor)

Last validated: 2026-02-14
Validation evidence: skills repo CI-coupled release gate

## Purpose
Get an agent productive in under 10 minutes for CI triage, release GO/NO-GO, and artifact verification.

## 1) Establish context
- Skills repo: `svelderrainruiz/labview-icon-editor-codex-skills`
- Source project repo: `svelderrainruiz/labview-icon-editor`
- CI gate workflow: `.github/workflows/ci.yml`
- Release workflow: `.github/workflows/release-skill-layer.yml`

## 2) First 5 commands (authenticated)
```powershell
gh auth status
```

```powershell
gh run list --repo svelderrainruiz/labview-icon-editor-codex-skills --workflow ci.yml --limit 5
```

```powershell
gh api repos/svelderrainruiz/labview-icon-editor-codex-skills/actions/runs/<RUN_ID> --jq '{status, conclusion, head_sha, head_branch, run_attempt, updated_at}'
```

```powershell
gh api repos/svelderrainruiz/labview-icon-editor-codex-skills/actions/runs/<RUN_ID>/jobs --paginate --jq '.jobs[] | {name, status, conclusion}'
```

```powershell
gh api repos/svelderrainruiz/labview-icon-editor-codex-skills/actions/runs/<RUN_ID>/artifacts --jq '.artifacts[] | .name'
```

## 3) GO/NO-GO gate (minimum)
A release candidate run is GO-eligible only if all are true:
- status = completed
- conclusion = success
- no required job has failure/cancelled/timed_out/startup_failure/action_required
- required artifacts exist:
  - `docker-contract-ppl-bundle-windows-x64-<run_id>`
  - `docker-contract-ppl-bundle-linux-x64-<run_id>`
  - `docker-contract-vip-package-self-hosted-<run_id>`

If any condition fails: NO-GO (no release publish).

## 4) Dispatch source of truth
Use skills repo release workflow inputs in `.github/workflows/release-skill-layer.yml`:
- `release_tag`
- `consumer_repo` (source project repo)
- `consumer_ref` (source project ref)
- `consumer_sha` (source project SHA)
- `labview_profile` (LabVIEW target preset id)
- `source_labview_version_override` (optional effective `.lvversion` override, `major.minor`, minimum `20.0`)
- `run_lv2020_edge_smoke` (optional non-gating LV2020 x64 edge diagnostics)

Compatibility-only (deprecated) inputs:
- `run_self_hosted`
- `run_build_spec`

## 5) Provenance fields expected in release notes
- `skills_ci_repo`
- `skills_ci_run_url`
- `skills_ci_run_id`
- `skills_ci_run_attempt`
- `source_project_repo`
- `source_project_ref`
- `source_project_sha`

## 6) Fast escalation path
- If run is still `queued`/`in_progress`: monitor and do not publish.
- If run is `completed` + `failure`: capture failed jobs, mark NO-GO, and rerun after fixes.
- If run is `completed` + `success`: verify required artifacts and proceed with release publish.

## 6.1) Self-hosted scheduling and remote triage
- Verify required runner labels exist on at least one online runner:
```powershell
gh api repos/svelderrainruiz/labview-icon-editor-codex-skills/actions/runners --jq '.runners[] | {name, status, labels: [.labels[].name]}'
```
- `run-lunit-smoke-lv2020x64` uses resolved source-year x64 label from `resolve-labview-profile` output (`self-hosted-windows-lv<YYYY>x64`).
- Self-hosted jobs enforce source-project remote hygiene via `Assert-SourceProjectRemotes.ps1`:
  - sets/updates `upstream` to `https://github.com/<source-project-repo>.git`
  - validates non-interactive `git ls-remote upstream`
  - fails hard when remote connectivity/auth is broken
- LV2020 smoke command contract is run-only:
  - `g-cli --lv-ver <YYYY> --arch 64 lunit -- -r <report> <project.lvproj>`
  - no deterministic `g-cli ... lunit -- -h` preflight.
- Source-year override behavior:
  - the job keeps key `run-lunit-smoke-lv2020x64` for compatibility,
  - execution target year and `.lvversion` are resolved from effective target selection in `resolve-labview-profile`,
  - when provided, `source_labview_version_override` is authoritative for CI execution target (format `major.minor`; Minimum supported LabVIEW version is 20.0),
  - when override is omitted, source project `.lvversion` is used.
- Optional deferred LV2020 edge coverage:
  - set `run_lv2020_edge_smoke: true` to run `run-lunit-smoke-lv2020x64-edge`,
  - this edge lane is diagnostic-only and non-gating.
- On LV2020 smoke failure, CI may run a diagnostic-only LV2026 x64 control probe (for comparable outcomes like `no_testcases` / `failed_testcases`) and writes comparative results into `lunit-smoke.result.json` and the job summary.
- CI invokes `Invoke-LunitSmokeLv2020.ps1` with `-EnforceLabVIEWProcessIsolation`, so active LabVIEW processes are cleared before LV2020 run and before any LV2026 control probe.
- If process isolation cannot clear active LabVIEW instances, control probe is skipped with reason `skipped_unable_to_clear_active_labview_processes`.
- CI invokes `-AllowNoTestcasesWhenControlProbePasses`; when LV2020 outcome is `no_testcases` and LV2026 control probe passes, the smoke job passes with advisory `lv2020_no_testcases_control_probe_passed`.
- All other LV2020 smoke failures remain blocking for downstream self-hosted jobs.
- Triage order for LV2020 smoke:
  1. `lunit-smoke.result.json`
  2. `reports/lunit-report-lv<effective_year>-x64.xml`
  3. `reports/lunit-report-lv2026-x64-control.xml` (if present)
  4. `lunit-smoke.log`

## 7) Canonical references
- `.github/workflows/ci.yml`
- `.github/workflows/release-skill-layer.yml`
- `docs/agents/release-gates.md`

## 8) Release payload files
When `release-skill-layer` publishes a tag, expect:
- `lvie-codex-skill-layer-installer.exe`
- `lvie-ppl-bundle-windows-x64.zip`
- `lvie-ppl-bundle-linux-x64.zip`
- `lvie-vip-package-self-hosted.zip`
- `release-provenance.json`
- `release-payload-manifest.json`

