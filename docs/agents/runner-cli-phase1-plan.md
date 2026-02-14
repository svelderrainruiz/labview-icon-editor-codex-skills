# Runner-CLI Phase 1 Integration Plan

Last updated: 2026-02-13
Status: planned

## Objective
Integrate `runner-cli` into this repo as a control-plane adapter for GitHub Actions dispatch and run lookup, while preserving current reliability through existing `gh` and REST fallback paths.

## Scope (Phase 1 only)
- Add a `runner-cli` execution path in:
  - `scripts/Invoke-AutonomousCiLoop.ps1`
  - `scripts/Invoke-ReleaseOrchestrator.ps1`
- Use `runner-cli` only for:
  - workflow dispatch
  - run query/list correlation used for post-dispatch binding
- Preserve output model expected by current telemetry and contracts:
  - `workflow_run.dispatch_response.*`
  - head SHA correlation fields
  - summary fields already consumed in JSONL records

## Non-Goals (Phase 1)
- No workflow YAML structural changes.
- No migration of package/build job logic to `runner-cli`.
- No removal of `gh` or REST fallback behavior.
- No schema-breaking changes to autonomous loop JSON records.

## Current Baseline
- `Invoke-AutonomousCiLoop.ps1` currently dispatches and queries via `gh`.
- `Invoke-ReleaseOrchestrator.ps1` dispatches via `gh`, then falls back to REST API.
- Contracts already enforce dispatch telemetry and correlation behavior.

## Proposed Adapter Contract
Define shared helper functions (script-local in each file for Phase 1):

1) `Invoke-WorkflowDispatch`
- Inputs:
  - workflow file/name
  - repo/branch/ref
  - normalized `key=value` inputs
- Behavior:
  - Try `runner-cli` first (if present and enabled)
  - On non-zero/unsupported result, fall back to `gh`
  - In orchestrator only, keep REST as final fallback
- Output object shape:
  - `method`: `runner-cli` | `gh` | `rest`
  - `exit_code`: integer
  - `output_preview`: first N lines of raw output
  - `dispatched`: boolean

2) `Resolve-WorkflowRunMeta`
- Inputs:
  - workflow identifier
  - branch/ref
  - dispatch start time
  - expected HEAD SHA (optional)
  - poll interval
- Behavior:
  - Try `runner-cli` run-list/query if available
  - Fall back to existing `gh run list` logic
  - Keep current dispatch-time + event + SHA correlation constraints
- Output object shape:
  - `run_id`
  - `url`
  - `head_sha`

3) `Test-RunnerCliAvailability`
- Performs lightweight binary/version probe.
- Returns boolean and probe output.

## Feature Toggle / Selection Rules
Phase 1 selection order:
1. If `runner-cli` is available and not explicitly disabled, use it.
2. If unavailable or failing, use `gh`.
3. For orchestrator dispatch only: if `gh` fails/unavailable, use REST with token.

Suggested control flags:
- `-DispatchBackend auto|runner-cli|gh|rest` (or equivalent split flags)
- Default: `auto`

## Validation Plan
1. Static contracts
- Extend `tests/AutonomousCiLoopContract.Tests.ps1` to assert adapter/fallback markers exist.
- Add/extend orchestrator contract test(s) to enforce fallback order and non-breaking fields.

2. Runtime smoke
- One-cycle autonomous loop with `MaxCycles=1`, verify:
  - dispatch succeeds
  - `dispatch_response.exit_code` emitted
  - run correlation fields remain present
- Optional run with forced fallback (disable/override `runner-cli`) to prove parity.

3. Regression safety
- Existing local contract suites remain green.
- No changes to existing workflow input defaults (including `consumer_ref=develop` behavior).

## Deliverables
- Updated scripts:
  - `scripts/Invoke-AutonomousCiLoop.ps1`
  - `scripts/Invoke-ReleaseOrchestrator.ps1`
- Updated tests:
  - `tests/AutonomousCiLoopContract.Tests.ps1`
  - orchestrator contract coverage if missing
- Updated docs:
  - `README.md` usage notes for backend selection/fallback
  - `docs/agents/change-log.md` entry

## Acceptance Criteria
- Phase 1 can dispatch and bind runs with `runner-cli` when available.
- Fallback path remains functional with no schema break in logs/artifacts.
- Contract tests for new adapter invariants pass.
- One runtime smoke cycle validates emitted telemetry parity.

## Rollout Notes
- Keep commit scope focused on control-plane behavior.
- Avoid introducing hard dependency on `runner-cli` until fallback confidence is proven in CI.
- Promote to Phase 2 only after observing stable behavior across multiple dispatch cycles.

## PR & Merge Checklist
- [ ] Scripts updated: autonomous loop + release orchestrator
- [ ] Contracts updated for backend toggles and fallback markers
- [ ] README updated with operator-facing backend controls
- [ ] Local contract runs passed:
  - [ ] `tests/AutonomousCiLoopContract.Tests.ps1`
  - [ ] `tests/ReleaseStateContract.Tests.ps1`
- [ ] One-cycle autonomous smoke captured evidence in JSONL
- [ ] PR description includes fallback behavior and non-goals
- [ ] Merge only after required checks are green
