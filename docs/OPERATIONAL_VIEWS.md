# Operational views

Operational views let multiple workstations use one OSCAR deployment while each viewer loads only its assigned lanes. They do not create new users, roles, lane copies, or databases, and they do not change lane unique identifiers or historical data.

> **Companion Video Guides:** Watch [Module 05 — Sync Multi-Lane Spreadsheet Configuration (`05-admin-lane-spreadsheet-sync.mp4`)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/05-admin-lane-spreadsheet-sync.mp4), [Module 10 — Scope Workstation Lanes with Fail-Closed Operational Views (`10-operational-views-scoping.mp4`)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/10-operational-views-scoping.mp4), and [Module 32 — Build, Scope & Export Opt-In Custom Widget Dashboards (`32-custom-widget-dashboards.mp4`)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/32-custom-widget-dashboards.mp4) in [VIDEO_GUIDES.md](VIDEO_GUIDES.md#32-custom-widget-dashboards).

## Configure lanes

In the Lane System configuration, add one or more **Operational View Keys**. Keys must contain 1–63 lowercase letters, numbers, or hyphens and cannot begin or end with a hyphen. A lane can belong to more than one view.

For bulk configuration, the lane CSV export includes an `OperationalViews` column. Separate multiple keys with semicolons:

```text
north-gate;secondary
```

CSV files exported by earlier releases remain importable. Their lanes have no view assignment until an administrator adds one.

When importing a lane CSV in **SensorHub Admin → Services → OSCAR Service Module**, a successful
upload loads the lanes immediately and records the persistent bucket object key in the edited
service configuration. Click **Apply Changes**, then the global **Save** action, confirm **Yes**
in the dialog, and wait for **SensorHub Configuration Saved**. Merely opening the confirmation
dialog does not persist the configuration. Perform one
supported OSCAR restart and verify that the live Lane, RPM, and camera modules return; finding the
lane UIDs in historical database results alone is not a persistence check. If Apply Changes and
Save are omitted, the uploaded runtime modules are not an accepted durable configuration.

## Open or switch a view

Operators and administrators can switch views directly from the **Scoped View** dropdown in the top navigation bar (showing **All Lanes** and each configured view with its lane count), or open a view URL directly by replacing `north-gate` with the configured key:

```text
https://oscar.example/?view=north-gate
https://oscar.example/view/north-gate
```

The gateway redirects the second form to the first. OSCAR keeps the view parameter while navigating, opening event details, using the map, and handling alarm notifications:

- **Unrestricted accounts (`Administrator`, or `Operator`/`Viewer` accounts with no `allowedViews` restriction in `/users`):** When at least one Operational View is configured on the node (or `?view=` is present in the URL), the top bar displays the **Scoped View** dropdown containing **All Lanes** plus every configured view key and its assigned lane count. Deployments with zero configured Operational Views hide the dropdown automatically to keep the header uncluttered.
- **View-restricted accounts (`allowedViews` assigned in `/users` or via federated tunnel group policy):** **All Lanes** is omitted, and the control displays only the user's permitted views (rendering a compact read-only badge when assigned a single view, or a dropdown limited strictly to their assigned views when granted two or more).
- **Safe route transitions:** Selecting a different view from `/lane-view` or `/event-details` automatically returns the browser to the scoped Dashboard (`/?view=<key>`) or Event Log (`/event-log?view=<key>`) and clears any open preview drawer so the operator is never stranded on a lane or event outside the newly selected view.

Event UUID searches and copied Event Details links also retain the active view. A canonical link includes the encoded observation ID and source node, for example `event-details?eventId=<id>&nodeId=<node>&view=north-gate`. The Viewer resolves that ID only against occupancy streams belonging to lanes visible in the active view; a UUID from another view fails closed instead of revealing the event.

The normal root URL remains the unscoped administrative/legacy view and loads every lane:

```text
https://oscar.example/
```

Invalid keys and valid keys with no assigned lanes fail closed and load no lane data. Scoped dashboards, events, maps, national statistics, generated reports, alarm transfer, and Status of Health use only the lanes in the active view.

The Viewer preserves `?view=<key>` when the operator selects the Status of Health icon. Consequently, `/health/` shows all discovered lanes, while `/health/?view=north-gate` shows every lane assigned to `north-gate`. Connection, fault, and occupancy status is refreshed for only those visible lanes on entry and every 30 seconds. Requests contain at most 10 health streams, and the Viewer allows no more than two health requests in flight across all configured nodes.

Operational views are a workstation presentation boundary, not an authorization boundary. Anyone authorized to use the unscoped root URL can still see all lanes. Use network controls and OSCAR authentication if view URLs must be restricted to particular workstations or users.

## Opt-In Custom Widget Dashboards (`/dashboards`)

Custom Widget Dashboards (`/dashboards`) provide an opt-in, multi-widget workspace for control rooms, gatehouse wallboards, and shift supervisors without altering OSCAR's canonical console routes:

- **Canonical 8 routes remain untouched:** Dashboard (`/`), Events (`/event-log`), Event Details (`/event-details`), Lane View (`/lane-view`), Status of Health (`/health`), Map (`/map`), National (`/national-view`), and Report Generator (`/report`) preserve their fixed operational layouts and URLs. Operators open the additive workspace from **Custom Dashboards** (mosaic `+` tile-grid icon) in the left navigation drawer, where saved custom pages can also be pinned as one-click drawer shortcuts (`/dashboards/?id=<page-id>`).
- **Starter templates & responsive 12-column grid:** Selecting **Starter Templates** or **Add Dashboard** on `/dashboards` initializes a page from curated templates or an empty canvas across `lg` (`12`-column), `md` (`8`-column), and `sm` (`4`-column) breakpoints:
  - **Multi-Lane Wallboard:** Side-by-side live HLS camera feeds (`4`), real-time count charts (`4`), and a lane status strip automatically bound to discovered lanes.
  - **Alarm & Map Overview:** Combines live lane status tiles, geospatial map tracking (including mobile detector trails and alarm pins), **Quick View** inspection, and the active alarm queue.
  - **Statistics Overview:** Four **Alarm Statistics** cards (**Rate trend**, **Lane comparison**, **Mean adjudication time**, and **Hour-of-day / Day-of-week profile**) preconfigured at a `300 s` refresh interval.
  - **Dashboard Layout (`Dashboard`):** Standard lane status grid, active alarm table, and side-by-side **Quick View** panel on an editable grid.
  - **Blank dashboard:** Empty `12`-column canvas opened directly in **Edit Layout** mode for adding and resizing any supported widget (including spectroscopic **RS-350 / Kromek D5** views, **State of Health**, **Event Lookup**, **Report Generator**, and **Alarm Transfer**).
- **Per-operator and per-Operational-View layout scope isolation:** Dashboard definitions are keyed by `(username, activeViewKey)` (`buildLayoutScopeKey`). Signing in as a different operator or switching **Scoped View** (for example, `?view=north-gate` vs. `?view=south-gate` or unscoped **All Lanes**) isolates saved custom pages per operator and view while enforcing fail-closed Operational View lane filtering inside every widget.
- **Validated JSON export & import (`<= 512 KiB`):** **Import / Export** exports the active dashboard (`oscar-dashboard-<id>-<YYYY-MM-DD>.json`) or all dashboards in the current scope (`oscar-dashboards-<YYYY-MM-DD>.json`) using the `oscar-viewer-pages` JSON schema (`schemaVersion = 4`, plain string lane identifiers only—never live datasource objects or credentials). Imports enforce a strict `<= 512 KiB` (`524,288`-byte) file-size ceiling, validate widget types, grid bounds, and filter schemas before state mutation, and support **Merge with existing dashboards** or **Replace all dashboards**.
- **Scale-safe 50-lane guardrails:**
  - **Per-page live stream caps:** Each custom dashboard page enforces `<= 4` live video widgets and `<= 6` live count-chart widgets so wallboards remain responsive on 50-lane portals without exhausting browser media decoders or WebSocket/HLS connections.
  - **Bounded statistics refresh (`>= 60 s`, `POOL <= 2`):** **Alarm Statistics** widgets allow manual refresh (`0 s`) or automatic intervals of `>= 60 s` (`300 s` default). Historical profile queries push `phenomenonTime` windows down to PostgreSQL `oscar_archive_generation_summary` counters across `<= 30` coarse intervals at `POOL <= 2` concurrency—avoiding per-lane `searchObservations` retention probes and respecting OSCAR's two-session DuckDB cold-tier cap.
  - **Widget-isolated Event Table read state:** Custom **Alarm Table** and **Event Table** widgets isolate local selection and filter state per widget instance so custom wallboards never overwrite or clear the shared workstation unread alarm watermark (`/sensorhub/buckets/adjudication/dashboard-read-state`) on the canonical `/` Dashboard.
  - **Global audible alarm monitoring:** A singleton application-wide stream monitor (`useGlobalAlarmStreamMonitor`) keeps real-time Gamma, Neutron, and Mobile Detector occupancy audible alarms active while viewing `/dashboards` and all other console routes without duplicating MQTT subscriptions.

> **Complete Widget Catalog, JSON Schema & Developer Guide:** See **[Custom Widget Dashboards Guide](CUSTOM_WIDGET_DASHBOARDS_GUIDE.md)** for the full 17-widget operator reference, `schemaVersion = 4` JSON import/export format, and the 10-step developer checklist for adding new custom widgets.
>
> **Captioned Video Walkthrough (`#32`):** Watch **[Module 32 — Build, Scope & Export Opt-In Custom Widget Dashboards (`32-custom-widget-dashboards.mp4`)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/32-custom-widget-dashboards.mp4)** ([WebVTT captions](https://github.com/ORNL/oscar-video-guides/blob/main/captions/32-custom-widget-dashboards.vtt)) in [VIDEO_GUIDES.md](VIDEO_GUIDES.md#32-custom-widget-dashboards).
