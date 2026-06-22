# Navius GPS — Developer Documentation

## Table of contents

1. [General architecture](#general-architecture)
2. [Rust modules](#rust-modules)
3. [C++ modules](#c-modules)
4. [QML modules](#qml-modules)
5. [Build and deployment](#build-and-deployment)
6. [GPS and lomiri-location-service](#gps-and-lomiri-location-service)
7. [Valhalla server and traffic](#valhalla-server-and-traffic)
8. [Navius community server](#navius-community-server)
9. [TTS (Text-to-Speech)](#tts-text-to-speech)
10. [Data persistence](#data-persistence)
11. [Debug and control files](#debug-and-control-files)
12. [Environment variables and debugging](#environment-variables-and-debugging)
13. [LLS patches](#lls-patches)

---

## General architecture

```
┌─────────────────────────────────────────────────────────┐
│                      QML (UI)                           │
│  Main.qml · SearchPanel · NavBar · PreferencesPanel … │
├─────────────────────────────────────────────────────────┤
│                    Rust (backend)                       │
│  SatelliteModel · NavHttp · NavTts · NavTracker        │
├───────────────────┬─────────────────────────────────────┤
│  C++ (glue)       │  JavaScript (route logic)           │
│  satellite_source │  NavSearch.js · SimRoute.js         │
│  location_props   │  TodoDB.js                          │
├───────────────────┴─────────────────────────────────────┤
│  lomiri-location-service (D-Bus) · GPS HAL             │
└─────────────────────────────────────────────────────────┘
```

The main binary is Rust. A `QGuiApplication` and `QQmlEngine` are initialised from Rust using the `qmetaobject` crate. Rust QObjects are registered in the QML engine before loading `Main.qml` from the embedded QRC.

The UI is 100% QML + Lomiri Components. Routing and geocoding logic lives in `NavSearch.js` (JavaScript in the QML engine). GPS and TTS logic lives in Rust.

---

## Rust modules

### `main.rs`

Entry point. Responsibilities:

- Initialise `QGuiApplication` and `QQmlEngine`
- Register QML types: `SatelliteModel`, `NavHttp`, `NavTts`, `NavTracker`
- Load the embedded QRC (`qrc.rs`)
- Load `Main.qml` into the engine

Environment variables set here: `QML_XHR_ALLOW_FILE_READ=1`, `QML_XHR_ALLOW_FILE_WRITE=1`.

### `satellite_model.rs`

`QObject` exposed to QML as `SatelliteModel`. Acts as proxy between:

- **`SatelliteSource`** (C++): real GPS position source via Qt Positioning + LLS
- **QML UI**: observable properties for position, accuracy, heading, speed, satellites

1 Hz tick for satellite properties; 10–30 Hz tick for the interpolated position (dead-reckoning managed in `GpsSource.qml`).

Properties exposed to QML: `pos_lat`, `pos_lon`, `pos_accuracy`, `pos_speed`, `pos_bearing`, `pos_has_fix`, `sat_count`, `sat_used`, `satellites` (JSON list).

### `nav_http.rs`

`QObject` for async HTTP. Wrapper around `QNetworkAccessManager`.

- Method: `post(req_id: int, url: string, body: string, content_type: string)`
- Signal: `done(req_id: int, body: string, err: string)`

Used by `NavSearch.js` for requests to Valhalla (routing) and Photon (geocoding).

### `nav_tts.rs`

`QObject` for multi-engine TTS. Manages three backends:

| Backend | Implementation |
|---------|---------------|
| Piper | Child process (`vendor/piper_aarch64/piper`), WAV via stdout |
| Mimic HTS | `extras/mimic/mimic`, WAV via temporary file |
| PicoTTS | `pico2wave`, WAV via temporary file |

FIFO queue of texts to play. Async pre-generation of WAVs for upcoming instructions to minimise latency.

Exposed methods: `say(text)`, `say_with_lang(lang, text)`, `beep()`, `alert_beep()`, `set_engine_override(engine)`, `engine_for_lang(lang)`, `clear_all_tts_cache()`, `get_voice_list()`.

**Global mute (`muted`):** a `qt_property!(bool)`. When `true`, ALL sound methods (`say`, `say_with_lang`, `beep`, `alert_beep`, `reroute_beep`, `play_*`) `return` immediately without playing anything. In `Main.qml` it is bound (via a `Binding`) to `_soundCap === "silencio"`, so silent mode is a full mute — no beep or speech plays, including those without a guard at their call-site (e.g. the offline reroute beep).

**Text normalisation fixes (Spanish):**

- `" 1 km"` → `" un kilómetro"` — prevents the TTS from reading "uno kilómetro" in Spanish.
- Ordinals (`º`/`ª`): the parser consumes any period that may follow the ordinal indicator (e.g. `"3º."`, `"4.º"`) to prevent the engine from reading it as a pause or "punto". Example: `"3ª."` → `"tercera"` with no trailing period.

Both transformations are applied in the normalisation function before synthesis, regardless of engine.

### `nav_tracker.rs`

`QObject` for GPS track recording in SQLite.

- Database: `~/.local/share/navius.woodyst/gps_tracks.db`
- Table `tracks`: `id, name, date_ts, duration_s, dist_m, point_count, route_json`
- Table `track_points`: `track_id, seq, lat, lon, spd_kmh, ts`
- Methods: `start_recording()`, `add_point(lat, lon, spd_kmh, ts)`, `stop_and_save()`, `discard_recording()`, `set_route_json(json)`, `list_tracks_async()`, `get_track_sim_route_async(id)`, `export_gpx_async(id)`, `delete_track_async(id)`, `rename_track(id, name)`, `poll()`. Async results via signals: `tracks_ready`, `sim_route_ready(id, points, route)`, `gpx_ready`, `track_deleted`.

**Valhalla route attached to the track (`route_json`):** while recording, if navigation is active, `Main.qml` calls `set_route_json(JSON.stringify(_navData))` (at recording start and on every reroute). The Valhalla route (shape + maneuvers) is stored in the `route_json` column of `tracks`. The column is added via an idempotent migration (`ALTER TABLE ... ADD COLUMN`, ignoring the error if it already exists) in `open_db()`. `get_track_sim_route_async` returns the track points **and** the `route_json` (empty if the track has no route — old tracks or recorded without navigating) in the `sim_route_ready(id, points, route)` signal.

**Two replay modes** (chosen in the track list in `PreferencesPanel`):

| Mode | Button | Behaviour |
|------|--------|-----------|
| Driving | "Simular" (with `route_json`) | `_startNavigation(savedRoute)`: drives the saved Valhalla route with the track as the GPS source. Snap per `snapToRouteEnabled`, bisector and calculations identical to real navigation. Corrects the track's GPS anomalies by snapping to the road. |
| Raw GPS | "GPS crudo" (or tracks without `route_json`) | `_trackReplayRaw = true`: the track is the only geometry (`routeShape` = track, no snap, blue line = track). Shows the real GPS path for diagnosing GPS behaviour during recording. |

The `root._trackReplayRaw` flag separates both paths in the `_wasTrackReplay` block of `_startNavigation`. The `trackSimRequested(id, name, raw)` signal carries the `raw` flag from the button.

### `nav_music.rs`

Local music library for the app sandbox. Manages the track directory and Content Hub imports. Exposes four public functions accessible from QML via `nav_http.rs`:

- `music_dir()` — returns (and creates if absent) `$XDG_DATA_HOME/navius.woodyst/Music/`. **Critical note**: on Ubuntu Touch `XDG_DATA_HOME=/home/phablet/.local/share` (without the package name), so `navius.woodyst` must be appended explicitly; otherwise it would point to `~/.local/share/Music/`, which AppArmor denies.
- `list_tracks()` — returns JSON `[{"name":..,"path":..}]`. Uses `read_dir` + `file_type()` (lstat, without following symlinks) so that symlinks to `~/Music` are listed without requiring the `music_files_read` policy group.
- `import_tracks(urls)` — receives newline-separated URLs from Content Hub. If a URL comes from `HubIncoming` (temporary) → **copies** to the sandbox. If it is an external file (e.g. `~/Music`) → creates a **symlink** in the sandbox pointing to the original; creating a symlink does not require reading the target, so AppArmor does not deny it. Returns the number of tracks imported.
- `remove_track(name)` — `fs::remove_file`; for a symlink this removes only the link, leaving the original in `~/Music` untouched.

### `qrc.rs`

`qrc!` macro that embeds all QML files and assets into the binary as Qt resources (QRC). See the full list in the file. When adding a new QML file, it must be added here.

---

## C++ modules

### `satellite_source.h`

Class `SatelliteSource` (QObject). GPS source combining:

1. **Qt Positioning + LLS**: position and GPS fix via `QLlsPositionInfoSource`
2. **Satellite bridge**: reads `/run/user/32011/navius.woodyst/navius-sat.txt` as secondary satellite data source when LLS does not provide them

Manages automatic reconnection to LLS when the service restarts.

**Critical bug fixed**: `init_pos_and_session()` connected `llsRestarted` on every call, accumulating `StartPositionUpdates` calls exponentially. Connections are now registered once in `init_sources()`.

**Critical bug fixed**: `startUpdates()` must be called on the main thread (has internal `QEventLoop`). `QMetaObject::invokeMethod` is used to guarantee this.

### `location_props.h` / `location_props.cpp`

Class `LocationPropsWatcher` (QObject). Responsibilities:

- Polling `VisibleSpaceVehicles` from LLS via D-Bus (satellite data, non-standard method)
- Detecting LLS restart via the D-Bus `NameOwnerChanged` signal
- Emitting `llsRestarted()` signal when LLS reappears on the bus

When `llsRestarted` fires, `SatelliteSource` recreates the LLS session and calls `startPositionUpdates` again.

---

## QML modules

### `Main.qml`

Root window. Contains:

- `ApplicationWindow` with states `idle`, `navigating`, `parking`
- `Settings id: appSettings` with all global configuration
- Instances of all panels and dialogs (SearchPanel, NavBar, PreferencesPanel, etc.)
- Navigation logic: `_startNavigation()`, `_stopNavigation()`, `drawRoute()`, recalculation
- TTS logic: instruction pre-generation (`_pregenerateUpcoming()`), instruction queue
- Traffic management: `_trafficCheck()`, alternative route comparison
- Simulator logic: `simStart()`, `simStop()`, `_applySimRoute()`

Environment variables it sets: `QML_XHR_ALLOW_FILE_READ=1`, `QML_XHR_ALLOW_FILE_WRITE=1`.

**Trip sharing:**

| Element | Description |
|---------|-------------|
| `_shareToken` | Active share token (empty string = not sharing) |
| `_shareCreating` | `true` while waiting for `POST /share` response |
| `shareUpdateTimer` | 5 s timer (repeat: true) that calls `_pushShareUpdate()` |
| `_startSharing()` | Makes `POST /api/v1/share`, saves the token, opens `TripSharePanel` |
| `_stopSharing()` | Makes `DELETE /api/v1/share/:token`, clears the token |
| `_pushShareUpdate()` | Makes `PUT /api/v1/share/:token/location` with position, heading and route state |

If the user is not logged in, `_startSharing()` opens `LoginPanel` instead.

**Map modes — `mapView.applyLightMode()`:**

| `mapStyleMode` | Style applied |
|----------------|---------------|
| `"satellite"` | `satelliteStyleUrl` (ArcGIS raster) |
| `"positron"` | `positronUrl` (Carto or navius-maps) |
| `"bright"` | `brightUrl` (OpenFreeMap or navius-maps) |
| `"fiord"` | `fiordUrl` (navius-maps only) |
| `"dark"` | `darkUrl` (navius-maps only) |
| `"auto"` + `lightMode="night"` | `darkUrl` (explicit night, intense) |
| `"auto"` + solar night | `nightUrl` = `fiordUrl` (soft auto night) |
| `"auto"` + day | `dayUrl` (liberty) |

`darkUrl` and `nightUrl` are separate properties: `darkUrl` points to the `dark` style on navius-maps; `nightUrl` points to `fiordUrl` (softer). This is important: **Auto** night mode uses Fiord, not Dark.

The map style button (`mapStyleBtn`) cycles through available styles based on `mapView._navius` (whether the configured server is navius-maps) and `mapNaviusStyles` (JSON array of extra available styles).

**Settings synchronisation:**

| Element | Description |
|---------|-------------|
| `_settingsSyncBlocked` | Blocks `_onSettingChanged()` during `_applyServerSettings()` to avoid loops |
| `settingsSyncTimer` | 3 s timer (debounce, repeat: false); restarts with each setting change |
| `_onSettingChanged()` | Calls `settingsSyncTimer.restart()` if the user is logged in |
| `_pushSettingsToServer(silent)` | Makes `PUT /api/v1/settings` with the snapshot of the 41 `SYNC_KEYS` |
| `_pullSettingsFromServer(onConflictCallback)` | Makes `GET /api/v1/settings`; if the server has changes and there are local unsynced changes, calls the conflict callback |
| `_applyServerSettings(data)` | Enables `_settingsSyncBlocked`, applies `NavSettings.applySnapshot()`, disables flag |
| `settingsConflictDialog` | Dialog allowing the user to choose between "Use server" or "Keep local" when there is a conflict |

**`mainAuthSettings`** (`Settings { category: "auth" }`):

| Property | Type | Description |
|----------|------|-------------|
| `token` | string | JWT of the active session (empty = not logged in) |
| `email` | string | Logged-in user email |
| `recordar` | bool | Remember session between launches |
| `userId` | int | Numeric user ID (obtained from JWT `sub`) |
| `settingsChangedSinceSync` | bool | There are local changes not yet uploaded |
| `settingsLastSyncAt` | string | ISO timestamp of the last successful sync |

**Offline reroute guard:**

`_rerouteBeepedOffline: bool` — set when a recalculation is attempted without internet and the warning beep has already been emitted. Reset when connection is restored. Prevents repeated beeps.

**Route proximity filter — `_routeInfo(lat, lon, margin)`:**

Projects the point `(lat, lon)` onto the active route polyline. Returns `{ onRoute: bool, arcDist: real }` where `arcDist` is the geodetic distance (metres) from the projected point to the start of the route. `margin` (metres) is the transverse proximity tolerance. Used by the community alert system to filter alerts off-route.

**Community alerts:**

| Element | Description |
|---------|-------------|
| `_commAlertas[]` | Array of active alerts `{lat, lng, categoria, subtipo, ...}` loaded from server |
| `_checkCommAlerts()` | Iterates `_commAlertas` and emits TTS/visual warnings on approach; uses `_routeInfo()` to filter by route |

Alerts are only shown on the map if the user is logged in (`mainAuthSettings.token !== ""`).

**Main menu — item order:**

| Position | Item | Visibility condition |
|----------|------|----------------------|
| 1 | Account / Login | Always |
| 2 | Share trip / Sharing | Always |
| 3 | Route preview | Only if navigation is active |
| 4 | Tasks | Always |
| 5 | Messages | Always |
| 6 | Music | Always |
| 7 | Parking (Save / Delete / View vehicle / Go to parking) | Depending on active vehicle state |
| 8 | Settings | Always |
| 9 | Map lock | Always |
| 10 | Debug | Always |
| 11 | GPS simulation | Always |

### `GpsSource.qml`

Unified GPS abstraction combining:

- Real fix (via `SatelliteModel`)
- GPS simulation (synthesised route, time-distance model)
- Dead-reckoning (position interpolation between real fixes)
- Manual mode (fixed debug position)

Provides `Main.qml` with a position stream at 10–30 Hz regardless of source.

**Speed in real GPS (`_onRealGpsTick`):**  
Controlled by `useHardwareSpeed` (bound to `appSettings.useHardwareSpeed`, default `true`).

- `true`: uses `satModel.pos_speed_kmh` (Doppler chip speed). The hardware calculates speed via frequency shift of the satellite signal; more accurate than d/dt at low speed and during sudden changes.
- `false`: calculates `_speedMs = haversineM(p1, p2) / dt` (consecutive position difference).

Heading (`_headRad`) and acceleration (`_accelMss`) are always calculated by d/dt of positions, since Doppler does not provide heading. If `hwSpeedKmh < 0` (chip without Doppler fix), d/dt is used as fallback even with `useHardwareSpeed = true`.

**GPS simulation (`_simAdvance`):**  
Time-distance model. `_simDistM` accumulates metres travelled; position is interpolated over `_simRouteCumDistM` (cumulative distances pre-calculated in `simStart()`). Effective speed: `commSpeedLimitKmh > 0 ? commLimit : routeSpd`, multiplied by `simSpeedBias`. Ensures primary and interpolated ticks use exactly the same speed.

**Map bearing — route anticipation:**

*Goal:* the map should point towards the angular centre of the route visible ahead, anticipating turns by `routeAheadSecs` seconds. The target angle is not the current GPS heading but the absolute angle that symmetrically centres the visible route on screen. The map pursues that target smoothly, without abrupt jumps on real ticks.

*Implementation with a sim route (`simRoutePoints` available):*

1. **`_simWantedVisibleAheadDistM(secsAhead)`** — computes how many metres of sim route will be travelled in `secsAhead` seconds. Applies a `_speedMs / valhallaSpeed` ratio (clamped 0.1–3.0) by dividing each segment's real timestamps by that ratio: going faster than Valhalla predicts increases the visible distance proportionally.

2. **`_simRouteIdealBisectorRad(distM, mapBearingRad)`** — walks `simRoutePoints` from `simIdx` for `distM` metres. For each point it computes the **angle from the vehicle to the point** (not the segment heading), relative to `mapBearingRad`. It identifies the leftmost point (`bisectorMinPt`, red in the overlay), the rightmost (`bisectorMaxPt`, blue) and the route point closest to the centre angle (`bisectorCtrPt`, green). All three are real route points → always on the road, and green is always between red and blue. Returns `mapBearingRad + (minRel + maxRel) / 2` — the map's **target angle**.

3. **Two-stage smooth pursuit in `onGpsTick` (Main.qml)** — the target is recomputed every tick:
   - **Stage 1 (target):** `_smoothMapTgt` follows the raw bisector with τ = 0.8 s.
   - **Stage 2 (pursuit):** `_mapBearingDeg` (written to `mapView.bearing`) follows `_smoothMapTgt` with τ = 0.15 s.

   ⚠️ **`_bdt` must be the REAL elapsed time**, not the timer's nominal period. The QML timer fires at ~8 Hz even when `drHz` is 30; capping `_bdt` to `1/drHz` (≈0.033 s) makes the exponential smoothers integrate time ~4× slower (effective τ ~3 s instead of 0.8 s) and the map lags ~15° behind in curves. Use `_bdt = min(now - _lastBearingMs, 0.5)` (0.5 s cap only to guard against jumps after a pause). The same pitfall appears in position interpolation and in the vehicle arrow rate-limit.

*Fallback without a sim route:* if `simRoutePoints` is null but `navBar.routeData` exists, the point `distM/2` metres ahead on the Valhalla shape is used (this is the path for "driving" mode and for replay with a saved Valhalla route). If there is no route, `mapHeadRad` (road heading at the snap, real ticks only) is used.

**Route snap — `snapToRouteEnabled` and `snapDistM`:**

Snap projects the GPS position onto the active route shape. It controls both the display position and the interpolation base.

- `snapToRouteEnabled` (bool, bound to `appSettings.snapToRouteEnabled`): enables/disables snap.
- `snapDistM` (real, bound to `appSettings.snapDistM`, default 8 m): maximum GPS→shape distance for snap to apply.
- `_snapActive` (internal bool): recomputed on every real tick. `true` only if `snapToRouteEnabled && dist(GPS, snapPoint) ≤ snapDistM`.

When `_snapActive = false`:
- `_lastRealTickPos.lat/lon` = raw GPS position (not snapped).
- `_onInterpTick` enters the dead-reckoning branch (from `_drBaseLat/Lon`), not shape-walking.
- The vehicle is shown at the raw GPS position and interp ticks follow the direction of travel.

`_updateShapePos` is always called (needed for ETA and manoeuvre detection), but its result is only used for position when `_snapActive = true`.

**Snap bounded to the active leg — `routeShapeLegEnd`:**

In multi-stop routes, the global shape concatenates all legs. Without a boundary, `_updateShapePos` can latch onto the start of the next leg when GPS approaches an intermediate waypoint intersection.

- `routeShapeLegEnd` (int, −1 = no limit): last index of the active leg in `routeShape`. Initialised to `legShapeEnds[0]` when navigation starts; advanced to `legShapeEnds[N]` on each `onIntermediateArrived`. Reset to −1 in `onRouteShapeChanged`.
- `_updateShapePos` limits `end = min(_shapeIdx + 200, routeShapeLegEnd)`.
- `_snapToRoute` iterates only up to `routeShapeLegEnd`.

### `NavSearch.js`

Search and routing engine. Main functions:

- `geocode(query, lat, lon, cb)`: geocoding via Photon (`navius-maps.egpsistemas.com/photon`, self-hosted worldwide index)
- `route(waypoints, opts, cb)`: route calculation with Valhalla; includes `date_time` for predicted traffic
- `trace_attributes(shape, cb)`: gets speed limits per route segment
- `detectOsmScout(cb)`: detects whether a local OSM Scout server is present
- `fetchPoisAlongRoute(category, cb)`: queries Overpass for POIs along the route; server selected by route centre position (`navius-maps.egpsistemas.com/overpass/` for Spain, public pool for the rest of the world); retries with next server on empty results
- `probeOverpassServers()`: called at startup — probes candidate servers and builds `_overpassActivePool`

The `route()` function sends `date_time: {type: 0, value: "current"}` (immediate route) or `{type: 1, value: "YYYY-MM-DDTHH:MM"}` (scheduled route).

### `SearchPanel.qml`

Route planning panel. Destination state machine `_dests: [{lat, lon, name, todos:[{text, done}]}]`.

Sections:
- Saved plans (top)
- Destination list with expandable TODOs
- Nearby POI by category
- Departure time (stickyBottom)
- CALCULATE ROUTE button + save plan (stickyBottom)

Settings: `planSt.json` (plans), `nav.*` (current waypoints).

### `NavBar.qml`

Active navigation bar. Shows current instruction, distance, ETA, speed, speed limit. Manages progression through route steps based on GPS position.

**Speed limits — priority logic:**

`_effLimit` — limit shown in the navigation bar speed sign:

```
commSpeedLimit > 0  →  commSpeedLimit
    else radarMaxspeed > 0  →  radarMaxspeed
    else (showRoadSpeedLimit && _speedLimit > 0)  →  _speedLimit
    else  →  0 (no visible limit)
```

`_colorLimit` — limit used to colour the speedometer (visual alert):

```
radarMaxspeed > 0  →  radarMaxspeed
    else commSpeedLimit > 0  →  commSpeedLimit
    else (showRoadSpeedLimit && commAlertSpeed > 0)  →  commAlertSpeed
    else (showRoadSpeedLimit && _speedLimit > 0)  →  _speedLimit
    else  →  0 (no colour alert)
```

Key difference: `_colorLimit` places radar above community limit (radar is more geographically accurate); `_effLimit` places community first (the user may have set it manually).

If `showRoadSpeedLimit` is disabled (default), OSM road limits (`_speedLimit`) produce neither sign nor colour alert.

**ETA in the bar:**

The current leg summary line shows:
```
NavSearch.formatDist(_legDistKm) · NavSearch.formatTime(_legTimeSec) · NavSearch.formatEta(_legTimeSec)
```
The total line (final destination):
```
NavSearch.formatDist(_distKm) · NavSearch.formatTime(_timeSec) · NavSearch.formatEta(_timeSec)
```
`NavSearch.formatEta(seconds)` calculates the arrival time by adding seconds to `Date()` now and formats it as `HH:MM`.

**Multi-stop navigation — active leg isolation:**

The route shape (`routeData.shape`) is a single array concatenating all legs. `legShapeEnds[i]` is the index of the last point of leg `i`. NavBar uses `_legEndIdx = legShapeEnds[_completedLegs]` to scope all operations to the active leg:

- **Snap and off-route** (`update()`): search is limited to `[start, _legEndIdx]`. Cannot latch onto future legs.
- **Wrong-direction**: uses the snap `minI` which is already bounded → also limited to the active leg.
- **Arrival detection**: computes `_distToLegEnd` to `shape[_legEndIdx]` (the active leg's waypoint).
- **`nearDest`**: suppresses off-route and wrong-direction when `_step >= last manoeuvre of leg` OR `_legArrivalPending` OR `_distToLegEnd < 150 m`. The 150 m guard prevents spurious rerouting from GPS drift at an intermediate waypoint intersection.
- **Rerouting** (`offRoute()`): recalculates all remaining waypoints (from current position to the final destination), not just the active leg.

Arrival confirmation flow:
1. `_distToLegEnd ≤ 10 m` / overshoot / stopped >5 s nearby → `legArrivalReached(legIdx, isFinal)` → `legArrivalBanner`.
2. User confirms → `confirmLegArrival()` → `_completedLegs++`; if the last leg → `arrived()`.
3. `intermediateArrived(waypointIndex)` → Main.qml advances `gpsSource.routeShapeLegEnd` to the new leg.
4. NavBar re-arms (`_legArrivalArmed = true`) for the next leg.

### `PreferencesPanel.qml`

Settings panel with collapsible sections. The open/closed state of each section is persisted in `Settings { category: "PrefPanelSections" }`.

Signals emitted to `Main.qml`: `soundTest`, `langChanged`, `lightModeApplied`, `simToggled`, `voicesRequested`, `voiceSelected`, `engineChanged`, `helpRequested`, `aboutRequested`, `tourRequested`, etc.

**Options level (`prefLevel`):**

`appSettings.prefLevel` controls which sections and controls are visible:
- `0` = Minimum: only sections with `_sectionMinLevel: 0` visible
- `1` = Medium: sections with `_sectionMinLevel` 0 and 1 visible
- `2` = Advanced: all sections visible

Each declarable section has `property int _sectionMinLevel` and `property bool hasContent: panel.cfg.prefLevel >= _sectionMinLevel`. Sections with `hasContent = false` are not rendered.

**Numeric controls:**
`[−]` / `[+]` stepper buttons are used instead of `Slider`. Reason: in Lomiri/QML, Sliders capture the vertical scroll of the parent `Flickable` when the user scrolls through the panel, accidentally changing values.

**Default value indicator:**
Next to each numeric or selection control, `↺ <default_value>` is shown when the current value differs from the default. If the value is already the default, the indicator is not shown.

**Restore defaults:**
Double-confirmation button in the panel header. First tap: `_confirm = true`, shows "⚠ Restore defaults". Second tap within 3 s: applies `resetAllToDefaults()`. A 3 s timer resets `_confirm` to `false` if not confirmed.

### `NavSettings.js`

`.pragma library` — settings sync with the community server.

- `SYNC_KEYS` — array of the 41 syncable keys (map, routes, GPS, speed/radar, voice/sound, UI, vehicles). Keys are logical and independent of the Qt Settings category: if a setting changes category in the app, the server key does not change.
- `snapshot(s)` — extracts a `{key: value}` object from `appSettings` for the 41 keys. Ready to send to the server.
- `applySnapshot(s, data)` — applies server data to `appSettings`. Ignores unknown keys. Converts types according to the current local value (bool, number, string) for robustness against data from older versions.
- `getSettings(token, callback)` — `GET /api/v1/settings`. Callback: `(ok, settingsObj, updatedAt, errCode)`. Error codes: `""` ok, `"net"` no network, `"401"` unauthenticated, `"404"` server without support, other number = HTTP code.
- `putSettings(token, settingsObj, callback)` — `PUT /api/v1/settings`. Callback: `(ok, errCode)`.
- `serverUrl()` / `setServerUrl(u)` — server URL (default `https://navius-api.egpsistemas.com`).
- `_xhr(method, url, token, body, callback)` — XHR helper with Qt 5.12 workaround: saves intermediate status and responseText because on 4xx/5xx errors they arrive as 0/"" at `readyState=4`.

### `AlertasOverlay.qml`

Community alerts overlay on the map. Shows active alert markers `_commAlertas[]` as coloured icons. Tapping a marker shows a popup with category, subtype and time since creation. Includes the button to report a new alert (requires login).

### `NavAlerts.js`

`.pragma library` — community alerts logic.

- Fetch alerts in the map bounding box from the server (`GET /api/v1/alertas`).
- Converts alerts to QML markers with corresponding icon (assets `alertas/*.png`).
- `jwtSub(token)` — extracts the `sub` field (userId) from the JWT without verifying signature (for internal use only).
- Voting logic: confirm / dismiss alert (`POST /api/v1/alertas/:id/voto`).

### `LoginPanel.qml`

Login and registration panel with the Navius server. Modes: login (email + password), registration (email + password), password recovery. On successful login saves the JWT in `mainAuthSettings.token` and email in `mainAuthSettings.email`. If server settings differ from local, triggers `_pullSettingsFromServer()` with conflict callback.

### `TripSharePanel.qml`

Bottom trip sharing panel. Properties: `shareUrl`, `creating`, `active`. Signals: `createRequested()`, `stopRequested()`, `dismissed()`.

Visual states:
- **No active share**: description, "Create link" button
- **Creating**: text spinner "Generating link…"
- **Active share**: shows the URL with copyable field (Copy button with 2 s feedback), "Open in browser" button and "Stop" button (red)

The panel does not close when tapping outside. The only exit point is the "Close" button.

### `MediaPanel.qml`

Integrated music playback panel. Music enters the sandbox via **Content Hub**; playback uses `file://` from the app's own directory (`~/.local/share/navius.woodyst/Music/`), which media-hub permits through its allowlist.

- `property var navHttpObj` — reference to the Rust `NavHttp` object; exposes `music_dir`, `music_list`, `music_import`, `music_remove`.
- `ListModel { id: musicModel }` with fields `name` and `path`. Populated by `reloadLibrary()` by parsing the JSON from `navHttpObj.music_list()`. Refreshed automatically whenever the panel becomes visible.
- `ContentPeerPicker { contentType: ContentType.Music; handler: ContentHandler.Source }` — opens the file manager in Content Hub mode. `peer.selectionType = ContentTransfer.Multiple` allows selecting multiple tracks at once.
- `Connections { target: root.activeTransfer; onStateChanged }` — when the transfer reaches `Charged`, iterates `activeTransfer.items`, calls `navHttpObj.music_import(urls)`, then `activeTransfer.finalize()`.
- `Audio` component (QtMultimedia 5.6): `player.source = "file://" + path`.
- TTS ducking: `duck(bool)` adjusts volume via PulseAudio (`ttsObj.set_music_volume`), 600 ms delay on restore.
- Expandable help section with the `find ~/Music … -exec ln -s {} musicdir/ \;` command for manually creating symlinks from a terminal without duplicating files.

### `MediaWidget.qml`

Compact bar visible above `statusBar` when a track is loaded. Shows track name and basic controls (previous, play/pause, next, close). Disappears when music stops or player closes.

### `RouteSelectPanel.qml`

Panel showing up to 3 route alternatives calculated by Valhalla. For each alternative shows distance, estimated time and segment speed profile. Allows changing vehicle type, viewing full instructions (`InstructionListPanel`) or starting navigation.

### `RouteViewPanel.qml`

Active route summary panel. Shows the list of stops with distance and time to each. Accessible during navigation.

### `SatelliteView.qml`

GPS satellite view. Draws on a `Canvas`:
- Azimuthal polar view (azimuth/elevation) of all visible satellites
- Colour-coded SNR bars (green = in use, grey = visible but not used)
- Text with number of visible/used satellites and fix status (no fix / 2D / 3D)

Data received from `satModel.satellites` (JSON array updated at 1 Hz).

### `SpeedView.qml`

Circular speedometer overlaid on the map. Shows current speed in km/h. Indicator colour changes based on `_overLimit` (calculated in `NavBar.qml` by comparing speed with `_colorLimit`). Visible during and outside active navigation.

### `OfflineBanner.qml`

Banner appearing at the top when there is no internet connection. Detection runs every 6–30 s (adaptive interval). Disappears automatically when connection is restored. Does not block the UI.

### `NavMessages.js`

`.pragma library` — server message logic.

- `fetchMsgs(deviceId, token, sinceId, callback)` — `GET /api/v1/mensajes` with pagination parameters. Returns array of new messages.
- Marks messages as read: `POST /api/v1/mensajes/:id/leido`.
- Marks messages as deleted (soft delete per device): `POST /api/v1/mensajes/:id/eliminado`.

### `MessagesPanel.qml`

Server messages panel (broadcast, per user or per device). Scrollable list with unread badge. Supports messages with web link and with navigation destination (Go button). Opens `MsgDetailPopup` when tapping a message.

### `MsgDetailPopup.qml`

Modal popup with full message detail: title, type/importance, full body, date, web link (opens in browser) and navigation destination button if the message has coordinates.

### `VehicleSetupDialog.qml`

Custom vehicle management dialog. Allows creating, renaming and deleting vehicles with aliases and type (Valhalla costing: `auto`, `motorcycle`, `bicycle`, `pedestrian`, `truck`, etc.). The active vehicle is used for routing and parking. Data persisted in `appSettings.vehiclesJson` (JSON array, also synced to server via `SYNC_KEYS`).

### `ParkingDialog.qml`

Parking dialog with two modes:
- **Save**: records current lat/lon as the active vehicle's parking position.
- **Navigate**: allows selecting from all vehicles with a saved parking spot and adds the destination to the route planner.

### `InstructionListPanel.qml`

Panel with the full list of active route instructions. Shows manoeuvre icon, text and distance for each step. Opened from the "View instructions" button in `RouteSelectPanel` and from the navigation bar. Tapping a step centres the map on that position.

### `StopTodoPanel.qml`

Panel showing pending TODOs for the current stop when arriving at the destination. Allows marking each task as completed. Integrates with `TodoDB.js` to read/write task state.

### `CompassWidget.qml`

Compass widget overlaid on the map. Shows the current map orientation and, when tapped, resets north and enables follow mode.

### `NaviusLogo.qml`

Navius vector logo component (loads `assets/logo.svg`). Used in the splash screen and in the `AboutDialog`.

### `BtnLabel.qml`

Reusable component for button labels with text, optional icon and pressed state. Simplifies visual consistency of main menu buttons.

### `OsmScoutDialog.qml`

OSM Scout local server configuration dialog. Shows detection status and allows manually entering the URL.

### `RouteRestoreDialog.qml`

Dialog appearing on startup if `navius_route` has `wasNavigating=true`. Asks whether to restore the previous navigation. If the user accepts, recalculates the route from the current position.

### `SharedLocationDialog.qml`

Dialog for sharing the current position as a one-time link (not real-time trip share). Generates a static URL with the current coordinates.

### `GoogleMapsPanel.qml`

Panel for opening the current position or a searched destination in Google Maps in the external browser.

### `TtsVoicesPanel.qml`

Piper voice download and management panel. Lists available voices on the voice server, shows downloaded ones, and allows downloading/deleting individual voices.

### `TrafficRouteDialog.qml`

Dialog showing the comparison between the current route and a faster alternative found by the traffic system. Allows accepting the alternative or keeping the current route.

### `TourOverlay.qml`

Multi-step interactive tour (20 steps). Displayed automatically on startup if `tourSettings.showOnStart` is true. Steps: welcome, map, search, planning, TODOs, departure time, route selection, navigation, community alerts, trip sharing, TTS, music player, speedometer, server messages, satellites, track recording, Valhalla server, settings, farewell.

### `AboutDialog.qml`

Modal dialog with app information: name, description, official Valhalla server and its features, tech stack, licence.

### `HelpPanel.qml`

Help panel in Q&A format by section. Covers all user features except debugging.

### `WhatsNewDialog.qml`

What's new dialog. Shown on startup if `lastSeenVersion !== currentVersion`. Has version logic based on timestamp (`"YYYY-MM-DD HH:mm:ss"`).

---

## Build and deployment

### Requirements

- [Clickable](https://clickable-ut.dev/) ≥ 8.7.0
- Docker with Ubuntu Touch aarch64 build image

### Build

```bash
# For aarch64 device
clickable build

# Only the Mimic HTS library
bash compilar_solo_mimic.sh
```

### Deploy

```bash
clickable install    # installs the .click on the USB-connected device
clickable launch     # launches the app on the device
```

**Always kill the previous instance before launching**:

```bash
ssh phablet@<ip> "kill \$(pgrep -x navius)"
```

### Postbuild (`clickable.yaml`)

The `postbuild` step automatically bundles:

- `espeak-ng` + data (phonemes for Piper)
- `piper` binary and its libraries (`vendor/piper_aarch64/`)
- Compiled PicoTTS (`vendor/picotts/`)
- Mimic HTS + Spanish voice (`vendor/mimic_hts/` + `extras/mimic/`)
- `libpcaudio_stub.so` (PCM audio without PulseAudio)
- `libpiper_limit.so` (limits Piper CPU via `setrlimit`)
- `libQMapLibre.so` + `MapboxMap` plugin

### Adding a new QML file

1. Create the file in `qml/`
2. Add it to `src/qrc.rs` in the `qrc!` macro
3. Instantiate it in `Main.qml` or the corresponding panel

---

## GPS and lomiri-location-service

Navius uses [lomiri-location-service](https://gitlab.com/ubports/development/core/lomiri-location-service) (LLS) as the GPS backend via D-Bus.

A patched package (`3.4.1+navius6`) is distributed that fixes multiple issues with HALIUM_10 and Waydroid.

### Positioning stack

```
GPS HAL (hardware)
    ↓
lomiri-location-service (D-Bus)
    ↓  (qt-pim-locationplugin-lls)
Qt Positioning (QLlsPositionInfoSource)
    ↓
satellite_source.h (C++)
    ↓
SatelliteModel (Rust QObject)
    ↓
GpsSource.qml (dead-reckoning + interpolation)
    ↓
Main.qml / NavBar.qml
```

### Enabling debug traces

```cpp
// src/location_props.h
static constexpr bool NAVIUS_DEBUG = true;   // navius traces on stderr

// lomiri-location-service/include/.../lls_trace.h
static constexpr bool LLS_DEBUG = true;      // LLS internal traces on stderr
```

```bash
# View log on device
ssh phablet@<ip> "journalctl --user -f -u navius.woodyst_navius.desktop"
```

---

## Valhalla server and traffic

### Route request format

```javascript
{
    locations: [
        { lat: 40.4168, lon: -3.7038, type: "break" },
        { lat: 41.3851, lon: 2.1734,  type: "break" }
    ],
    costing: "auto",
    costing_options: { auto: { use_tolls: 0 } },
    alternates: 2,
    directions_options: { units: "kilometers", language: "es-ES" },
    date_time: { type: 0, value: "current" }  // or type: 1 with ISO value
}
```

`date_time.type`:
- `0`: current time
- `1`: departure time (`value: "2026-05-20T08:30"`)
- `2`: arrival time

### Predicted traffic

The valhalla.egpsistemas.com server has predicted traffic generated with synthetic profiles:

| Level | Road type | Free-flow | Peak | Night |
|-------|-----------|-----------|------|-------|
| 0 | Motorways | 115 km/h | 85 | 110 |
| 1 | Primary/secondary | 85 km/h | 55 | 80 |
| 2 | Local/residential | 45 km/h | 25 | 40 |

Peak hours: Mon–Fri 7–9h and 17–19h (parabolic fade). Traffic is encoded in 2016 DCT-II buckets per tile.

---

## Navius community server

Code in `navius_server/` (separate repository). REST server for alerts, users, settings sync, trip sharing and push messages.

### Stack

| Component | Version / role |
|-----------|---------------|
| Rust + Axum | Async web framework |
| SQLx | Async ORM for MariaDB |
| MariaDB 11 | Main database |
| Redis | Active share state (TTL 24 h, key `share:<token>`) |
| Docker Compose | Server deployment |

### Endpoints by module

All authenticated endpoints require `Authorization: Bearer <jwt>` in the header.

**Users (`/api/v1/usuarios`)**

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/v1/usuarios/registro` | No | Registration with email + password |
| POST | `/api/v1/usuarios/login` | No | Login; returns JWT |
| GET | `/api/v1/usuarios/verificar/:token` | No | Email verification |
| POST | `/api/v1/usuarios/refresh` | No | Renews an expired token (up to 90 days after expiry); returns new JWT |

**Token renewal (`POST /api/v1/usuarios/refresh`)**

| Field | Value |
|-------|-------|
| Auth | `Authorization: Bearer <expired_token>` |
| Condition | Token may be expired but not more than 90 days ago |
| Response | `{ "token": "<new_jwt>" }` |

Renewal works without re-login: the expired JWT (with a valid signature) is sent in the header. The server validates the signature with `validate_exp = false`, verifies the user still exists and that the token has not been expired for more than 90 days, and returns a new JWT.

The app calls `_refreshToken()` in `Main.qml` when the share endpoint returns 401. If the refresh succeeds, it retries the original operation once.

**Alerts (`/api/v1/alertas`)**

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/v1/alertas` | Yes | Active alerts in bounding box (`?lat_min=…&lat_max=…&lng_min=…&lng_max=…`) |
| POST | `/api/v1/alertas` | Yes | Create alert |
| POST | `/api/v1/alertas/:id/voto` | Yes | Confirm (1) or dismiss (0) alert |
| DELETE | `/api/v1/alertas/:id` | Yes | Deactivate own alert |

**Settings (`/api/v1/settings`)**

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/v1/settings` | Yes | Gets `{settings: {key: value}, updated_at}` |
| PUT | `/api/v1/settings` | Yes | Upsert settings `{settings: {key: value, …}}` (per key) |

Keys must be alphanumeric + underscore, max 120 characters. Upsert is atomic per key.

**Share (`/api/v1/share`)**

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/v1/share` | Yes | Creates share; if one already exists it is deleted first. Returns `{token, url}` |
| PUT | `/api/v1/share/:token/location` | Yes | Updates position + route state in Redis |
| GET | `/api/v1/share/:token/state` | No | Returns current share state (position, route, destination) |
| DELETE | `/api/v1/share/:token` | Yes | Revokes the share (deletes Redis + DB) |
| GET | `/share/:token` | No | Follower HTML page (viewer) |

Share state is stored only in Redis with 24 h TTL. The `shares` table in MariaDB stores the token↔user mapping to allow only one active share per user.

**Trip share viewer (`GET /share/:token`)**

The viewer is an HTML SPA embedded in the Rust binary. Technical stack:

| Technology | Version/Use |
|-----------|-------------|
| MapLibre GL JS | v4 (CDN jsdelivr) |
| Vector tiles | `navius-maps.egpsistemas.com` (Liberty, Fiord, Positron, Bright) |
| Polling | `GET /api/v1/share/:token/state` every 5 s |
| Redis cache | 24 h TTL per token |

**Viewer features:**
- Position marker: custom DOM element separating position transform (MapLibre `Marker`) from icon rotation (CSS `transform` on the inner element). This avoids conflict between MapLibre's `translate` and CSS `rotate`.
- **Auto-follow**: active by default; disabled on map `dragstart`. Re-enabled with the Centre button (◎).
- **Style selector**: Auto / Night (Fiord) / Day (Liberty) / Positron / Bright. Style change calls `map.setStyle()`, which destroys all layers and sources. The `idle` event (more reliable than `load` after `setStyle()`) is used to re-add the route layer, with `routeReady = false` as a flag.
- **`trimToRemaining(coords, lng, lat)`**: trims the route shape to show only the segment from the current position onwards. Projects the current point onto the polyline using Euclidean distance in spherical coordinates (corrected by `cos(lat)` for longitudes).
- **Route shape**: sent in `PUT /location` as `route_shape: [[lon, lat], ...]` with up to 10,000 points (≈200 KB per update every 5 s).

**Messages (`/api/v1/mensajes`)**

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/v1/mensajes` | Yes | Messages directed to the device or user (broadcast included) |
| POST | `/api/v1/mensajes/:id/leido` | Yes | Mark message as read |
| POST | `/api/v1/mensajes/:id/eliminado` | Yes | Soft delete per device |

**Speed limits (`/api/v1/limites`)**

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/v1/limites` | Yes | Community limits within radius (`?lat=…&lng=…&radio_m=…`) |
| POST | `/api/v1/limites` | Yes | Report community limit |

**Billboards (`/api/v1/billboards`)**

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/v1/billboards?lat=&lng=&radio=` | No | Active billboards within radius (km). Default 30 km. Filtered by `activo=1` and `expira_en > NOW()` |
| POST | `/api/v1/billboards` | Admin (`X-Admin-Key`) | Create billboard. JSON body: `{lat, lng, bearing?, tipo?, titulo, subtitulo?, url?, expira_en?}` |
| DELETE | `/api/v1/billboards/:id` | Admin (`X-Admin-Key`) | Deactivate billboard (soft delete: `activo=0`) |

**MariaDB connection pool**

| Parameter | Value | Reason |
|-----------|-------|--------|
| `max_lifetime` | 1800 s | Recycles connections before MySQL closes them due to `wait_timeout` |
| `idle_timeout` | 600 s | Frees idle connections to avoid saturating the pool |
| `test_before_acquire` | `true` | Verifies the connection is alive before handing it to a handler; prevents "MySQL server has gone away" errors |

Configured in `main.rs` with `MySqlPoolOptions::new()`.

### Migrations (0001–0011)

| Migration | Table(s) | Description |
|-----------|----------|-------------|
| 0001 | `usuarios` | User registration: email, argon2id hash, role, email verification |
| 0002 | `alertas`, `alerta_votos`, `error_mapa_cola` | Community alerts with categories, subtypes, lane, votes |
| 0003 | — (ALTER) | Adds `coords POINT` column + `SPATIAL INDEX` to alerts; triggers `alertas_bi/bu`; indices `idx_activa_expira`, `idx_expira_activa` |
| 0004 | — (ALTER) | Changes `lat`/`lng` from `DECIMAL(9,6)` to `DOUBLE` (fix coordinate corruption with SQLx binary) |
| 0005 | — (ALTER) | Adds `velocidad TINYINT UNSIGNED` column to alerts |
| 0006 | `limites_velocidad` | Community speed limits (lat, lng, bearing, speed) |
| 0007 | `mensajes`, `mensajes_estado` | Server messages with broadcast/user/device support; delivery/read state per device |
| 0008 | — (ALTER) | Adds `url`, `dest_lat`, `dest_lon`, `dest_nombre` to `mensajes` (messages with navigation destination) |
| 0009 | `user_settings` | Settings synced per user (composite PK `user_id + key_name`, atomic upsert) |
| 0010 | `shares` | Active share tokens; unique index `idx_shares_user` guarantees one share per user |
| 0011 | `billboards` | Geo-referenced advertising billboards: lat/lng, bearing, type (side/bridge), title, subtitle, URL, expiry |

### Deploy

```bash
# From the host with access to the server
rsync -av navius_server/ <your-server>:/srv/navius_server/

# On the server
ssh <your-server> "cd /srv/navius_server && docker compose up --build -d"
```

### Database access

```bash
# From the server or via SSH tunnel
mysql -u navius -p'<password>' --skip-ssl -h 127.0.0.1 navius
```

---

## TTS (Text-to-Speech)

### Architecture

```
NavTts (Rust QObject)
    ├── Piper: spawn process + WAV via stdout
    ├── Mimic HTS: spawn process + WAV via file
    └── PicoTTS: spawn pico2wave + WAV via file
         ↓
    FIFO text queue
         ↓
    libpcaudio_stub.so → PCM → /dev/snd/pcmC*D*p
```

### Pre-generation

`Main.qml` calls `_pregenerateUpcoming(step)` in `nav_tts.rs` to generate WAVs for the next N instructions in the background. When it is time to play them, the WAV is already cached and latency is ~0.

### Piper CPU limit

`libpiper_limit.so` uses `LD_PRELOAD + setrlimit(RLIMIT_CPU)` to limit the CPU usage of the Piper process, preventing it from degrading the UI on low-end devices.

---

## Data persistence

### Files on device

```
~/.local/share/navius.woodyst/
├── gps_tracks.db        # SQLite: recorded tracks
├── gps_tracks/          # Exported GPX files
├── debug/               # Debug and control files (see section 11)
└── QtProject/           # Qt Settings
```

### QML Settings categories

| Category | Contents |
|----------|----------|
| `nav` | current waypoints, route options |
| `dest_history` | destination history (max 50) |
| `favorites` | favourites with name and address |
| `saved_plans` | saved plans (JSON) |
| `search_ui` | search panel UI state |
| `PrefPanelSections` | collapsible section state |
| `whatsNew` | last seen version of the what's new dialog |
| `tour` | `showOnStart` for the assistant |
| `auth` | `token`, `email`, `recordar`, `userId`, `settingsChangedSinceSync`, `settingsLastSyncAt` |
| `device_msg` | `deviceId` (persistent UUID), `lastMsgId` (last received message ID) |

Trip share is **not persisted** between sessions: `_shareToken` is a runtime property of `Main.qml` and is lost when the app closes. If the app closes with an active share, the token remains valid on the server for 24 h, but the app does not recover it on restart.

### Settings synced with server (`user_settings`)

The 41 keys of `NavSettings.SYNC_KEYS` are synced with the `user_settings` table on the server. The mechanism:

1. When any `appSettings` setting changes: 3 s debounce → `_pushSettingsToServer()`
2. On startup with active session: `_pullSettingsFromServer()` checks whether newer settings exist on the server
3. If there is a conflict (local unsynced changes + changes on the server): `settingsConflictDialog` asks the user to choose

Server upsert is per individual key, allowing a setting to change Qt category without losing the synced value.

### TODOs (LocalStorage SQLite)

TODOs are saved via `TodoDB.js` in Qt LocalStorage (SQLite). The per-destination key is `"${lat}_${lon}"`. Structure:

```sql
CREATE TABLE todos (dest_key TEXT, text TEXT, done INTEGER, ord INTEGER)
```

---

## Debug and control files

All debug files reside in:

```
~/.local/share/navius.woodyst/debug/
```

The directory is created automatically when debug mode is enabled in PreferencesPanel, when `satModel.set_traces_enabled(true)` is called, or on the first write of any debug file.

---

### `.traces_enabled`

Flag file (empty). Its presence enables writing of `net_debug.log`, `tts_debug.log` and `piper_limit.log`. Managed by `satModel.set_traces_enabled(bool)`.

---

### Control files

#### `navius_cmd` — Remote command input

Written externally (SSH), read by the app every 400 ms (only with `debugMode=true`). The full content is used as a deduplication key: if it does not change, it is not reprocessed.

**Batch format** (recommended):
```
<unix_epoch>
<cmd1>
<cmd2>
...
```
The first line is a Unix timestamp (`>1e9`); each subsequent line is a command.

**Legacy format** (single line):
```
<epoch> <cmd>
```
or simply:
```
<cmd>
```

**Available commands:**

| Command | Effect |
|---------|--------|
| `2d` | Switch to 2D mode |
| `3d` | Switch to 3D mode (pitch 60°) |
| `north` | North-up mode |
| `heading` | Heading-up mode |
| `follow` | Enable follow mode |
| `pause` | Freeze simulation position |
| `resume` | Unfreeze simulation |
| `dbg` | Toggle debug overlay |
| `poi` | Toggle GPS/centre markers + cardinal POIs |
| `shot` | Save screenshot to `navius_shot.png` |
| `pos<lat>,<lon>` | Set manual position (e.g. `pos40.32,-3.51`) |
| `posoff` | Release manual position |
| `pitch+N` / `pitch-N` | Increase/decrease pitch by N degrees |
| `pitchN` | Set pitch to N degrees |
| `bear+N` / `bear-N` | Rotate bearing by N degrees |
| `bear0` | Reset bearing to north |

**Example usage from SSH:**
```bash
D=/home/phablet/.local/share/navius.woodyst/debug
echo "$(date +%s)
2d
north" > $D/navius_cmd
```

---

#### `navius_ack` — Command response

Written by the app after processing each command or batch. Format:

```
HH:MM:SS.mmm CMD: <cmd1>|<cmd2>|...
  mode=heading/navMap pitch=60 bear=45 mpp=5.1234 cy=320 fov=0.785 poi=false follow=true paused=false sim_mode=true sim_route=0 rv=false ...
  AZ: lat=40.123456 lon=-3.123456 bear=45 spd=35 rawSpd=35.2 secs=15 az=true hasPos=true azTgt=13.500 mpp=5.12345 pxR=2 mapH=800 dist=145.8 zoom=13.500
```

**Monitor from SSH:**
```bash
tail -f $D/navius_ack
```

---

### State files (written by the app)

#### `navius_route` — Navigation state (JSON)

Updated every 2 s while `_navActive || simMode`. Also read on startup to restore navigation if `wasNavigating=true`.

```json
{
  "active": true,
  "dist_m": 12345,
  "eta_s": 680,
  "limit_kmh": 50,
  "speed_kmh": 45,
  "lat": 40.416800,
  "lon": -3.703800,
  "sim_mode": false,
  "sim_route_idx": 0,
  "sim_seg": 42,
  "sim_total": 1200,
  "dests": [{"lat": 41.3851, "lon": 2.1734, "name": "Barcelona"}],
  "maneuver": "Continue straight for 500 m"
}
```

| Field | Description |
|-------|-------------|
| `active` | Navigation active |
| `dist_m` | Remaining distance in metres (−1 if inactive) |
| `eta_s` | Remaining time in seconds (−1 if inactive) |
| `limit_kmh` | Speed limit for current segment |
| `speed_kmh` | Current speed rounded |
| `lat`, `lon` | Current GPS position |
| `sim_mode` | Simulation mode active |
| `sim_route_idx` | Selected simulation route index |
| `sim_seg` | Current segment in the sim route |
| `sim_total` | Total points in the sim route |
| `dests` | List of destination waypoints |
| `maneuver` | Current manoeuvre text |

---

#### `navius_autostart` — Startup configuration (JSON)

Read once in `Component.onCompleted`. Written externally by the developer. All fields are optional:

```json
{
  "sim":      true,
  "debug":    true,
  "pos":      "40.4168,-3.7038",
  "routeIdx": 2
}
```

| Field | Type | Description |
|-------|------|-------------|
| `sim` | bool | Enable simulated GPS mode on startup |
| `debug` | bool | Enable debug mode on startup |
| `pos` | string | Set initial position `"lat,lon"` |
| `routeIdx` | int | Auto-start simulation route N |

---

#### `navius_trace` / `navius_trace_YYYYMMDD_HHMMSS` — GPS trace log

Only written with `debugMode=true`. When starting navigation, the session path is updated to `navius_trace_YYYYMMDD_HHMMSS`; `navius_trace` is the fallback for the non-navigation session. Updated every 2 s together with `navius_route`.

Format: plain text, one entry per real tick with interpolated ticks nested:

```
HH:MM:SS.mmm lat=40.123456 lon=-3.123456 spd=45.2 head=45.3 seg=12 dist=1234.5 fix=true
  HH:MM:SS.mmm interp lat=40.123460 lon=-3.123450 spd=45.1 head=45.3
  HH:MM:SS.mmm interp lat=40.123465 lon=-3.123440 spd=45.0 head=45.2
```

---

#### `navius_sl_debug.txt` — Speed limit debug

Written by `satModel.write_text_file("navius_sl_debug.txt", ...)` when the SL debug overlay is active (`showSlDebug=true` + `debugMode=true`). One line per segment with the speed limit source (community / Valhalla / OSM / legal by class / default).

---

### Log files (append, require `.traces_enabled`)

#### `net_debug.log`

Written by `satModel.log_to_file()`. Contains XHR debug lines for routing (Valhalla) and geocoding (Photon) requests generated in `NavSearch.js`.

```
2026-05-22T10:30:00 route: POST https://valhalla.egpsistemas.com/route
2026-05-22T10:30:00 route: 200 OK 1234 bytes 0.456s
```

#### `tts_debug.log`

Written by `nav_tts.rs`. Logs engine selection, synthesis, timings, cache:

```
[1716500000.123] piper: say "Turn right" lang=es-ES
[1716500000.234] piper: synthesis done 0.111s cache=MISS written=/path/to/cache.wav
[1716500001.456] piper: say "In 200 metres, continue straight" lang=es-ES
[1716500001.500] piper: synthesis done 0.044s cache=HIT
```

#### `piper_limit.log`

Written by `libpiper_limit.so` (LD_PRELOAD on the Piper process). Logs CPU throttling events. Each entry is one line:

```
piper_limit: nice(10) applied pid=12345
piper_limit: RLIMIT_CPU set to 2s per 5s window
```

---

### Useful SSH commands

```bash
D=/home/phablet/.local/share/navius.woodyst/debug

# Monitor acknowledgments
tail -f $D/navius_ack

# View navigation state in real time
watch -n2 cat $D/navius_route | python3 -m json.tool

# Follow GPS trace
tail -f $D/navius_trace

# Follow all logs
tail -f $D/net_debug.log $D/tts_debug.log $D/piper_limit.log

# Send batch command
echo "$(date +%s)
3d
heading" > $D/navius_cmd

# Set manual position
echo "$(date +%s)
pos40.4168,-3.7038" > $D/navius_cmd
```

---

## Environment variables and debugging

| Variable | Effect |
|----------|--------|
| `NAVIUS_DEBUG=true` | Enables GPS/LLS traces on stderr (defined in `location_props.h`) |
| `LLS_DEBUG=true` | Enables LLS internal traces on stderr (defined in `lls_trace.h`) |
| `QML_XHR_ALLOW_FILE_READ=1` | Allows `XMLHttpRequest` to `file://` |
| `QML_XHR_ALLOW_FILE_WRITE=1` | Allows write via XHR to `file://` |
| `QML_DISABLE_DISK_CACHE=1` | Disables compiled QML cache (useful during development) |

### In-app log panel

In `SearchPanel.qml`, the log area shows network requests and routing errors. Activated by tapping the log area.

---

## LLS patches

The package `lomiri-location-service 3.4.1+navius6` includes the following patches:

### navius1 — Waydroid SIGSEGV + EDEADLK

Waydroid overwrites GPS callbacks while LLS dispatches them → SIGSEGV. Fixed with `std::shared_mutex`. Split of `register_callbacks()` into three phases to avoid EDEADLK from HAL re-entry.

### navius2 — Non-blocking `start_positioning()` + satellite API

`start_positioning()` and `register_callbacks()` run in a detached thread so the D-Bus thread does not block on binder IPC. Added D-Bus method `GetVisibleSpaceVehicles` and `Restart=always` in systemd.

### navius3 — Fast path + concurrent recovery guard

Fast path in `start_positioning()`: if the GPS handle is valid, calls `u_hardware_gps_start()` directly. Atomic flag `positioning_active` prevents two concurrent recovery threads.

### navius4 — Watchdog + dispatch modes in fast path

Thread watchdog (5 s tick, 10 s threshold): detects frozen GPS, re-registers callbacks and restarts GPS. `dispatch_updated_modes_to_driver()` added to fast path before `u_hardware_gps_start()`.

### navius5 — Centralised `lls_trace.h`

`LLS_DEBUG` constant and `LLS_TRACE()` macro moved to a single shared header.

### navius6 — GPS indicator fix + HAL deadlock hardening

`engine.cpp`: `is_any_active = last_provider_result` → `|=` — with two providers only the last one's result was used, so the GPS indicator never appeared if only the first provider was active. `android_hardware_abstraction_layer.cpp`: `start_positioning()` uses `try_to_lock` to avoid blocking the D-Bus thread; phase 4 of `register_callbacks()` runs without lock to prevent re-entry deadlock; null guard in `stop_positioning()`.

### Upstream contributions (UBports)

Five merge requests have been submitted to [lomiri-location-service upstream](https://gitlab.com/ubports/development/core/lomiri-location-service). Fork: [gitlab.com/woodyst1/lomiri-location-service](https://gitlab.com/woodyst1/lomiri-location-service).

| MR | Description | Status |
|---|---|---|
| [!57](https://gitlab.com/ubports/development/core/lomiri-location-service/-/merge_requests/57) | `engine`: fix `is_any_active \|=` | ✅ Approved |
| [!58](https://gitlab.com/ubports/development/core/lomiri-location-service/-/merge_requests/58) | `gps`: race/EDEADLK/D-Bus hang/watchdog | In review |
| [!59](https://gitlab.com/ubports/development/core/lomiri-location-service/-/merge_requests/59) | `data`: trust-stored `.path` unit | In review |
| [!60](https://gitlab.com/ubports/development/core/lomiri-location-service/-/merge_requests/60) | `data`: `Restart=always` + clean `After=` | In review |
| [!61](https://gitlab.com/ubports/development/core/lomiri-location-service/-/merge_requests/61) | `service`: `GetVisibleSpaceVehicles` D-Bus method | In review |

### LLS package build

```bash
cd lomiri-location-service
bash debs/build-deb.sh 2>&1 | tee /tmp/build-lls.log
```

To install (with version change):

```bash
bash debs/update-phablet.sh
```

---

## Integrated music player

### Architecture

The player uses `Audio` (QtMultimedia 5.6) with the `ubuntu-media-hub` backend. Tracks are stored in the app sandbox and played back with `file://`.

**`nav_music.rs`** — Rust library: manages the sandbox directory, imports via Content Hub, creates symlinks.  
**`MediaPanel.qml`** — full panel (list + controls + volume slider + ducking + symlink help).  
**`MediaWidget.qml`** — compact bar over the map (visible while a track is loaded).

### Why media-hub cannot read `~/Music` directly

`authenticate_open_uri_request` in media-hub 4.7 has a **hardcoded allowlist by package name**. It only permits `file://` access to:

- The app's own directory (`~/.local/share/<pkg>/`, `~/.cache/<pkg>/`)
- The package `music.ubports` (official music app) → can read `~/Music` and `~/Videos`
- System paths (`/android/system/media/audio/ui/`)

Any other third-party app (including `navius.woodyst`) receives `"Client is not allowed to access"` when attempting `file:///home/phablet/Music/…`. **This is not an AppArmor bug** — kernel permissions are correct. The allowlist is hardcoded in media-hub's source and can only be bypassed by being `music.ubports` or running unconfined.

### Solution: Content Hub + sandbox

Music reaches Navius exclusively through **Content Hub** (`Lomiri.Content`). The flow is:

1. `ContentPeerPicker` (ContentType.Music) → the user selects files in the file manager.
2. Content Hub copies files to `~/.cache/navius.woodyst/HubIncoming/` (temporary).
3. `Connections { target: activeTransfer; onStateChanged }` detects the `Charged` state.
4. `import_tracks(urls)` in Rust:
   - If the URL is from `HubIncoming` → **copies** to `~/.local/share/navius.woodyst/Music/`.
   - If the URL is an external file (e.g. `~/Music/`) → creates a **symlink** in the sandbox pointing to the original. Creating a symlink does not require reading the source file (only writes to the destination directory), so AppArmor does not deny it even without `music_files_read` in the profile.
5. `activeTransfer.finalize()` cleans up `HubIncoming`.
6. `reloadLibrary()` refreshes the track list.

Playback uses `player.source = "file://" + path`. media-hub accepts this `file://` because the path starts with `~/.local/share/navius.woodyst/`, which is in its allowlist for the app's own sandbox.

### Symlinks to `~/Music` — why it works

media-hub-server runs with the AppArmor profile `owner @{HOME}/[^.]*/** rk`, which allows it to follow symlinks and read the real file in `~/Music`. Furthermore, media-hub **does not canonicalize the path** (it does not call `realpath`) before checking the allowlist, so a symlink at `~/.local/share/navius.woodyst/Music/song.mp3` passes the prefix check.

Navius lists symlinks with `file_type()` (lstat, without following the link), so it does not need to read the real file — that is delegated to media-hub at playback time.

**Users can create symlinks manually** from a Terminal or SSH to link their entire `~/Music` without duplicating storage. The player screen includes an expandable help section with the exact command.

### Note on `XDG_DATA_HOME` in Ubuntu Touch

The Navius process receives `XDG_DATA_HOME=/home/phablet/.local/share` (without the package name). `music_dir()` must append `navius.woodyst` explicitly: `$XDG_DATA_HOME/navius.woodyst/Music/`. Without this, `create_dir_all` would attempt to create `~/.local/share/Music/`, which AppArmor denies, and the import would fail silently.

### Why MPRIS2 is not viable (AppArmor)

Controlling an external player via MPRIS2/D-Bus requires sending messages to `org.mpris.MediaPlayer2.*`. The navius AppArmor profile has a catch-all `deny dbus (send)`, and the UBports kernel has active D-Bus mediation. There is no policy_group in `apparmor-easyprof-ubuntu` that allows MPRIS2 to third-party apps.

### TTS ducking

`Main.qml` detects `navTts.is_speaking()` every 100 ms and calls `mediaPanel.duck(true/false)`. MediaPanel adjusts volume via PulseAudio (`ttsObj.set_music_volume`) to the configured `duckVolume` (default 70%) and restores it 600 ms after TTS ends.

### Lomiri/QML compatibility

- `Slider` in Lomiri.Components uses `minimumValue`/`maximumValue`, not `from`/`to`.
- `Slider.onMoved` not available in QtQuick.Controls 2.2 → use `onValueChanged`.
- Properties with underscore prefix (`_foo`) do not generate `onFooChanged` handler → avoid for properties with inline handlers.
- `Connections` uses old syntax `onSignal: { ... }` (not `function onSignal()`, Qt 5.15+).

## Advertisement system (billboards)

Geo-referenced advertising billboards drawn on the map that generate a proximity notification on screen.

### Architecture

| Layer | File | Responsibility |
|-------|------|----------------|
| DB | `billboards` (migration 0011) | Stores billboards with coordinates, type, texts, URL and expiry |
| Server | `routes/billboards.rs` | Public GET (spatial query), POST/DELETE admin only |
| JS | `NavAlerts.js` (`obtenerBillboards`) | Fetch from the app, reuses the same infrastructure as alerts |
| QML | `Main.qml` (`bridgeCanvas`, `adPanel`) | Map rendering + notification panel |

### Billboard types (`tipo`)

| Type | Visual description |
|------|--------------------|
| `lado` | Billboard to one side of the road: vertical post from the GPS point, panel offset perpendicular to bearing. Posts at 25% and 75% of panel width. |
| `puente` | Billboard centred over the road (motorway gantry style): horizontal bar between two posts at panel edges; vehicle icon passes underneath. |

### Layer z-order

```
z:0  alertCanvas    — community alerts, radars, limits, GPS ticks
z:1  posOverlayRoot — vehicle icon
z:3  bridgeCanvas   — all billboards (side and bridge), above car
z:4  NavBar, adPanel, CompassWidget, scale bars
```

Billboards are sorted by Y position on screen (ascending): those higher on screen (further away) are painted first and appear behind closer ones.

### Fetch from app

`_fetchBillboards()` is called on each `onGpsTick`. Refresh thresholds:

- **No active route**: every ~500 m, 5 km radius.
- **Active route**: every ~20 km, 30 km radius.

`_adShownTs` is reset when starting a route or track replay so AdPanel shows again even if the billboard has already appeared in that session.

### Proximity panel (AdPanel)

`_checkBillboardProximity(lat, lon)` is called on each gpsTick. Activates `adPanel` if:

1. No other AdPanel is active (`_adPanelBb === null`).
2. A billboard is within 300 m.
3. More than 60 s have passed since the billboard was last shown (`_adShownTs`).

The panel appears below `NavBar` with height animation (200 ms), shows title and subtitle (or URL domain as fallback), and closes automatically after 12 s or when ✕ is pressed. If the URL contains `"navius"` the badge with the blue "N" is shown.

### Touch interaction

- **Tap on panel** (area left of ✕ button): opens `url` with `Qt.openUrlExternally`.
- **Direct tap on map** over a billboard: detected in the map `MouseArea`; recalculates the billboard bounding box based on type and bearing, opens `url` if the touch falls inside.

### Production management

```bash
# Create billboard (curl from server)
curl -X POST http://localhost:8080/api/v1/billboards \
  -H "X-Admin-Key: $ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"lat":40.416,"lng":-3.703,"bearing":90,"tipo":"lado",
       "titulo":"Navius Pro","subtitulo":"Navigation without limits",
       "url":"https://navius.app","expira_en":"2026-12-31T23:59:59"}'

# Deactivate billboard id=5
curl -X DELETE http://localhost:8080/api/v1/billboards/5 \
  -H "X-Admin-Key: $ADMIN_SECRET"

# View active billboards near Madrid
curl "http://localhost:8080/api/v1/billboards?lat=40.416&lng=-3.703&radio=50"
```
