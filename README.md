# labview-icon-editor-codex-skills

Layered Codex skill assets for `labview-icon-editor` CI/runtime integrations.

- SPDX-License-Identifier: `0BSD`
- Primary packaged layer: `lvie-codex-skill-layer-installer.exe`
- Current layer modules:
  - `ci-debt/*`
  - `lunit-contract/*`
  - `proactive-loop/*`
  - `headless-parity/*`
  - `linux-ppl-container-build/*`
  - `belt-suspenders/*`
  - `vipm-cli-machine/*`

## Release contract
The release asset is pinned by the consumer lock file and validated by:
- SHA256 digest
- required files list
- manifest `license_spdx` (`0BSD`)

Parity evidence contract:
- Primary evidence source is this repository's `labview-parity-gate` workflow run URL.
- `labview-parity-gate` performs a consumer sandbox preflight by cloning `consumer_ref`, asserting `HEAD == consumer_sha`, and emitting a static evidence artifact.
- Consumer parity run URL is retained as secondary provenance in release notes.
- Upstream `svelderrainruiz/labview-icon-editor` requires strict triple parity (`Linux`, `Self-Hosted`, `Windows`).
- Fork consumers are accepted with container-only parity requirements (`Linux`, `Windows`).

Installer contract:
- Canonical NSIS root: `C:\Program Files (x86)\NSIS`
- Required binary: `C:\Program Files (x86)\NSIS\makensis.exe`
- Optional override: repository variable `NSIS_ROOT` or script argument `-MakensisPath`
- NSIS headless install supports `/S`.
- Consumer lock defines installer args and install-root template.
