#!/usr/bin/env python3
"""navius_tui.py — Control remoto de Navius via SSH + fichero de comandos."""

import curses, subprocess, threading, time, re, json, os, shlex

HOST      = "phablet@eut"
DATA_DIR  = "/home/phablet/.local/share/navius.woodyst"
CMD_F     = f"{DATA_DIR}/navius_cmd"
ACK_F     = f"{DATA_DIR}/navius_ack"
ROUTE_F   = f"{DATA_DIR}/navius_route"
PARAMS_F  = os.path.expanduser("~/.navius_tui_params.json")

SIM_ROUTE_NAMES = [
    "Provença→Pl.Catalunya BCN",
    "Test fijo 1 (NO)",
    "Test fijo 2 (SE)",
    "Test tramo",
    "Ruta usuario",
]

# ── Estado remoto (actualizado por hilo de polling) ───────────────────────
st = {
    'mode':'?/?', 'pitch':0, 'bear':0, 'mpp':0.0, 'cy':0,
    'fov':18.435,
    'poi':False, 'follow':False, 'paused':False, 'cmd':'', 'ack_t':'--:--:--',
    'sim_mode': False, 'sim_route': 0,
    'rv': False, 'rv_pts':0,
    'rv_zoom':0.0, 'rv_zH':0.0, 'rv_zW':0.0,
    'rv_dLat':0.0, 'rv_dLon':0.0,
    'rv_cLat':0.0, 'rv_cLon':0.0,
    'rv_vH':0.0,   'rv_vW':0.0,
    'rv_spanV':0.0,'rv_spanH':0.0,
    'rv_mpp':0.0,  'rv_mppT':0.0, 'rv_savedZ':0.0,
    'az_spd':0.0, 'az_secs':15, 'az_mpp':0.0, 'az_pxR':0.0,
    'az_mapH':0.0, 'az_dist':0.0, 'az_tMpp':0.0, 'az_zoom':0.0,
}
rt = {
    'active': False,
    'dist_m': -1, 'eta_s': -1, 'limit_kmh': 0, 'speed_kmh': 0,
    'lat': 0.0, 'lon': 0.0, 'maneuver': '',
    'sim_mode': False, 'sim_route_idx': 0,
    'sim_seg': 0, 'sim_total': 0,
}
st_lock = threading.Lock()
rt_lock = threading.Lock()

# ── Sliders ───────────────────────────────────────────────────────────────
sliders = [
    {'name':'PITCH',   'val':0.0,  'min':0,   'max':60,   'step':1,   'big':5,
     'fmt':'%.0f°', 'send': lambda v: f'pitch{v:.0f}'},
    {'name':'ZOOM',    'val':13.0, 'min':12,  'max':20,   'step':0.1, 'big':1,
     'fmt':'%.2f',  'send': lambda v: f'zoom{v:.2f}'},
    {'name':'BEARING', 'val':0.0,  'min':0,   'max':359,  'step':5,   'big':45,
     'fmt':'%.0f°', 'send': lambda v: f'bear{v:.0f}'},
]
cur_sl = 0

PARAM_KEYS = ['pitch', 'zoom', 'bearing']

# Campos de posición manual
pos_fields = [
    {'label': 'Lat', 'value': '', 'buf': ''},
    {'label': 'Lon', 'value': '', 'buf': ''},
]
pos_editing = False   # True cuando se está editando un campo
pos_cur_f   = 0       # campo activo (0=lat, 1=lon)


def _save_params():
    data = {PARAM_KEYS[i]: sliders[i]['val'] for i in range(len(sliders))}
    data['pos_lat'] = pos_fields[0]['value']
    data['pos_lon'] = pos_fields[1]['value']
    try:
        with open(PARAMS_F, 'w') as f:
            json.dump(data, f, indent=2)
    except OSError:
        pass


