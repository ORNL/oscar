# Mobile detector simulators

Stand-ins for an RS-350 backpack and a Kromek D5 walker, so a Mobile Detector System lane can be
exercised without hardware. Both are stdlib-only Python 3 TCP servers: point the lane's RPM host
and port at the machine that runs them.

| Script | Device | Default port | Protocol |
|---|---|---|---|
| `rs350_mock.py` | RS-350 backpack | 10110 | Pushes one ANSI N42.42 (2011) document per second, framed STX…ETX. The driver only reads. |
| `d5_mock.py` | Kromek D5 RIID | 10111 | Answers the driver's polled Kromek serial requests over SLIP framing (RadiometricsV1, RadiometricStatus with GPS, Status, About). |

```bash
python3 tools/mobile-detector-mocks/rs350_mock.py --port 10110
python3 tools/mobile-detector-mocks/d5_mock.py --port 10111
```

Each simulated walker loops a synthetic 1.2 km route near Oak Ridge, TN (the D5 runs it the
opposite way) at 1.4 m/s and reports its GPS position. Counts are Poisson background plus 1/r²
contributions from two hotspots on the route (Cs-137 and Co-60); while the expected rate exceeds
background × `alarm_factor`, the RS-350 documents carry alarm blocks and the D5 sets its dose-alarm
flag, so each pass by a hotspot produces an alarm occupancy on the lane.

Override any default with `--config cfg.json`: a JSON object with any subset of the script's
`DEFAULT_CONFIG` keys (`route`, `hotspots`, `speed_mps`, `background_gamma_cps`, `alarm_factor`,
`serial`, …).

Stopping a script and starting it again is the quickest way to test detector outages: the lane's
comm status, the RS-350 self-recovery and D5 reconnect backoff, and the Comm Failure indicator in
the viewer.
