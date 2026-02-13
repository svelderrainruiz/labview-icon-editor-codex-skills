# Release Gates Contract (Agent View)

Last validated: 2026-02-13
Validation evidence: consumer runs 22002791381, 22004004032, 22005219153

## Contract intent
Define deterministic GO/NO-GO release decisions for labview-icon-editor consumer runs before dispatching skill-layer release.

## Gate inputs
From consumer CI run metadata:
- run status
- run conclusion
- job conclusions
- artifact inventory
- head SHA / branch

## Required artifacts
- lv_icon_x64.lvlibp
- lv_icon_x86.lvlibp
- conformance-full
- core-conformance-linux-evidence
- core-conformance-windows-evidence

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

## Evidence backfill (last 3 runs)
| Run ID | Branch | Status | Conclusion | Failed jobs | Missing required artifacts | Result |
| --- | --- | --- | --- | --- | --- | --- |
| 22002791381 | reconcile/issue-91-forward-port-456 | completed | failure | Build VI Package; Pipeline Contract | none | NO-GO |
| 22004004032 | reconcile/issue-91-forward-port-456 | completed | failure | Build VI Package; Pipeline Contract | none | NO-GO |
| 22005219153 | reconcile/issue-91-forward-port-456 | in_progress | pending | none so far | lv_icon_x64.lvlibp; lv_icon_x86.lvlibp | NO-GO (not complete) |

## Dispatch policy
Only dispatch .github/workflows/release-skill-layer.yml when GO.

Required dispatch inputs:
- release_tag (example v0.4.1)
- consumer_repo
- consumer_ref
- consumer_sha
- run_self_hosted
- run_build_spec

## Provenance policy
Release notes must include parity and consumer evidence fields produced by labview-parity-gate and release-skill-layer workflows.

## Auth boundary policy
- Git operations are independent of GitHub auth.
- Release dispatch and run querying require GitHub auth.
- Prefer short-lived token usage for automation.

## Operational commands
```powershell
gh api repos/svelderrainruiz/labview-icon-editor/actions/runs/<RUN_ID> --jq '{status, conclusion, head_sha, head_branch, run_attempt, updated_at}'
```

```powershell
gh api repos/svelderrainruiz/labview-icon-editor/actions/runs/<RUN_ID>/jobs --paginate --jq '.jobs[] | {name, status, conclusion}'
```

```powershell
gh api repos/svelderrainruiz/labview-icon-editor/actions/runs/<RUN_ID>/artifacts --jq '.artifacts[] | .name'
```

## Decision examples
- NO-GO examples:
	- run 22002791381 (completed failure, Build VI Package + Pipeline Contract failed)
	- run 22004004032 (completed failure, Build VI Package + Pipeline Contract failed)
- Active monitoring example: run 22005219153 (in_progress; packed libraries not yet present).