def _load_params():
    try:
        with open(PARAMS_F) as f:
            data = json.load(f)
        for i, key in enumerate(PARAM_KEYS):
            if key in data:
                sl = sliders[i]
                sl['val'] = max(sl['min'], min(sl['max'], float(data[key])))
        if 'pos_lat' in data:
            pos_fields[0]['value'] = str(data['pos_lat'])
            pos_fields[0]['buf']   = pos_fields[0]['value']
        if 'pos_lon' in data:
            pos_fields[1]['value'] = str(data['pos_lon'])
            pos_fields[1]['buf']   = pos_fields[1]['value']
    except (OSError, ValueError, KeyError):
        pass


# ── SSH helpers ───────────────────────────────────────────────────────────
def send(cmd_or_cmds):
    ts = f'{time.time():.6f}'
    if isinstance(cmd_or_cmds, list):
        # Batch: primera línea = timestamp, resto = comandos
        content = ts + '\n' + '\n'.join(cmd_or_cmds) + '\n'
    else:
        # Legado: cmd\ntimestamp (timestamp hace el contenido único para dedup)
        content = f'{cmd_or_cmds}\n{ts}\n'
    remote = f'printf %s {shlex.quote(content)} > {CMD_F}'
    subprocess.Popen(['ssh', HOST, remote],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _ssh_read(remote_path):
    try:
        r = subprocess.run(
            ['ssh', HOST, f'cat {remote_path} 2>/dev/null'],
            capture_output=True, text=True, timeout=4)
        return r.stdout.strip()
    except Exception:
        return ''


def poll_loop():
    while True:
        try:
            txt = _ssh_read(ACK_F)
            _parse_ack(txt)
        except Exception:
            pass
        try:
            rtxt = _ssh_read(ROUTE_F)
            _parse_route(rtxt)
        except Exception:
            pass
        time.sleep(0.8)


def _parse_ack(txt):
    if not txt:
        return
    def g(pat, conv=str, default=None):
        m = re.search(pat, txt)
        return conv(m.group(1)) if m else default
    with st_lock:
        st['mode']   = g(r'mode=(\S+)',          str,   st['mode'])
        st['pitch']  = g(r'pitch=(\d+)',          int,   st['pitch'])
        st['bear']   = g(r'bear=(\d+)',           int,   st['bear'])
        st['mpp']    = g(r'mpp=([\d.]+)',         float, st['mpp'])
        st['cy']     = g(r'cy=(\d+)',             int,   st['cy'])
        st['fov']    = g(r'fov=([\d.]+)',         float, st['fov'])
        st['poi']      = g(r'poi=(true|false)',      str,   'false') == 'true'
        st['follow']   = g(r'follow=(true|false)',   str,   'false') == 'true'
        st['paused']   = g(r'paused=(true|false)',   str,   'false') == 'true'
        st['sim_mode'] = g(r'sim_mode=(true|false)', str,   'false') == 'true'
        st['sim_route']= g(r'sim_route=(\d+)',       int,   st['sim_route'])
        st['rv']       = g(r'\brv=(true|false)',      str,   'false') == 'true'
        st['rv_pts']   = g(r'rv_pts=(\d+)',           int,   0)
        st['rv_zoom']  = g(r'rv_zoom=([\d.-]+)',      float, 0.0)
        st['rv_zH']    = g(r'rv_zH=([\d.-]+)',        float, 0.0)
        st['rv_zW']    = g(r'rv_zW=([\d.-]+)',        float, 0.0)
        st['rv_dLat']  = g(r'rv_dLat=([\d.-]+)',      float, 0.0)
        st['rv_dLon']  = g(r'rv_dLon=([\d.-]+)',      float, 0.0)
        st['rv_cLat']  = g(r'rv_cLat=([\d.-]+)',      float, 0.0)
        st['rv_cLon']  = g(r'rv_cLon=([\d.-]+)',      float, 0.0)
        st['rv_vH']    = g(r'rv_vH=([\d.-]+)',         float, 0.0)
        st['rv_vW']    = g(r'rv_vW=([\d.-]+)',         float, 0.0)
        st['rv_spanV'] = g(r'rv_spanV=([\d.-]+)',      float, 0.0)
        st['rv_spanH'] = g(r'rv_spanH=([\d.-]+)',      float, 0.0)
        st['rv_mpp']   = g(r'rv_mpp=([\d.-]+)',        float, 0.0)
        st['rv_mppT']  = g(r'rv_mppT=([\d.-]+)',       float, 0.0)
        st['rv_savedZ']= g(r'rv_savedZ=([\d.-]+)',     float, 0.0)
        st['az_spd']   = g(r'AZ: spd=([\d.]+)',        float, st['az_spd'])
        st['az_secs']  = g(r'secs=(\d+)',              int,   st['az_secs'])
        st['az_mpp']   = g(r'AZ:.*mpp=([\d.]+)',       float, st['az_mpp'])
        st['az_pxR']   = g(r'pxR=([\d.]+)',            float, st['az_pxR'])
        st['az_mapH']  = g(r'mapH=([\d.]+)',           float, st['az_mapH'])
        st['az_dist']  = g(r'dist=([\d.]+)',           float, st['az_dist'])
        st['az_tMpp']  = g(r'tMpp=([\d.]+)',           float, st['az_tMpp'])
        st['az_zoom']  = g(r'AZ:.*zoom=([\d.]+)',      float, st['az_zoom'])
        st['cmd']      = g(r'CMD:\s*(\S+)',            str,   st['cmd'])
        m = re.match(r'\d{4}-\d{2}-\d{2}T(\d{2}:\d{2}:\d{2})', txt)
        if m:
            st['ack_t'] = m.group(1)


def _parse_route(txt):
    if not txt:
        return
    try:
        data = json.loads(txt)
        with rt_lock:
            rt['active']        = data.get('active', False)
            rt['dist_m']        = data.get('dist_m', -1)
            rt['eta_s']         = data.get('eta_s', -1)
            rt['limit_kmh']     = data.get('limit_kmh', 0)
            rt['speed_kmh']     = data.get('speed_kmh', 0)
            rt['lat']           = data.get('lat', 0.0)
            rt['lon']           = data.get('lon', 0.0)
            rt['maneuver']      = data.get('maneuver', '')
            rt['sim_mode']      = data.get('sim_mode', False)
            rt['sim_route_idx'] = data.get('sim_route_idx', 0)
            rt['sim_seg']       = data.get('sim_seg', 0)
            rt['sim_total']     = data.get('sim_total', 0)
    except (ValueError, KeyError):
        pass


# ── Presets ───────────────────────────────────────────────────────────────
def preset_debug():
    cmds = ['heading', 'follow', 'zoom13.14', 'pitch0', 'pause']
    with st_lock:
        if not st['poi']:   cmds.insert(2, 'poi')
    for cmd in cmds:
        send(cmd)
        time.sleep(0.5)
    send('dbg')


def preset_reset():
    for cmd in ['north', '2d', 'follow', 'resume']:
        send(cmd)
        time.sleep(0.5)


# ── TUI ───────────────────────────────────────────────────────────────────
def tui(scr):
    global cur_sl, pos_editing, pos_cur_f

    curses.curs_set(0)
    scr.nodelay(True)

    if curses.has_colors():
        curses.start_color()
        curses.use_default_colors()
        curses.init_pair(1, curses.COLOR_CYAN,   -1)
        curses.init_pair(2, curses.COLOR_GREEN,  -1)
        curses.init_pair(3, curses.COLOR_YELLOW, -1)
        curses.init_pair(4, curses.COLOR_RED,    -1)
        curses.init_pair(5, curses.COLOR_BLACK,  curses.COLOR_CYAN)
        curses.init_pair(6, curses.COLOR_BLACK,  curses.COLOR_GREEN)
        curses.init_pair(7, curses.COLOR_WHITE,  curses.COLOR_BLUE)
        curses.init_pair(8, curses.COLOR_BLACK,  curses.COLOR_WHITE)
        curses.init_pair(9, curses.COLOR_WHITE,  curses.COLOR_RED)

    CYA = curses.color_pair(1)
    GRN = curses.color_pair(2)
    YEL = curses.color_pair(3)
    RED = curses.color_pair(4)
    SEL = curses.color_pair(5)
    BON = curses.color_pair(6)
    BTN = curses.color_pair(7)
    FLD = curses.color_pair(8)
    ERR = curses.color_pair(9)
    BLD = curses.A_BOLD

    def a(r, c, s, attr=0):
        try:
            scr.addstr(r, c, str(s), attr)
        except curses.error:
            pass

    def hline(r):
        h, w = scr.getmaxyx()
        a(r, 0, '─' * max(1, w - 1), CYA)

    def btn(r, c, label, active):
        a(r, c, f' {label} ', BON | BLD if active else BTN)

    def eta_str(secs):
        if secs < 0: return '--:--'
        m, s = divmod(int(secs), 60)
        h, m = divmod(m, 60)
        if h > 0: return f'{h}h{m:02d}m'
        return f'{m}:{s:02d}'

    def dist_str(m):
        if m < 0: return '---'
        if m >= 1000: return f'{m/1000:.1f}km'
        return f'{m}m'

    while True:
        h, w = scr.getmaxyx()
        scr.erase()

        # ── Título ────────────────────────────────────────────────────────
        title = '  NAVIUS REMOTE CONTROL  '
        a(0, max(0, (w - len(title)) // 2), title, CYA | BLD)
        hline(1)

        # ── Estado remoto ─────────────────────────────────────────────────
        with st_lock:
            s = dict(st)

        a(2, 2, f"mode={s['mode']}  pitch={s['pitch']}°  bear={s['bear']}°"
                f"  mpp={s['mpp']:.4f}  cy={s['cy']}  fov={s['fov']:.3f}°", YEL)
        a(3, 2,  'follow=', 0)
        a(3, 9,  'ON ' if s['follow'] else 'OFF', GRN if s['follow'] else RED)
        a(3, 13, '  poi=', 0)
        a(3, 19, 'ON ' if s['poi']    else 'OFF', GRN if s['poi']    else RED)
        a(3, 23, '  paused=', 0)
        a(3, 32, 'YES' if s['paused'] else 'NO ', YEL if s['paused'] else 0)
        a(3, 36, f"  último cmd={s['cmd']}", CYA)
        hline(4)

        # ── Botones — modos ───────────────────────────────────────────────
        bm, mm = s['mode'].split('/') if '/' in s['mode'] else ('?', '?')
        a(5, 2, '[!]', YEL | BLD);  btn(5,  5, '2D',      mm == '2d')
        a(5,10, '[@]', YEL | BLD);  btn(5, 13, '3D',      mm == '3d')
        a(5,18, '[n]', YEL | BLD);  btn(5, 21, 'North  ', bm == 'north')
        a(5,31, '[h]', YEL | BLD);  btn(5, 34, 'Heading', bm == 'heading')

        # ── Botones — sim / follow / debug ────────────────────────────────
        a(6, 2, '[p]', YEL | BLD);  btn(6,  5, 'Pause ', s['paused'])
        a(6,13, '[r]', YEL | BLD);  btn(6, 16, 'Resume', not s['paused'])
        a(6,25, '[f]', YEL | BLD);  btn(6, 28, 'Follow', s['follow'])
        a(6,36, '[s]', YEL | BLD);  a(6, 39, 'SimToggle  ', 0)
        a(6,51, '[o]', YEL | BLD);  btn(6, 54, 'POI', s['poi'])
        a(6,59, '[d]', YEL | BLD);  a(6, 62, 'DBG  ', 0)
        a(6,68, '[c]', YEL | BLD);  a(6, 71, 'Shot  ', 0)
        a(6,78, '[v]', YEL | BLD);  btn(6, 81, 'RouteView', s['rv'])
        hline(7)

        # ── Sliders ───────────────────────────────────────────────────────
        bar_w = max(20, min(40, w - 42))
        for i, sl in enumerate(sliders):
            sel   = (i == cur_sl)
            frac  = max(0.0, min(1.0, (sl['val'] - sl['min']) / (sl['max'] - sl['min'])))
            filled = int(frac * bar_w)
            bar   = '█' * filled + '─' * (bar_w - filled)
            val   = sl['fmt'] % sl['val']
            rng   = f"[{sl['min']:.0f}‥{sl['max']:.0f}]"
            pfx   = '►' if sel else ' '
            attr  = SEL | BLD if sel else 0
            r     = 8 + i
            a(r, 2,  f"{pfx} {sl['name']:7s} {rng:11s}", attr)
            a(r, 26, bar, GRN | BLD if sel else CYA)
            a(r, 26 + bar_w + 1, f'{val:>8}', YEL | BLD)
            if sel:
                a(r, 26 + bar_w + 10, '  ←→ valor  PgUp/Dn grande  Enter reenvía', CYA)

        sep_row = 8 + len(sliders)
        hline(sep_row)

        # ── Posición manual ───────────────────────────────────────────────
        r0 = sep_row + 1
        a(r0, 2, 'POSICIÓN MANUAL:', CYA | BLD)
        a(r0, 19, '[Tab]', YEL | BLD); a(r0, 24, 'campo siguiente  ', 0)
        a(r0, 41, '[e]', YEL | BLD);   a(r0, 44, 'editar  ', 0)
        a(r0, 53, '[G]', YEL | BLD);   a(r0, 56, 'enviar  ', 0)
        a(r0, 65, '[X]', YEL | BLD);   a(r0, 68, 'liberar', 0)

        for fi, pf in enumerate(pos_fields):
            editing_this = pos_editing and (pos_cur_f == fi)
            label = f" {pf['label']}: "
            val   = (pf['buf'] if pos_editing and pos_cur_f == fi else pf['value']).ljust(18)
            fattr = FLD | BLD if editing_this else (SEL if fi == pos_cur_f else 0)
            col   = 2 + fi * 32
            a(r0 + 1, col, label, YEL | BLD)
            a(r0 + 1, col + len(label), val, fattr)
            if editing_this:
                a(r0 + 1, col + len(label) + len(val), '◄', CYA | BLD)

        hline(r0 + 2)

        # ── Rutas sim ─────────────────────────────────────────────────────
        r1 = r0 + 3
        with rt_lock:
            rv = dict(rt)

        a(r1, 2, 'RUTAS SIM:', CYA | BLD)
        a(r1, 12, '[0-4] seleccionar y aplicar', YEL)
        sm_on  = rv['sim_mode']
        sm_idx = rv['sim_route_idx']
        col = 2
        for ri, rname in enumerate(SIM_ROUTE_NAMES):
            label = f' [{ri}] {rname} '
            attr  = (GRN | BLD) if (sm_on and sm_idx == ri) else 0
            a(r1 + 1, col, label, attr)
            col += len(label) + 1
        if sm_on and rv['sim_seg'] > 0:
            pct = int(rv['sim_seg'] * 100 / max(1, rv['sim_total'] - 1))
            a(r1 + 2, 2, f"sim: seg {rv['sim_seg']}/{rv['sim_total']}  ({pct}%)"
                        + f"  pos: {rv['lat']:.5f},{rv['lon']:.5f}"
                        + f"  {rv['speed_kmh']} km/h", GRN if sm_on else 0)
        else:
            a(r1 + 2, 2, f"sim: {'ON' if sm_on else 'OFF'}  pos: {rv['lat']:.5f},{rv['lon']:.5f}", 0)
        hline(r1 + 3)

        # ── Ruta en curso ─────────────────────────────────────────────────
        r1b = r1 + 4
        if rv['active']:
            a(r1b, 2, 'RUTA:', GRN | BLD)
            a(r1b, 8, f"  dist: {dist_str(rv['dist_m'])}", 0)
            a(r1b, 24, f"  ETA: {eta_str(rv['eta_s'])}", 0)
            spd_attr = RED | BLD if rv['limit_kmh'] > 0 and rv['speed_kmh'] > rv['limit_kmh'] else 0
            a(r1b, 38, f"  vel: {rv['speed_kmh']} km/h", spd_attr)
            if rv['limit_kmh'] > 0:
                a(r1b, 52, f"  lím: {rv['limit_kmh']} km/h", YEL)
            man = rv['maneuver'][:w - 4] if rv['maneuver'] else '(sin maniobra)'
            a(r1b + 1, 2, f"Maniobra: {man}", 0)
        else:
            a(r1b, 2, 'RUTA: sin navegación activa', 0)

        hline(r1b + 2)

        # ── RouteView debug ───────────────────────────────────────────────
        r1c = r1b + 3
        rv_on = s['rv']
        a(r1c, 2, 'ROUTEVIEW:', CYA | BLD)
        btn(r1c, 13, 'OPEN' if rv_on else 'CLOSED', rv_on)
        a(r1c, 24, '[v] toggle', YEL)
        if s['rv_pts'] > 0:
            a(r1c, 36, f"pts={s['rv_pts']}  "
                       f"spanV={s['rv_spanV']:.0f}m  spanH={s['rv_spanH']:.0f}m  "
                       f"vH={s['rv_vH']:.0f}px  vW={s['rv_vW']:.0f}px", 0)
            a(r1c+1, 2, f"savedZ={s['rv_savedZ']:.2f}  "
                        f"mpp={s['rv_mpp']:.4f}  mppT={s['rv_mppT']:.4f}  "
                        f"zH={s['rv_zH']:.2f}  zW={s['rv_zW']:.2f}  "
                        f"zoom={s['rv_zoom']:.2f}", YEL | BLD)
        else:
            a(r1c, 36, '(sin datos — abrir RouteView primero)', 0)
            a(r1c+1, 2, '', 0)
        hline(r1c + 2)
        raz = r1c + 3
        a(raz, 2, 'AUTO-ZOOM:', CYA | BLD)
        a(raz, 13, f"spd={s['az_spd']:.1f}km/h  secs={s['az_secs']}s  "
                   f"mpp={s['az_mpp']:.5f}  pxR={s['az_pxR']:.0f}  mapH={s['az_mapH']:.0f}", 0)
        a(raz+1, 2, f"  dist={s['az_dist']:.1f}m  tMpp={s['az_tMpp']:.5f}  "
                    f"zoom={s['az_zoom']:.3f}", YEL | BLD)
        a(raz+1, 55, '  [ ] azsecs-5    ] [ azsecs+5', CYA)
        hline(raz + 2)
        r2 = raz + 3

        # ── Presets & ayuda ───────────────────────────────────────────────
        a(r2,   2,  '[F1]', YEL | BLD);  a(r2,   6, ' Debug Setup   ', 0)
        a(r2,  22,  '[F2]', YEL | BLD);  a(r2,  26, ' Reset normal  ', 0)
        a(r2+1, 2,  '[↑↓]', YEL | BLD);  a(r2+1, 6, ' Seleccionar slider  ', 0)
        a(r2+1,28,  '[←→]', YEL | BLD);  a(r2+1,32, ' Cambiar valor  ', 0)
        a(r2+1,49,  '[q/Esc]', YEL | BLD); a(r2+1,56, ' Salir', 0)
        hline(r2 + 2)
        a(r2+3, 2, f"Ack: {s['ack_t']}  |  {HOST}  |  {CMD_F}", CYA)

        scr.refresh()

        # ── Input ─────────────────────────────────────────────────────────
        try:
            key = scr.getch()
        except Exception:
            key = -1

        if key == -1:
            time.sleep(0.04)
            continue

        # Modo edición de campo de posición
        if pos_editing:
            pf = pos_fields[pos_cur_f]
            if key in (10, 13, curses.KEY_ENTER, ord('\t'), curses.KEY_BTAB):
                # Confirmar campo y pasar al siguiente o terminar edición
                pf['value'] = pf['buf']
                pos_cur_f = (pos_cur_f + 1) % len(pos_fields)
                if key not in (ord('\t'), curses.KEY_BTAB):
                    pos_editing = (pos_cur_f != 0)  # cierra al llegar al final
            elif key == 27:
                pf['buf'] = pf['value']
                pos_editing = False
            elif key in (curses.KEY_BACKSPACE, 127, 8):
                pf['buf'] = pf['buf'][:-1]
            elif 32 <= key < 127:
                pf['buf'] += chr(key)
            continue

        sl = sliders[cur_sl]

        def clamp(v, lo, hi):
            return round(max(lo, min(hi, v)), 4)

        if key in (ord('q'), 27):
            break

        elif key == curses.KEY_UP or key == ord('\t'):
            cur_sl = (cur_sl - 1) % len(sliders)
        elif key == curses.KEY_DOWN or key == curses.KEY_BTAB:
            cur_sl = (cur_sl + 1) % len(sliders)

        elif key == curses.KEY_RIGHT:
            sl['val'] = clamp(sl['val'] + sl['step'], sl['min'], sl['max'])
            send(sl['send'](sl['val'])); _save_params()
        elif key == curses.KEY_LEFT:
            sl['val'] = clamp(sl['val'] - sl['step'], sl['min'], sl['max'])
            send(sl['send'](sl['val'])); _save_params()
        elif key == curses.KEY_PPAGE:
            sl['val'] = clamp(sl['val'] + sl['big'], sl['min'], sl['max'])
            send(sl['send'](sl['val'])); _save_params()
        elif key == curses.KEY_NPAGE:
            sl['val'] = clamp(sl['val'] - sl['big'], sl['min'], sl['max'])
            send(sl['send'](sl['val'])); _save_params()
        elif key in (10, 13, curses.KEY_ENTER):
            send(sl['send'](sl['val'])); _save_params()

        # Rutas sim
        elif key == ord('0'): send('simroute0')
        elif key == ord('1'): send('simroute1')
        elif key == ord('2'): send('simroute2')
        elif key == ord('3'): send('simroute3')
        elif key == ord('4'): send('simroute4')

        # Modos 2D/3D
        elif key == ord('!'): send('2d')
        elif key == ord('@'): send('3d')
        elif key == ord('n'): send('north')
        elif key == ord('h'): send('heading')
        elif key == ord('f'): send('follow')
        elif key == ord('p'): send('pause')
        elif key == ord('r'): send('resume')
        elif key == ord('s'): send('sim')
        elif key == ord('o'): send('poi')
        elif key == ord('d'): send('dbg')
        elif key == ord('c'): send('shot')
        elif key == ord('v'): send('routeview')

        elif key == ord('['):
            new_secs = max(5, st['az_secs'] - 5)
            send(f'azsecs{new_secs}')
        elif key == ord(']'):
            new_secs = min(120, st['az_secs'] + 5)
            send(f'azsecs{new_secs}')

        # Posición manual
        elif key == ord('e'):
            # Iniciar edición del campo activo
            pos_editing = True
            pos_fields[pos_cur_f]['buf'] = pos_fields[pos_cur_f]['value']

        elif key == ord('G'):
            # Enviar posición
            try:
                lat = float(pos_fields[0]['value'])
                lon = float(pos_fields[1]['value'])
                send(f'pos{lat:.6f},{lon:.6f}')
                _save_params()
            except ValueError:
                pass

        elif key == ord('X'):
            # Liberar posición manual
            send('posoff')

        elif key == curses.KEY_F1:
            threading.Thread(target=preset_debug, daemon=True).start()
        elif key == curses.KEY_F2:
            threading.Thread(target=preset_reset, daemon=True).start()


# ── Entry point ───────────────────────────────────────────────────────────
if __name__ == '__main__':
    _load_params()
    threading.Thread(target=poll_loop, daemon=True).start()
    try:
        curses.wrapper(tui)
    except KeyboardInterrupt:
        pass
    print(f"Hasta luego.  Parámetros guardados en {PARAMS_F}")
