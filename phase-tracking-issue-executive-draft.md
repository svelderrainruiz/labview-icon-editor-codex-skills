# Release Control Plane Modernization (Phased)

## Why now
We need reliable, low-risk release orchestration between `labview-icon-editor-codex-skills` and `labview-icon-editor` with explicit GO/NO-GO gates, auditable provenance, and minimal credential exposure.

## Outcome we want
- Token-first orchestration (short-lived credentials, no persistent login requirement).
- Deterministic gate evaluation from consumer CI (status, failures, required artifacts).
- Machine-verifiable release state and dispatch evidence.
- Progressive rollout with clear acceptance criteria by phase.

## Phases
- [ ] Phase 1: Auth Boundary + Safe Dispatch Foundation
- [ ] Phase 2: Machine-Verifiable Release State
- [ ] Phase 3: Promotion + Rollback Controls
- [ ] Phase 4: Governance Metrics and Continuous Improvement

## Current context
- Active candidate run: 22004004032
- Active plan: release-plan-22004004032.md
- Orchestrator: scripts/Invoke-ReleaseOrchestrator.ps1

## Tracking model
Use this issue as the umbrella tracker. Keep detailed deliverables and acceptance criteria in the first comment (paste from the detailed checklist draft).

## Initial decisions requested
- [ ] Approve token-first auth boundary model for orchestration.
- [ ] Approve JSON as canonical release state (markdown as operator view).

## Suggested labels
release-control-plane, phase-1, phase-2, phase-3, phase-4, blocker, decision-needed, security
