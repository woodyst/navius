# Waydroid Multi-Instance Setup

## Resumen

Se configuró una segunda instancia de Waydroid (`waydroid2`) en `/opt/waydroid2` que coexiste
independientemente con la instancia original (`waydroid` en `/var/lib/waydroid`).

## Archivos creados

| Archivo | Propósito |
|---|---|
| `/opt/waydroid2/` | Directorio de datos aislado (imágenes, LXC config, rootfs, overlay) |
| `/usr/local/bin/waydroid2` | Wrapper: ejecuta wrapper_runner.py con `--work /opt/waydroid2` |
| `/usr/lib/waydroid/wrapper_runner.py` | Patchea `tools.config.defaults["work"]` en runtime antes de que waydroid lo cargue, usando sitecustomize.py |
| `/lib/systemd/system/waydroid2-container.service` | Servicio systemd para el daemon D-Bus del contenedor (BusName: `id.waydro.Container.waydroid2`) |

## Parches aplicados a waydroid

### 1. `/usr/lib/waydroid/tools/helpers/lxc.py`
- Se añadió `import os`
- Se añadió variable `_CN = os.environ.get("WAYDROID_INSTANCE_NAME", "waydroid")` tras los imports
- Se añadió función `get_cn()` que retorna `_CN`
- Reemplazo de `"-n", "waydroid"` → `"-n", get_cn()` en todos los comandos LXC

### 2. `/usr/lib/waydroid/tools/actions/container_manager.py`
- Se añadió `import os`
- Se añadieron variables:
  ```python
  _CN = os.environ.get("WAYDROID_INSTANCE_NAME", "")
  if _CN:
      _BNAME = "id.waydro.Container." + _CN
  else:
      _BNAME = "id.waydro.Container"
  ```
- Reemplazo de `"id.waydro.Container"` → `_BNAME` en `dbus.service.BusName()`

### 3. `/usr/lib/waydroid/tools/actions/initializer.py`
- Se añadió `import os`
- Se añadieron variables:
  ```python
  _CN = os.environ.get("WAYDROID_INSTANCE_NAME", "")
  if _CN:
      _DB = "id.waydro.Initializer." + _CN
  else:
      _DB = "id.waydro.Initializer"
  INAME = _DB
  ```
- Reemplazo de `"id.waydro.Initializer"` → `INAME` en decoradores y llamadas D-Bus

## Política D-Bus

Se actualizó `/usr/share/dbus-1/system.d/id.waydro.Container.conf`:
```xml
<policy user="root">
    <allow own="id.waydro.Container"/>
    <allow own="id.waydro.Container.default"/>
    <allow own="id.waydro.Container.waydroid2"/>
    <allow own="id.waydro.Container.*"/>
</policy>
<policy context="default">
    <allow send_destination="id.waydro.Container"/>
    <allow send_destination="id.waydro.Container.default"/>
    <allow send_destination="id.waydro.Container.waydroid2"/>
    <allow receive_sender="id.waydro.Container"/>
    <allow receive_sender="id.waydro.Container.default"/>
    <allow receive_sender="id.waydro.Container.waydroid2"/>
</policy>
```

## Cómo funciona

1. Se ejecuta `waydroid2 [comando]` → invoca `wrapper_runner.py --work /opt/waydroid2 [comando]`
2. `wrapper_runner.py` crea un `sitecustomize.py` en site-packages de Python que parchea
   `tools.config.defaults["work"]` Y todos los paths derivados (images_path, rootfs, lxc, etc.)
3. El script ejecuta waydroid con `WAYDROID_INSTANCE_NAME=waydroid2` en el entorno
4. Los archivos patched leen esa variable para:
   - Nombre del contenedor LXC (`waydroid2` vs `waydroid`)
   - Nombre del bus D-Bus (`id.waydro.Container.waydroid2` vs `id.waydro.Container`)
   - Nombre de la interface D-Bus (`id.waydro.Initializer.waydroid2` vs `id.waydro.Initializer`)

## Comandos útiles

```bash
# Estado
sudo waydroid status          # instancia original
sudo waydroid2 status         # instancia aislada

# Servicios (daemon D-Bus del contenedor)
sudo systemctl start waydroid-container.service
sudo systemctl start waydroid2-container.service

# Arrancar/parar contenedor LXC
sudo waydroid container start    # via D-Bus manager del servicio original
sudo waydroid2 container start   # via D-Bus manager del servicio aislado

# Logs
tail -f /var/lib/waydroid/waydroid.log
tail -f /opt/waydroid2/waydroid.log

# Revertir a original (sin los cambios)
sudo apt-get install --reinstall waydroid

# Para crear una tercera instancia:
# 1. Copiar: sudo cp -a /opt/waydroid2 /opt/waydroid3
# 2. Actualizar wrapper: cambiar WAYDROID_INSTANCE_NAME a "waydroid3"
# 3. Agregar BusName al policy D-Bus
# 4. Crear servicio systemd correspondiente
```

