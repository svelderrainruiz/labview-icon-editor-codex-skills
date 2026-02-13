# Detailed Checklist Comment Draft — Release Control Plane Modernization (Phased)

Use this as the first comment under the umbrella issue body.

## Objective
Create a reliable, auditable release control plane in `labview-icon-editor-codex-skills` that:
- Monitors consumer CI gates (`labview-icon-editor`) deterministically,
- Dispatches release workflows only on GO conditions,
- Captures provenance and auth-boundary evidence by contract,
- Reduces manual release risk and operational toil.

## Scope
- Token-first orchestration model (short-lived credentials, no persistent host login requirement).
- Contract-driven gate evaluation for run status, failed jobs, and required artifacts.
- Machine-readable release state outputs (JSON) alongside markdown operator view.
- Phase tracking and governance conventions for rollout.

## Non-goals
- Replacing all consumer CI logic in `labview-icon-editor`.
- Introducing new release channels beyond canary/stable in this initiative.
- Building a UI dashboard in this phase set.

---

## Current Context
- Active consumer candidate run: `22004004032`
- Consumer repo/ref: `svelderrainruiz/labview-icon-editor` / `reconcile/issue-91-forward-port-456`
- Active plan doc: `release-plan-22004004032.md`
- Orchestrator script: `scripts/Invoke-ReleaseOrchestrator.ps1`

---

## Phase 1 — Auth Boundary + Safe Dispatch Foundation
**Goal:** enforce separation of Git operations from GitHub-auth-required operations.

### Deliverables
- [ ] Auth-boundary contract documented in repo runbooks/README.
- [ ] Orchestrator supports token injection (`GH_TOKEN` or explicit parameter).
- [ ] Dispatch precheck fails fast with actionable message when credentials are missing.
- [ ] Release workflow contract test verifies dispatch/auth assumptions.

### Acceptance Criteria
- [ ] A release orchestration attempt without token exits with clear NO-GO reason.
- [ ] A release orchestration attempt with short-lived token can dispatch successfully.
- [ ] No persistent login requirement is documented as mandatory for orchestration.

---

## Phase 2 — Machine-Verifiable Release State
**Goal:** replace markdown-only status interpretation with canonical JSON evidence.

### Deliverables
- [ ] Add `release-state.json` output schema (status, gate verdicts, missing artifacts, bad jobs, timestamps).
- [ ] Orchestrator writes state transitions to JSON on each gate cycle.
- [ ] Add `dispatch-result.json` artifact with workflow dispatch metadata.
- [ ] Contract tests validate schema presence/fields and update behavior.

### Acceptance Criteria
- [ ] GO/NO-GO is derivable from JSON without reading markdown.
- [ ] JSON evidence links to consumer run metadata and dispatch parameters.
- [ ] Markdown plan references canonical JSON state path.

---

## Phase 3 — Promotion + Rollback Controls
**Goal:** improve operational resilience post-dispatch.

### Deliverables
- [ ] Introduce promotion lanes (`canary` → `stable`) in policy contract.
- [ ] Add rollback trigger contract and runbook.
- [ ] Add provenance bundle checklist (asset digest + parity evidence + dispatch metadata).

### Acceptance Criteria
- [ ] Canary failure can be rolled back with documented procedure and evidence.
- [ ] Stable promotion requires explicit phase gate checks.

---

## Phase 4 — Governance Metrics and Continuous Improvement
**Goal:** use phase data to reduce failure rates and improve lead time.

### Deliverables
- [ ] Capture lead time by phase (candidate detected → dispatched → published).
- [ ] Track top gate failure causes and flaky job signals.
- [ ] Add periodic review checklist (weekly/biweekly).

### Acceptance Criteria
- [ ] Metrics are available from stored artifacts/logs without manual reconstruction.
- [ ] At least one improvement action is defined from observed bottlenecks.

---

## Risks & Mitigations
- **Token scope too broad** → Use fine-grained PAT, least privilege, short expiry.
- **Credential leakage in logs** → Never echo token values; scrub environment output.
- **Rate-limit/API instability** → Retry/backoff and graceful fallback behavior.
- **Contract drift between repos** → Add contract tests in skill repo and consumer adapter checks.

## Dependencies
- GitHub token with workflow dispatch rights for target repo(s).
- Consumer CI run artifact conventions remain stable (or versioned policy updates).
- PowerShell runtime compatibility for orchestrator and tests.

## Decisions Log
- [ ] **Decision:** Token-first auth boundary model.
  - **Date:** YYYY-MM-DD
  - **Rationale:** Minimize persistent credentials while enabling automation.
- [ ] **Decision:** JSON as canonical release state, markdown as human view.
  - **Date:** YYYY-MM-DD
  - **Rationale:** Deterministic machine checks and auditable history.

## Work Tracking Checklist
- [ ] Create Phase 1 PR(s)
- [ ] Create Phase 2 PR(s)
- [ ] Create Phase 3 PR(s)
- [ ] Create Phase 4 PR(s)
- [ ] Attach all related PRs/workflow runs to this issue

## Suggested Labels
`release-control-plane`, `phase-1`, `phase-2`, `phase-3`, `phase-4`, `blocker`, `decision-needed`, `security`

## Definition of Done (Initiative)
- [ ] Phases 1–2 completed and verified in a real release run.
- [ ] Phase 3 controls documented and smoke-tested.
- [ ] Phase 4 metrics collection active with first review performed.
