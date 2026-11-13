# Live Video

OSCAR 3.11.0 starts Lane Details video only after the HLS stream has received a decodable H.264 keyframe. Until that point, the Viewer shows **Preparing live video** instead of presenting an empty player. If preparation or playback cannot recover within the bounded retry period, the Viewer shows a localized error and a **Retry** action.

> **Companion Video Guides:** Watch [Module 11 — Inspect Live Lane Camera Stream & Gamma/Neutron Waveforms (`11-live-lane-video-and-charts.mp4`)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/11-live-lane-video-and-charts.mp4) and [Module 13 — Adjudicate Event with 5-Frame Media, Daily File & Report (`13-event-details-adjudication-and-daily-file.mp4`)](https://github.com/ORNL/oscar-video-guides/blob/main/videos/13-event-details-adjudication-and-daily-file.mp4) in [VIDEO_GUIDES.md](VIDEO_GUIDES.md#11-live-lane-video-and-charts).

## Camera requirements

- The configured camera endpoint must be reachable by the OSCAR container and provide an H.264 video stream.
- Camera clocks and packet timestamps must advance continuously.
- Configure a closed GOP with a keyframe interval of one to two seconds. At 15 frames per second, a one-second interval is `15` frames.
- Do not depend on a keyframe interval longer than the desired live-video startup time. OSCAR discards packets received before the first keyframe so that the first HLS segment can be decoded independently.

### Multi-camera lanes and per-lane camera limits

OSCAR supports multiple cameras on a single lane out of the box across CSV import/export, SensorHub Admin configuration, live HLS viewing, Status of Health, and occupancy recording, subject to explicit per-event safety bounds in the five-frame retained-media gallery:

- **CSV import/export & Admin configuration (`0..N` sequential groups):** Lane CSVs accept any sequential number of six-column camera groups (`CameraType0..Password0`, `CameraType1..Password1`, `CameraType2..Password2`, …), and SensorHub Admin stores cameras as an ordered `ffmpegConfig` list on each `LaneSystem`.
- **Live HLS, occupancy recording & health monitoring:** During an occupancy, `CameraRecordingCoordinator` triggers and collects MP4 recordings across all configured lane cameras in parallel (backed by a 64-thread `FileControl` pool and 16-thread `HLSControl` pool). In the Viewer, Live Lane Details (`VideoMedia`) streams one selected camera page at a time (`<` / `>` controls cleanly stop the prior stream and release its viewer lease before starting the next), while Dashboard and Status of Health render an independent connectivity indicator per camera.
- **Five-frame retained-media per-event limits:** Both the backend `/buckets/videos/media/{eventId}` endpoint (`MediaResourceHandler`) and the Viewer (`RetainedMedia.ts`) enforce three hard per-occupancy safety caps across all `5` published JPEG frames per camera (`1 MiB` JSON catalog max; `12 MiB`, `20 MP`, and `6,000 px` max per frame):
  1. **Maximum `8` cameras per event** (`MAX_MEDIA_SETS_PER_EVENT = 8`).
  2. **Maximum `120,000,000` total pixels per event** (`cameras × 5 frames × width × height ≤ 120,000,000` prior to 30-day secondary-frame pruning), which determines the resolution-dependent camera ceiling per lane:

| Camera Stream Resolution | Pixels per Camera (`×5` JPEGs) | Supported Cameras per Lane (Five-Frame Gallery) |
| --- | --- | --- |
| `1080p` (`1920×1080`) or lower | `10.4 MP` | **Up to `8` cameras** (`82.9 MP` total; bounded by the 8-camera cap) |
| `5 MP` (`3072×1728`) | `26.5 MP` | **Up to `4` cameras** (`106.2 MP` total; a 5th camera reaches `132.7 MP > 120 MP`) |
| `4K` (`3840×2160`) | `41.5 MP` | **Up to `2` cameras** (`82.9 MP` total; a 3rd camera reaches `124.4 MP > 120 MP`) |

  3. **Maximum `64 MiB` total JPEG bytes per event** across all published frames.
- **Fallback behavior if exceeded:** If a lane's published media sets exceed `8` cameras, `120 MP`, or `64 MiB` for an event, `/buckets/videos/media/{eventId}` rejects the response (`HTTP 400`) and Event Details falls back to legacy MP4 playback (`videoPaths`), which remains available only during the 24-hour MP4 rollback grace window. Keep multi-camera lanes within the resolution table above so long-term five-frame evidence remains viewable after source MP4 pruning.
- **Site-wide host & UI sizing:** Each configured camera module maintains an active packet-copy (`-c copy`) RTSP reader, so site-wide network ingress (~`3–6 Mbps` per H.264 stream), FFmpeg worker threads, and asynchronous JPEG extraction scale with total cameras across all lanes. On narrow (`1280×800`) displays, Dashboard lane rows fit `3–4` camera status pills inline comfortably before wrapping onto a second line.

### Built-in loopback RTSP proxy

OSCAR embeds `mediamtx` inside the `oscar` container image (`/usr/local/bin/mediamtx`) and supervises it automatically on container loopback (`127.0.0.1`) whenever `rtsp://` or `rtsps://` camera streams are configured. Operators continue to configure and edit real camera hostnames, ports, credentials, and stream paths in SensorHub Admin UI, `config.json`, and CSV imports/exports; internal loopback proxy URLs are never persisted or exported.

- **Single upstream socket per unique camera URL per node**: If multiple lanes or sensors on the same node reference the same normalized RTSP URL, OSCAR shares one upstream camera connection through `mediamtx` using lease-based reference counting.
- **Automatic RTSP URL normalization and clean `TEARDOWN`**: Accidental multiple leading slashes in RTSP paths (for example `//h264Preview_01_sub`) are collapsed to a single leading `/` before connecting, and stopping or editing a camera removes the unused proxy path so `mediamtx` sends an RTSP `TEARDOWN` immediately.
- **Truthful connection status, 4K burst buffering, and in-place recovery**: OSCAR configures `mediamtx` with `writeQueueSize: 4096` and `15 s` read/write timeouts (plus a `10 s` minimum live FFmpeg stream-probe floor) so high-bitrate 4K physical PoE cameras with multi-second keyframe intervals neither overflow reader queues nor drop upstream TCP sockets under load, verifies upstream stream readiness before marking a camera `Online`, reconnects the FFmpeg stream processor in place without restarting the parent SensorHub module, and respawns `mediamtx` automatically if the child process ever exits unexpectedly.

The OSCAR camera emulator prepares its source assets with a one-second closed GOP and then republishes them with stream copy. This keeps the Raspberry Pi workload low while giving every emulated camera a predictable startup bound. The implementation is maintained in [ORNL/Camera-emulator](https://github.com/ORNL/Camera-emulator).

### Prepare and apply emulator assets

Run these commands from the Camera-emulator repository root before its first start, or after replacing either tracked source recording:

```sh
./scripts/prepare-assets.sh
./scripts/validate-assets.sh
docker compose up -d --no-deps --force-recreate publisher-rpm-1 publisher-rpm-2
docker compose ps
```

`prepare-assets.sh` writes validated, ignored derivatives under `assets/prepared/` atomically; it does not replace the tracked `assets/RPM_1.mp4` and `assets/RPM_2.mp4` sources. `validate-assets.sh` verifies H.264, dimensions, frame rate, the leading random-access frame, every internal keyframe gap, and the loop seam. Recreate only `publisher-rpm-1` and `publisher-rpm-2` so their existing FFmpeg processes open the new derivatives. MediaMTX and OSCAR do not need to be recreated or reset.

Preserve the emulator's `.env`, configuration, tracked source media, and all OSCAR deployment state. Do not add `--volumes`, delete Docker volumes, re-import lanes, or rerun OSCAR initialization for this media update. To deliberately rebuild otherwise-current derivatives after changing the preparation recipe, use `FORCE_PREPARE_ASSETS=1 ./scripts/prepare-assets.sh`, validate again, and recreate only the two publisher services as shown above.

## Viewer behavior

The live-video panel has three explicit states:

| State | Meaning |
| --- | --- |
| Preparing live video | The start command succeeded and OSCAR is waiting for the first usable HLS playlist and keyframe. Initial playlist-not-found responses are expected in this state. |
| Playing | The browser loaded the playlist and is advancing decoded video. |
| Live video could not be played | Preparation or playback exhausted its bounded recovery attempts. Select **Retry** after checking the camera and network. |

The Viewer retries transient playlist and media failures without repeatedly issuing start commands. After a terminal failure, selecting **Retry** waits for the old start attempt to settle, sends one stop command, and then issues one fresh start command. Leaving Lane Details, changing lanes, or unmounting the player releases that viewer's lease and sends the normal stop command; when another operator is actively watching the same lane, OSCAR keeps the shared HLS muxer running until the last active viewer leaves or times out. Stopping while OSCAR is still waiting for the first keyframe is treated as a successful cancellation: native resources are finalized, incomplete HLS artifacts are removed, and queued packets cannot leak into a later restart. Actual packet-write or cleanup failures are still reported.

## Occupancy recording integrity

MP4 occupancy recordings use a bounded FIFO for each configured camera. Start, close, and cancel
commands for one camera therefore execute in request order, while different cameras can still make
progress independently. Each start creates a generation-qualified name of the form
`<timestamp>-g<generation>.mp4`; a later reconnect or occupancy must never overwrite or claim that
path.

An MP4 OPEN remains pending until that exact recording generation successfully muxes its first
keyframe. OSCAR drops preceding mid-GOP packets, waits at most five seconds, and accepts the command
only while the same generation is still active. Stop, packet-write failure, timeout, or a stale
generation wakes and rejects the wait, cancels the output, and removes its hidden partial. Because
the per-camera FIFO queues CLOSE behind OPEN, a short occupancy can still save the first decodable
keyframe instead of finalizing a header-only, zero-packet clip. This adds only one volatile readiness
read to the steady-state packet path after the gate has opened.

The close operation's validated result is authoritative. OSCAR attaches only that returned path to
the alarm that requested it, and verifies its exact lane, camera, and recording generation. It does
not rediscover the clip by scanning a directory or by reading a mutable current-filename field.
Blank, duplicate, stale-generation, cross-camera, invalid-extension, missing, empty, or unfinalized
results fail closed instead of being published in `videoPaths`.

An occupancy that does not become an alarm explicitly cancels and removes its unpublished camera
recordings. A close timeout quarantines that camera's command queue from new recording work, but
OSCAR continues to observe the underlying close result. If the close completes after the owning
occupancy has been invalidated, the validated late path is removed instead of becoming an orphan.
Camera reconnects, overlapping lifecycle callbacks, and concurrent listener registration/removal
use generation gates and race-safe listener collections so a callback cannot migrate to a later
occupancy.

The eight-second command watchdog starts only after a command reaches the head of its per-camera
FIFO, any pre-submission alarm/save decision resolves, and the camera operation is actually
submitted. It counts neither legitimate FIFO wait nor the bounded decision wait. Each active
operation remains bounded independently, genuinely hung operations still quarantine the queue,
and the four-command pending cap prevents unbounded growth.

## Acceptance test

1. Open Lane Details for a lane with a connected camera.
2. Confirm the panel first shows **Preparing live video**, then begins playing within the configured camera keyframe interval plus normal network latency.
3. Confirm the playback time advances and the first HLS segment begins with a keyframe and decodes without missing-SPS/PPS errors.
4. Repeat on the first, middle, and last configured lanes, then switch rapidly between two lanes and confirm the old stream is stopped.
5. Stop an emulator publisher or disconnect a test camera. Confirm the Viewer eventually shows **Live video could not be played** and a **Retry** action instead of remaining at `0:00` indefinitely.
6. Restore the source, select **Retry**, and confirm playback resumes.
7. Start or reconnect a test camera and immediately run a short alarm occupancy. Confirm OPEN is not acknowledged before a muxed keyframe and exactly one nonblank, unique `videoPaths` entry exists for each configured camera; every path must include a generation suffix, belong to that camera, exist, contain a leading keyframe, finalize, and decode in the browser.
8. Run a non-alarm occupancy and confirm its unpublished MP4 and any partial file are removed.
9. Trigger back-to-back alarms and a camera reconnect during recording. Confirm each alarm references only its own camera generations, no new orphan or partial appears, and every retained-media ledger row names the same event, lane, camera, and source clip with one successful attempt.
10. Queue a short-occupancy `CLOSE` behind a keyframe-gated `OPEN`, with each operation individually below eight seconds but their cumulative queue time above eight seconds. Confirm the camera is not quarantined and the next occupancy receives only its own generation-qualified path.
11. Let the bounded alarm/save decision consume eight seconds before submitting `CLOSE`. Confirm the pre-submission wait does not quarantine the camera and that `CLOSE` receives its own full operation timeout.
12. Exercise a delayed active close past the command timeout. Confirm later recording commands for that camera fail closed until cleanup completes and the late clip is removed rather than attached to another alarm.

## Troubleshooting

| Symptom | Checks |
| --- | --- |
| Preparing lasts longer than expected | Check camera connectivity, confirm the stream is H.264, and measure the source keyframe interval. A long GOP directly increases worst-case startup time. |
| Live video could not be played | Restore camera/network reachability, inspect FFmpeg reconnect logs, and select **Retry**. |
| Player remains at `0:00` | Confirm the deployed OSCAR 3.11.0 image includes the keyframe-gated HLS and Viewer recovery fixes; inspect the first segment for a leading keyframe and valid H.264 parameter sets. |
| Emulator playback is slow to start | Run the emulator asset-preparation and validation scripts, then recreate the publisher containers. Runtime publishing should continue to use stream copy rather than live transcoding. |
| Recordings fail after a live-video change | Treat this as a regression. Live HLS and MP4 share camera input but have separate output rules; run the recording acceptance test before release. |
| Alarm recording preparation times out | Confirm the camera produces an H.264 keyframe within five seconds and that the packet path has no write failure. OSCAR deliberately rejects the OPEN and removes the hidden partial instead of attaching a zero-packet MP4. |
| An alarm references a clip from another event or camera | Stop release qualification. Recordings are bound by lane, camera, event, and generation; inspect the per-camera command queue and recording-coordinator logs. Never repair the database by guessing a nearby filename. |
| A timed-out close later leaves an MP4 | Stop release qualification. The late authoritative result should be observed and removed after invalidation; capture the queue timeout and cleanup logs before restarting the camera module. |