## Red

Ambas instancias comparten el bridge `waydroid0` gestionado por `waydroid-net.sh`.
Cada contenedor tiene una MAC address diferente y recibe una IP distinta del dnsmasq.

Si se necesitan redes completamente separadas, habría que:
1. Crear un bridge LXC adicional (ej: `lxcbr1`)
2. Modificar el config de waydroid2 para usar ese bridge
3. Copiar `waydroid-net.sh` como `waydroid2-net.sh` con diferente subred

## Notas

- La sesión (`waydroid2 session start`) requiere un display Wayland/X11 disponible.
  En un servidor headless, el contenedor LXC puede correr sin interfaz gráfica.
- Los datos de apps, configuraciones y downloads son completamente independientes entre instancias.
- El servicio `waydroid2-container.service` debe estar activo para que `waydroid2` pueda comunicar
  con el contenedor vía D-Bus.

---

## Arreglo del 26/09/2026: ninguna instancia arrancaba

Escrito desde la sesión de Navius Android, que se topó con esto al querer usar
el banco de pruebas. **Tres cosas estaban rotas**, y las tres afectaban a las
dos instancias, no solo a la de UT.

### 1. `get_cn_dontexist()` en `lxc.py`

El parche del punto 1 de arriba —sustituir `"-n", "waydroid"` por `"-n",
get_cn()`— dejó **ocho llamadas escritas como `get_cn_dontexist()`**, función
que no existe en ningún sitio (líneas 386, 407, 416, 420, 425, 444, 466). La
definición sí estaba bien: `def get_cn()` en la línea 20.

Resultado: cualquier `session start`, de la instancia que fuera, moría con

```
org.freedesktop.DBus.Python.NameError: ...
NameError: name 'get_cn_dontexist' is not defined
```

y el error salía **por D-Bus desde el gestor de contenedor**, así que no se
parecía a lo que era. Arreglado con un `sed` a `get_cn()`. Copia previa en
`/usr/lib/waydroid/tools/helpers/lxc.py.bak-20260926`.

### 2. Los nodos binder no se llamaban como decía la configuración

El módulo `binder_linux` de Debian crea por omisión `anbox-binder`,
`anbox-vndbinder` y `anbox-hwbinder`. Las dos `waydroid.cfg` pedían
`binder`/`vndbinder`/`hwbinder`, que no existían, así que el contenedor
arrancaba y se moría a los cuatro segundos con `Can't open /dev/binder`.

Waydroid acepta los dos juegos de nombres —los `anbox-*` están **los primeros**
en `tools/helpers/drivers.py`—, pero tienen que coincidir en tres sitios:

1. `/sys/module/binder_linux/parameters/devices`
2. las claves `binder`, `vndbinder` y `hwbinder` de cada `waydroid.cfg`
3. las tres `lxc.mount.entry` de `<work>/lxc/<instancia>/config_nodes`, que
   montan el nodo del anfitrión como `/dev/binder` dentro del contenedor

**Y el módulo no se puede descargar**: `rmmod` contesta siempre «Device or
resource busy» aunque el refcount sea 0 y no haya ningún contenedor. O sea que
si los nombres no cuadran, no hay arreglo sin reiniciar la máquina. Por eso se
optó por adaptarse a los nombres del módulo y no al revés:

- `/etc/modprobe.d/waydroid-binder.conf` fija ahora
  `devices=anbox-binder,anbox-vndbinder,anbox-hwbinder`.
- Las dos `waydroid.cfg` apuntan a esos nombres (copias `.bak-20260926`).
- `config_nodes` de la instancia 1, también. **La de `/opt/waydroid2` está sin
  tocar**: se regenera al inicializar, y no había contenedor de UT que probar.
  Si al arrancar UT aparece `Can't open /dev/binder`, es eso.

### 3. Propiedades perdidas en `waydroid_base.prop` (instancia 1)

`waydroid_base.prop` **se regenera**, y se había llevado por delante dos líneas
puestas el 02/09 sin las que el banco no se puede manejar por adb:

- `ro.adb.secure=0`, o adb se queda en `unauthorized` y no hay pantalla donde
  aceptar el diálogo.
- `persist.waydroid.suspend=false`, o el contenedor pasa a FROZEN en cuanto no
  hay ventana visible y `adb shell` se cuelga sin decir nada.

Las dos vuelven a estar. Si desaparecen otra vez, mirar qué las borra antes de
volver a ponerlas.

### Estado al terminar

Instancia 1 (Navius) **funcionando**: contenedor RUNNING, IP 192.168.240.112,
adb conectado, APK x86_64 instalado y la app corriendo y traducida. Instancia 2:
`waydroid2-container.service` levantado, contenedor parado y `/opt/waydroid2`
todavía sin datos de app, igual que estaba. Las dos siguen sin arrancar solas.
