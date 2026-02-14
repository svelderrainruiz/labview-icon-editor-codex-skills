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

## 7) Canonical references
- `.github/workflows/ci.yml`
- `.github/workflows/release-skill-layer.yml`
- `docs/agents/release-gates.md`

