# Agent Quickstart (labview-icon-editor)

Last validated: 2026-02-13
Validation evidence: consumer run 22005219153

## Purpose
Get an agent productive in under 10 minutes for CI triage, release GO/NO-GO, and parity-aware troubleshooting.

## 1) Establish context
- Consumer repo: svelderrainruiz/labview-icon-editor
- Active branch (current release lane): reconcile/issue-91-forward-port-456
- Skills control repo: svelderrainruiz/labview-icon-editor-codex-skills
- Active skills release workflow: .github/workflows/release-skill-layer.yml

## 2) First 5 commands (authenticated)
```powershell
gh auth status
```

```powershell
gh run list --repo svelderrainruiz/labview-icon-editor --workflow ci-composite.yml --branch reconcile/issue-91-forward-port-456 --limit 5
```

```powershell
gh api repos/svelderrainruiz/labview-icon-editor/actions/runs/<RUN_ID> --jq '{status, conclusion, head_sha, head_branch, run_attempt, updated_at}'
```

```powershell
gh api repos/svelderrainruiz/labview-icon-editor/actions/runs/<RUN_ID>/jobs --paginate --jq '.jobs[] | {name, status, conclusion}'
```

```powershell
gh api repos/svelderrainruiz/labview-icon-editor/actions/runs/<RUN_ID>/artifacts --jq '.artifacts[] | .name'
```

## 3) GO/NO-GO gate (minimum)
A candidate run is GO-eligible only if all are true:
- status = completed
- conclusion = success
- no required job has failure/cancelled/timed_out/startup_failure/action_required
- required artifacts exist:
  - lv_icon_x64.lvlibp
  - lv_icon_x86.lvlibp
  - conformance-full
  - core-conformance-linux-evidence
  - core-conformance-windows-evidence

If any condition fails: NO-GO (no release dispatch).

## 4) Known high-signal failing jobs
When these fail, treat as release blockers:
- Build VI Package
- Pipeline Contract

## 5) Dispatch source of truth
Use skills repo workflow inputs in .github/workflows/release-skill-layer.yml:
- release_tag
- consumer_repo
- consumer_ref
- consumer_sha
- run_self_hosted
- run_build_spec

## 6) Provenance fields expected in release notes
- skills_parity_gate_repo
- skills_parity_gate_run_url
- skills_parity_gate_run_id
- skills_parity_gate_run_attempt
- skills_parity_enforcement_profile
- consumer_repo
- consumer_ref
- consumer_sha
- consumer_sandbox_checked_sha
- consumer_sandbox_evidence_artifact
- consumer_parity_run_url
- consumer_parity_run_id
- consumer_parity_head_sha

## 7) Fast escalation path
- If run is still in_progress/queued: keep monitoring and do not dispatch.
- If run is completed failure: capture failed jobs + links, mark NO-GO, wait for next candidate.
- If run is completed success and gates pass: dispatch release-skill-layer.
