# labview-icon-editor-codex-skills

Layered Codex skill assets for `labview-icon-editor` CI/runtime integrations.

- SPDX-License-Identifier: `0BSD`
- Primary packaged layer: `lvie-codex-skill-layer-installer.exe`
- Current layer modules:
  - `ci-debt/*`
  - `lunit-contract/*`
  - `proactive-loop/*`
  - `headless-parity/*`
  - `belt-suspenders/*`

## Release contract
The release asset is pinned by the consumer lock file and validated by:
- SHA256 digest
- required files list
- manifest `license_spdx` (`0BSD`)

Installer contract:
- Canonical NSIS root: `C:\Program Files (x86)\NSIS`
- Required binary: `C:\Program Files (x86)\NSIS\makensis.exe`
- Optional override: repository variable `NSIS_ROOT` or script argument `-MakensisPath`
- NSIS headless install supports `/S`.
- Consumer lock defines installer args and install-root template.
