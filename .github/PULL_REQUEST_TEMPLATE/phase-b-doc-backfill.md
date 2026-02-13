# Phase B — Docs Backfill PR

## Objective
Backfill agent docs using evidence from the last 3 relevant consumer CI runs and align operational guidance with current contracts.

## Linked tracking
- Initiative issue: #2
- Phase: Phase 2 (Machine-Verifiable Release State) support / documentation stabilization

## Scope in this PR
- [ ] Update `docs/agents/quickstart.md`
- [ ] Update `docs/agents/release-gates.md`
- [ ] Update `docs/agents/ci-catalog.md`
- [ ] Add/update `docs/agents/change-log.md`
- [ ] (Optional) Add run-specific examples for known failure modes

## Run evidence backfill (required)
List at least 3 runs used for validation.

| Run ID | Branch | Status | Conclusion | Failed jobs | Missing required artifacts | Notes |
| --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |

## Contract alignment checks
- [ ] Required artifacts list matches release gate contract:
  - `lv_icon_x64.lvlibp`
  - `lv_icon_x86.lvlibp`
  - `conformance-full`
  - `core-conformance-linux-evidence`
  - `core-conformance-windows-evidence`
- [ ] Job-failure set matches orchestration logic (`failure`, `cancelled`, `timed_out`, `startup_failure`, `action_required`)
- [ ] Dispatch prerequisites match `.github/workflows/release-skill-layer.yml`
- [ ] Provenance fields listed in docs match release-notes contract

## Validation commands (paste output summary)
```powershell
gh run list --repo svelderrainruiz/labview-icon-editor --workflow ci-composite.yml --branch reconcile/issue-91-forward-port-456 --limit 10
```

```powershell
gh api repos/svelderrainruiz/labview-icon-editor/actions/runs/<RUN_ID>/jobs --paginate --jq '.jobs[] | {name, status, conclusion}'
```

```powershell
gh api repos/svelderrainruiz/labview-icon-editor/actions/runs/<RUN_ID>/artifacts --jq '.artifacts[] | .name'
```

## Review checklist
- [ ] Docs remain concise and operational (checklists/tables over narrative)
- [ ] Every operational claim is traceable to workflow/contract/run evidence
- [ ] “Last validated” metadata updated in touched docs
- [ ] Change log entry added with links to evidence

## Risk notes
- Ambiguous job naming changes in consumer CI
- Contract drift between skills repo scripts and doc text

## Post-merge follow-up
- [ ] Comment on issue #2 with PR link and key deltas
- [ ] Queue next iteration for machine-readable release-state docs (`release-state.json`/`dispatch-result.json`)
