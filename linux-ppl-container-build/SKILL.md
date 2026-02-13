---
name: linux-ppl-container-build
description: Build LabVIEW packed project libraries (PPL) via the Linux Docker container parity lane with deterministic preflight checks, artifact expectations, and failure diagnostics.
---

# Linux PPL Container Build Skill

Use this skill when the request asks to build a PPL through Linux Docker/container parity or to diagnose Linux container PPL build failures.

## Inputs expected
- Target repository path and branch/SHA context.
- Build intent and target output filename (for example `lv_icon_x64.lvlibp`).
- Linux container image/tag used by parity pipeline.

## Guardrails
1. Verify repo contains `.lvversion` and expected project/build spec metadata.
2. Verify the Linux container parity build lane is enabled for the run/profile.
3. Run only the Linux container PPL path when requested; do not substitute host builds.
4. Capture and surface container logs and status files when build fails.

## Success criteria
- PPL artifact generated and named per pipeline convention.
- Artifact is published to the workflow artifacts set.
- Build logs are available for diagnostics.
- No hidden fallbacks to non-container execution paths.

## Suggested operator checklist
- Confirm image pull succeeded.
- Confirm parity script step executed in container context.
- Confirm output artifact path exists before upload.
- Confirm final artifact is present in run artifacts.
