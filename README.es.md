# Navius GPS

Navegador GPS para Ubuntu Touch. Rust + QML, empaquetado como Click.

[Web](https://www.egpsistemas.com/site/navius) · [GitHub](https://github.com/woodyst/navius) · [Donaciones](https://liberapay.com/Navius-GPS/) · [English version](README.md)

**Comunidad** · [Telegram — GUI & Design](https://t.me/+zjjkxqdlAfphOGJk) · [Telegram — Bugs & Issues](https://t.me/+69rlmf-nlEU4NmM0)

[¿Otro navegador GPS?](docs/philosophy.es.md) · [Manual de usuario](docs/user.es.md) · [Documentación del desarrollador](docs/developer.es.md)

[Another GPS navigator?](docs/philosophy.en.md) · [User manual](docs/user.en.md) · [Developer docs](docs/developer.en.md)

---

## Características

- Navegación turn-by-turn con instrucciones de voz (TTS)
- Rutas con Valhalla (servidor propio o público), alternativas, sin peajes/ferries/autopistas
- Mapa vectorial con MapLibre (tiles propios o Maptiler)
- Vista satélite con overlay de señal GPS
- Límites de velocidad por tramo (OSM Legal Default Speeds)
- Tráfico predicho sintético por jerarquía de red (Valhalla predicted traffic)
- Planificación de rutas con hora de salida programada y planes guardados
- TODOs por destino (tareas a realizar en cada parada)
- Búsqueda de POI cercanos (gasolina, parking, restaurantes, hoteles…)
- Grabación de ruta GPS (tracks SQLite + exportación GPX)
- Simulador de conducción con control manual de velocidad/dirección
- Integración con Google Maps (apertura externa)
- Modo satélite y modo 3D (edificios)
- Dead-reckoning e interpolación GPS a 10 Hz
- Soporte Waydroid concurrente sin pérdida de GPS

---

## Arquitectura

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

### Módulos Rust

| Módulo               | Descripción                                                                                                 |
| -------------------- | ----------------------------------------------------------------------------------------------------------- |
| `main.rs`            | Inicialización Qt, registro de tipos QML, carga del motor                                                   |
| `satellite_model.rs` | `QObject` expuesto a QML: proxy entre `SatelliteSource` (C++) y la UI; tick a 1 Hz                          |
| `nav_http.rs`        | `QObject` para HTTP POST asíncrono via `QNetworkAccessManager`; señal `done(req_id, body, err)`             |
| `nav_tts.rs`         | TTS multi-motor: Piper (neural), Mimic HTS (español), PicoTTS (fallback); cola FIFO, pre-generación de WAVs |
| `nav_tracker.rs`     | Grabación de tracks GPS en SQLite; haversine, exportación GPX                                               |
| `qrc.rs`             | Carga los recursos QRC generados por `build.rs`                                                             |

### Módulos C++

| Fichero                 | Descripción                                                                                                                                        |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `satellite_source.h`    | `SatelliteSource`: fuente de datos GPS. Lee de LLS via Qt Positioning + bridge de satélites. Gestiona reconexión automática a LLS                  |
| `location_props.h/.cpp` | `LocationPropsWatcher`: polling de `VisibleSpaceVehicles` a LLS; detecta reinicio de LLS via D-Bus `NameOwnerChanged` y emite señal `llsRestarted` |

### QML principal

| Fichero                | Descripción                                                                                                                                 |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `Main.qml`             | Ventana raíz; estados app (`idle`, `navigating`, `parking`); configuración global                                                           |
| `GpsSource.qml`        | Abstracción GPS: unifica fix real, simulación, dead-reckoning e interpolación a 10 Hz                                                       |
| `NavSearch.js`         | Lógica de geocodificación (Photon/Komoot) y cálculo de rutas (Valhalla API); enriquecimiento de límites de velocidad via `trace_attributes` |
| `SearchPanel.qml`      | Panel de planificación: destinos, TODOs por parada, hora de salida, planes guardados, favoritos, historial, búsqueda POI                    |
| `NavBar.qml`           | Barra de navegación activa: instrucción actual, distancia, ETA, velocidad, límite de velocidad                                              |
| `SpeedView.qml`        | Cuentakilómetros (velocímetro circular)                                                                                                     |
| `SatelliteView.qml`    | Vista polar de satélites con señal SNR                                                                                                      |
| `PreferencesPanel.qml` | Ajustes: servidor Valhalla, tipo de vehículo, TTS, simulador, estilos de mapa                                                               |
| `TodoDB.js`            | API SQLite (LocalStorage) para TODOs por destino                                                                                            |
| `SimRoute.js`          | Generador de ruta de simulación con velocidad real                                                                                          |

---

## Compilar y desplegar

Requiere [Clickable](https://clickable-ut.dev/) ≥ 8.7.0.

```bash
# Compilar para dispositivo aarch64
clickable build

# Desplegar en el dispositivo (USB)
clickable install

# Lanzar
clickable launch
```

Para compilar solo la biblioteca TTS Mimic:

```bash
bash compilar_solo_mimic.sh
```

### Dependencias del build

El `postbuild` de `clickable.yaml` empaqueta automáticamente:

- **espeak-ng** + datos (pronunciación para Piper)
- **Piper** (descargado de GitHub si no está en `vendor/piper_aarch64/`)
- **PicoTTS** (`vendor/picotts/`, compilado en el build)
- **Mimic HTS español** (`vendor/mimic_hts/` + `extras/mimic/`)
- **libpcaudio stub** (`src/libpcaudio_stub.c`) — PCM audio sin dependencia de PulseAudio
- **libpiper_limit** (`src/libpiper_limit.c`) — limita uso de CPU de Piper via `setrlimit`
- **libQMapLibre** + plugin MapboxMap (`lib/`)

---

## GPS y lomiri-location-service

Navius usa [lomiri-location-service](https://gitlab.com/ubports/development/core/lomiri-location-service) (LLS) como backend GPS via D-Bus. Se distribuye un paquete parcheado (`3.4.1+navius6`) que corrige múltiples problemas de estabilidad con el GPS HAL de HALIUM_10, especialmente cuando Waydroid corre en paralelo.

### Parches LLS (navius1–navius6)

**navius1** — Waydroid SIGSEGV + EDEADLK  
Waydroid sobreescribe los callbacks GPS de LLS mientras LLS los está despachando → SIGSEGV. Corregido con `std::shared_mutex` (callbacks en shared lock; `register_callbacks()` en exclusive). Split en tres fases de `register_callbacks()` para evitar EDEADLK por re-entrada del HAL durante `u_hardware_gps_new()`.

**navius2** — `start_positioning()` no bloqueante + API de satélites  
`start_positioning()` y `register_callbacks()` corren en hilo detached para que el hilo D-Bus no bloquee en binder IPC (puede bloquearse indefinidamente cuando Waydroid tiene el HAL). Añadido método D-Bus `GetVisibleSpaceVehicles` y `Restart=always` en la unidad systemd.

**navius3** — fast path + guard de recuperación concurrente  
Fast path en `start_positioning()`: si el handle GPS es válido (caso normal), llama directamente a `u_hardware_gps_start()` sin crear un hilo. Flag atómico `positioning_active` para evitar dos hilos de recuperación concurrentes.

**navius4** — Watchdog + dispatch modes en fast path  
Thread watchdog (tick 5 s, umbral 10 s): detecta GPS congelado, re-registra callbacks y reinicia GPS automáticamente. `dispatch_updated_modes_to_driver()` añadido al fast path antes de `u_hardware_gps_start()`.

**navius5** — `lls_trace.h` centralizado  
Constante `LLS_DEBUG` y macro `LLS_TRACE()` movidas a un único header compartido (`include/location_service/com/lomiri/location/lls_trace.h`).

**navius6** — Fix indicador GPS + protección deadlock HAL  
`engine.cpp`: `is_any_active = resultado_último_provider` → `|=` — con dos providers solo el resultado del último determinaba el indicador, por lo que el GPS nunca aparecía como activo si solo el primer provider estaba funcionando. `android_hardware_abstraction_layer.cpp`: `start_positioning()` usa `try_to_lock` para no bloquear el hilo D-Bus; la fase 4 de `register_callbacks()` corre sin lock para evitar deadlock por re-entrada; null guard en `stop_positioning()`.

### Contribuciones upstream (UBports)

Se han enviado cinco merge requests al [repositorio upstream](https://gitlab.com/ubports/development/core/lomiri-location-service) para beneficiar a todos los usuarios de Ubuntu Touch. Fork: [gitlab.com/woodyst1/lomiri-location-service](https://gitlab.com/woodyst1/lomiri-location-service).

| MR | Descripción | Estado |
|---|---|---|
| [!57](https://gitlab.com/ubports/development/core/lomiri-location-service/-/merge_requests/57) | `engine`: fix `is_any_active \|=` | ✅ Aprobado |
| [!58](https://gitlab.com/ubports/development/core/lomiri-location-service/-/merge_requests/58) | `gps`: race/EDEADLK/cuelgue D-Bus/watchdog | En revisión |
| [!59](https://gitlab.com/ubports/development/core/lomiri-location-service/-/merge_requests/59) | `data`: unidad `.path` de trust-stored | En revisión |
| [!60](https://gitlab.com/ubports/development/core/lomiri-location-service/-/merge_requests/60) | `data`: `Restart=always` + limpiar `After=` | En revisión |
| [!61](https://gitlab.com/ubports/development/core/lomiri-location-service/-/merge_requests/61) | `service`: método D-Bus `GetVisibleSpaceVehicles` | En revisión |

### Fixes en navius (este repo)

- **Reconexión automática** (`location_props.cpp`): `NameOwnerChanged` en D-Bus; cuando LLS se reinicia navius recrea la fuente de posición y la sesión LLS automáticamente.
- **Lambda leak** (`satellite_source.h`): `init_pos_and_session()` reconectaba `llsRestarted` en cada llamada, acumulando llamadas `StartPositionUpdates` exponencialmente. Las conexiones se registran una sola vez en `init_sources()`.
- **`startUpdates()` en hilo principal** (`satellite_source.h`): el plugin Qt LLS usa `QEventLoop` internamente en `startUpdates()`. Llamarlo desde un hilo sin event loop bloqueaba para siempre. Corregido con `QMetaObject::invokeMethod` en el hilo principal.

### Activar trazas de depuración

```cpp
// src/location_props.h
static constexpr bool NAVIUS_DEBUG = true;   // trazas navius en stderr

// lomiri-location-service/include/.../lls_trace.h
static constexpr bool LLS_DEBUG = true;      // trazas LLS en stderr
```

Ver trazas en el dispositivo:

```bash
ssh phablet@<ip> "journalctl --user -f -u navius.woodyst_navius.desktop"
# o
adb shell "sudo -u phablet NAVIUS_DEBUG=1 /opt/click.ubuntu.com/navius.woodyst/current/navius 2>&1"
```

---

## Servidor Valhalla

Navius puede usar cualquier servidor Valhalla. El servidor propio se configura en **Preferencias → Servidor Valhalla**.

Servidor por defecto: `https://valhalla.egpsistemas.com`

### Build del mapa

Los tiles se construyen con el pipeline de Valhalla estándar. El pipeline tiene 13 fases:

| Fase  | Descripción                                                                 |
| ----- | --------------------------------------------------------------------------- |
| 01    | Descarga PBF                                                                |
| 02–06 | Parse, enhance, build tiles                                                 |
| …     | …                                                                           |
| 13    | Tráfico predicho (`generate_traffic.py` + `valhalla_add_predicted_traffic`) |

El tráfico predicho usa perfiles sintéticos por nivel de tile:

| Nivel | Tipo de vía           | Free-flow | Punta | Noche |
| ----- | --------------------- | --------- | ----- | ----- |
| 0     | Autopistas/autovías   | 115 km/h  | 85    | 110   |
| 1     | Primarias/secundarias | 85 km/h   | 55    | 80    |
| 2     | Locales/residenciales | 45 km/h   | 25    | 40    |

Horas punta: Lu-Vi 7-9h y 17-19h (fade parabólico).

Las peticiones de ruta incluyen siempre `date_time` para que Valhalla aplique el perfil de velocidad correspondiente a la hora actual o a la hora de salida programada.

---

## Búsqueda de POI (Overpass API)

Los puntos de interés cercanos (gasolina, parking, restaurantes, hoteles, radares…) se obtienen via [Overpass API](https://wiki.openstreetmap.org/wiki/Overpass_API) usando un pool de servidores públicos con fallback automático.

### Selección de servidor

Al arrancar, Navius sondea una lista de servidores candidatos y construye un pool activo con los que responden correctamente. Al realizar una búsqueda, el servidor se elige en función del **centro geográfico de la ruta** (no la posición del dispositivo), de modo que las búsquedas en Alemania o Japón usen un servidor apropiado aunque el dispositivo esté en España.

- **Servidor propio — España** (`navius-maps.egpsistemas.com/overpass/`): se usa para consultas en España. Instancia Overpass propia que cubre la Península Ibérica.
- **Servidor propio — mundial** (`navius-maps.egpsistemas.com/overpass-world/`): se usa para el resto de regiones. Instancia Overpass propia con datos del planeta completo.
- **Pool público**: 9 servidores de fallback mundiales (`z.overpass-api.de`, `overpass.nchc.org.tw`, `overpass.openstreetmap.fr`, y otros).
- **Reintento en 0 resultados**: si un servidor devuelve 0 elementos, la consulta se reintenta con el siguiente candidato (máx. 2 reintentos).

---

## Geocodificación

La búsqueda de direcciones y lugares usa [Photon](https://github.com/komoot/photon), un geocodificador de código abierto basado en datos de OpenStreetMap.

Servidor por defecto: `https://navius-maps.egpsistemas.com/photon` (instancia propia, índice mundial)

Los resultados usan el nombre local OSM de cada lugar. El idioma de la consulta se elige automáticamente según el idioma del sistema (soportados: `de`, `en`, `fr`; otros idiomas devuelven el nombre local).

---

## TTS (Text-to-Speech)

Tres motores disponibles, seleccionables en Preferencias:

| Motor         | Calidad              | Latencia | Idiomas              |
| ------------- | -------------------- | -------- | -------------------- |
| **Piper**     | Neural (alta)        | ~300 ms  | Muchos (voces .onnx) |
| **Mimic HTS** | HTS (media)          | ~100 ms  | Español (integrado)  |
| **PicoTTS**   | Concatenativo (baja) | ~50 ms   | ES, EN, DE, FR, IT   |

Piper pre-genera WAVs de las próximas instrucciones en segundo plano para minimizar latencia de reproducción. `libpiper_limit.so` limita la CPU de Piper via `LD_PRELOAD + setrlimit`.

---

## Bridge de satélites

Cuando el GPS hardware no está accesible directamente (Waydroid, emuladores), el bridge `navius-sat-bridge.py` lee los datos NMEA del HAL y los escribe en `/run/user/32011/navius.woodyst/navius-sat.txt`. `SatelliteSource` lee este fichero como fuente secundaria si LLS no da datos.

```bash
# Instalar el bridge (en el dispositivo)
bash bridge/install.sh
```

---

## Estructura de ficheros

```
navius/
├── src/
│   ├── main.rs                  # Entrypoint Rust
│   ├── satellite_model.rs       # QObject GPS proxy
│   ├── satellite_source.h       # C++: LLS + bridge GPS
│   ├── location_props.h/.cpp    # C++: polling SVs, reconexión LLS
│   ├── nav_http.rs              # HTTP asíncrono
│   ├── nav_tts.rs               # TTS (Piper/Mimic/Pico)
│   ├── nav_tracker.rs           # Tracks GPS SQLite/GPX
│   ├── build.rs                 # Compilación QRC + C++
│   ├── libpcaudio_stub.c        # Stub PCM audio
│   └── libpiper_limit.c         # Límite CPU Piper
├── qml/
│   ├── Main.qml                 # Ventana principal
│   ├── GpsSource.qml            # Abstracción GPS
│   ├── NavSearch.js             # Geocodificación + routing Valhalla
│   ├── SearchPanel.qml          # Planificación de ruta
│   ├── NavBar.qml               # Barra de navegación activa
│   ├── SpeedView.qml            # Velocímetro
│   ├── SatelliteView.qml        # Vista satélites
│   ├── PreferencesPanel.qml     # Configuración
│   ├── RouteSelectPanel.qml     # Selección de vehículo/tipo de ruta
│   ├── RouteViewPanel.qml       # Lista de instrucciones
│   ├── StopTodoPanel.qml        # TODOs por parada
│   ├── TodoDB.js                # SQLite LocalStorage TODOs
│   ├── SimRoute.js              # Ruta de simulación
│   ├── SimTestRoutes.js         # Rutas de test para simulador
│   └── [otros paneles y diálogos]
├── vendor/
│   ├── piper_aarch64/           # Binario Piper + libs
│   ├── picotts/                 # PicoTTS fuente
│   ├── mimic_hts/               # Mimic HTS español fuente
│   └── mimic_hts_voice/         # Voz HTS española
├── extras/
│   └── mimic/                   # Mimic compilado (generado)
├── bridge/
│   ├── navius-sat-bridge.py     # Bridge satélites NMEA
│   ├── navius-sat-bridge-hal.c  # Acceso HAL directo
│   └── navius-sat-bridge.service # Unidad systemd
├── lib/
│   ├── libQMapLibre.so.3.0.0    # MapLibre GL
│   └── MapboxMap/               # Plugin QML MapboxMap
├── assets/
│   ├── logo.svg
│   └── gps_search.png
├── clickable.yaml               # Configuración de build Clickable
├── manifest.json                # Metadatos Click
├── navius.apparmor              # Permisos AppArmor
└── Cargo.toml                   # Dependencias Rust
```

---

## Persistencia de datos

Todos los datos de usuario se guardan en:

```
~/.local/share/navius.woodyst/
├── gps_tracks.db        # SQLite: tracks grabados
├── gps_tracks/          # GPX exportados
└── QtProject/           # Qt Settings (favoritos, historial, planes, waypoints, preferencias)
```

### Settings QML (categorías)

| Categoría      | Contenido                                                               |
| -------------- | ----------------------------------------------------------------------- |
| `nav`          | waypoints actuales, opciones de ruta (peajes, ferry, tierra, autopista) |
| `dest_history` | historial de destinos recientes (máx. 50)                               |
| `favorites`    | favoritos con nombre y dirección                                        |
| `saved_plans`  | planes guardados (destinos + TODOs + hora de salida + opciones)         |
| `search_ui`    | estado expandido de secciones en el panel                               |

Los TODOs por destino se almacenan en SQLite via `TodoDB.js` (LocalStorage) con clave `dest_key = "${lat}_${lon}"`.

---

## Variables de entorno y debug

| Variable                                    | Efecto                                                                  |
| ------------------------------------------- | ----------------------------------------------------------------------- |
| `NAVIUS_DEBUG=true` (en `location_props.h`) | Activa trazas GPS/LLS en stderr                                         |
| `LLS_DEBUG=true` (en `lls_trace.h`)         | Activa trazas internas de LLS                                           |
| `QML_XHR_ALLOW_FILE_READ/WRITE=1`           | Permite XMLHttpRequest a `file://` (activado por defecto en el binario) |
| `QML_DISABLE_DISK_CACHE=1`                  | Desactiva caché de QML compilado                                        |

El log de instrucciones y peticiones de red se puede ver dentro de la app activando el panel de log (toca el área de log en SearchPanel).

---

## Licencia

Copyright (C) 2026 Eduardo García-Mádico Portabella

Este programa es software libre: puede redistribuirlo y/o modificarlo bajo los términos de la GNU General Public License versión 3, tal como la publica la Free Software Foundation.

Este programa se distribuye con la esperanza de que sea útil, pero SIN NINGUNA GARANTÍA; sin siquiera la garantía implícita de COMERCIABILIDAD o IDONEIDAD PARA UN PROPÓSITO PARTICULAR. Consulte la GNU General Public License para más detalles.

Debería haber recibido una copia de la GNU General Public License junto con este programa. Si no, consulte <http://www.gnu.org/licenses/>.
