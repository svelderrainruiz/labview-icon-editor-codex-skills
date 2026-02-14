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

## Docker CI
- Workflow: `.github/workflows/docker-contract-ci.yml`
- Purpose: run repository contract tests (`tests/*.Tests.ps1`) inside Docker.
- Trigger: pull requests touching contracts/scripts/docs/manifest and manual `workflow_dispatch`.
- Shared test runner: `scripts/Invoke-ContractTests.ps1` (used by local/container execution paths).
- Local run (PowerShell image):
  - `pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/Invoke-DockerContractCI.ps1`
- Local run (NI LabVIEW Linux image already on this machine):
  - `pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/Invoke-DockerContractCI.ps1 -DockerImage 'nationalinstruments/labview:2026q1-linux' -BootstrapPowerShell`
- Deterministic NI local iteration (recommended):
  - Build once: `docker build -t nationalinstruments/labview:2026q1-linux-pwsh -f docker/ni-lv-pwsh.Dockerfile .`
  - Optional pin override at build time: `docker build --build-arg PESTER_VERSION=5.7.1 -t nationalinstruments/labview:2026q1-linux-pwsh -f docker/ni-lv-pwsh.Dockerfile .`
  - Optional native VIPM CLI install (deterministic, checksum-verified): `docker build --build-arg VIPM_CLI_URL='<artifact-url>' --build-arg VIPM_CLI_SHA256='<sha256>' --build-arg VIPM_CLI_ARCHIVE_TYPE='tar.gz' -t nationalinstruments/labview:2026q1-linux-pwsh -f docker/ni-lv-pwsh.Dockerfile .`
    - Supported archive types: `tar.gz`/`tgz`/`zip`
    - Contract: if either `VIPM_CLI_URL` or `VIPM_CLI_SHA256` is set, both must be provided.
    - Image install path: `/usr/local/bin/vipm`
  - Run tests: `pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/Invoke-DockerContractCI.ps1 -DockerImage 'nationalinstruments/labview:2026q1-linux-pwsh'`

### What to test after image changes
- Verify tools in image:
  - `docker run --rm nationalinstruments/labview:2026q1-linux-pwsh pwsh -NoProfile -Command "$PSVersionTable.PSVersion.ToString(); (Get-Module -ListAvailable Pester | Sort-Object Version -Descending | Select-Object -First 1).Version.ToString()"`
- Verify native VIPM (when `VIPM_CLI_*` build args were provided):
  - `docker run --rm nationalinstruments/labview:2026q1-linux-pwsh bash -lc "command -v vipm >/dev/null && (vipm --version || vipm version)"`
- Fast smoke test (one suite):
  - `pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/Invoke-DockerContractCI.ps1 -DockerImage 'nationalinstruments/labview:2026q1-linux-pwsh' -TestPath './tests/ManifestContract.Tests.ps1'`
- Full contract suite:
  - `pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/Invoke-DockerContractCI.ps1 -DockerImage 'nationalinstruments/labview:2026q1-linux-pwsh' -TestPath './tests/*.Tests.ps1'`
- VIPM activation contract on NI image:
  - `pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/Invoke-DockerContractCI.ps1 -DockerImage 'nationalinstruments/labview:2026q1-linux-pwsh' -TestPath './tests/VipmCliActivationContract.Tests.ps1'`
  - Covers `VIPM_COMMUNITY_EDITION=true` => `vipm activate` preflight behavior.

## Windows->Linux VI Package flow
- Workflow: `.github/workflows/windows-linux-vipm-package.yml`
- Purpose: build PPL in Windows LabVIEW image, then build VI Package in Linux LabVIEW image using the exact Windows-built PPL artifact.

### Handoff contract
- Windows stage emits artifact bundle with:
  - PPL file
  - `ppl-manifest.json` containing `ppl_sha256`, `labview_version`, `bitness`, source/run provenance.
- Linux stage verifies:
  - bundle manifest exists,
  - bundle SHA256 matches manifest,
  - optional explicit SHA matches producer output,
  - `labview_version` and `bitness` match workflow inputs.

### Dispatch inputs you must provide
- `consumer_ref`: branch/tag/SHA to build/package.

### Optional override inputs
- `windows_build_command`: custom command for Windows PPL build. Leave blank to use built-in container parity command.
- `windows_ppl_path`: path to generated PPL in workspace.
- `vipm_project_path`: path to `.vipb` (or path accepted by `vipm build`).

### Typical dispatch values
- `windows_labview_image`: `nationalinstruments/labview:2026q1-windows`
- `linux_labview_image`: `nationalinstruments/labview:2026q1-linux-pwsh`
- `consumer_repo`: `svelderrainruiz/labview-icon-editor`
- `consumer_ref`: `main` (or release branch/SHA)
- `windows_build_command`: `` (empty => auto build command)
- `windows_ppl_path`: `consumer/resource/plugins/lv_icon.lvlibp`
- `linux_ppl_target_path`: `consumer/resource/plugins/lv_icon.lvlibp`
- `vipm_project_path`: `consumer/Tooling/deployment/NI Icon editor.vipb`
- `labview_version`: `2026`
- `bitness`: `64`

### Notes
- Linux stage fails fast if `vipm` is not available in the selected Linux image.
- If `vipm_community_edition=true`, Linux stage runs `vipm activate` before `vipm build`.
