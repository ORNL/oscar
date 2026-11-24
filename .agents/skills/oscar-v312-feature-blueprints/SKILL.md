---
name: oscar-v312-feature-blueprints
description: >-
  Implementation blueprint and pre-merge checklist for OSCAR v3.12.0 planned
  features: Mobile Detector System (RS-350 backpack & Kromek D5 walker across
  osh-oakridge-modules#57, oscar-viewer#49, oscar#76) and Opt-In Custom Widget
  Dashboards (/dashboards in oscar-viewer#50). Activate when developing,
  rebasing, or reviewing v3.12.0 feature branches.
---

# OSCAR `v3.12.0` Feature Blueprints

Use this skill when developing, rebasing, or reviewing the planned `v3.12.0` feature branches tracked in [`docs/ARCHITECTURAL_ROADMAP.md`](../../../docs/ARCHITECTURAL_ROADMAP.md) and [GitHub Milestones `#2`–`#4`](https://github.com/ORNL/oscar/milestones).

## Shared Branch Collaboration Rules
1. Collaborate directly on `ORNL/*` branches (`Write` branch-maintainer access is enabled for the review group; default branches and `v*` tags require Repository Admin merge after 50-lane certification).
2. Use **matching branch names** across coordinated repositories so `.github/workflows/ci.yml` resolves the matching `ORNL/oscar` branch automatically:
   - Mobile Detector System (`#80`): `feat/v3.12.0-mobile-detector-system`
   - Opt-In Custom Widget Dashboards (`#81`): `feat/v3.12.0-custom-dashboards` (keep unstacked from `feat/v3.12.0-mobile-detector-system`)

## Blueprint A — Mobile Detector System ([`ORNL/oscar#80`](https://github.com/ORNL/oscar/issues/80))
1. **Rebase cleanly onto `v3.11.14`+ `main`** across `osh-oakridge-modules`, `oscar-viewer`, and `oscar`, dropping already-merged `v3.11.14` bugfix commits and preserving hardened `HLSVideoComponent.tsx`, `useLaneHealth.ts`, and `WebIdAnalysis.tsx`.
2. **Backend (`sensorhub-system-mobile`, `ORNL/osh-oakridge-modules#57`):**
   - Reuse `OccupancyProcessStarter` (including `initAsync = true` `INITIALIZING -> INITIALIZED` support) and `RpmRecoverySupervisor`.
   - Scope camera/HLS capability tracking to the `MobileDetectorSystem` instance (`doStop()` cleanup; no static global `ConcurrentHashMap`).
   - Verify mobile datastreams in `OscarTieredObsStore`, `DatabasePurger`, and `dist/config/standard/config.json` so 1 Hz GPS (`LiveDriverLocationOutput`) and spectra never bloat `ONLY oscar.obs`.
   - Add JUnit tests under `sensors/sensorhub-system-mobile/src/test/java` and wire `:sensorhub-system-mobile:test` into `.github/workflows/ci.yml`.
3. **Viewer (`ORNL/oscar-viewer#49`) & Root (`ORNL/oscar#76`):**
   - Route mobile radiation alarms through the single global `AlarmAudio` in `Providers.tsx`.
   - Bound GPS trail queries with explicit `resultTime` / `phenomenonTime` windows + `limit` (`<= 500`), manage live feeds via `SharedConnectionPool`, keep dev simulators excluded from `build/install/oscar` (`tools/validate-packaged-release.js`), and complete `en`/`es`/`fr`/`el` locale keys + Cypress component tests.

## Blueprint B — Opt-In Custom Widget Dashboards ([`ORNL/oscar#81`](https://github.com/ORNL/oscar/issues/81))
1. **Rebase directly onto `v3.11.14`+ `main`** in `ORNL/oscar-viewer` (`feat/v3.12.0-custom-dashboards`).
2. **Additive Opt-In Route (`/dashboards`):**
   - Keep all 8 canonical routes (`/`, `/map`, `/event-log`, `/lane-view`, `/report-view`, `/health`, `/servers`, `/users`) untouched as the default operator experience (`/` remains the canonical Dashboard).
   - Add `/dashboards` as an opt-in workspace in `Navbar.tsx` wrapped in `scopedHref("/dashboards", activeView)`.
3. **Safety & 50-Lane Resource Caps:**
   - Never remove `<AlarmAudio />` from `src/app/Providers.tsx` or mount `<AlarmAudio />` inside widgets.
   - Enforce per-dashboard widget caps (`<= 4` simultaneous live-video widgets, `<= 6` simultaneous live-chart widgets), use `SharedConnectionPool` with clean teardown, honor `?view=<scope>` lane filtering, version `redux-persist` state, remove `.DS_Store`, and pass `npm run validate:locales` + Cypress component specs.
