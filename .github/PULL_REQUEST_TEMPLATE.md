## Summary
<!-- Concise explanation of the capability or fix, why this design was chosen, and how it preserves 50-lane performance and multi-year stability. -->

## Related Roadmap Issues & Coordinated PRs
<!-- Link the ORNL/oscar Milestone/Issue and any matching-branch PRs in osh-core, osh-addons, osh-oakridge-modules, oscar-viewer, oscar-video-guides, or oscar-regression. -->
- Milestone / Tracking Issue:
- Coordinated Submodule PRs:

## Architectural & 50-Lane Scale Checklist (`AGENTS.md`)
- [ ] **Storage & DuckDB Concurrency:** Preserves `PARQUET_PRIMARY` 22-stream lifecycle, zero growing SQL indexes, and `<= 2` concurrent DuckDB sessions (`docs/STORAGE_ARCHITECTURE.md`).
- [ ] **Driver, EventBus & Security Hygiene:** Zero per-tick SWE `DataComponent.copy()` cloning on `>= 1 Hz` streams; non-blocking reconnect/stop teardown; EventBus subscriptions cancelled in `doStop()`.
- [ ] **Viewer Routes, Safety & Localization:** Preserves canonical operator routes, global `AlarmAudio` singleton, and `en`/`es`/`fr`/`el` localization parity (`node tools/validate-release-metadata.js`).
- [ ] **Sanitization:** Zero private RFC1918 lab IPs, internal `.local` hostnames, `.DS_Store`, credentials, or non-redistributable EML binaries.

## Verification
- [ ] `node tools/validate-release-metadata.js`
- [ ] Gradle self-contained module tests & `installDist` packaging validation (`node tools/validate-packaged-release.js`)
