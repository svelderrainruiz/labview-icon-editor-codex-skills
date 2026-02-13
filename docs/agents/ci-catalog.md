# CI Catalog (Agent-Oriented)

Last validated: 2026-02-13
Validation evidence: runs 22002791381, 22004004032, 22005219153

## Purpose
Provide a quick map of high-value CI jobs in labview-icon-editor so agents can triage quickly.

## Current observed jobs
| Job | Role | Release impact |
| --- | --- | --- |
| Run Metadata | baseline run metadata | informational |
| PowerShell Lint | script hygiene | blocking if failed |
| VIP Prerelease Requirements Lint | prerelease policy checks | blocking if failed |
| Pre-Release Context | release preflight context | blocking if failed |
| Build runner-cli (win-x64) / publish | tool artifact build | blocking if failed |
| Build runner-cli (linux-x64) / publish | tool artifact build | blocking if failed |
| Resolve Codex Skill Layer Asset | skill-layer linkage | blocking if failed |
| LabVIEW Version Gate | version contract check | blocking if failed |
| Validate LabVIEW Files (pylavi, report-only) | static validation evidence | blocking if failed |
| Core Conformance Evidence (Hosted Windows) | conformance evidence | required evidence |
| Core Conformance Evidence (Hosted Linux) | conformance evidence | required evidence |
| Compute Version | version derivation | blocking if failed |
| Build Windows Container Packed Library | produce lv_icon_x86.lvlibp lane | required for gate |
| Build Linux Container Packed Library | produce lv_icon_x64.lvlibp lane | required for gate |
| Conformance Check (Full, Strict) | full conformance artifact | required for gate |
| Detect VIPC changes | dependency drift signal | conditional blocker |
| Apply VIPC (LV x64) | environment prep | may block downstream tests |
| Apply VIPC (LV x86) | environment prep | may block downstream tests |
| Test Source Using LV 64-bit | runtime validation | release confidence gate |

## Known critical failures to prioritize
- Build VI Package
- Pipeline Contract

When either fails, treat run as NO-GO for release dispatch.

## Recent failure evidence
- Run 22002791381: Build VI Package + Pipeline Contract failed.
- Run 22004004032: Build VI Package + Pipeline Contract failed.
- Run 22005219153: currently in_progress; failures not observed yet.

## Artifact-to-job mental map
- lv_icon_x64.lvlibp: expected from Linux container packed library lane.
- lv_icon_x86.lvlibp: expected from Windows container packed library lane.
- conformance-full: expected from strict conformance lane.
- core-conformance-linux-evidence: expected from hosted Linux evidence lane.
- core-conformance-windows-evidence: expected from hosted Windows evidence lane.

## Fast triage recipe
1. Check run status/conclusion.
2. Check failed/cancelled/timed_out jobs.
3. Check required artifact presence.
4. Decide GO/NO-GO via release-gates contract.

## Notes
This catalog should be refreshed when the consumer workflow job list changes.
Current branch under active monitoring: reconcile/issue-91-forward-port-456.
