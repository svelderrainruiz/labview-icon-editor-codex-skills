# Headless Parity Preflight Contract

This module captures the fail-fast compatibility gate used in headless self-hosted parity.

## Gate Requirements
- `.lvversion` is canonical.
- `lv_icon_editor.lvproj` root `LVVersion` is optional and not required for pass/fail.
- Path ownership is resolved by `runner-cli parity context`; project-parent path matching is not required.

## Preflight Command
- `pwsh -NoProfile -File .\Tooling\Assert-LabVIEWVersion.ps1 -RepoRoot <repo>`
