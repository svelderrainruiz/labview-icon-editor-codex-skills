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
- Workflow: `.github/workflows/ci.yml`
- Purpose: run repository contract tests, build deterministic Windows/Linux container PPL bundles, run a full VIPB diagnostics suite on Linux, then build a native self-hosted Windows VI package.
- Trigger: pull requests touching contracts/scripts/docs/manifest and manual `workflow_dispatch` (optional `labview_profile`, default `lv2026`).
- Shared test runner: `scripts/Invoke-ContractTests.ps1` (used by local/container execution paths).
- Pipeline order:
  - `contract-tests` -> `build-ppl-windows` -> `build-ppl-linux`
  - `contract-tests` -> `gather-release-notes`
  - `contract-tests` -> `resolve-labview-profile`
  - `contract-tests` + `gather-release-notes` + `resolve-labview-profile` -> `prepare-vipb-linux`
  - `build-vip-self-hosted` needs `build-ppl-windows`, `build-ppl-linux`, and `prepare-vipb-linux`
- LabVIEW profiles (advisory):
  - profile catalog is repo-owned under `profiles/labview`.
  - profile id resolution runs in `resolve-labview-profile` and publishes `docker-contract-labview-profile-resolution-<run_id>`.
  - profile mismatch vs consumer emits `::warning` + summary advisory, but does not override build target.
  - consumer `.lvversion` remains authoritative for VIPB target enforcement.
- VIPB version authority contract:
  - `prepare-vipb-linux` treats `consumer/.lvversion` as authoritative for VIPB LabVIEW target.
  - VIPB prep fails fast when `Package_LabVIEW_Version` differs from `.lvversion` target for selected bitness.
  - diagnostics artifact is still uploaded for post-mortem (`capture diagnostics, then fail`).
- Failure triage:
  - when VIPB prep fails, `Fail if VIPB diagnostics suite failed` now logs root cause + authority status inline and points to `prepare-vipb.error.json`, `vipb-diagnostics-summary.md`, and artifact `docker-contract-vipb-prepared-linux-<run_id>`.
- PPL source contract (CI Pipeline lane):
  - consumer repo: `svelderrainruiz/labview-icon-editor`
  - consumer ref: `patch/456-2020-migration-branch-from-9e46ecf`
  - expected SHA: `9e46ecf591bc36afca8ddf4ce688a5f58604a12a`
  - windows output path: `consumer/resource/plugins/lv_icon.windows.lvlibp`
  - linux output path: `consumer/resource/plugins/lv_icon.linux.lvlibp`
- Native self-hosted packaging contract:
  - runner labels: `[self-hosted, windows, self-hosted-windows-lv]`
  - `.vipb` flow in self-hosted lane is consume-only:
    - consume prepared VIPB artifact from Linux prep job into `consumer/Tooling/deployment/NI Icon editor.vipb`
    - consume x64 PPL `consumer/resource/plugins/lv_icon_x64.lvlibp` from Windows bundle
    - build native x86 PPL `consumer/resource/plugins/lv_icon_x86.lvlibp`
  - package version baseline for native lane: `0.1.0.<run_number>`
  - runner-cli fallback build/download is explicitly disabled in this lane via `LVIE_RUNNER_CLI_SKIP_BUILD=1` and `LVIE_RUNNER_CLI_SKIP_DOWNLOAD=1`
