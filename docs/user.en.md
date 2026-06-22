# Navius GPS — User Manual

[Web](https://www.egpsistemas.com/site/navius) · [GitHub](https://github.com/woodyst/navius) · [Donate](https://liberapay.com/Navius-GPS/)

## Table of contents

1. [Getting started](#getting-started)
2. [Navius account](#navius-account)
3. [The map](#the-map)
4. [Searching for a destination](#searching-for-a-destination)
5. [Planning a route](#planning-a-route)
6. [Per-destination TODOs](#per-destination-todos)
7. [Departure time and saved plans](#departure-time-and-saved-plans)
8. [Route selection](#route-selection)
9. [Turn-by-turn navigation](#turn-by-turn-navigation)
10. [Trip sharing](#trip-sharing)
11. [Music player](#music-player)
12. [Voice (TTS)](#voice-tts)
13. [Speedometer and speed limits](#speedometer-and-speed-limits)
14. [Community alerts](#community-alerts)
15. [Server messages](#server-messages)
16. [GPS satellite view](#gps-satellite-view)
17. [Track recording](#track-recording)
18. [Valhalla server and traffic](#valhalla-server-and-traffic)
19. [Settings](#settings)
20. [Data and privacy](#data-and-privacy)

---

## Getting started

When you open Navius for the first time, the welcome assistant walks you through all app features. You can return to it at any time from **Settings → Help → Open assistant**.

For Navius to work correctly you need:

- **Internet connection** for place search and route calculation (or a local Valhalla server)
- **Location permission** to receive the GPS position from the device

The first time the GPS acquires a signal it may take up to 1–2 minutes (cold fix). Once fixed, subsequent fixes are instant.

---

## Navius account

### Registration and login

Navius has a community server that lets you sync your settings across devices, report traffic alerts and share your position in real time.

To create an account:

1. Open the **≡** menu (top-right corner)
2. Tap **Account / Login**
3. Select **Register** and enter your email and password
4. You will receive a verification email; tap the link to activate the account

If you already have an account, select **Log in** and enter your credentials.

### Settings synchronisation

Once logged in, Navius automatically syncs your settings with the server:

- **When a setting changes**: the change is uploaded to the server automatically about 3 seconds later
- **When the app opens**: if there are more recent settings on the server (e.g. you changed them from another device), Navius detects this and asks you what to do

### Settings conflict

If you have local unsynced changes and there are also new changes on the server, a dialog appears with two options:

- **Use server**: applies the server settings and discards local changes
- **Keep local**: keeps your current settings and uploads them to the server

Synced settings include: map style, route options, GPS configuration, speed alerts, TTS engine, language, vehicle type, and more (41 settings in total). GPS position, active navigation state and debug options are not synced.

---

## The map

### Navigating the map

- **Pan**: drag one finger in any direction
- **Zoom**: pinch with two fingers or use the side zoom bar
- **Rotate**: twist with two fingers (in North-up mode the map returns to north automatically)
- **Re-centre**: tap the compass button to return to your position and enable tracking

### View modes

| Button | Effect |
|--------|--------|
| **2D / 3D** | Toggles between flat view and tilted driving perspective. In 3D mode extruded buildings are visible |
| **North / Heading** | The map can always point north or rotate to follow your direction of travel |
| **Compass** | Re-centres on your position and enables continuous tracking |

### Map styles

The map style button (on the map corner) lets you cycle through available styles. Tap to move to the next style; the current style name is shown below the icon.

| Style | Icon | Description |
|-------|------|-------------|
| **Auto** | ⊙ | Changes automatically based on sun position (day from ~7:00 to ~20:00, night otherwise) |
| **Satellite** | 🛰 | High-resolution satellite imagery |
| **Positron** | ☀ | Minimalist light map |
| **Bright** | 🌐 | Light map with vivid colours |
| **Fiord** | 🌊 | Soft dark map (used as night style in Auto mode) |
| **Night** | 🌙 | Intense dark map |

In **Auto** mode: the map uses the light style during the day and switches to Fiord at night (based on sun position, not a fixed clock time). If the Navius server is configured, Fiord and Night styles are available; otherwise equivalent styles from external providers are used.

> **Note**: the explicit **Night** mode uses the intense dark style; **Auto** night mode uses Fiord (softer). The style cycle button only shows styles available for the configured server.

### Landscape mode

When you rotate the device to landscape, the map fills the full screen height and the navigation panel (top bar with instruction, speed, etc.) moves to the left side, giving more space to the map.

---

## Searching for a destination

1. Tap the **"Start navigation"** button at the top to open the planning panel
2. Type the name of a place, address, city or coordinates (e.g. `40.4168, -3.7038`)
3. Results come from OpenStreetMap via the Photon/Komoot geocoder
4. Tap a result to add it as a destination

### POI search

In the planning panel, the **Nearby POI** section lets you search for points of interest near your current position or any added destination:

- Fuel stations — show the **fuel price** when available in OSM
- Car parks
- Restaurants and cafés
- Hotels
- Supermarkets
- Hospitals and pharmacies
- And more categories

Tap a POI to view its information (opening hours, phone, website, price…) and add it as a destination.

### History and favourites

- The **history** automatically saves the last 50 searched destinations
- **Favourites** are places saved manually with a custom name
- Both appear in the planning panel without needing to search

To add a favourite: search for the place → tap the star icon next to the result.

---

## Planning a route

### Multi-stop route

Navius lets you add as many destinations as you need. The route passes through all of them in order:

1. Add the first destination
2. Tap **+ Add stop** to add more destinations
3. Use the ↑↓ arrows to reorder stops
4. Tap **×** to remove a stop

### Route options

Before calculating you can enable or disable:

| Option | Effect |
|--------|--------|
| **No tolls** | Avoids toll roads |
| **No motorways** | Avoids dual carriageways and motorways |
| **No ferries** | Avoids ferry crossings |
| **No unpaved** | Avoids dirt or gravel tracks |

---

## Per-destination TODOs

You can associate a task list with any destination in the trip.

### Adding tasks

1. In the planning panel, expand a destination
2. Tap **+ Task**
3. Type the task text and confirm

Tasks are associated with the destination's coordinates and saved automatically.

### Managing tasks during navigation

When you arrive at the destination, Navius shows an on-screen notification. Tap **Open** to see the list of pending tasks and mark them as completed one by one.

### Persistence

TODOs are saved indefinitely. The next time you plan a route to the same place (same coordinates), you will see the tasks saved from previous sessions.

---

## Departure time and saved plans

### Scheduling departure time

Enable the **Departure time** toggle at the bottom of the planning panel. Two selectors will appear:

- **Day**: Today, Tomorrow, Day after tomorrow, etc.
- **Time**: HH:MM scroll wheel (5-minute intervals)

The route will be calculated using the traffic profile for that time of day. For example, a Monday 8:00 route will use morning peak traffic times.

### Saving a trip plan

Press the **⊕** button next to the CALCULATE ROUTE button to save the current plan. A plan includes:

- All destinations and their TODOs
- Scheduled departure time (if enabled)
- Route options (no tolls, etc.)
- Automatically generated name with the final destination and time

### Loading and deleting plans

Saved plans appear in the **Saved plans** section at the top of the planning panel:

- Tap a plan to load it (restores all destinations, TODOs and configuration)
- If the departure date has passed, it is automatically adjusted to the next day at the same time
- Tap the **🗑** icon to delete the plan

---

## Route selection

After tapping **CALCULATE ROUTE**, the selection panel appears with up to 3 alternatives:

- Each alternative shows: total distance, estimated time and speed profile
- The route is drawn on the map when selected
- You can change the **vehicle type** (car, motorbike, bicycle, on foot, truck…)
- Tap **View instructions** to see the full list of manoeuvres before departing
- Tap **Start** to begin navigation

---

## Turn-by-turn navigation

### Navigation bar

During navigation, the top bar shows:

| Element | Description |
|---------|-------------|
| **Manoeuvre icon** | Arrow or symbol for the next manoeuvre |
| **Distance to turn** | Metres or km to the next turn |
| **Street name** | Current street and name of the next one |
| **Speed** | Your current speed in km/h |
| **Limit** | Speed limit for the current segment |
| **Leg summary** | Distance · time · ETA to next waypoint |
| **Total summary** | Distance · time · ETA to final destination |

The **ETA** (estimated time of arrival) is calculated by adding remaining time to the current time and displayed in HH:MM format.

### Voice instructions

Instructions are announced by voice with enough advance notice to react. The active TTS engine (Piper, Mimic or PicoTTS) generates the audio in real time.

### Route recalculation

If you deviate from the route, Navius automatically recalculates from your current position to the next destination.

### Arriving at intermediate stops

When you arrive at each intermediate stop, Navius notifies you and, if there are pending TODOs, shows the banner to open them. Navigation continues automatically towards the next stop on confirmation.

### Stopping navigation

Tap the **Stop** button (■) in the navigation bar or swipe to close the panel.

### Route recovery on startup

If you close Navius with active navigation, when you reopen it a dialog asks whether you want to continue with the previous route. Tap **Continue** to resume from your current position, or **Discard** to start fresh.

### Alternative routes via traffic

During navigation, Navius periodically checks whether a significantly faster alternative route exists. If detected, a banner appears at the bottom showing the time saved. Tap **View alternative** to compare it on the map and decide whether to switch.

---

## Trip sharing

The trip sharing feature lets other people see your position and route in real time from any web browser, without needing Navius installed.

**Requirement**: you need an active Navius account (logged in).

### Enabling sharing

1. Open the **≡** menu
2. Tap **Share trip**
3. Tap **Create link** — Navius generates a unique link at `https://navius-api.egpsistemas.com/share/…`
4. Tap **Copy** to copy the link to the clipboard, or share it directly via WhatsApp, Telegram or any other app

While sharing is active, the menu item is shown in red with the text **Sharing**.

### What the follower sees

The follower page shows in real time:

- The **map** with your current position and a vehicle icon pointing in your direction
- Your **active route** drawn on the map (only the remaining portion, trimmed as you advance)
- Your current **speed** in km/h
- **Destinations** with remaining distance and estimated arrival time (ETA)

The follower page includes:

- **Map style selector**: can choose between Auto, Night (Fiord), Day (Liberty), Positron and Bright
- **Centre button** (◎): appears when the follower pans the map manually; tap to resume auto-following your position
- **Auto-follow**: the page automatically follows your position with smooth animation; if the follower pans the map, auto-follow pauses until they tap Centre

Position updates every 5 seconds while Navius is in the foreground with active navigation.

### When Navius closes

If you close Navius or the app goes to the background and stops sending updates, the follower page shows a **"Navius closed · Last known position"** banner with the last received position. The link remains valid for 24 hours.

### Automatic session renewal

If your session has expired (token expired) when trying to create or update a share, Navius automatically renews the token without requiring you to log in again. This renewal works up to 90 days after the original token expired.

### Stopping sharing

1. Open the **≡** menu
2. Tap **Sharing** (shown in red when a share is active)
3. Tap **Stop**

Permission is revoked immediately: the follower page will stop receiving updates as soon as it refreshes.

---

## Music player

Navius includes an integrated music player accessible from the **≡ → Music** menu.

### Opening the player

1. Open the **≡** menu
2. Tap **Music**
3. Browse the folders in `~/Music` to find your music
4. Tap a track to play it

### Supported formats

mp3, ogg, flac, m4a, opus, wav, aac, oga, wma

### Controls

- **▶ / ⏸**: play / pause
- **⏮ / ⏭**: previous / next track
- **Volume bar**: adjusts playback volume
- **×**: close the player and stop music

### Music widget

While a track is playing, a small compact bar appears above the status bar showing the track name and basic controls. It is visible even when the music panel is closed.

### Ducking with TTS

When Navius announces a navigation instruction by voice, the music volume is automatically lowered to 15 %. It is restored 600 ms after the instruction ends.

---

## Voice (TTS)

Navius includes three speech synthesis engines selectable in **Settings → Voice**:

### Piper (recommended)

- Neural quality, the most natural voice
- Latency ~300 ms (Navius pre-generates audio in the background)
- Supports multiple languages with `.onnx` voices
- Download additional voices from **Settings → Voice → View available voices**

### Mimic HTS

- HTS synthesis, good quality in Spanish
- Latency ~100 ms
- Built-in Spanish voice, no downloads needed

### PicoTTS

- Basic concatenative engine
- Latency ~50 ms (very fast)
- Languages: Spanish, English, German, French, Italian

### Voice configuration

In **Settings → Voice** you can:

- Select the engine
- Choose language (Spanish, English, French, German, etc.)
- Select a specific voice within the engine
- Test the voice with free text

---

## Speedometer and speed limits

### Speedometer

The circular odometer shows your current speed in real time.

### Speed limits

Navius can obtain the speed limit from several sources. When you exceed the limit, the indicator in the navigation bar changes colour.

**Limit priority for the colour alert:**

1. **OSM radar** — if the route passes a fixed or section camera with a maximum speed defined in OpenStreetMap
2. **Community limit** — if another Navius user has reported a limit on that segment
3. **Road limit** — road speed limit from OSM (only if the **Show road maximum speed** option is enabled in Settings; disabled by default because coverage of this data in OSM is not reliable)

If none of these sources is available, the indicator shows no colour alert even at high speed.

### Configuring alerts

In **Settings → General**:

- **Speed alert**: enables/disables the visual and audible alert
- **Threshold**: percentage above the limit that triggers the alert (default: 1%, equivalent to 1 km/h margin)
- **Show road maximum speed**: enables OSM road limit as an alert source (not always reliable; disabled by default)

---

## Community alerts

Community alerts are warnings that other Navius drivers report in real time, appearing on your map during navigation.

**Requirement**: you need an active Navius account (logged in).

### Alert types

| Category | Available subtypes |
|----------|--------------------|
| Traffic | Normal · Heavy · Stopped |
| Police / Speed camera | Mobile camera · Hidden radar |
| Accident | Minor · Multiple collision |
| Hazard | Road works · Car on shoulder · Broken traffic light · Pothole |
| Road closed | — |
| Lane blocked | Left · Right · Centre |
| Map error | (with text description) |
| Bad weather | Slippery road · Flooding · Snow · Fog · Ice |

### How they are shown

During navigation, you will only see alerts that are on your active route (filtered by proximity). If an alert is nearby, Navius emits an audible warning and displays the alert icon on the map.

### How to report an alert

1. Tap the alert button on the map (triangular warning icon)
2. Select the category and, if applicable, the subtype
3. Confirm — the alert is sent to the server with your current position and heading

Alerts have a limited validity period. Other users can confirm or dismiss them with the vote buttons that appear when tapping the marker.

---

## Server messages

The Navius community server can send you informational messages: maintenance notices, app updates or notifications directed to your device.

**Requirement**: you need an active Navius account (logged in).

### Viewing messages

1. Open the **≡** menu
2. Tap **Messages** — if there are unread messages a counter appears next to the icon
3. Tap a message to read its full content

### Notifications

If you receive a new message while using the app, a notification banner appears at the top of the screen. Tap the banner to open the messages panel directly.

Messages can include a link to a navigation destination. In that case you will see a **Navigate** button that adds that destination directly to the route planner.

---

## GPS satellite view

Tap the **satellite icon** to open the satellite view. It shows:

- **Azimuthal polar view**: position of each satellite in the sky (azimuth and elevation)
- **SNR signal bars**: signal strength of each satellite
- **Fix status**: no signal / 2D fix / 3D fix
- **Satellite count**: visible and in use

Useful for diagnosing reception problems or comparing signal in different locations.

---

## Track recording

Navius can record your GPS journey in real time.

### Enabling recording

Enable **Record track** in **Settings → Navigation**. Recording starts when there is a GPS fix and stops when disabled or the app closes.

### Viewing and exporting tracks

Recorded tracks are listed in **Settings → Navigation → Recorded tracks**:

- **View on map**: shows the route on the map
- **Export GPX**: saves the track in standard GPX format to `~/.local/share/navius.woodyst/gps_tracks/`
- **Simulate**: plays back the track as a GPS simulation route
- **Delete**: removes the track from the database

---

## Valhalla server and traffic

### Official server

Navius uses the **valhalla.egpsistemas.com** server by default, which offers:

- **Worldwide coverage**: the full planet with OpenStreetMap data
- **Predicted traffic**: speed profiles by time of day and day of week across the entire road network
- **All vehicles**: car, motorbike, truck, bicycle, on foot, moped and more
- **No limits**: unrestricted use for Navius users

### Predicted traffic

Predicted traffic allows Valhalla to adjust travel times according to the time of day. For example:

- A motorway may have 115 km/h at free-flow and 85 km/h at peak hour
- An urban street may have 45 km/h at night and 25 km/h at peak hour

Navius always sends the current time or scheduled departure time to the server so it applies the correct profile.

### Own server

You can use your own Valhalla server. Configure the URL in **Settings → Valhalla Server**. Useful for:

- Full privacy (no data leaves the device)
- Working without internet
- Custom map data

### Offline maps with OSM Scout Server

Install **OSM Scout Server** from the Ubuntu Touch OpenStore to calculate routes and search for places entirely without an internet connection. Maps and routing data are downloaded to the device.

Navius automatically detects whether OSM Scout Server is running. Enable it from **Settings → Valhalla Server → Detect local server** or wait for Navius to detect it on startup.

---

## Settings

The settings panel opens with the **⚙ Settings** button in the **≡** menu.

### Options level

The settings panel has a level selector at the top:

| Level | Description |
|-------|-------------|
| **Minimum** | Essential options only. Recommended for most users |
| **Medium** | Additional navigation and GPS behaviour options |
| **Advanced** | All options, including technical and debug configuration |

Sections and options that do not correspond to the selected level are hidden automatically to keep the panel simple.

### [−] [+] controls instead of sliders

Numeric values (interpolation Hz, distances, times…) are adjusted with **[−]** and **[+]** buttons instead of sliders. This avoids accidental changes when scrolling through the panel.

### Default value indicator ↺

Next to each option whose current value differs from the default, the default value is shown with a **↺** symbol (e.g. `↺ 8 m`, `↺ 15 s`, `↺ on`). If the value is already the default, the indicator is not shown.

### Restore defaults

At the top of the settings panel there is a **↺ Restore defaults** button.

- Tapping it once shows a confirmation message
- You must tap it **a second time** to confirm (double-tap safety)
- If you do not confirm within 3 seconds, the confirmation is cancelled automatically
- On confirmation, all settings return to their factory values

### Quick settings

Frequently used options accessible without opening sections:

- Map colour mode (day/night/auto)
- Auto-zoom (adjusts zoom based on speed)
- Map orientation (fixed north or following heading)

### General

- GPS interpolation (dead-reckoning) at 10/20/30 Hz
- Speed alert (warning threshold)
- **Show road maximum speed** — uses the OSM road limit as a speed alert source. Disabled by default (coverage not reliable in OSM).
- **Inhibit sleep during navigation** — prevents the screen from turning off while navigating (enabled by default).
- **Global text scale** — adjusts the size of all app text (range 0.8–1.5).
- Manual position (useful for testing without GPS)

### Valhalla server

- Route server URL
- Option to auto-detect local server (OSM Scout)

### Navigation

- **Vehicle type** — select the active vehicle or open the vehicle manager to create/rename/delete custom vehicles with aliases and type (car, motorbike, bicycle, on foot, truck…). The active vehicle also determines which parking position is used.
- **Doppler GPS speed** — uses the GPS chip speed (Doppler effect) instead of calculating it from position differences. More accurate at low speed and during acceleration; disable if you observe erratic speeds on your device.
- GPS track recording
- Recorded track management

### Billboards (advertisements)

During navigation, virtual advertising billboards may appear on the map alongside roads. When you approach within 300 m of a billboard, a panel briefly appears below the navigation bar with the ad title and description.

- Tap the panel to open the advertiser's website in the browser
- The panel closes automatically after 12 seconds
- The same billboard does not reappear until 60 seconds have passed
- You can also tap the billboard directly on the map to open its link

### Voice

- TTS engine (Piper / Mimic HTS / PicoTTS)
- Instruction language
- Voice selection
- Piper voice downloads
- Voice test

### Help

- User manual (this documentation)
- Welcome assistant
- "Show assistant on startup" option
- About Navius

---

## Data and privacy

Navius stores the following data **on the device only**:

| Data | Location |
|------|----------|
| Recorded GPS tracks | `~/.local/share/navius.woodyst/gps_tracks.db` |
| Exported GPX files | `~/.local/share/navius.woodyst/gps_tracks/` |
| Favourites, history, preferences | `~/.local/share/navius.woodyst/QtProject/` |
| Per-destination TODOs | SQLite LocalStorage (QtProject) |
| Saved trip plans | Settings (QtProject) |

Place searches are sent to the **Photon/Komoot** geocoder (OpenStreetMap). Route calculations are sent to the configured Valhalla server.

If you use your own Valhalla server, no data leaves the device.
