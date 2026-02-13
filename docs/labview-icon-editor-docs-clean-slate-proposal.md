# labview-icon-editor Documentation Clean-Slate Proposal (Agent-First)

## Recommendation
Yes—build a clean-slate documentation baseline iteratively.

A full rewrite in one pass usually drifts before it helps. A thin, high-signal baseline that ships quickly and is refined each cycle gives agents immediate leverage while staying accurate.

## Primary Goal
Reduce agent ramp-up time for `labview-icon-editor` to under 10 minutes for:
- CI triage
- PPL build troubleshooting
- release gate decisions
- parity and provenance checks

## Iterative Strategy
1. **Bootstrap (Week 1):** publish minimal canonical docs for repo map, CI contracts, and release flow.
2. **Operate (Weeks 2-3):** update docs from real incident/release outcomes (failed jobs, gate misses, artifact drift).
3. **Stabilize (Week 4+):** enforce docs-as-contract with lightweight checks and ownership.

## Clean-Slate Doc Set (v1)
Create these as the canonical agent-facing set in `labview-icon-editor`:

1) `docs/agents/quickstart.md`
- 5-minute “how to be useful now” path.
- Most common commands and expected outputs.
- Current branch/release conventions.

2) `docs/agents/repo-map.md`
- Critical folders, workflows, contracts, and ownership map.
- Where CI truth comes from vs where human notes live.

3) `docs/agents/ci-catalog.md`
- Job names, purpose, required/optional status, success criteria.
- Failure signatures and first remediation action.

4) `docs/agents/build-and-artifacts.md`
- PPL build lanes (Linux/Windows/self-hosted), expected artifacts, naming conventions.
- Artifact completeness matrix used for GO/NO-GO.

5) `docs/agents/release-gates.md`
- Deterministic gate contract (status, conclusion, failed jobs, required artifacts, provenance fields).
- Dispatch inputs and release publish rules.

6) `docs/agents/troubleshooting.md`
- Top recurring failures (for example Build VI Package, Pipeline Contract).
- Known causes, quick checks, and escalation path.

7) `docs/agents/change-log.md`
- Short ledger of doc-impacting operational changes.
- Link to runs/issues/PRs that changed behavior.

## Authoring Rules (to keep docs clean)
- Keep each page under ~250 lines for fast agent retrieval.
- Use one source-of-truth rule per concern (no duplicated contracts).
- Every operational claim must link to a workflow file, contract file, or run evidence.
- Prefer checklists and tables over narrative prose.
- Add “Last validated on” timestamp and validating run/commit.

## Maintenance Loop
After every release candidate run:
- Capture: what failed, what changed, what was ambiguous.
- Update: only affected sections in agent docs.
- Validate: run one “new-agent simulation” against docs to complete a standard triage task.
- Record: one-line entry in `docs/agents/change-log.md`.

## Success Metrics
- Median time for an agent to produce correct GO/NO-GO verdict.
- Number of clarifying questions needed before first useful action.
- Repeat incidents caused by stale/missing docs.
- % of release steps executable from docs without tribal knowledge.

## Execution Plan (practical)
- **Phase A (now):** scaffold the 7 files with tight v1 content.
- **Phase B:** backfill from last 3 real runs and current release contracts.
- **Phase C:** add contract tests for required doc sections and stale timestamps.

## Suggested Next Action
Start with `quickstart.md`, `release-gates.md`, and `ci-catalog.md` first. Those three deliver the fastest operational lift for agents and release orchestration.