- Published artifacts:
  - `docker-contract-ppl-windows-raw-<run_id>` containing:
    - `consumer/resource/plugins/lv_icon.windows.lvlibp`
  - `docker-contract-ppl-bundle-windows-<run_id>` containing:
    - `lv_icon.windows.lvlibp`
    - `ppl-manifest.json` (`ppl_sha256`, `ppl_size_bytes`, LabVIEW version/bitness provenance)
  - `docker-contract-ppl-linux-raw-<run_id>` containing:
    - `consumer/resource/plugins/lv_icon.linux.lvlibp`
  - `docker-contract-ppl-bundle-linux-<run_id>` containing:
    - `lv_icon.linux.lvlibp`
    - `ppl-manifest.json` (`ppl_sha256`, `ppl_size_bytes`, LabVIEW version/bitness provenance)
  - `docker-contract-release-notes-<run_id>` containing:
    - `release_notes.md`
    - `release-notes-manifest.json` (SHA256 and size for the gathered release notes payload)
  - `docker-contract-labview-profile-resolution-<run_id>` containing:
    - `profile-resolution.json` (selected profile, consumer target, mismatch classification, warning message)
  - `docker-contract-vipb-prepared-linux-<run_id>` containing:
    - prepared `NI Icon editor.vipb` (consumed by self-hosted lane)
    - `vipb.before.xml`, `vipb.after.xml`
    - `vipb.before.sha256`, `vipb.after.sha256`
    - `vipb-diff.json`, `vipb-diff-summary.md`
    - `vipb-diagnostics.json`, `vipb-diagnostics-summary.md`
    - `prepare-vipb.status.json`, `prepare-vipb.error.json` (failure path)
    - `prepare-vipb.log`
    - `display-information.input.json`
    - `profile-resolution.input.json`
  - `docker-contract-vipb-modified-self-hosted-<run_id>` containing:
    - consumed `consumer/Tooling/deployment/NI Icon editor.vipb` used by the self-hosted package build (post-mortem copy)
  - `docker-contract-vip-package-self-hosted-<run_id>` containing:
    - latest built `.vip` from the native self-hosted lane
- Local run (PowerShell image):
  - `pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/Invoke-DockerContractCI.ps1`
- Local diagnostics suite exercise (bounded Docker):
  - `pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/Invoke-PrepareVipbDiagnosticsLocal.ps1`
  - Default bounds: `--memory=3g`, `--cpus=2`, timeout `300s`.
  - Fast triage order:
    1. `vipb-diagnostics-summary.md`
    2. `vipb-diagnostics.json`
    3. `prepare-vipb.log`
    4. `vipb.before.xml` vs `vipb.after.xml`
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

## Autonomous CI loop
- Continuous autonomous branch integration helper:
  - `pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/Invoke-AutonomousCiLoop.ps1`
- Typical bounded smoke run (1 cycle, stop on failure):
  - `pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/Invoke-AutonomousCiLoop.ps1 -MaxCycles 1 -StopOnFailure`
- Pass workflow dispatch inputs (`key=value`) repeatedly:
  - `pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/Invoke-AutonomousCiLoop.ps1 -WorkflowInput "ppl_build_lane=linux-container" -WorkflowInput "consumer_ref=develop"`
  - If `consumer_ref` is omitted, the loop now defaults it to `develop`.
- Backend selection (phase-1 runner-cli adapter):
  - `-DispatchBackend auto|runner-cli|gh` (default `auto`)
  - `-RunQueryBackend auto|runner-cli|gh` (default `auto`)
  - In `auto`, loop prefers `runner-cli` when available and falls back to `gh`.
- Built-in package triage profile (reaches `package-vip-linux` even when consumer parity scripts are missing):
  - `pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/Invoke-AutonomousCiLoop.ps1 -TriagePackageVipLinux`
  - Profile injects both `windows_build_command` and `linux_build_command` stubs so parallel PPL jobs can complete without consumer parity scripts.
- Remediation mode with VIPM CLI injection during image fallback builds:
  - `pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/Invoke-AutonomousCiLoop.ps1 -TriagePackageVipLinux -VipmCliUrl "<artifact-url>" -VipmCliSha256 "<sha256>" -VipmCliArchiveType tar.gz`
- Optional JSONL log output:
  - `pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/Invoke-AutonomousCiLoop.ps1 -LogPath ./artifacts/release-state/autonomous-ci-loop.jsonl`
  - Each cycle now records `workflow_run.vipm_help_preview` with `observed`, `usage_line_observed`, `source`, and `check_error`.
  - Each cycle also records `workflow_run.dispatch_response` with `exit_code` and `output_preview` from the dispatch command.
  - `workflow_run.dispatch_response.method` indicates the backend used (`runner-cli` or `gh`).
  - Run correlation is pinned to dispatch time plus expected `HEAD` SHA to avoid selecting a different concurrent run on the same branch.

## Release orchestrator backend selection
- Script: `scripts/Invoke-ReleaseOrchestrator.ps1`
- New optional switch:
  - `-DispatchBackend auto|runner-cli|gh|rest` (default `auto`)
- Behavior:
  - `auto`: tries `runner-cli` (if present), then `gh`, then REST API token fallback.
  - `runner-cli`/`gh`/`rest`: force a specific backend and fail fast if unavailable.
