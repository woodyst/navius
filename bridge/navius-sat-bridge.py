#!/usr/bin/env python3
"""
navius-sat-bridge — lee VisibleSpaceVehicles de lomiri-location-service y
escribe /run/navius-sat.txt para que Navius muestre datos de satélites.

Requiere ejecutarse como root (crea sesión GPS que activa gps::Provider).
Instalación: ver install.sh
"""

import dbus
import dbus.mainloop.glib
from gi.repository import GLib
import struct
import time
import sys
import os

OUTPUT_FILE = "/run/navius-sat.txt"

def guess_system(prn):
    if 1  <= prn <= 32: return 1   # GPS
    if 65 <= prn <= 96: return 2   # GLONASS
    if 33 <= prn <= 64: return 1   # SBAS/WAAS
    return 0

def write_sats(sats):
    """Escribe la lista de satélites en formato texto de forma atómica."""
    tmp = OUTPUT_FILE + ".tmp"
    try:
        with open(tmp, 'w') as f:
            f.write(f"{int(time.time())}\n")
            f.write(f"{len(sats)}\n")
            for (prn, snr, az, el, used, sys_id) in sats:
                f.write(f"{prn} {snr:.2f} {az:.2f} {el:.2f} {int(used)} {sys_id}\n")
        os.rename(tmp, OUTPUT_FILE)
        print(f"[bridge] {len(sats)} sats → {OUTPUT_FILE}", flush=True, file=sys.stderr)
    except Exception as e:
        print(f"[bridge] write error: {e}", flush=True, file=sys.stderr)

def on_properties_changed(iface, changed, invalidated):
    if 'VisibleSpaceVehicles' not in changed:
        return

    svs_raw = changed['VisibleSpaceVehicles']
    sats = []
    try:
        for prn_key, fields in svs_raw.items():
            sv = list(fields)
            # Layout confirmado en location_props.cpp:
            # f1=snr  f2=has_almanac  f3=has_ephemeris  f4=used_in_fix
            # f5=azimuth  f6=elevation
            if len(sv) < 6:
                print(f"[bridge] sv {prn_key} solo {len(sv)} campos", file=sys.stderr)
                continue
            prn  = int(prn_key)
            snr  = float(sv[0])
            used = bool(sv[3])
            az   = float(sv[4])
            el   = float(sv[5])
            sats.append((prn, snr, az, el, used, guess_system(prn)))
    except Exception as e:
        print(f"[bridge] parse error: {e}", flush=True, file=sys.stderr)
        return

    write_sats(sats)

def create_root_session(bus):
    """Crea una sesión root en lomiri-location-service para activar gps::Provider."""
    try:
        svc = bus.get_object(
            'com.lomiri.location.Service',
            '/com/lomiri/location/Service')
        iface = dbus.Interface(svc, 'com.lomiri.location.Service')

        # 8 args: position, altitude, heading, velocity, h_accuracy, has_v, has_vel, has_hdg
        session_path = iface.CreateSessionForCriteria(
            True, False, False, False, 3000.0, False, False, False)

        print(f"[bridge] sesión root: {session_path}", flush=True, file=sys.stderr)

        session_obj = bus.get_object('com.lomiri.location.Service', str(session_path))
        session_iface = dbus.Interface(session_obj,
                                       'com.lomiri.location.Service.Session')
        session_iface.StartPositionUpdates()
        print("[bridge] StartPositionUpdates enviado", flush=True, file=sys.stderr)
        return session_obj
    except Exception as e:
        print(f"[bridge] error creando sesión: {e}", flush=True, file=sys.stderr)
        return None

if __name__ == '__main__':
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()

    # Suscribir a PropertiesChanged ANTES de crear la sesión
    bus.add_signal_receiver(
        on_properties_changed,
        signal_name='PropertiesChanged',
        dbus_interface='org.freedesktop.DBus.Properties',
        bus_name='com.lomiri.location.Service',
        path='/com/lomiri/location/Service')

    print("[bridge] suscrito a VisibleSpaceVehicles", flush=True, file=sys.stderr)

    # Crear sesión root para activar gps::Provider
    GLib.timeout_add(500, lambda: create_root_session(bus) and False)

    try:
        GLib.MainLoop().run()
    except KeyboardInterrupt:
        print("[bridge] detenido", file=sys.stderr)
        # Borrar archivo para que Navius sepa que no hay datos
        try:
            os.remove(OUTPUT_FILE)
        except FileNotFoundError:
            pass
