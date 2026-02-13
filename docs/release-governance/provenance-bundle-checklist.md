# Provenance Bundle Checklist (Phase 3)

Use this checklist before promoting canary -> stable.

## Required Asset Data
- [ ] Asset name recorded (`lvie-codex-skill-layer-installer.exe`)
- [ ] SHA256 recorded
- [ ] Release tag recorded

## Required Skills Parity Fields
- [ ] `skills_parity_gate_repo`
- [ ] `skills_parity_gate_run_url`
- [ ] `skills_parity_gate_run_id`
- [ ] `skills_parity_gate_run_attempt`
- [ ] `skills_parity_enforcement_profile`

## Required Consumer Provenance Fields
- [ ] `consumer_repo`
- [ ] `consumer_ref`
- [ ] `consumer_sha`
- [ ] `consumer_sandbox_checked_sha`
- [ ] `consumer_sandbox_evidence_artifact`
- [ ] `consumer_parity_run_url`
- [ ] `consumer_parity_run_id`
- [ ] `consumer_parity_head_sha`

## Evidence Attachments
- [ ] `release-state-<runId>.json`
- [ ] `dispatch-result-<runId>.json`
- [ ] Link to release workflow run
- [ ] Link to parity gate workflow run
