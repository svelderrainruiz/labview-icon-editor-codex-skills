# Rollback Runbook (Phase 3)

Last validated: 2026-02-13

## Purpose
Provide an operational rollback procedure when a promoted candidate violates parity, provenance, or artifact integrity contracts.

## Preconditions
- Confirm rollback trigger exists in `rollback-trigger.contract.json`.
- Identify impacted release tag and previous known-good tag.
- Gather release evidence paths:
  - `artifacts/release-state/release-state-<runId>.json`
  - `artifacts/release-state/dispatch-result-<runId>.json`

## Rollback Procedure
1. Declare rollback incident in issue tracker (include run ID, tag, trigger ID).
2. Mark candidate as revoked in release tracking notes.
3. Re-publish previous known-good release asset/tag if needed.
4. Block further promotion until root cause is recorded.
5. Capture rollback evidence fields:
   - rollback reason
   - impacted release tag
   - replacement release tag
   - operator
   - timestamp UTC

## Post-Rollback Validation
- Confirm release consumers can resolve the replacement tag.
- Confirm provenance fields are complete for replacement release.
- Confirm parity gate evidence references valid successful runs.

## Escalation
- Critical trigger (`artifact-integrity-failure`): immediate maintainer escalation.
- High severity triggers: escalate if unresolved within one release cycle.
