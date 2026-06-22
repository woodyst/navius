# Navius GPS — Documentación del desarrollador

## Tabla de contenidos

1. [Arquitectura general](#arquitectura-general)
2. [Módulos Rust](#módulos-rust)
3. [Módulos C++](#módulos-c)
4. [Módulos QML](#módulos-qml)
5. [Build y despliegue](#build-y-despliegue)
6. [GPS y lomiri-location-service](#gps-y-lomiri-location-service)
7. [Servidor Valhalla y tráfico](#servidor-valhalla-y-tráfico)
8. [Servidor comunitario Navius](#servidor-comunitario-navius)
9. [TTS (Text-to-Speech)](#tts-text-to-speech)
10. [Persistencia de datos](#persistencia-de-datos)
11. [Ficheros de depuración y control](#ficheros-de-depuración-y-control)
12. [Variables de entorno y depuración](#variables-de-entorno-y-depuración)
13. [Patches LLS](#patches-lls)

---

## Arquitectura general

```
┌─────────────────────────────────────────────────────────┐
│                      QML (UI)                           │
│  Main.qml · SearchPanel · NavBar · PreferencesPanel … │
├─────────────────────────────────────────────────────────┤
│                    Rust (backend)                       │
│  SatelliteModel · NavHttp · NavTts · NavTracker        │
├───────────────────┬─────────────────────────────────────┤
│  C++ (glue)       │  JavaScript (lógica de ruta)        │
│  satellite_source │  NavSearch.js · SimRoute.js         │
│  location_props   │  TodoDB.js                          │
├───────────────────┴─────────────────────────────────────┤
│  lomiri-location-service (D-Bus) · GPS HAL             │
└─────────────────────────────────────────────────────────┘
```

El binario principal es Rust. Se inicializa un `QGuiApplication` y un `QQmlEngine` desde Rust usando el crate `qmetaobject`. Los QObjects Rust se registran en el engine QML antes de cargar `Main.qml` desde el QRC embebido.

La UI es 100% QML + Lomiri Components. La lógica de routing y geocodificación está en `NavSearch.js` (JavaScript en motor QML). La lógica GPS y TTS vive en Rust.

---

## Módulos Rust

### `main.rs`

Punto de entrada. Responsabilidades:

- Inicializar `QGuiApplication` y `QQmlEngine`
- Registrar los tipos QML: `SatelliteModel`, `NavHttp`, `NavTts`, `NavTracker`
- Cargar el QRC embebido (`qrc.rs`)
- Cargar `Main.qml` en el engine

Variables de entorno procesadas aquí: `QML_XHR_ALLOW_FILE_READ=1`, `QML_XHR_ALLOW_FILE_WRITE=1`.

### `satellite_model.rs`

`QObject` expuesto a QML como `SatelliteModel`. Actúa de proxy entre:

- **`SatelliteSource`** (C++): fuente de posición GPS real via Qt Positioning + LLS
- **UI QML**: propiedades observables de posición, precisión, rumbo, velocidad, satélites

Tick a 1 Hz para las propiedades de satélites; tick a 10-30 Hz para la posición interpolada (dead-reckoning gestionado en `GpsSource.qml`).

Propiedades expuestas a QML: `pos_lat`, `pos_lon`, `pos_accuracy`, `pos_speed`, `pos_bearing`, `pos_has_fix`, `sat_count`, `sat_used`, `satellites` (lista JSON).

### `nav_http.rs`

`QObject` para HTTP asíncrono. Wrapper sobre `QNetworkAccessManager`.

- Método: `post(req_id: int, url: string, body: string, content_type: string)`
- Señal: `done(req_id: int, body: string, err: string)`

Usado por `NavSearch.js` para las peticiones a Valhalla (routing) y Photon (geocodificación).

### `nav_tts.rs`

`QObject` para TTS multi-motor. Gestiona tres backends:

| Backend | Implementación |
|---------|---------------|
| Piper | Proceso hijo (`vendor/piper_aarch64/piper`), WAV via stdout |
| Mimic HTS | `extras/mimic/mimic`, WAV via fichero temporal |
| PicoTTS | `pico2wave`, WAV via fichero temporal |

Cola FIFO de textos a reproducir. Pre-generación asíncrona de WAVs de las próximas instrucciones para minimizar latencia.

Métodos expuestos: `say(text)`, `say_with_lang(lang, text)`, `beep()`, `alert_beep()`, `set_engine_override(engine)`, `engine_for_lang(lang)`, `clear_all_tts_cache()`, `get_voice_list()`.

**Mute global (`muted`):** propiedad `qt_property!(bool)`. Cuando es `true`, TODOS los métodos de sonido (`say`, `say_with_lang`, `beep`, `alert_beep`, `reroute_beep`, `play_*`) hacen `return` inmediato sin reproducir nada. En `Main.qml` se ata con un `Binding` a `_soundCap === "silencio"`, de modo que el modo silencio es un mute total — ningún beep o locución suena, incluso los que no tienen guarda en su call-site (p. ej. el beep de recálculo sin internet).

**Fixes de normalización de texto (español):**

- `" 1 km"` → `" un kilómetro"` — evita que el TTS lea "uno kilómetro" en español.
- Ordinales (`º`/`ª`): el parser consume el punto que pudiera seguir al indicador ordinal (ej. `"3º."`, `"4.º"`) para evitar que el motor lo lea como pausa o "punto". Ejemplo: `"3ª."` → `"tercera"` sin punto final.

Ambas transformaciones se aplican en la función de normalización antes de sintetizar, independientemente del motor.

### `nav_tracker.rs`

`QObject` para grabación de tracks GPS en SQLite.

- Base de datos: `~/.local/share/navius.woodyst/gps_tracks.db`
- Tabla `tracks`: `id, name, date_ts, duration_s, dist_m, point_count, route_json`
- Tabla `track_points`: `track_id, seq, lat, lon, spd_kmh, ts`
- Métodos: `start_recording()`, `add_point(lat, lon, spd_kmh, ts)`, `stop_and_save()`, `discard_recording()`, `set_route_json(json)`, `list_tracks_async()`, `get_track_sim_route_async(id)`, `export_gpx_async(id)`, `delete_track_async(id)`, `rename_track(id, name)`, `poll()`. Resultados async vía señales: `tracks_ready`, `sim_route_ready(id, points, route)`, `gpx_ready`, `track_deleted`.

**Ruta Valhalla asociada al track (`route_json`):** al grabar, si hay navegación activa, `Main.qml` llama a `set_route_json(JSON.stringify(_navData))` (al iniciar grabación y en cada recálculo). La ruta Valhalla (shape + maniobras) se guarda en la columna `route_json` de `tracks`. La columna se añade con una migración idempotente (`ALTER TABLE ... ADD COLUMN`, ignorando el error si ya existe) en `open_db()`. `get_track_sim_route_async` devuelve los puntos del track **y** el `route_json` (vacío si el track no tiene ruta — tracks antiguos o grabados sin navegar) en la señal `sim_route_ready(id, points, route)`.

**Dos modos de replay** (elegidos en la lista de tracks de `PreferencesPanel`):

| Modo | Botón | Comportamiento |
|------|-------|----------------|
| Conducción | "Simular" (con `route_json`) | `_startNavigation(rutaGuardada)`: se conduce la ruta Valhalla guardada con el track como fuente de GPS. Snap según `snapToRouteEnabled`, bisector y cálculos idénticos a navegación real. Corrige las anomalías GPS del track al snappear a la vía. |
| GPS crudo | "GPS crudo" (o tracks sin `route_json`) | `_trackReplayRaw = true`: el track es la única geometría (`routeShape` = track, sin snap, línea azul = track). Muestra el recorrido GPS real para diagnóstico del comportamiento del GPS durante la grabación. |

El flag `root._trackReplayRaw` separa ambos caminos en el bloque `_wasTrackReplay` de `_startNavigation`. La señal `trackSimRequested(id, name, raw)` lleva el flag `raw` desde el botón.

### `nav_music.rs`

Biblioteca de música local del sandbox. Gestiona el directorio de pistas y la importación vía Content Hub. Expone cuatro funciones públicas accesibles desde QML a través de `nav_http.rs`:

- `music_dir()` — devuelve (y crea si no existe) `$XDG_DATA_HOME/navius.woodyst/Music/`. **Nota crítica**: en Ubuntu Touch `XDG_DATA_HOME=/home/phablet/.local/share` (sin el package name), por lo que hay que añadir `navius.woodyst` explícitamente; sin eso se apuntaría a `~/.local/share/Music/`, que AppArmor deniega.
- `list_tracks()` — devuelve JSON `[{"name":..,"path":..}]`. Usa `read_dir` + `file_type()` (lstat, sin seguir symlinks) para poder listar symlinks a `~/Music` sin necesitar el policy group `music_files_read`.
- `import_tracks(urls)` — recibe URLs separadas por `\n` de Content Hub. Si la URL pertenece a `HubIncoming` (fichero temporal) → **copia** al sandbox. Si es un fichero externo (p. ej. `~/Music`) → crea un **symlink** en el sandbox apuntando al original; crear un symlink no requiere leer el fichero destino, por lo que AppArmor no lo deniega. Devuelve el número de pistas importadas.
- `remove_track(name)` — `fs::remove_file`; para un symlink elimina solo el enlace sin tocar el fichero real en `~/Music`.

### `qrc.rs`

Macro `qrc!` que embebe todos los ficheros QML y assets en el binario como recursos Qt (QRC). Ver lista completa en el fichero. Al añadir un nuevo fichero QML hay que añadirlo aquí.

---

## Módulos C++

### `satellite_source.h`

Clase `SatelliteSource` (QObject). Fuente GPS que combina:

1. **Qt Positioning + LLS**: posición y fix GPS vía `QLlsPositionInfoSource`
2. **Bridge de satélites**: lee `/run/user/32011/navius.woodyst/navius-sat.txt` como fuente secundaria de datos de satélites cuando LLS no los da

Gestiona la reconexión automática a LLS cuando el servicio se reinicia.

**Bug crítico corregido**: `init_pos_and_session()` conectaba `llsRestarted` en cada llamada, acumulando llamadas `StartPositionUpdates` exponencialmente. Las conexiones se registran una sola vez en `init_sources()`.

**Bug crítico corregido**: `startUpdates()` debe llamarse en el hilo principal (tiene `QEventLoop` interno). Se usa `QMetaObject::invokeMethod` para garantizarlo.

### `location_props.h` / `location_props.cpp`

Clase `LocationPropsWatcher` (QObject). Responsabilidades:

- Polling de `VisibleSpaceVehicles` a LLS vía D-Bus (datos de satélites, método no estándar)
- Detección de reinicio de LLS mediante la señal D-Bus `NameOwnerChanged`
- Señal `llsRestarted()` emitida cuando LLS reaparece en el bus

Cuando `llsRestarted` se emite, `SatelliteSource` recrea la sesión LLS y llama a `startPositionUpdates` de nuevo.

---

## Módulos QML

### `Main.qml`

Ventana raíz. Contiene:

- `ApplicationWindow` con estados `idle`, `navigating`, `parking`
- `Settings id: appSettings` con toda la configuración global
- Instancias de todos los paneles y diálogos (SearchPanel, NavBar, PreferencesPanel, etc.)
- Lógica de navegación: `_startNavigation()`, `_stopNavigation()`, `drawRoute()`, recálculo
- Lógica de TTS: pre-generación de instrucciones (`_pregenerateUpcoming()`), cola de instrucciones
- Gestión de tráfico: `_trafficCheck()`, comparación de rutas alternativas
- Lógica del simulador: `simStart()`, `simStop()`, `_applySimRoute()`

Variables de entorno que activa: `QML_XHR_ALLOW_FILE_READ=1`, `QML_XHR_ALLOW_FILE_WRITE=1`.

**Share de viaje:**

| Elemento | Descripción |
|----------|-------------|
| `_shareToken` | Token del share activo (cadena vacía = no compartiendo) |
| `_shareCreating` | `true` mientras espera respuesta de `POST /share` |
| `shareUpdateTimer` | Timer de 5 s (repeat: true) que llama a `_pushShareUpdate()` |
| `_startSharing()` | Hace `POST /api/v1/share`, guarda el token, abre `TripSharePanel` |
| `_stopSharing()` | Hace `DELETE /api/v1/share/:token`, borra el token |
| `_pushShareUpdate()` | Hace `PUT /api/v1/share/:token/location` con posición, rumbo y estado de ruta |

Si el usuario no tiene sesión, `_startSharing()` abre `LoginPanel` en su lugar.

**Sincronización de settings:**

| Elemento | Descripción |
|----------|-------------|
| `_settingsSyncBlocked` | Bloquea `_onSettingChanged()` durante `_applyServerSettings()` para evitar bucle |
| `settingsSyncTimer` | Timer de 3 s (debounce, repeat: false); se reinicia con cada cambio de setting |
| `_onSettingChanged()` | Llama a `settingsSyncTimer.restart()` si el usuario está logueado |
| `_pushSettingsToServer(silent)` | Hace `PUT /api/v1/settings` con el snapshot de las 41 `SYNC_KEYS` |
| `_pullSettingsFromServer(onConflictCallback)` | Hace `GET /api/v1/settings`; si hay cambios en el servidor y locales sin sincronizar, llama al callback de conflicto |
| `_applyServerSettings(data)` | Activa `_settingsSyncBlocked`, aplica `NavSettings.applySnapshot()`, desactiva flag |
| `settingsConflictDialog` | Dialog que permite elegir entre "Usar servidor" o "Mantener local" cuando hay conflicto |

**`mainAuthSettings`** (`Settings { category: "auth" }`):

| Propiedad | Tipo | Descripción |
|-----------|------|-------------|
| `token` | string | JWT de la sesión activa (vacío = no logueado) |
| `email` | string | Email del usuario logueado |
| `recordar` | bool | Recordar la sesión entre arranques |
| `userId` | int | ID numérico del usuario (obtenido del JWT `sub`) |
| `settingsChangedSinceSync` | bool | Hay cambios locales no subidos al servidor |
| `settingsLastSyncAt` | string | ISO de la última sincronización correcta |

**Offline reroute guard:**

`_rerouteBeepedOffline: bool` — se activa cuando se intenta recalcular sin internet y ya se ha emitido el pitido de aviso. Se resetea al recuperar conexión. Evita pitidos repetitivos.

**Route proximity filter — `_routeInfo(lat, lon, margin)`:**

Proyecta el punto `(lat, lon)` sobre la polilínea de la ruta activa. Devuelve `{ onRoute: bool, arcDist: real }` donde `arcDist` es la distancia geodésica (metros) desde el punto proyectado hasta el inicio de la ruta. `margin` (metros) es la tolerancia de proximidad transversal. Usado por el sistema de alertas comunitarias para filtrar alertas fuera de la ruta.

**Alertas comunitarias:**

| Elemento | Descripción |
|----------|-------------|
| `_commAlertas[]` | Array de alertas activas `{lat, lng, categoria, subtipo, ...}` cargadas del servidor |
| `_checkCommAlerts()` | Itera `_commAlertas` y emite avisos TTS/visuales al aproximarse; usa `_routeInfo()` para filtrar por ruta |

Las alertas solo se muestran en el mapa si el usuario está logueado (`mainAuthSettings.token !== ""`).

**Modos de mapa — `mapView.applyLightMode()`:**

| `mapStyleMode` | Estilo aplicado |
|----------------|-----------------|
| `"satellite"` | `satelliteStyleUrl` (raster ArcGIS) |
| `"positron"` | `positronUrl` (Carto o navius-maps) |
| `"bright"` | `brightUrl` (OpenFreeMap o navius-maps) |
| `"fiord"` | `fiordUrl` (navius-maps, solo si servidor Navius) |
| `"dark"` | `darkUrl` (navius-maps, solo si servidor Navius) |
| `"auto"` + `lightMode="night"` | `darkUrl` (noche explícita, intenso) |
| `"auto"` + noche solar | `nightUrl` = `fiordUrl` (noche suave auto) |
| `"auto"` + día | `dayUrl` (liberty) |

`darkUrl` y `nightUrl` son propiedades separadas: `darkUrl` apunta al estilo `dark` del servidor navius; `nightUrl` apunta a `fiordUrl` (más suave). Esto es importante: el modo **Auto** de noche usa Fiord, no Dark.

El selector de estilo en el mapa (`mapStyleBtn`) cicla por los estilos disponibles según `mapView._navius` (si el servidor configurado es navius-maps) y `mapNaviusStyles` (JSON array de estilos extra disponibles).

**Menú principal — orden de ítems:**

| Posición | Ítem | Condición de visibilidad |
|----------|------|--------------------------|
| 1 | Cuenta / Login | Siempre |
| 2 | Compartir viaje / Compartiendo | Siempre |
| 3 | Prev. Ruta | Solo si hay navegación activa |
| 4 | Tareas | Siempre |
| 5 | Mensajes | Siempre |
| 6 | Música | Siempre |
| 7 | Parking (Guardar / Borrar / Ver vehículo / Ir al aparcamiento) | Según estado del vehículo activo |
| 8 | Ajustes | Siempre |
| 9 | Bloq. Mapa | Siempre |
| 10 | Debug | Siempre |
| 11 | Simulación GPS | Siempre |

### `GpsSource.qml`

Abstracción GPS unificada que combina:

- Fix real (via `SatelliteModel`)
- Simulación GPS (ruta sintetizada, modelo tiempo-distancia)
- Dead-reckoning (interpolación de posición entre fixes reales)
- Modo manual (posición fija de depuración)

Proporciona a `Main.qml` un flujo de posiciones a 10-30 Hz independientemente de la fuente.

**Velocidad en GPS real (`_onRealGpsTick`):**  
Controlado por `useHardwareSpeed` (binding a `appSettings.useHardwareSpeed`, default `true`).

- `true`: usa `satModel.pos_speed_kmh` (velocidad Doppler del chip). El hardware calcula la velocidad por desplazamiento de frecuencia de la señal satelital; es más precisa que d/dt a baja velocidad y en cambios bruscos.
- `false`: calcula `_speedMs = haversineM(p1, p2) / dt` (diferencia de posiciones consecutivas).

El rumbo (`_headRad`) y la aceleración (`_accelMss`) se calculan siempre por d/dt de posiciones, ya que el Doppler no proporciona heading. Si `hwSpeedKmh < 0` (chip sin fix Doppler), se usa d/dt como fallback incluso con `useHardwareSpeed = true`.

**Simulación GPS (`_simAdvance`):**  
Modelo tiempo-distancia. `_simDistM` acumula metros recorridos; la posición se interpola sobre `_simRouteCumDistM` (distancias acumuladas precalculadas en `simStart()`). Velocidad efectiva: `commSpeedLimitKmh > 0 ? commLimit : routeSpd`, multiplicada por `simSpeedBias`. Garantiza que ticks primarios e interpolados usen exactamente la misma velocidad.

**Bearing del mapa — anticipación de ruta:**

*Objetivo:* el mapa debe apuntar hacia el centro angular de la ruta visible por delante, anticipando los giros con `routeAheadSecs` segundos de antelación. El ángulo objetivo no es el heading GPS actual, sino el ángulo absoluto que centra simétricamente la ruta visible en pantalla. El mapa persigue ese objetivo suavemente, sin saltos bruscos en ticks reales.

*Implementación con ruta sim (`simRoutePoints` disponible):*

1. **`_simWantedVisibleAheadDistM(secsAhead)`** — calcula cuántos metros de ruta sim se recorrerán en `secsAhead` segundos. Aplica un ratio `_speedMs / valhallaSpeed` (clamped 0.1–3.0) dividiendo los timestamps reales de cada tramo por ese ratio: si se va más rápido que Valhalla predice, la distancia visible aumenta proporcionalmente.

2. **`_simRouteIdealBisectorRad(distM, mapBearingRad)`** — recorre `simRoutePoints` desde `simIdx` hasta `distM` metros. Para cada punto calcula el **ángulo desde el vehículo al punto** (no el rumbo del segmento), relativo a `mapBearingRad`. Identifica el punto más a la izquierda (`bisectorMinPt`, rojo en el overlay), el más a la derecha (`bisectorMaxPt`, azul) y el punto de la ruta más cercano al ángulo central (`bisectorCtrPt`, verde). Los tres son puntos reales de la ruta → siempre sobre la vía, y el verde siempre entre rojo y azul. Devuelve `mapBearingRad + (minRel + maxRel) / 2` — el **ángulo objetivo** del mapa.

3. **Persecución suave en dos etapas en `onGpsTick` (Main.qml)** — el target se recalcula en cada tick:
   - **Etapa 1 (target):** `_smoothMapTgt` persigue el bisector crudo con τ = 0.8 s.
   - **Etapa 2 (pursuit):** `_mapBearingDeg` (lo que se escribe en `mapView.bearing`) persigue `_smoothMapTgt` con τ = 0.15 s.

   ⚠️ **`_bdt` debe ser el tiempo REAL transcurrido**, no el periodo nominal del timer. El timer QML dispara a ~8 Hz aunque `drHz` valga 30; si se capa `_bdt` a `1/drHz` (≈0.033 s), los suavizados exponenciales integran el tiempo ~4× más lento (τ efectivo ~3 s en vez de 0.8 s) y el mapa se arrastra ~15° por detrás en curva. Se usa `_bdt = min(now - _lastBearingMs, 0.5)` (tope 0.5 s solo anti-salto tras pausa). La misma trampa aparece en la interpolación de posición y en el rate-limit de la flecha.

*Fallback sin ruta sim:* si `simRoutePoints` es null pero hay `navBar.routeData`, se usa el punto a `distM/2` metros adelante sobre el shape Valhalla (es el camino del modo "conducción" y del replay con ruta Valhalla guardada). Si no hay ninguna ruta, se usa `mapHeadRad` (heading de la calzada en el snap, solo ticks reales).

**Snap a ruta — `snapToRouteEnabled` y `snapDistM`:**

El snap es la proyección del GPS sobre el shape de la ruta activa. Controla tanto el display como la base de la interpolación.

- `snapToRouteEnabled` (bool, binding a `appSettings.snapToRouteEnabled`): activa/desactiva el snap.
- `snapDistM` (real, binding a `appSettings.snapDistM`, default 8 m): distancia máxima GPS→shape para que el snap se aplique.
- `_snapActive` (bool interno): se recalcula en cada tick real. `true` solo si `snapToRouteEnabled && dist(GPS, snapPoint) ≤ snapDistM`.

Cuando `_snapActive = false`:
- `_lastRealTickPos.lat/lon` = posición GPS cruda (no snapada).
- `_onInterpTick` entra en la rama de dead reckoning (desde `_drBaseLat/Lon`), no en shape-walking.
- El vehículo se muestra en la posición GPS real y los ticks interp siguen la dirección de marcha.

`_updateShapePos` siempre se llama (necesario para ETA y detección de maniobras), pero su resultado solo se usa en posición si `_snapActive = true`.

**Snap acotado al leg activo — `routeShapeLegEnd`:**

En rutas multi-parada, el shape global concatena todos los legs. Sin límite, `_updateShapePos` puede engancharse al inicio del leg siguiente cuando el GPS se aproxima al cruce de una parada intermedia.

- `routeShapeLegEnd` (int, −1 = sin límite): índice final del leg activo en `routeShape`. Se inicializa a `legShapeEnds[0]` al arrancar la nav y avanza a `legShapeEnds[N]` en cada `onIntermediateArrived`. Se resetea a −1 en `onRouteShapeChanged`.
- `_updateShapePos` limita `end = min(_shapeIdx + 200, routeShapeLegEnd)`.
- `_snapToRoute` itera solo hasta `routeShapeLegEnd`.

### `NavSearch.js`

Motor de búsqueda y routing. Funciones principales:

- `geocode(query, lat, lon, cb)`: geocodificación vía Photon (`navius-maps.egpsistemas.com/photon`, instancia propia con índice mundial)
- `route(waypoints, opts, cb)`: cálculo de ruta con Valhalla; incluye `date_time` para tráfico predicho
- `trace_attributes(shape, cb)`: obtiene límites de velocidad por tramo de ruta
- `detectOsmScout(cb)`: detecta si hay un servidor OSM Scout local
- `fetchPoisAlongRoute(category, cb)`: consulta Overpass para POIs a lo largo de la ruta; servidor elegido por el centro geográfico de la ruta (`navius-maps.egpsistemas.com/overpass/` para España, pool público para el resto del mundo); reintenta con el siguiente servidor si devuelve 0 resultados
- `probeOverpassServers()`: llamada al arrancar — sondea servidores candidatos y construye `_overpassActivePool`

La función `route()` envía `date_time: {type: 0, value: "current"}` (ruta inmediata) o `{type: 1, value: "YYYY-MM-DDTHH:MM"}` (ruta programada).

### `SearchPanel.qml`

Panel de planificación de ruta. State machine de destinos `_dests: [{lat, lon, name, todos:[{text, done}]}]`.

Secciones:
- Planes guardados (parte superior)
- Lista de destinos con TODOs expandibles
- POI cercanos por categoría
- Hora de salida (stickyBottom)
- Botón CALCULAR RUTA + guardar plan (stickyBottom)

Settings: `planSt.json` (planes), `nav.*` (waypoints actuales).

### `NavBar.qml`

Barra de navegación activa. Muestra instrucción actual, distancia, ETA, velocidad, límite de velocidad. Gestiona el avance por los steps de la ruta según la posición GPS.

**Límites de velocidad — lógica de prioridad:**

`_effLimit` — límite que se muestra en la señal de velocidad de la barra de navegación:

```
commSpeedLimit > 0  →  commSpeedLimit
    else radarMaxspeed > 0  →  radarMaxspeed
    else (showRoadSpeedLimit && _speedLimit > 0)  →  _speedLimit
    else  →  0 (sin límite visible)
```

`_colorLimit` — límite usado para colorear el velocímetro (alerta visual):

```
radarMaxspeed > 0  →  radarMaxspeed
    else commSpeedLimit > 0  →  commSpeedLimit
    else (showRoadSpeedLimit && commAlertSpeed > 0)  →  commAlertSpeed
    else (showRoadSpeedLimit && _speedLimit > 0)  →  _speedLimit
    else  →  0 (sin alerta de color)
```

La diferencia clave: `_colorLimit` pone el radar por encima del límite comunitario (el radar es más preciso geográficamente); `_effLimit` pone el comunitario primero (el usuario puede haberlo ajustado manualmente).

Si `showRoadSpeedLimit` está desactivado (valor por defecto), los límites de la vía OSM (`_speedLimit`) no producen ni señal ni alerta de color.

**ETA en la barra:**

La línea de resumen del tramo actual muestra:
```
NavSearch.formatDist(_legDistKm) · NavSearch.formatTime(_legTimeSec) · NavSearch.formatEta(_legTimeSec)
```
La línea total (destino final):
```
NavSearch.formatDist(_distKm) · NavSearch.formatTime(_timeSec) · NavSearch.formatEta(_timeSec)
```
`NavSearch.formatEta(segundos)` calcula la hora de llegada sumando los segundos a `Date()` actual y la formatea como `HH:MM`.

**Navegación multi-parada — aislamiento del leg activo:**

El shape de ruta (`routeData.shape`) es un array único que concatena todos los legs. `legShapeEnds[i]` es el índice del último punto del leg `i`. NavBar usa `_legEndIdx = legShapeEnds[_completedLegs]` para acotar todas las operaciones al leg activo:

- **Snap y off-route** (`update()`): búsqueda limitada a `[start, _legEndIdx]`. No puede engancharse a legs futuros.
- **Wrong-direction**: usa el `minI` del snap acotado → también limitado al leg activo.
- **Detección de llegada**: calcula `_distToLegEnd` al punto `shape[_legEndIdx]` (waypoint del leg activo).
- **`nearDest`**: suprime off-route y wrong-direction cuando `_step >= última maniobra del leg` OR `_legArrivalPending` OR `_distToLegEnd < 150 m`. Los 150 m evitan rerouting espúreo por deriva GPS en el cruce de la parada intermedia.
- **Rerouting** (`offRoute()`): recalcula todos los waypoints restantes (desde la posición actual hasta el destino final), no solo el leg activo.

Flujo de confirmación de llegada:
1. `_distToLegEnd ≤ 10 m` / rebaso / parado >5 s cerca → `legArrivalReached(legIdx, isFinal)` → `legArrivalBanner`.
2. Usuario confirma → `confirmLegArrival()` → `_completedLegs++`; si es el último leg → `arrived()`.
3. `intermediateArrived(waypointIndex)` → Main.qml avanza `gpsSource.routeShapeLegEnd` al nuevo leg.
4. NavBar se rearma (`_legArrivalArmed = true`) para el siguiente leg.

### `PreferencesPanel.qml`

Panel de ajustes con secciones colapsables. El estado de apertura/cierre de cada sección se persiste en `Settings { category: "PrefPanelSections" }`.

Señales emitidas hacia `Main.qml`: `soundTest`, `langChanged`, `lightModeApplied`, `simToggled`, `voicesRequested`, `voiceSelected`, `engineChanged`, `helpRequested`, `aboutRequested`, `tourRequested`, etc.

**Nivel de opciones (`prefLevel`):**

`appSettings.prefLevel` controla qué secciones y controles son visibles:
- `0` = Mínimo: solo `_sectionMinLevel: 0` visibles
- `1` = Medio: `_sectionMinLevel` 0 y 1 visibles
- `2` = Avanzado: todo visible

Cada sección declarable tiene `property int _sectionMinLevel` y `property bool hasContent: panel.cfg.prefLevel >= _sectionMinLevel`. Las secciones con `hasContent = false` no se renderizan.

**Controles numéricos:**
Se usan botones `[−]` / `[+]` (steppers) en lugar de `Slider`. Motivo: en Lomiri/QML los Sliders capturan el scroll vertical del `Flickable` padre cuando el usuario hace scroll por el panel, cambiando el valor accidentalmente.

**Indicador de valor por defecto:**
Junto a cada control numérico o de selección se muestra `↺ <valor_defecto>` cuando el valor actual difiere del predeterminado. Si el valor ya es el default, el indicador no aparece.

**Restaurar valores:**
Botón doble-confirmación en la cabecera del panel. Primer toque: estado `_confirm = true`, muestra "⚠ Restaurar valores por defecto". Segundo toque en ≤3 s: aplica `resetAllToDefaults()`. Timer de 3 s resetea `_confirm` a `false` si no se confirma.

### `NavSettings.js`

`.pragma library` — settings sync con el servidor comunitario.

- `SYNC_KEYS` — array con las 41 claves sincronizables (mapa, rutas, GPS, velocidad/radar, voz/sonido, UI, vehículos). Las claves son lógicas e independientes de la categoría Qt Settings: si un setting cambia de categoría en la app, la clave del servidor no cambia.
- `snapshot(s)` — extrae un objeto `{clave: valor}` de `appSettings` para las 41 claves. Listo para enviar al servidor.
- `applySnapshot(s, data)` — aplica datos del servidor a `appSettings`. Ignora claves desconocidas. Convierte tipos según el valor local actual (bool, number, string) para robustez ante datos de versión anterior.
- `getSettings(token, callback)` — `GET /api/v1/settings`. Callback: `(ok, settingsObj, updatedAt, errCode)`. Códigos de error: `""` ok, `"net"` sin red, `"401"` no autenticado, `"404"` servidor sin soporte, otro número = código HTTP.
- `putSettings(token, settingsObj, callback)` — `PUT /api/v1/settings`. Callback: `(ok, errCode)`.
- `serverUrl()` / `setServerUrl(u)` — URL del servidor (por defecto `https://navius-api.egpsistemas.com`).
- `_xhr(method, url, token, body, callback)` — helper XHR con workaround Qt 5.12: guarda status y responseText intermedios porque en errores 4xx/5xx llegan a 0/"" en `readyState=4`.

### `AlertasOverlay.qml`

Overlay de alertas comunitarias sobre el mapa. Muestra los marcadores de alertas activas `_commAlertas[]` como iconos coloreados. Al tocar un marcador muestra un popup con categoría, subtipo y tiempo desde creación. Incluye el botón para reportar una nueva alerta (requiere login).

### `NavAlerts.js`

`.pragma library` — lógica de alertas comunitarias.

- Fetch de alertas en el bounding box del mapa desde el servidor (`GET /api/v1/alertas`).
- Conversión de alertas a marcadores QML con icono correspondiente (assets `alertas/*.png`).
- `jwtSub(token)` — extrae el campo `sub` (userId) del JWT sin verificar firma (solo para uso interno).
- Lógica de votación: confirmar / desmentir alerta (`POST /api/v1/alertas/:id/voto`).

### `LoginPanel.qml`

Panel de login y registro con el servidor Navius. Modos: login (email + contraseña), registro (email + contraseña), recuperación de contraseña. Al hacer login exitoso guarda el JWT en `mainAuthSettings.token` y el email en `mainAuthSettings.email`. Si hay ajustes en el servidor diferentes a los locales, dispara `_pullSettingsFromServer()` con callback de conflicto.

### `TripSharePanel.qml`

Panel inferior de compartir viaje. Propiedades: `shareUrl`, `creating`, `active`. Señales: `createRequested()`, `stopRequested()`, `dismissed()`.

Estados visuales:
- **Sin share activo**: descripción, botón "Crear enlace"
- **Creando**: spinner textual "Generando enlace…"
- **Share activo**: muestra la URL con campo copiable (botón Copiar con feedback 2 s), botón "Abrir en navegador" y botón "Detener" (rojo)

El panel no cierra al tocar fuera. El único punto de salida es el botón "Cerrar".

### `MediaPanel.qml`

Panel de reproducción de música integrado. La música entra al sandbox vía **Content Hub**; la reproducción usa `file://` desde el directorio propio de la app (`~/.local/share/navius.woodyst/Music/`), que media-hub permite por su allowlist.

- `property var navHttpObj` — referencia al objeto `NavHttp` de Rust; expone `music_dir`, `music_list`, `music_import`, `music_remove`.
- `ListModel { id: musicModel }` con campos `name` y `path`. Se rellena en `reloadLibrary()` parseando el JSON de `navHttpObj.music_list()`. Se refresca automáticamente al hacerse visible el panel.
- `ContentPeerPicker { contentType: ContentType.Music; handler: ContentHandler.Source }` — lanza el gestor de archivos en modo Content Hub. `peer.selectionType = ContentTransfer.Multiple` permite seleccionar varias pistas a la vez.
- `Connections { target: root.activeTransfer; onStateChanged }` — cuando el transfer pasa a `Charged`, recorre `activeTransfer.items`, llama `navHttpObj.music_import(urls)` y luego `activeTransfer.finalize()`.
- Componente `Audio` (QtMultimedia 5.6): `player.source = "file://" + path`.
- Ducking TTS: `duck(bool)` ajusta el volumen vía PulseAudio (`ttsObj.set_music_volume`), 600 ms de retardo al restaurar.
- Sección de ayuda expandible con el comando `find ~/Music … -exec ln -s {} musicdir/ \;` para crear symlinks manuales desde terminal sin duplicar ficheros.

### `MediaWidget.qml`

Barra compacta visible sobre `statusBar` cuando hay una pista cargada. Muestra nombre de pista y controles básicos (anterior, play/pause, siguiente, cerrar). Desaparece al detener la música o cerrar el reproductor.

### `RouteSelectPanel.qml`

Panel que muestra hasta 3 alternativas de ruta calculadas por Valhalla. Para cada alternativa muestra distancia, tiempo estimado y perfil de velocidad del tramo. Permite cambiar el tipo de vehículo, ver las instrucciones completas (`InstructionListPanel`) o iniciar la navegación.

### `RouteViewPanel.qml`

Panel de resumen de ruta activa. Muestra la lista de paradas con distancia y tiempo a cada una. Accesible durante la navegación.

### `SatelliteView.qml`

Vista de satélites GPS. Dibuja sobre un `Canvas`:
- Vista polar acimutal (azimut/elevación) de todos los satélites visibles
- Barras SNR codificadas por color (verde = en uso, gris = visible pero no usado)
- Texto con número de satélites visibles / en uso y estado del fix (sin fix / 2D / 3D)

Datos recibidos de `satModel.satellites` (JSON array actualizado a 1 Hz).

### `SpeedView.qml`

Velocímetro circular superpuesto al mapa. Muestra la velocidad actual en km/h. El color del indicador cambia según `_overLimit` (calculado en `NavBar.qml` comparando velocidad con `_colorLimit`). Visible durante y fuera de navegación activa.

### `OfflineBanner.qml`

Banner que aparece en la parte superior cuando no hay conexión a internet. La detección se hace cada 6-30 s (intervalo adaptativo). Desaparece automáticamente al recuperar conexión. No bloquea la UI.

### `NavMessages.js`

`.pragma library` — lógica de mensajes del servidor.

- `fetchMsgs(deviceId, token, sinceId, callback)` — `GET /api/v1/mensajes` con parámetros de paginación. Devuelve array de mensajes nuevos.
- Marca mensajes como leídos: `POST /api/v1/mensajes/:id/leido`.
- Marca mensajes como eliminados (soft delete por dispositivo): `POST /api/v1/mensajes/:id/eliminado`.

### `MessagesPanel.qml`

Panel de mensajes del servidor (broadcast, por usuario o por dispositivo). Lista scrollable con badge de no leídos. Soporte para mensajes con enlace web y con destino de navegación (botón "Ir"). Abre `MsgDetailPopup` al tocar un mensaje.

### `MsgDetailPopup.qml`

Popup modal con el detalle completo de un mensaje: título, tipo/importancia, cuerpo completo, fecha, enlace web (abre en navegador) y botón de destino de navegación si el mensaje tiene coordenadas.

### `VehicleSetupDialog.qml`

Dialog de gestión de vehículos propios. Permite crear, renombrar y eliminar vehículos con alias y tipo (costing Valhalla: `auto`, `motorcycle`, `bicycle`, `pedestrian`, `truck`, etc.). El vehículo activo es el que se usa para el routing y el parking. Los datos se persisten en `appSettings.vehiclesJson` (JSON array, también sincronizado al servidor via `SYNC_KEYS`).

### `ParkingDialog.qml`

Dialog de aparcamiento con dos modos:
- **Guardar**: registra lat/lon actuales como posición de aparcamiento del vehículo activo.
- **Navegar**: permite seleccionar entre todos los vehículos con parking guardado y añade el destino al planificador de ruta.

### `InstructionListPanel.qml`

Panel con la lista completa de instrucciones de la ruta activa. Muestra icono de maniobra, texto y distancia para cada step. Se abre desde el botón "Ver instrucciones" en `RouteSelectPanel` y desde la barra de navegación. Al tocar un step, el mapa se centra en esa posición.

### `StopTodoPanel.qml`

Panel que muestra los TODOs pendientes de la parada actual al llegar al destino. Permite marcar cada tarea como completada. Se integra con `TodoDB.js` para leer/escribir el estado de las tareas.

### `CompassWidget.qml`

Widget de brújula superpuesto al mapa. Muestra la orientación actual del mapa y, al tocarlo, resetea el norte y activa el follow mode.

### `NaviusLogo.qml`

Componente de logo vectorial Navius (carga `assets/logo.svg`). Usado en la splash y en el `AboutDialog`.

### `BtnLabel.qml`

Componente reutilizable para etiquetas de botón con texto, icono opcional y estado de presionado. Simplifica la consistencia visual de los botones del menú principal.

### `OsmScoutDialog.qml`

Dialog de configuración del servidor OSM Scout local. Muestra el estado de detección y permite forzar la URL manualmente.

### `RouteRestoreDialog.qml`

Dialog que aparece al arrancar si `navius_route` tiene `wasNavigating=true`. Pregunta si restaurar la navegación anterior. Si el usuario acepta, recalcula la ruta desde la posición actual.

### `SharedLocationDialog.qml`

Dialog para compartir la posición actual como enlace puntual (no share de viaje en tiempo real). Genera una URL estática con las coordenadas actuales.

### `GoogleMapsPanel.qml`

Panel que permite abrir la posición actual o un destino buscado en Google Maps en el navegador externo.

### `TtsVoicesPanel.qml`

Panel de descarga y gestión de voces Piper. Lista las voces disponibles en el servidor de voces, muestra las descargadas y permite descargar/eliminar voces individuales.

### `TrafficRouteDialog.qml`

Dialog que muestra la comparación entre la ruta actual y una alternativa más rápida encontrada por el sistema de tráfico. Permite aceptar la alternativa o mantener la ruta actual.

### `TourOverlay.qml`

Tour interactivo multi-paso (20 pasos). Se muestra automáticamente al inicio si `tourSettings.showOnStart` es true. Pasos: bienvenida, mapa, búsqueda, planificación, TODOs, hora de salida, selección de ruta, navegación, alertas comunitarias, compartir viaje, TTS, reproductor de música, velocímetro, mensajes del servidor, satélites, grabación de tracks, servidor Valhalla, ajustes, despedida.

### `AboutDialog.qml`

Dialog modal con información de la app: nombre, descripción, servidor oficial Valhalla y sus características, stack tecnológico, licencia.

### `HelpPanel.qml`

Panel de ayuda en formato Q&A por secciones. Cubre todas las funciones de usuario excepto depuración.

### `WhatsNewDialog.qml`

Dialog de novedades. Se muestra al inicio si `lastSeenVersion !== currentVersion`. Tiene lógica de versión basada en timestamp (`"YYYY-MM-DD HH:mm:ss"`).

---

## Build y despliegue

### Requisitos

- [Clickable](https://clickable-ut.dev/) ≥ 8.7.0
- Docker con imagen de build Ubuntu Touch aarch64

### Compilar

```bash
# Para dispositivo aarch64
clickable build

# Sólo la librería Mimic HTS
bash compilar_solo_mimic.sh
```

### Desplegar

```bash
clickable install    # instala el .click en el dispositivo conectado por USB
clickable launch     # lanza la app en el dispositivo
```

**Siempre matar la instancia anterior antes de lanzar**:

```bash
ssh phablet@<ip> "kill \$(pgrep -x navius)"
```

### Postbuild (`clickable.yaml`)

El paso `postbuild` empaqueta automáticamente:

- `espeak-ng` + datos (pronunciación para Piper)
- Binario `piper` y sus librerías (`vendor/piper_aarch64/`)
- PicoTTS compilado (`vendor/picotts/`)
- Mimic HTS + voz española (`vendor/mimic_hts/` + `extras/mimic/`)
- `libpcaudio_stub.so` (audio PCM sin PulseAudio)
- `libpiper_limit.so` (limita CPU de Piper via `setrlimit`)
- `libQMapLibre.so` + plugin `MapboxMap`

### Añadir un nuevo fichero QML

1. Crear el fichero en `qml/`
2. Añadirlo a `src/qrc.rs` en la macro `qrc!`
3. Instanciarlo en `Main.qml` o en el panel correspondiente

---

## GPS y lomiri-location-service

Navius usa [lomiri-location-service](https://gitlab.com/ubports/development/core/lomiri-location-service) (LLS) como backend GPS vía D-Bus.

Se distribuye un paquete parcheado (`3.4.1+navius6`) que corrige múltiples problemas con HALIUM_10 y Waydroid.

### Stack de posicionamiento

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
GpsSource.qml (dead-reckoning + interpolación)
    ↓
Main.qml / NavBar.qml
```

### Activar trazas de depuración

```cpp
// src/location_props.h
static constexpr bool NAVIUS_DEBUG = true;   // trazas navius en stderr

// lomiri-location-service/include/.../lls_trace.h
static constexpr bool LLS_DEBUG = true;      // trazas LLS en stderr
```

```bash
# Ver log en dispositivo
ssh phablet@<ip> "journalctl --user -f -u navius.woodyst_navius.desktop"
```

---

## Servidor Valhalla y tráfico

### Formato de petición de ruta

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
    date_time: { type: 0, value: "current" }  // o type: 1 con valor ISO
}
```

`date_time.type`:
- `0`: hora actual
- `1`: hora de salida (`value: "2026-05-20T08:30"`)
- `2`: hora de llegada

### Tráfico predicho

El servidor valhalla.egpsistemas.com tiene tráfico predicho generado con perfiles sintéticos:

| Nivel | Tipo de vía | Free-flow | Punta | Noche |
|-------|-------------|-----------|-------|-------|
| 0 | Autopistas/autovías | 115 km/h | 85 | 110 |
| 1 | Primarias/secundarias | 85 km/h | 55 | 80 |
| 2 | Locales/residenciales | 45 km/h | 25 | 40 |

Horas punta: Lu-Vi 7-9h y 17-19h (fade parabólico). El tráfico se codifica en 2016 buckets DCT-II por tile.

---

## Servidor comunitario Navius

Código en `navius_server/` (repositorio separado). Servidor REST para alertas, usuarios, settings sync, share de viaje y mensajes push.

### Stack

| Componente | Versión / rol |
|------------|--------------|
| Rust + Axum | Framework web async |
| SQLx | ORM async para MariaDB |
| MariaDB 11 | Base de datos principal |
| Redis | Estado de shares activos (TTL 24 h, clave `share:<token>`) |
| Docker Compose | Deploy en servidor |

### Endpoints por módulo

Todos los endpoints autenticados requieren `Authorization: Bearer <jwt>` en la cabecera.

**Usuarios (`/api/v1/usuarios`)**

| Método | Ruta | Auth | Descripción |
|--------|------|------|-------------|
| POST | `/api/v1/usuarios/registro` | No | Registro con email + contraseña |
| POST | `/api/v1/usuarios/login` | No | Login; devuelve JWT |
| GET | `/api/v1/usuarios/verificar/:token` | No | Verificación de email |
| POST | `/api/v1/usuarios/refresh` | No | Renueva token expirado (hasta 90 días tras la caducidad); devuelve nuevo JWT |

**Renovación de token (`POST /api/v1/usuarios/refresh`)**

| Campo | Valor |
|-------|-------|
| Auth | `Authorization: Bearer <token_expirado>` |
| Condición | El token puede estar caducado pero no más de 90 días |
| Respuesta | `{ "token": "<nuevo_jwt>" }` |

La renovación se hace sin relogin: se envía el JWT expirado (con firma válida) en la cabecera. El servidor valida la firma con `validate_exp = false`, verifica que el usuario aún existe y que el token no lleva más de 90 días caducado, y devuelve un nuevo JWT.

La app llama a `_refreshToken()` en `Main.qml` cuando el endpoint de share responde 401. Si el refresh es exitoso, reintenta la operación original una sola vez.

**Alertas (`/api/v1/alertas`)**

| Método | Ruta | Auth | Descripción |
|--------|------|------|-------------|
| GET | `/api/v1/alertas` | Sí | Alertas activas en bounding box (`?lat_min=…&lat_max=…&lng_min=…&lng_max=…`) |
| POST | `/api/v1/alertas` | Sí | Crear alerta |
| POST | `/api/v1/alertas/:id/voto` | Sí | Confirmar (1) o desmentir (0) alerta |
| DELETE | `/api/v1/alertas/:id` | Sí | Desactivar alerta propia |

**Settings (`/api/v1/settings`)**

| Método | Ruta | Auth | Descripción |
|--------|------|------|-------------|
| GET | `/api/v1/settings` | Sí | Obtiene `{settings: {clave: valor}, updated_at}` |
| PUT | `/api/v1/settings` | Sí | Upsert de settings `{settings: {clave: valor, …}}` (por clave) |

Las claves deben ser alfanuméricas + guión bajo, máx. 120 caracteres. El upsert es atómico por clave.

**Share (`/api/v1/share`)**

| Método | Ruta | Auth | Descripción |
|--------|------|------|-------------|
| POST | `/api/v1/share` | Sí | Crea share; si ya existe uno lo borra primero. Devuelve `{token, url}` |
| PUT | `/api/v1/share/:token/location` | Sí | Actualiza posición + estado de ruta en Redis |
| GET | `/api/v1/share/:token/state` | No | Devuelve estado actual del share (posición, ruta, destino) |
| DELETE | `/api/v1/share/:token` | Sí | Revoca el share (borra Redis + DB) |
| GET | `/share/:token` | No | Página HTML del seguidor (viewer) |

El estado del share se guarda solo en Redis con TTL de 24 h. La tabla `shares` en MariaDB guarda la asignación token↔usuario para permitir un solo share activo por usuario.

**Visor de viaje compartido (`GET /share/:token`)**

El visor es una SPA HTML incrustada en el binario Rust. Stack técnico:

| Tecnología | Versión/Uso |
|-----------|-------------|
| MapLibre GL JS | v4 (CDN jsdelivr) |
| Tiles vectoriales | `navius-maps.egpsistemas.com` (Liberty, Fiord, Positron, Bright) |
| Polling | `GET /api/v1/share/:token/state` cada 5 s |
| Cache Redis | TTL 24 h por token |

**Funcionalidades del visor:**
- Marcador de posición: elemento DOM personalizado separando transformación de posición (MapLibre `Marker`) de la rotación del icono (CSS `transform` en el elemento interior). Esto evita el conflicto entre el `translate` de MapLibre y el `rotate` del CSS.
- **Auto-follow**: activo por defecto; se desactiva con `dragstart` del mapa. Se reactiva con el botón Centrar (◎).
- **Selector de estilo**: Auto / Noche (Fiord) / Día (Liberty) / Positron / Bright. El cambio de estilo llama a `map.setStyle()`, lo que destruye las capas y fuentes. Se usa el evento `idle` (más fiable que `load`) para re-añadir la capa de ruta tras el cambio de estilo, con `routeReady = false` como flag.
- **`trimToRemaining(coords, lng, lat)`**: recorta el shape de la ruta para mostrar solo el tramo desde la posición actual hacia adelante. Proyecta el punto actual sobre el polyline usando distancia euclídea en coordenadas esféricas (corregida por `cos(lat)` para las longitudes).
- **Shape de ruta**: enviado en `PUT /location` como `route_shape: [[lon, lat], ...]` con hasta 10.000 puntos (≈200 KB por actualización cada 5 s).

**Mensajes (`/api/v1/mensajes`)**

| Método | Ruta | Auth | Descripción |
|--------|------|------|-------------|
| GET | `/api/v1/mensajes` | Sí | Mensajes dirigidos al dispositivo o usuario (broadcast incluido) |
| POST | `/api/v1/mensajes/:id/leido` | Sí | Marca el mensaje como leído |
| POST | `/api/v1/mensajes/:id/eliminado` | Sí | Soft delete por dispositivo |

**Límites de velocidad (`/api/v1/limites`)**

| Método | Ruta | Auth | Descripción |
|--------|------|------|-------------|
| GET | `/api/v1/limites` | Sí | Límites comunitarios en radio (`?lat=…&lng=…&radio_m=…`) |
| POST | `/api/v1/limites` | Sí | Reportar límite comunitario |

**Billboards (`/api/v1/billboards`)**

| Método | Ruta | Auth | Descripción |
|--------|------|------|-------------|
| GET | `/api/v1/billboards?lat=&lng=&radio=` | No | Billboards activos en radio (km). Por defecto 30 km. Filtra por `activo=1` y `expira_en > NOW()` |
| POST | `/api/v1/billboards` | Admin (`X-Admin-Key`) | Crear billboard. Body JSON: `{lat, lng, bearing?, tipo?, titulo, subtitulo?, url?, expira_en?}` |
| DELETE | `/api/v1/billboards/:id` | Admin (`X-Admin-Key`) | Desactivar billboard (soft delete: `activo=0`) |

### Migraciones (0001–0011)

| Migración | Tabla(s) | Descripción |
|-----------|----------|-------------|
| 0001 | `usuarios` | Registro de usuarios: email, hash argon2id, rol, verificación email |
| 0002 | `alertas`, `alerta_votos`, `error_mapa_cola` | Alertas comunitarias con categorías, subtipos, carril, votos |
| 0003 | — (ALTER) | Añade columna `coords POINT` + `SPATIAL INDEX` a alertas; triggers `alertas_bi/bu`; índices `idx_activa_expira`, `idx_expira_activa` |
| 0004 | — (ALTER) | Cambia `lat`/`lng` de `DECIMAL(9,6)` a `DOUBLE` (fix corrupción de coordenadas con SQLx binary) |
| 0005 | — (ALTER) | Añade columna `velocidad TINYINT UNSIGNED` a alertas |
| 0006 | `limites_velocidad` | Límites de velocidad comunitarios (lat, lng, bearing, velocidad) |
| 0007 | `mensajes`, `mensajes_estado` | Mensajes del servidor con soporte broadcast/usuario/dispositivo; estado de entrega/lectura por dispositivo |
| 0008 | — (ALTER) | Añade `url`, `dest_lat`, `dest_lon`, `dest_nombre` a `mensajes` (mensajes con destino de navegación) |
| 0009 | `user_settings` | Settings sincronizados por usuario (PK compuesta `user_id + key_name`, upsert atómico) |
| 0010 | `shares` | Tokens de share activo; unique index `idx_shares_user` garantiza un share por usuario |
| 0011 | `billboards` | Carteles publicitarios geo-referenciados: lat/lng, bearing, tipo (lado/puente), título, subtítulo, URL, caducidad |

### Deploy

```bash
# Desde el host con acceso a SERVIDOR
rsync -av navius_server/ SERVIDOR:/srv/navius_server/

# En SERVIDOR
ssh SERVIDOR "cd /srv/navius_server && docker compose up --build -d"
```

### Acceso a la base de datos

```bash
# Desde SERVIDOR o via SSH tunnel
mysql -u navius -p'CONTRASEÑA' --skip-ssl -h 127.0.0.1 navius
```

### Pool de conexiones MariaDB

| Parámetro | Valor | Motivo |
|-----------|-------|--------|
| `max_lifetime` | 1800 s | Recicla conexiones antes de que MySQL las cierre por `wait_timeout` (28800 s por defecto, pero en algunos configs puede ser menor) |
| `idle_timeout` | 600 s | Libera conexiones inactivas para no saturar el pool |
| `test_before_acquire` | `true` | Verifica que la conexión sigue viva antes de devolverla al handler; evita errores "MySQL server has gone away" |

Configurado en `main.rs` con `MySqlPoolOptions::new()`.

---

## TTS (Text-to-Speech)

### Arquitectura

```
NavTts (Rust QObject)
    ├── Piper: spawn proceso + WAV via stdout
    ├── Mimic HTS: spawn proceso + WAV via fichero
    └── PicoTTS: spawn pico2wave + WAV via fichero
         ↓
    Cola FIFO de textos
         ↓
    libpcaudio_stub.so → PCM → /dev/snd/pcmC*D*p
```

### Pre-generación

`Main.qml` llama a `_pregenerateUpcoming(step)` en `nav_tts.rs` para generar en segundo plano los WAVs de las próximas N instrucciones. Cuando llega el momento de reproducirlas, el WAV ya está en caché y la latencia es ~0.

### Límite de CPU de Piper

`libpiper_limit.so` usa `LD_PRELOAD + setrlimit(RLIMIT_CPU)` para limitar el uso de CPU del proceso Piper, evitando que degrade la UI en dispositivos de gama baja.

---

## Persistencia de datos

### Ficheros en el dispositivo

```
~/.local/share/navius.woodyst/
├── gps_tracks.db        # SQLite: tracks grabados
├── gps_tracks/          # GPX exportados
├── debug/               # Ficheros de depuración y control (ver sección 10)
└── QtProject/           # Qt Settings
```

### Categorías de Settings QML

| Categoría | Contenido |
|-----------|-----------|
| `nav` | waypoints actuales, opciones de ruta |
| `dest_history` | historial de destinos (máx. 50) |
| `favorites` | favoritos con nombre y dirección |
| `saved_plans` | planes guardados (JSON) |
| `search_ui` | estado UI del panel de búsqueda |
| `PrefPanelSections` | estado de secciones colapsables |
| `whatsNew` | versión vista del dialog de novedades |
| `tour` | `showOnStart` para el asistente |
| `auth` | `token`, `email`, `recordar`, `userId`, `settingsChangedSinceSync`, `settingsLastSyncAt` |
| `device_msg` | `deviceId` (UUID persistente), `lastMsgId` (última ID de mensaje recibida) |

El share de viaje **no se persiste** entre sesiones: `_shareToken` es una propiedad de runtime de `Main.qml` y se pierde al cerrar la app. Si la app se cierra con un share activo, el token sigue válido en el servidor 24 h, pero la app no lo recupera al arrancar.

### Settings sincronizados con el servidor (`user_settings`)

Las 41 claves de `NavSettings.SYNC_KEYS` se sincronizan con la tabla `user_settings` del servidor. El mecanismo:

1. Al cambiar cualquier setting de `appSettings`: debounce 3 s → `_pushSettingsToServer()`
2. Al arrancar con sesión activa: `_pullSettingsFromServer()` comprueba si hay settings más nuevos en el servidor
3. Si hay conflicto (cambios locales no sincronizados + cambios en el servidor): `settingsConflictDialog` pide al usuario elegir

El upsert en el servidor es por clave individual, lo que permite mover un setting de categoría Qt sin perder el valor sincronizado.

### TODOs (LocalStorage SQLite)

Los TODOs se guardan vía `TodoDB.js` en LocalStorage de Qt (SQLite). La clave por destino es `"${lat}_${lon}"`. Estructura:

```sql
CREATE TABLE todos (dest_key TEXT, text TEXT, done INTEGER, ord INTEGER)
```

---

## Ficheros de depuración y control

Todos los ficheros de depuración residen en:

```
~/.local/share/navius.woodyst/debug/
```

El directorio se crea automáticamente al activar el modo debug en PreferencesPanel, al llamar a `satModel.set_traces_enabled(true)`, o en la primera escritura de cualquier fichero debug.

---

### `.traces_enabled`

Fichero de flag (vacío). Su presencia activa la escritura de `net_debug.log`, `tts_debug.log` y `piper_limit.log`. Gestionado por `satModel.set_traces_enabled(bool)`.

---

### Ficheros de control

#### `navius_cmd` — Entrada de comandos remotos

Escrito externamente (SSH), leído por la app cada 400 ms (solo con `debugMode=true`). El contenido completo se usa como clave de deduplicación: si no cambia, no se reprocesa.

**Formato batch** (recomendado):
```
<unix_epoch>
<cmd1>
<cmd2>
...
```
La primera línea es un timestamp Unix (`>1e9`); cada línea posterior es un comando.

**Formato legado** (una sola línea):
```
<epoch> <cmd>
```
o simplemente:
```
<cmd>
```

**Comandos disponibles:**

| Comando | Efecto |
|---------|--------|
| `2d` | Cambiar a modo 2D |
| `3d` | Cambiar a modo 3D (pitch 60°) |
| `north` | Modo norte arriba |
| `heading` | Modo rumbo arriba |
| `follow` | Activar follow mode |
| `pause` | Congelar posición de simulación |
| `resume` | Descongelar simulación |
| `dbg` | Toggle overlay de debug |
| `poi` | Toggle marcadores GPS/centro + POIs cardinales |
| `shot` | Guardar captura en `navius_shot.png` |
| `pos<lat>,<lon>` | Fijar posición manual (ej: `pos40.32,-3.51`) |
| `posoff` | Liberar posición manual |
| `pitch+N` / `pitch-N` | Incrementar/decrementar pitch N grados |
| `pitchN` | Fijar pitch a N grados |
| `bear+N` / `bear-N` | Rotar bearing N grados |
| `bear0` | Resetear bearing a norte |

**Ejemplo de uso desde SSH:**
```bash
D=/home/phablet/.local/share/navius.woodyst/debug
echo "$(date +%s)
2d
north" > $D/navius_cmd
```

---

#### `navius_ack` — Respuesta de comandos

Escrito por la app tras procesar cada comando o batch. Formato:

```
HH:MM:SS.mmm CMD: <cmd1>|<cmd2>|...
  mode=heading/navMap pitch=60 bear=45 mpp=5.1234 cy=320 fov=0.785 poi=false follow=true paused=false sim_mode=true sim_route=0 rv=false ...
  AZ: lat=40.123456 lon=-3.123456 bear=45 spd=35 rawSpd=35.2 secs=15 az=true hasPos=true azTgt=13.500 mpp=5.12345 pxR=2 mapH=800 dist=145.8 zoom=13.500
```

**Monitorizar desde SSH:**
```bash
tail -f $D/navius_ack
```

---

### Ficheros de estado (escritos por la app)

#### `navius_route` — Estado de navegación (JSON)

Actualizado cada 2 s mientras `_navActive || simMode`. También leído al arrancar para restaurar la navegación si `wasNavigating=true`.

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
  "maneuver": "Continúa recto durante 500 m"
}
```

| Campo | Descripción |
|-------|-------------|
| `active` | Navegación activa |
| `dist_m` | Distancia restante en metros (−1 si inactiva) |
| `eta_s` | Tiempo restante en segundos (−1 si inactiva) |
| `limit_kmh` | Límite de velocidad del tramo actual |
| `speed_kmh` | Velocidad actual redondeada |
| `lat`, `lon` | Posición GPS actual |
| `sim_mode` | Modo simulación activo |
| `sim_route_idx` | Índice de ruta de simulación seleccionada |
| `sim_seg` | Segmento actual en la ruta de sim |
| `sim_total` | Total de puntos en la ruta de sim |
| `dests` | Lista de waypoints destino |
| `maneuver` | Texto de la maniobra actual |

---

#### `navius_autostart` — Configuración de arranque (JSON)

Leído una sola vez en `Component.onCompleted`. Escrito externamente por el desarrollador. Todos los campos son opcionales:

```json
{
  "sim":      true,
  "debug":    true,
  "pos":      "40.4168,-3.7038",
  "routeIdx": 2
}
```

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `sim` | bool | Activar modo GPS simulado al arrancar |
| `debug` | bool | Activar modo debug al arrancar |
| `pos` | string | Fijar posición inicial `"lat,lon"` |
| `routeIdx` | int | Auto-iniciar ruta de simulación N |

---

#### `navius_trace` / `navius_trace_YYYYMMDD_HHMMSS` — Log de trazas GPS

Solo se escribe con `debugMode=true`. Al iniciar una navegación, la ruta de sesión se actualiza a `navius_trace_YYYYMMDD_HHMMSS`; `navius_trace` es el fallback para la sesión sin navegación. Actualizado cada 2 s junto con `navius_route`.

Formato: texto plano, una entrada por tick real con los ticks interpolados anidados:

```
HH:MM:SS.mmm lat=40.123456 lon=-3.123456 spd=45.2 head=45.3 seg=12 dist=1234.5 fix=true
  HH:MM:SS.mmm interp lat=40.123460 lon=-3.123450 spd=45.1 head=45.3
  HH:MM:SS.mmm interp lat=40.123465 lon=-3.123440 spd=45.0 head=45.2
```

---

#### `navius_sl_debug.txt` — Debug de límites de velocidad

Escrito por `satModel.write_text_file("navius_sl_debug.txt", ...)` cuando el overlay SL debug está activo (`showSlDebug=true` + `debugMode=true`). Una línea por tramo con la fuente del límite de velocidad (comunitario / Valhalla / OSM / legal por clase / defecto).

---

### Ficheros de log (append, requieren `.traces_enabled`)

#### `net_debug.log`

Escrito por `satModel.log_to_file()`. Contiene líneas de debug de peticiones XHR de routing (Valhalla) y geocodificación (Photon) generadas en `NavSearch.js`.

```
2026-05-22T10:30:00 route: POST https://valhalla.egpsistemas.com/route
2026-05-22T10:30:00 route: 200 OK 1234 bytes 0.456s
```

#### `tts_debug.log`

Escrito por `nav_tts.rs`. Registra selección de motor, síntesis, tiempos, caché:

```
[1716500000.123] piper: say "Gire a la derecha" lang=es-ES
[1716500000.234] piper: synthesis done 0.111s cache=MISS written=/path/to/cache.wav
[1716500001.456] piper: say "En 200 metros, continúa recto" lang=es-ES
[1716500001.500] piper: synthesis done 0.044s cache=HIT
```

#### `piper_limit.log`

Escrito por `libpiper_limit.so` (LD_PRELOAD sobre el proceso Piper). Registra eventos de throttling de CPU. Cada entrada es una línea:

```
piper_limit: nice(10) applied pid=12345
piper_limit: RLIMIT_CPU set to 2s per 5s window
```

---

### Comandos SSH útiles

```bash
D=/home/phablet/.local/share/navius.woodyst/debug

# Monitorizar acknowledgments
tail -f $D/navius_ack

# Ver estado de navegación en tiempo real
watch -n2 cat $D/navius_route | python3 -m json.tool

# Seguir traza GPS
tail -f $D/navius_trace

# Seguir todos los logs
tail -f $D/net_debug.log $D/tts_debug.log $D/piper_limit.log

# Enviar comando batch
echo "$(date +%s)
3d
heading" > $D/navius_cmd

# Fijar posición manual
echo "$(date +%s)
pos40.4168,-3.7038" > $D/navius_cmd
```

---

## Variables de entorno y depuración

| Variable | Efecto |
|----------|--------|
| `NAVIUS_DEBUG=true` | Activa trazas GPS/LLS en stderr (definido en `location_props.h`) |
| `LLS_DEBUG=true` | Activa trazas internas de LLS (definido en `lls_trace.h`) |
| `QML_XHR_ALLOW_FILE_READ=1` | Permite `XMLHttpRequest` a `file://` |
| `QML_XHR_ALLOW_FILE_WRITE=1` | Permite escritura via XHR a `file://` |
| `QML_DISABLE_DISK_CACHE=1` | Desactiva caché de QML compilado (útil en desarrollo) |

### Panel de log en-app

En `SearchPanel.qml`, el área de log muestra las peticiones de red y errores de routing. Se activa tocando el área de log.

---

## Patches LLS

El paquete `lomiri-location-service 3.4.1+navius5` incluye los siguientes parches:

### navius1 — Waydroid SIGSEGV + EDEADLK

Waydroid sobreescribe los callbacks GPS mientras LLS los despacha → SIGSEGV. Corregido con `std::shared_mutex`. Split de `register_callbacks()` en tres fases para evitar EDEADLK por re-entrada del HAL.

### navius2 — `start_positioning()` no bloqueante + API de satélites

`start_positioning()` y `register_callbacks()` corren en hilo detached para que el hilo D-Bus no bloquee en binder IPC. Añadido método D-Bus `GetVisibleSpaceVehicles` y `Restart=always` en systemd.

### navius3 — Fast path + guard de recuperación concurrente

Fast path en `start_positioning()`: si el handle GPS es válido, llama directamente a `u_hardware_gps_start()`. Flag atómico `positioning_active` para evitar dos hilos de recuperación concurrentes.

### navius4 — Watchdog + dispatch modes en fast path

Thread watchdog (tick 5s, umbral 10s): detecta GPS congelado, re-registra callbacks y reinicia GPS. `dispatch_updated_modes_to_driver()` añadido al fast path antes de `u_hardware_gps_start()`.

### navius5 — `lls_trace.h` centralizado

Constante `LLS_DEBUG` y macro `LLS_TRACE()` movidas a un único header compartido.

### Build del paquete LLS

```bash
cd lomiri-location-service
bash debs/build-deb.sh 2>&1 | tee /tmp/build-lls.log
```

Para instalar (con cambio de versión):

```bash
bash debs/update-phablet.sh
```

---

## Reproductor de música integrado

### Arquitectura

El reproductor usa `Audio` (QtMultimedia 5.6) con el backend `ubuntu-media-hub`. Las pistas se almacenan en el sandbox de la app y se reproducen con `file://`.

**`nav_music.rs`** — biblioteca Rust: gestiona el directorio sandbox, importa vía Content Hub, crea symlinks.  
**`MediaPanel.qml`** — panel completo (lista + controles + slider volumen + ducking + ayuda symlink).  
**`MediaWidget.qml`** — barra compacta sobre el mapa (visible mientras hay pista cargada).

### Por qué media-hub no puede leer `~/Music` directamente

`authenticate_open_uri_request` en media-hub 4.7 tiene un **allowlist hardcodeado por nombre de paquete**. Solo permite `file://` a:

- El directorio propio de la app (`~/.local/share/<pkg>/`, `~/.cache/<pkg>/`)
- El paquete `music.ubports` (app oficial de música) → puede leer `~/Music` y `~/Videos`
- Rutas de sistema (`/android/system/media/audio/ui/`)

Cualquier otra app de terceros (incluida `navius.woodyst`) recibe `"Client is not allowed to access"` al intentar `file:///home/phablet/Music/…`. **No es un bug de AppArmor** — los permisos del kernel son correctos. El allowlist está en el código fuente de media-hub y solo puede eludirse siendo `music.ubports` o siendo `unconfined`.

### Solución: Content Hub + sandbox

La música llega a Navius exclusivamente a través de **Content Hub** (`Lomiri.Content`). El flujo es:

1. `ContentPeerPicker` (ContentType.Music) → el usuario selecciona ficheros en el gestor de archivos.
2. Content Hub copia los ficheros a `~/.cache/navius.woodyst/HubIncoming/` (temporal).
3. `Connections { target: activeTransfer; onStateChanged }` detecta el estado `Charged`.
4. `import_tracks(urls)` en Rust:
   - Si la URL es de `HubIncoming` → **copia** a `~/.local/share/navius.woodyst/Music/`.
   - Si la URL es un fichero externo (p. ej. `~/Music/`) → crea un **symlink** en el sandbox apuntando al original. Crear un symlink no requiere leer el fichero origen (solo escribe en el directorio destino), por lo que AppArmor no lo deniega aunque `music_files_read` no esté en el perfil.
5. `activeTransfer.finalize()` limpia `HubIncoming`.
6. `reloadLibrary()` refresca la lista.

La reproducción es `player.source = "file://" + path`. media-hub acepta este `file://` porque la ruta empieza por `~/.local/share/navius.woodyst/`, que está en su allowlist para el propio sandbox.

### Symlinks a `~/Music` — por qué funciona

media-hub-server corre con el perfil AppArmor `owner @{HOME}/[^.]*/** rk`, que le permite seguir symlinks y leer el fichero real en `~/Music`. Además, media-hub **no canoniza la ruta** (no llama a `realpath`) antes de comprobar el allowlist, por lo que un symlink bajo `~/.local/share/navius.woodyst/Music/cancion.mp3` pasa la comprobación de prefijo.

Navius lista los symlinks con `file_type()` (lstat, sin seguir el enlace), por lo que no necesita leer el fichero real — eso lo delega a media-hub en el momento de la reproducción.

**El usuario puede crear symlinks manualmente** desde una Terminal o por SSH para vincular toda su `~/Music` sin duplicar espacio. La pantalla del reproductor incluye una sección de ayuda expandible con el comando exacto.

### Nota sobre `XDG_DATA_HOME` en Ubuntu Touch

El proceso de Navius recibe `XDG_DATA_HOME=/home/phablet/.local/share` (sin el package name). `music_dir()` debe añadir `navius.woodyst` explícitamente: `$XDG_DATA_HOME/navius.woodyst/Music/`. Sin esto, `create_dir_all` intentaría crear `~/.local/share/Music/`, que AppArmor deniega, y la importación fallaría silenciosamente.

### Por qué MPRIS2 no es viable (AppArmor)

Controlar un reproductor externo vía MPRIS2/D-Bus requiere enviar mensajes a `org.mpris.MediaPlayer2.*`. El perfil AppArmor de navius tiene `deny dbus (send)` de catch-all, y el kernel de UBports tiene mediación D-Bus activa. No existe ningún policy_group en `apparmor-easyprof-ubuntu` que permita MPRIS2 a apps de terceros.

### Ducking TTS

`Main.qml` detecta `navTts.is_speaking()` cada 100 ms y llama `mediaPanel.duck(true/false)`. MediaPanel ajusta el volumen vía PulseAudio (`ttsObj.set_music_volume`) al `duckVolume` configurado (defecto 70 %) y lo restaura 600 ms después de que termine el TTS.

### Compatibilidad Lomiri/QML

- `Slider` en Lomiri.Components usa `minimumValue`/`maximumValue`, no `from`/`to`.
- `Slider.onMoved` no disponible en QtQuick.Controls 2.2 → usar `onValueChanged`.
- Propiedades con guión bajo (`_foo`) no generan handler `onFooChanged` → evitar para propiedades con handler inline.
- `Connections` usa sintaxis antigua `onSignal: { ... }` (no `function onSignal()`, Qt 5.15+).

## Sistema de publicidad (billboards)

Carteles publicitarios geo-referenciados que se dibujan sobre el mapa y generan una notificación de proximidad en pantalla.

### Arquitectura

| Capa | Fichero | Responsabilidad |
|------|---------|-----------------|
| BD | `billboards` (migración 0011) | Almacena carteles con coordenadas, tipo, textos, URL y caducidad |
| Servidor | `routes/billboards.rs` | GET público (consulta spatial), POST/DELETE solo admin |
| JS | `NavAlerts.js` (`obtenerBillboards`) | Fetch desde la app, reusa la misma infraestructura que alertas |
| QML | `Main.qml` (`bridgeCanvas`, `adPanel`) | Renderizado en mapa + panel de notificación |

### Tipos de billboard (`tipo`)

| Tipo | Descripción visual |
|------|--------------------|
| `lado` | Cartel a un lado de la vía: poste vertical desde el punto GPS, panel desplazado perpendicular al bearing. Postes en 25 % y 75 % del ancho del panel. |
| `puente` | Cartel centrado sobre la vía (tipo pórtico de autopista): barra horizontal entre dos postes en los bordes del panel; el icono del vehículo pasa por debajo. |

### Z-order de capas

```
z:0  alertCanvas    — alertas comunitarias, radares, límites, ticks GPS
z:1  posOverlayRoot — icono del vehículo
z:3  bridgeCanvas   — todos los billboards (lado y puente), sobre el coche
z:4  NavBar, adPanel, CompassWidget, barras de escala
```

Los billboards se ordenan por posición Y en pantalla (ascendente): los que están más arriba en pantalla (más lejos) se pintan primero y quedan detrás de los cercanos.

### Fetch desde la app

`_fetchBillboards()` se llama en cada `onGpsTick`. Umbrales de refresco:

- **Sin ruta activa**: cada ~500 m, radio 5 km.
- **Con ruta activa**: cada ~20 km, radio 30 km.

`_adShownTs` se resetea al iniciar una ruta o un track replay para que el AdPanel vuelva a mostrarse aunque el billboard ya haya aparecido antes en esa sesión.

### Panel de proximidad (AdPanel)

`_checkBillboardProximity(lat, lon)` se llama en cada gpsTick. Activa `adPanel` si:

1. No hay otro AdPanel activo (`_adPanelBb === null`).
2. Hay un billboard a menos de 600 m.
3. Han pasado más de 60 s desde la última vez que se mostró ese billboard (`_adShownTs`).

Al activarse, registra automáticamente una impresión vía `NavAlerts.registrarImpresion()`.

El panel aparece bajo `NavBar` con animación de altura (200 ms), muestra título y subtítulo (o dominio de la URL como fallback), y se cierra automáticamente a los 12 s o al pulsar ✕. Si la URL contiene `"navius"` se muestra el badge con la "N" azul.

### Interacción táctil

- **Tap en el panel** (área izquierda al botón ✕): abre `NavAlerts.clickUrl(id, token)` con `Qt.openUrlExternally`. El servidor registra el click y redirige (302) a la URL del billboard.
- **Tap directo en el mapa** sobre un billboard: detectado en `MouseArea` del mapa; recalcula la caja del cartel según su tipo y bearing, y abre el click URL si el toque cae dentro.

### Tracking de impresiones y clicks

Tabla `billboard_impresiones` (migración 0016):

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `billboard_id` | BIGINT | Billboard mostrado |
| `usuario_id` | INT NULL | Usuario autenticado (NULL si anónimo) |
| `device_id` | VARCHAR(100) NULL | ID del dispositivo (`x-device-id` header) |
| `mostrado_en` | DATETIME | Momento en que apareció el AdPanel |
| `click_en` | DATETIME NULL | Momento del click (NULL si no hubo) |

Endpoints:
- `POST /api/v1/billboards/:id/impresion` — registra impresión; acepta Bearer token y header `X-Device-Id`.
- `GET /api/v1/billboards/:id/click?token=<jwt>` — registra click y redirige (302) a la URL del billboard.

### Billboards dinámicos (autopromoción)

Job en `main.rs` que corre cada 120 s. Para cada vehículo activo (clave `navius:pos:{uid}` en Redis) que lleve más de 1 hora sin recibir un anuncio:

1. Calcula la posición del billboard ~120 s de viaje por delante: `dist_m = (speed_ms × 120).clamp(1000, 4000)`.
2. Si hay `navius:route:{uid}` en Redis (shape de la ruta activa), usa `punto_adelante_en_shape()` para seguir la geometría real de la vía. Si no, usa bearing + velocidad como aproximación.
3. Inserta el billboard en BD con caducidad `secs_to_reach + 300 s` (máx 1 h).
4. Inserta un mensaje `tipo='aviso', titulo='fetch_billboards'` para que la app descargue billboards inmediatamente sin esperar al umbral de 500 m.
5. Marca `navius:bb_last:{uid}` con TTL 3600 s para no repetir.

**Contenido del billboard dinámico** — configurable en la tabla `configuracion` sin redeploy:

```sql
SELECT clave, valor FROM configuracion;
-- billboard_demo_url       → URL de destino del click
-- billboard_demo_titulo    → Título del cartel
-- billboard_demo_subtitulo → Subtítulo del cartel
```

Para cambiar la URL o los textos basta con `UPDATE configuracion SET valor=... WHERE clave=...`. El job leerá los nuevos valores en la siguiente ejecución (≤ 120 s).

### Shape de ruta en Redis

Cuando el usuario comparte viaje con navegación activa, `share.rs` almacena el shape de la ruta en Redis:

- **Clave**: `navius:route:{usuario_id}`
- **Valor**: JSON `[[lon, lat], ...]` (pares lon/lat, orden Valhalla)
- **TTL**: 1800 s (30 min)

El job de billboards dinámicos usa este shape para situar el cartel sobre la vía real en lugar de una proyección plana.

### Gestión en producción

```bash
# Crear billboard manual (curl desde el servidor)
curl -X POST http://localhost:8080/api/v1/billboards \
  -H "X-Admin-Key: $ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"lat":40.416,"lng":-3.703,"bearing":90,"tipo":"lado",
       "titulo":"Navius Pro","subtitulo":"Navegación sin límites",
       "url":"https://navius.app","expira_en":"2026-12-31T23:59:59"}'

# Desactivar billboard id=5
curl -X DELETE http://localhost:8080/api/v1/billboards/5 \
  -H "X-Admin-Key: $ADMIN_SECRET"

# Ver billboards activos cerca de Madrid
curl "http://localhost:8080/api/v1/billboards?lat=40.416&lng=-3.703&radio=50"

# Cambiar URL del billboard de autopromoción sin redeploy
mysql -u navius -p navius -e \
  "UPDATE configuracion SET valor='https://nueva-url.com' WHERE clave='billboard_demo_url';"

# Forzar billboard en el próximo ciclo (limpiar cooldown)
docker exec navius-redis redis-cli DEL navius:bb_last:{uid}

# Ver impresiones y clicks
mysql -u navius -p navius -e \
  "SELECT billboard_id, COUNT(*) imp, SUM(click_en IS NOT NULL) clicks
   FROM billboard_impresiones GROUP BY billboard_id ORDER BY imp DESC LIMIT 10;"
```
