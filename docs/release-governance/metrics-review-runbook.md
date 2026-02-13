# Phase 4 Metrics Review Runbook

## Scope

This runbook defines how to collect and review release metrics for consumer parity runs and release dispatch decisions.

## Collection

1. Run `scripts/Invoke-ReleaseMetricsSnapshot.ps1` for each target consumer run.
2. Store outputs under `artifacts/release-metrics/`.
3. Link each metrics snapshot in the active release plan or issue update.

## Weekly Review

1. Aggregate snapshots generated during the review window.
2. Compare `gate_outcome`, `failed_job_count`, and `missing_required_artifact_count` trends.
3. Document top failure causes and likely flaky-signal candidates.
4. Open concrete action items for issues that recur across multiple runs.

## Continuous Improvement Actions

1. Prioritize fixes that move repeated `no-go` outcomes to `go`.
2. Record mitigation owners and target dates in issue #2 updates.
3. Re-evaluate required artifacts and gate rules when evidence quality changes.