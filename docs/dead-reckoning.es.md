# Dead Reckoning: Simulación de trayecto ante GPS impreciso

**Commit:** `053e929`  
**Ficheros:** `qml/GpsSource.qml`, `qml/Main.qml`, `po/*.po` (11 idiomas)

## Objetivo

Cuando el receptor GPS reporta saltos bruscos o pierde fix —túneles, aparcamientos,
interferencias— Navius continúa avanzando por la ruta usando la velocidad del último
fix válido corregida con datos Valhalla, en lugar de congelar el icono del vehículo.
El usuario ve un banner naranja persistente y al recuperar señal aparece un toast verde.

## Línea temporal de estados

```
t=0              túnel                   salida              GPS OK
 |───────────────|────────────────────────|─────────────────|
   GPS NORMAL    │  DR ACTIVO (naranja)   │  recuperación   │  GPS OK
                 ^                        ^─fix1─fix2─fix3^
             salto/nofix              3 buenos consecutivos
```

## 1. Detección de fix inválido

Se evalúa en `_onRealGpsTick()` **antes** de actualizar `_p2`, de modo que `_p2` siempre
apunta al último fix bueno.

| Criterio | Condición | Umbral |
|---|---|---|
| Sin fix de hardware | `!pHasFix` | — |
| Salto de posición | `haversine(_p2, newPos) > maxExpected` | `max(30 m, v × Δt × 2.5)` |

El factor 2.5 da margen para ruido GPS real. El piso de 30 m evita activar DR con el
vehículo parado. La condición adicional `_speedMs > 1.0` impide entrar en DR cuando
el vehículo está esencialmente detenido.

```javascript
// _p2 = último fix bueno (no actualizado hasta el final)
var _isBad = !pHasFix
if (!_isBad && _p2 !== null) {
    var _dtJ = (ms - _p2.ms) / 1000.0
    if (_dtJ > 0.1 && _dtJ < 10.0) {
        var _jumpDist = _haversineM(_p2.lat, _p2.lon, pLat, pLon)
        _isBad = _jumpDist > Math.max(30.0, _speedMs * _dtJ * 2.5)
    }
}
```

## 2. Activación de DR

Al primer fix inválido con ruta activa y vehículo en movimiento se activa
`drActive = true` y se guarda la velocidad en `_drSpeedMs`.

```javascript
if (_isBad) {
    _drBadCount++; _drGoodCount = 0; _drRecovFix = null
    if (!drActive && _drBadCount >= 1
            && routeShape && routeShape.length > 1
            && _lastRealTickPos !== null && _speedMs > 1.0) {
        drActive = true
        _drSpeedMs = _speedMs
    }
    if (drActive) { _drSimulateTick(ms); return }
}
```

## 3. Función `_drSimulateTick(ms)`

Genera un tick sintético `source="dr"` avanzando por el shape de ruta.
Al emitir con `isReal=true`, `_emit()` actualiza `_lastRealTickPos` y
`_realTickMs`, por lo que el interpTimer a 20 Hz continúa sin modificaciones.

**Cálculo de velocidad:**

| Variable | Valor | Razón |
|---|---|---|
| `spd` base | `_drSpeedMs` | Velocidad del último fix real |
| `spd` con ratio | `v_Valhalla × (v_GPS / v_Valhalla)` | Si `interpUseVhRatio=true` y hay velocidades Valhalla |
| `dt` | `now − _realTickMs`, acotado [0.1, 5.0] s | Tiempo real transcurrido; cap 5 s evita saltos si el timer se retrasa |
| `hdg` | Bearing del segmento en `pos.idx` | Heading sigue la geometría de la ruta |

```javascript
function _drSimulateTick(ms) {
    if (!_lastRealTickPos || !routeShape || routeShape.length < 2) {
        drActive = false; return
    }
    var dt = (_realTickMs > 0) ? (ms - _realTickMs) / 1000.0 : 1.0
    dt = Math.max(0.1, Math.min(5.0, dt))

    var spd = _drSpeedMs
    if (interpUseVhRatio && routeShapeSpeedKmh
            && _lastRealTickPos.idx < routeShapeSpeedKmh.length) {
        var vVh = routeShapeSpeedKmh[_lastRealTickPos.idx] / 3.6
        if (vVh > 0.1 && _drSpeedMs > 0.1) {
            var ratio = Math.max(0.1, Math.min(3.0, _drSpeedMs / vVh))
            spd = vVh * ratio
        }
    }

    var pos = _walkShape(_lastRealTickPos.idx, _lastRealTickPos.frac, spd * dt)
    if (!pos) { drActive = false; return }  // fin de ruta

    var hdg = _bearing(routeShape[pos.idx][1], routeShape[pos.idx][0], ...)
    _speedMs = spd; realSpeedKmh = spd * 3.6; _headRad = hdg
    _realTickMs = ms   // mantiene interpTimer a 20 Hz sin cambios
    _emit(pos.lat, pos.lon, spd * 3.6, hdg, _hasFix, true, ms, "dr")
}
```

