# CI Catalog (Agent-Oriented)

Last validated: 2026-02-15
Validation evidence: `CI Pipeline` + `release-skill-layer` contracts in this repository

## Purpose
Provide a fast map of deterministic CI/release jobs and artifacts for GO/NO-GO and release triage.

## Primary CI jobs (skills repo)
| Job | Role | Release impact |
| --- | --- | --- |
| `docker-ci` | contract suite and deterministic Docker test baseline | required |
| `resolve-source-target` | resolves source repo/ref/sha via input -> vars -> fallback and enforces strict SHA pin | required |
| `run-lunit-smoke-x64` | required native smoke gate (effective target year resolver-driven) | required |
| `build-x64-ppl-windows` | Windows x64 PPL artifact lane | required |
| `build-x64-ppl-linux` | Linux x64 PPL artifact lane | required |
| `prepare-vipb-linux` | authoritative VIPB diagnostics/prep lane | required |
| `build-vip-self-hosted` | self-hosted package build lane | required |
| `install-vip-x86-self-hosted` | post-package VIPM install/uninstall smoke lane | required |
| `ci-self-hosted-final-gate` | final required branch-protection gate | required |
| `validate-pylavi-docker-source-project` | deterministic pylavi static validation lane | advisory (non-gating) |
| `build-runner-cli-linux-docker` | deterministic runner-cli linux-x64 container lane | advisory (non-gating) |

## Required CI artifacts for release GO/NO-GO
- `docker-contract-ppl-bundle-windows-x64-<run_id>`
- `docker-contract-ppl-bundle-linux-x64-<run_id>`
- `docker-contract-vip-package-self-hosted-<run_id>`

## Release workflow map
| Job | Role |
| --- | --- |
| `resolve-release-context` | resolves release tag + source pins + auto-release decision |
| `ci-gate` | reusable `ci.yml` release gate |
| `package` | NSIS installer packaging |
| `publish-release-assets` | release asset staging + publish |
| `release-skipped` | deterministic non-failure skip path (`tag_exists`) |

## Release payload files
- `lvie-codex-skill-layer-installer.exe`
- `lvie-ppl-bundle-windows-x64.zip`
- `lvie-ppl-bundle-linux-x64.zip`
- `lvie-vip-package-self-hosted.zip`
- `release-provenance.json`
- `release-payload-manifest.json`

## Fast triage recipe
1. Confirm `ci-self-hosted-final-gate` is green on the target SHA.
2. Confirm required CI artifacts are present.
3. For release automation runs, inspect `resolve-release-context`:
   - `should_release=true` => publish path expected.
   - `should_release=false` + `skip_reason=tag_exists` => deterministic skip path expected.
4. Confirm portability variables are set in forked repos:
   - `LVIE_SOURCE_PROJECT_REPO`
   - `LVIE_SOURCE_PROJECT_REF`
   - `LVIE_SOURCE_PROJECT_SHA`
   - `LVIE_LABVIEW_PROFILE` (optional)
   - `LVIE_PARITY_ENFORCEMENT_PROFILE` (optional)
5. Use `docs/agents/release-gates.md` to decide GO/NO-GO.
