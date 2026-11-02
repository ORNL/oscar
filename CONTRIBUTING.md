# Contributing to OSCAR

Thank you for contributing to **OSCAR (Open Source Central Alarm Monitoring)**, maintained by Oak Ridge National Laboratory at [`https://github.com/ORNL/oscar`](https://github.com/ORNL/oscar).

## Repository Architecture

OSCAR is composed of coordinated repositories under the `ORNL` GitHub organization:

| Repository | Default Branch | Purpose |
| --- | --- | --- |
| [`ORNL/oscar`](https://github.com/ORNL/oscar) | `main` | Top-level Gradle build root, Docker Compose deployment, storage/backup CLI, release packaging, and documentation |
| [`ORNL/osh-oakridge-modules`](https://github.com/ORNL/osh-oakridge-modules) | `main` | Submodule (`include/osh-oakridge-modules`): Oak Ridge OpenSensorHub drivers, services, media/journal lifecycle, and localized operator manuals |
| [`ORNL/oscar-viewer`](https://github.com/ORNL/oscar-viewer) | `main` | Submodule (`web/oscar-viewer`): Next.js / TypeScript web interface |
| [`ORNL/osh-core`](https://github.com/ORNL/osh-core) | `OSCAR` | Submodule (`include/osh-core`): OpenSensorHub core fork |
| [`ORNL/osh-addons`](https://github.com/ORNL/osh-addons) | `OSCAR` | Submodule (`include/osh-addons`): OpenSensorHub addons & tiered PostGIS/Parquet datastore |
| [`ORNL/osh-js`](https://github.com/ORNL/osh-js) | `add-consys` | Locked tarball dependency in `ORNL/oscar-viewer` |
| [`ORNL/oscar-regression-suite`](https://github.com/ORNL/oscar-regression-suite) | `main` | Automated Playwright, ConSys API, emulator fault-injection, and 50-lane end-to-end regression suite |

## Fork & Pull Request Workflow

All contributors—including partner engineering teams (such as Botts Innovative Research) and external open-source contributors—contribute via fork-and-pull-request:

1. **Fork the target `ORNL/*` repository** under your personal or organization GitHub account.
2. **Create a focused feature or fix branch** from the repository's default branch (`main`, `OSCAR`, or `add-consys`).
3. **Coordinate cross-repository changes cleanly:**
   - Merge submodule or `osh-js` changes into their respective `ORNL/*` repositories first.
   - Then open a pull request on [`ORNL/oscar`](https://github.com/ORNL/oscar) updating the submodule commit pointer(s) so `ORNL/oscar` CI tests the integrated release end-to-end.
4. **Verify locally before opening a PR:**
   - Run `node tools/validate-release-metadata.js` when modifying versioned documentation, manuals, or configuration.
   - Run `./build-all.sh` (or `build-all.bat` on Windows) and confirm unit, storage-script, dependency-lock, and locale checks pass.
   - Never commit credentials, TLS private keys, `.env` runtime files, internal hostnames/IPs, or generated build outputs.
5. **Submit a Pull Request** targeting the `ORNL/*` default branch:
   - Protected branch rules require passing GitHub Actions status checks and code-owner review (`@tyronechrisharris`) before merge.