## 4. Recuperación

Se necesitan **3 fixes GPS consecutivos válidos** (sin salto entre ellos).
La consistencia se verifica comparando cada fix con `_drRecovFix` usando el mismo
umbral de la detección. Al salir se borran `_p0` y `_p1` porque los fixes anteriores
al DR no son válidos para calcular velocidad ni aceleración.

```javascript
} else if (drActive) {
    var _recovOk = true
    if (_drRecovFix !== null) {
        var _dtR = (ms - _drRecovFix.ms) / 1000.0
        if (_dtR > 0.1 && _dtR < 10.0)
            _recovOk = _haversineM(_drRecovFix.lat, _drRecovFix.lon, pLat, pLon)
                       <= Math.max(30.0, _speedMs * _dtR * 2.5)
    }
    _drRecovFix = {lat: pLat, lon: pLon, ms: ms}
    if (_recovOk) {
        _drGoodCount++
        if (_drGoodCount < 3) { _drSimulateTick(ms); return }
        // 3 fixes buenos → salir de DR
        drActive = false; _drBadCount = 0; _drGoodCount = 0
        _p0 = null; _p1 = null  // fixes anteriores al DR inválidos para v/a
    } else {
        _drGoodCount = 0; _drRecovFix = null
        _drSimulateTick(ms); return
    }
}
```

## 5. Modo simulación

La misma lógica DR se ejecuta en `_simAdvance()` para que el modo sim
(herramienta de debug) produzca el mismo comportamiento que el GPS real.
Los disparadores en sim son:

- `simSignalLost = true` → equivale a `!pHasFix`
- `gpsFailEnabled` con desplazamiento > umbral → equivale a salto de posición

## 6. Interfaz de usuario

El banner es **persistente** mientras `gpsSource.drActive` sea `true`.
Ocupa el texto central del statusBar con esta prioridad:

```
ttsPregenBusy > drActive > _statusCurrent > _startupMsg > _tileBusy > version
```

```qml
// qml/Main.qml — statusBar Label
text: root._ttsPregenBusy ? (i18n.tr("Pre-procesando motor TTS") + ...)
    : gpsSource.drActive  ? i18n.tr("GPS impreciso. Simulando trayecto.")
    : root._statusCurrent ? root._statusCurrent.text
    ...
color: root._ttsPregenBusy ? "#FFA000"
     : gpsSource.drActive  ? "#FF8A65"
     : root._statusCurrent ? root._statusCurrent.color
     ...
```

Al salir del DR, un bloque `Connections { onDrActiveChanged }` empuja
`"GPS recuperado"` (color `#81C784`) a `_statusQueue` (toast verde, 4 s).

## 7. Propiedades añadidas en GpsSource.qml

```qml
property bool drActive:     false   // visible desde Main.qml
property int  _drBadCount:  0
property int  _drGoodCount: 0
property real _drSpeedMs:   0
property var  _drRecovFix:  null
```

## Lista de verificación

- [ ] GPS real: activar `simSignalLost` mientras se navega → banner naranja aparece, icono sigue avanzando
- [ ] Desactivar `simSignalLost` → toast verde "GPS recuperado" tras ~3 s, icono resinca con GPS real
- [ ] `gpsFailEnabled` con `gpsFailDist=60 m` en sim: ticks desplazados > umbral → DR activo; ticks normales → recuperación en 3 fixes
- [ ] Sin ruta activa: GPS pierde fix → **no** entra en DR
- [ ] Vehículo parado (`_speedMs ≤ 1.0`): GPS pierde fix → **no** entra en DR
- [ ] Fin de ruta durante DR: `_walkShape` devuelve null → `drActive = false` sin crash
- [ ] Modo sim reproduce exactamente el mismo comportamiento que GPS real
- [ ] NavBar calcula distancias correctamente durante DR (ticks `source="dr"` llevan `isReal=true`)
