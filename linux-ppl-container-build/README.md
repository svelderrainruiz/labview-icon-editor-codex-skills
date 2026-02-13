# Linux Container PPL Build Skill

This module defines a Codex skill contract for building LabVIEW packed project libraries (PPL) through the Linux Docker container parity lane.

## Purpose
- Triggerable guidance for PPL build requests that must use Linux containers.
- Alignment with `labview-icon-editor` CI parity/build conventions.
- Deterministic artifact and diagnostics expectations for release gating.

## Scope
- Build orchestration patterns for Linux container execution.
- Required preflight checks before containerized PPL build.
- Expected outputs (`lv_icon_x64.lvlibp`, container logs, status markers).

## Out of scope
- Native host-based LabVIEW builds.
- Windows container and self-hosted runner operational details.
- Release tagging and publish flow details.
