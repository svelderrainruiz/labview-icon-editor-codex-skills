# Headless Parity Preflight Contract

This module captures the fail-fast compatibility gate used in headless self-hosted parity.

## Gate Requirements
- `.lvversion` is canonical.
- `lv_icon_editor.lvproj` root `LVVersion` must be compatible with `.lvversion`.
- `Split-Path -Parent $PROJECT_PATH` must equal `REPO_ROOT`.

Example mapping:
- `.lvversion` `21.0` <-> `LVVersion="21008000"`
