use cpp::cpp;
use qmetaobject::*;
use std::collections::HashSet;
use std::sync::{Mutex, OnceLock};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::io::Write;

static TTS_LOCK:        Mutex<()>   = Mutex::new(());
static PREGEN_ACTIVE:   AtomicBool  = AtomicBool::new(false);
static PREGEN_TOTAL:    AtomicUsize = AtomicUsize::new(0);
static PREGEN_DONE:     AtomicUsize = AtomicUsize::new(0);
// Set to true by play_round_then_instr to interrupt any ongoing WAV playback.
static PLAYBACK_CANCEL: AtomicBool  = AtomicBool::new(false);

/// Called from C++ navius_play_wav to check if playback should stop.
#[no_mangle]
pub extern "C" fn navius_is_cancelled() -> bool {
    PLAYBACK_CANCEL.load(Ordering::SeqCst)
}

// Serializa todos los procesos piper: el worker de la cola y say_piper comparten este mutex.
static PIPER_PROC_LOCK: Mutex<()> = Mutex::new(());

// Cola FIFO de jobs de pre-generación. El worker consume de uno en uno.
static PIPER_TX: OnceLock<std::sync::mpsc::SyncSender<PiperJob>> = OnceLock::new();

struct PiperJob { voice: String, text: String, out_path: String, key: String }

fn piper_enqueue(job: PiperJob) {
    let tx = PIPER_TX.get_or_init(|| {
        let (tx, rx) = std::sync::mpsc::sync_channel::<PiperJob>(256);
        std::thread::Builder::new()
            .name("piper-worker".to_string())
            .spawn(move || {
                for job in rx {
                    if !std::path::Path::new(&job.out_path).exists() {
                        generate_piper_wav(&job.voice, &job.text, &job.out_path, 1);
                    }
                    generating().lock().unwrap_or_else(|e| e.into_inner()).remove(&job.key);
                    PREGEN_DONE.fetch_add(1, Ordering::SeqCst);
                    let done  = PREGEN_DONE.load(Ordering::SeqCst);
                    let total = PREGEN_TOTAL.load(Ordering::SeqCst);
                    if total > 0 && done >= total && PREGEN_ACTIVE.load(Ordering::SeqCst) {
                        PREGEN_ACTIVE.store(false, Ordering::SeqCst);
                        log("pregenerate_round_dists: completado");
                    }
                }
            })
            .expect("piper worker spawn");
        tx
    });
    let _ = tx.send(job);
}

const APP_ROOT:        &str = "/opt/click.ubuntu.com/navius.woodyst/current";
#[allow(dead_code)]
const DATA_DIR:        &str = "/home/phablet/.local/share/navius.woodyst";
const PIPER_VOICES_DIR:&str = "/home/phablet/.local/share/navius.woodyst/tts-voices/piper";
const CACHE_LIVE_DIR:  &str = "/home/phablet/.local/share/navius.woodyst/tts_cache/tts_cache_live";
const CACHE_ROUND_DIR: &str = "/home/phablet/.local/share/navius.woodyst/tts_cache/tts_cache_round";
const CACHE_TMP_DIR:   &str = "/home/phablet/.local/share/navius.woodyst/tts_cache/tts_tmp";

/// Distancias de redondeo pre-generables (metros). Corresponden a los valores
/// que puede producir _roundDist() en NavBar.qml.
const ROUND_DISTANCES: &[i32] = &[
    10, 20, 30, 40, 50, 60, 70, 80, 90, 100,
    150, 200, 250, 300,
    400, 500,
    600, 800, 1000,
    2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000,
];

fn log(msg: &str) {
    let flag = format!("{DATA_DIR}/debug/.traces_enabled");
    if !std::path::Path::new(&flag).exists() { return; }
    let path = format!("{DATA_DIR}/debug/tts_debug.log");
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(f, "{}", msg);
    }
}

// ── TTS engine factory ───────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq)]
enum Engine { Piper, MimicHts, PicoTts, Espeak }

struct TtsState {
    engine:          Engine,
    voice:           String,
    engine_override: Option<Engine>,  // None = auto
}

static TTS_STATE:   OnceLock<Mutex<TtsState>>       = OnceLock::new();
static GENERATING:  OnceLock<Mutex<HashSet<String>>> = OnceLock::new();

fn generating() -> &'static Mutex<HashSet<String>> {
    GENERATING.get_or_init(|| Mutex::new(HashSet::new()))
}

fn tts_state() -> &'static Mutex<TtsState> {
    TTS_STATE.get_or_init(|| {
        Mutex::new(TtsState { engine: Engine::Espeak, voice: "es".to_string(), engine_override: None })
    })
}

// ── Language → voice mappings ────────────────────────────────────────────────

/// Returns path to a Piper .onnx voice file for the given lang code.
/// Accepts exact match (e.g. "es.onnx") or prefix match (e.g. "es_ES-davefx-medium.onnx" for "es").
fn piper_voice(lang_code: &str) -> Option<String> {
    let exact = format!("{PIPER_VOICES_DIR}/{lang_code}.onnx");
    if std::path::Path::new(&exact).exists() {
        log(&format!("piper_voice({lang_code}): exact {exact}"));
        return Some(exact);
    }
    let lc = lang_code.to_lowercase();
    let mut matches: Vec<String> = std::fs::read_dir(PIPER_VOICES_DIR)
        .into_iter().flatten().flatten()
        .filter_map(|e| {
            let n = e.file_name().to_string_lossy().to_lowercase();
            let after_prefix = n.strip_prefix(&lc);
            let ok = matches!(after_prefix, Some(s) if s.starts_with(['_', '-', '.']));
            if ok && n.ends_with(".onnx") && !n.ends_with(".part") {
                Some(e.path().to_string_lossy().into_owned())
            } else { None }
        })
        .collect();
    matches.sort();
    if let Some(p) = matches.into_iter().next() {
        log(&format!("piper_voice({lang_code}): prefix match {p}"));
        return Some(p);
    }
    log(&format!("piper_voice({lang_code}): not found in {PIPER_VOICES_DIR}"));
    None
}

/// PicoTTS voices (pico2wave -l argument).
fn pico_voice(lang: &str) -> Option<&'static str> {
    match lang {
        "en" | "en_US" => Some("en-US"),
        "en_GB"        => Some("en-GB"),
        "de" | "de_DE" => Some("de-DE"),
        "es" | "es_ES" => Some("es-ES"),
        "fr" | "fr_FR" => Some("fr-FR"),
        "it" | "it_IT" => Some("it-IT"),
        _ => None,
    }
}

/// espeak-ng voice name for the given language (always has a fallback).
fn espeak_voice(lang: &str) -> &'static str {
    match lang {
        // Regional variants (user-selectable)
        "es-la" | "es_la"          => "es-la",
        "en-gb" | "en_gb" | "en_GB"=> "en-gb",
        "en-sc" | "en_sc"          => "en-sc",
        "en-wls"| "en_wls"         => "en-wls",
        "fr-be" | "fr_be"          => "fr-be",
        "fr-ch" | "fr_ch"          => "fr-ch",
        "pt-pt" | "pt_pt"          => "pt-pt",
        // Standard
        "ca"            => "catalan",
        "de" | "de_DE"  => "german",
        "en" | "en_US"  => "english-us",
        "es" | "es_ES"  => "es",
        "fr" | "fr_FR"  => "french",
        "it" | "it_IT"  => "italian",
        "pt" | "pt_BR"  => "pt",
        "ru"            => "russian",
        "zh" | "zh_CN"  => "zh",
        "ar"            => "ar",
        "fa"            => "fa",
        _               => "es",
    }
}

// ── Engine selection ─────────────────────────────────────────────────────────

fn try_piper(orig: &str, norm: &str, base: &str) -> Option<(Engine, String)> {
    let bin = format!("{APP_ROOT}/lib/piper");
    if !std::path::Path::new(&bin).exists() {
        log(&format!("try_piper: binary absent: {bin}"));
        return None;
    }
    log(&format!("try_piper: binary ok, seeking voice orig={orig} norm={norm} base={base}"));
    // Try original first (may contain hyphens like "es_ES-davefx-medium"), then normalised, then base lang.
    piper_voice(orig)
        .or_else(|| piper_voice(norm))
        .or_else(|| piper_voice(base))
        .map(|v| { log(&format!("TTS: Piper selected, voice={v}")); (Engine::Piper, v) })
}

fn try_picotts(norm: &str, base: &str) -> Option<(Engine, String)> {
    let bin = format!("{APP_ROOT}/lib/pico2wave");
    if !std::path::Path::new(&bin).exists() { return None; }
    pico_voice(norm).or_else(|| pico_voice(base))
        .map(|v| { log(&format!("TTS: PicoTTS, voice={v}")); (Engine::PicoTts, v.to_string()) })
}

fn espeak_fallback(norm: &str) -> (Engine, String) {
    let v = espeak_voice(norm);
    log(&format!("TTS: espeak, voice={v}"));
    (Engine::Espeak, v.to_string())
}

fn engine_name(e: &Engine) -> &'static str {
    match e {
        Engine::Piper    => "piper",
        Engine::MimicHts => "mimic",
        Engine::PicoTts  => "pico",
        Engine::Espeak   => "espeak",
    }
}

fn try_mimic_hts() -> Option<(Engine, String)> {
    let bin   = format!("{APP_ROOT}/lib/mimic_hts_es");
    let voice = format!("{APP_ROOT}/lib/mimic-data/cstr_upc_upm_spanish_hts.htsvoice");
    if std::path::Path::new(&bin).exists() && std::path::Path::new(&voice).exists() {
        log("TTS: MimicHts selected");
        Some((Engine::MimicHts, voice))
    } else {
        log(&format!("try_mimic_hts: bin={} voice={}", bin, voice));
        None
    }
}

fn cache_key(engine: &str, lang: &str, text: &str) -> String {
    let mut h: u64 = 5381;
    for b in format!("{engine}\x00{lang}\x00{text}").bytes() {
        h = h.wrapping_mul(33).wrapping_add(b as u64);
    }
    format!("{h:016x}")
}

/// Frase de inicio de ruta por idioma.
fn start_phrase(lang: &str) -> &'static str {
    match lang.split('_').next().unwrap_or(lang) {
        "en" => "All ready. Let's go",
        "fr" => "Tout est prêt. C'est parti",
        "de" => "Alles bereit. Los geht's",
        "pt" => "Tudo pronto. Vamos",
        "it" => "Tutto pronto. Andiamo",
        "ca" => "Tot preparat. Anem",
        "ru" => "Всё готово. Поехали",
        _    => "Todo preparado. Vamos",
    }
}

/// Redondeo de distancia (metros) al valor inferior de escala, igual que _roundDist en QML.
fn round_dist(m: i32) -> i32 {
    if m <= 0    { return 10; }
    if m < 100   { return (m / 10).max(1) * 10; }
    if m < 300   { return (m / 50)  * 50; }
    if m < 500   { return (m / 100) * 100; }
    if m < 1000  { return (m / 200) * 200; }
    if m < 10000 { return (m / 1000)* 1000; }
    m
}

/// Texto hablado para una distancia de redondeo ("En 400 metros", "En 2 kilómetros").
fn format_dist_text(dist_m: i32, lang: &str) -> String {
    let base = lang.split('_').next().unwrap_or(lang);
    if dist_m < 1000 {
        let (prep, unit) = match base {
            "en" => ("In",   "meters"),
            "fr" => ("Dans", "mètres"),
            "de" => ("In",   "Meter"),
            "pt" => ("Em",   "metros"),
            "it" => ("Fra",  "metri"),
            "ca" => ("En",   "metres"),
            _    => ("En",   "metros"),
        };
        format!("{prep} {dist_m} {unit}")
    } else {
        let km = dist_m / 1000;
        let (prep, unit) = match base {
            "en" => ("In",   if km == 1 { "kilometer"   } else { "kilometers"   }),
            "fr" => ("Dans", if km == 1 { "kilomètre"   } else { "kilomètres"   }),
            "de" => ("In",   "Kilometer"),
            "pt" => ("Em",   if km == 1 { "quilómetro"  } else { "quilómetros"  }),
            "it" => ("Fra",  if km == 1 { "chilometro"  } else { "chilometri"   }),
            "ca" => ("En",   if km == 1 { "quilòmetre"  } else { "quilòmetres"  }),
            _    => ("En",   if km == 1 { "kilómetro"   } else { "kilómetros"   }),
        };
        // Usar forma apócope para 1 (evita "uno kilómetro" en TTS español/similar)
        let km_str = if km == 1 {
            match base {
                "en" => "one".to_string(),
                "pt" => "um".to_string(),
                _    => "un".to_string(),
            }
        } else {
            km.to_string()
        };
        format!("{prep} {km_str} {unit}")
    }
}

fn generate_to_cache(engine: &Engine, voice: &str, text: &str, path: &str, num_threads: u32) {
    match engine {
        Engine::MimicHts => {}  // sin caché; síntesis al vuelo en say_mimic_hts
        Engine::PicoTts => {
            let pico_lang = voice.split('-').next().unwrap_or("es").to_lowercase();
            let norm     = normalize_for_pico(text, &pico_lang);
            let bin      = format!("{APP_ROOT}/lib/pico2wave");
            let lang_dir = format!("{APP_ROOT}/lib/picotts-lang");
            let lib_dir  = format!("{APP_ROOT}/lib");
            let ok = std::process::Command::new(&bin)
                .env("NAVIUS_PICO_LANG", &lang_dir)
                .env("LD_LIBRARY_PATH", &lib_dir)
                .arg("-w").arg(path).arg("-l").arg(voice).arg(&norm)
                .status().map(|s| s.success()).unwrap_or(false);
            log(&format!("cache pico: ok={ok} path={path}"));
        }
        Engine::Piper => {
            generate_piper_wav(voice, text, path, num_threads);
        }
        Engine::Espeak => {}  // espeak no genera fichero WAV
    }
}

/// Selects engine respecting the user override.
/// Auto priority: Piper (if voices present) → Mimic HTS (es only) → PicoTTS → espeak-ng.
fn select_engine(lang: &str) -> (Engine, String) {
    let norm = lang.replace('-', "_");
    let base = norm.split('_').next().unwrap_or(&norm).to_string();
    let ov   = tts_state().lock().unwrap_or_else(|e| e.into_inner()).engine_override.clone();
    match ov {
        Some(Engine::Piper) =>
            try_piper(lang, &norm, &base).unwrap_or_else(|| {
                log("TTS: Piper forced but unavailable → espeak"); espeak_fallback(&norm)
            }),
        Some(Engine::MimicHts) =>
            try_mimic_hts().unwrap_or_else(|| {
                log("TTS: MimicHts forced but unavailable → espeak"); espeak_fallback(&norm)
            }),
        Some(Engine::PicoTts) =>
            try_picotts(&norm, &base).unwrap_or_else(|| {
                log("TTS: PicoTTS forced but unavailable → espeak"); espeak_fallback(&norm)
            }),
        Some(Engine::Espeak) => espeak_fallback(&norm),
        None => {
            // 1. Piper si hay voces descargadas
            if let Some(r) = try_piper(lang, &norm, &base) { return r; }
            // 2. Mimic HTS solo para español
            if base == "es" {
                if let Some(r) = try_mimic_hts() { return r; }
            }
            // 3. PicoTTS
            if let Some(r) = try_picotts(&norm, &base) { return r; }
            // 4. espeak-ng (siempre disponible)
            espeak_fallback(&norm)
        }
    }
}

// ── Texto → pico2wave: normalización específica ──────────────────────────────
// pico2wave/es-ES no normaliza ciertos caracteres correctamente:
//   '-'  → "punto central"  (lo omitimos con un espacio)
//   '4º' → "4 ordinal masculino"  (expandimos al ordinal en español)

fn normalize_for_pico(text: &str, lang: &str) -> String {
    const MASC: &[&str] = &["", "primero", "segundo", "tercero", "cuarto",
                              "quinto", "sexto", "séptimo", "octavo", "noveno", "décimo"];
    const FEM:  &[&str] = &["", "primera", "segunda", "tercera", "cuarta",
                              "quinta", "sexta", "séptima", "octava", "novena", "décima"];
    // Expansión de unidades antes del resto de la normalización
    let kmh = match lang {
        "en" => "kilometres per hour",
        "fr" => "kilomètres par heure",
        "de" => "Kilometer pro Stunde",
        "pt" => "quilómetros por hora",
        "it" => "chilometri all'ora",
        _    => "kilómetros por hora",
    };
    let text_owned = text
        .replace("km/h", kmh).replace("Km/h", kmh).replace("KM/H", kmh)
        .replace("m/s", if lang == "en" { "metres per second" } else { "metros por segundo" })
        // "1 km" → "un kilómetro" para evitar "uno kilómetro" en TTS español
        .replace(" 1 km", if lang == "en" { " 1 kilometer" } else { " un kilómetro" })
        .replace(" km", match lang {
            "en" => " kilometers", "fr" => " kilomètres", "pt" => " quilómetros",
            "it" => " chilometri", "ca" => " quilòmetres", _ => " kilómetros",
        });
    let text = text_owned.as_str();
    let chars: Vec<char> = text.chars().collect();
    let mut out = String::with_capacity(text.len() + 32);
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c.is_ascii_digit() {
            let s = i;
            while i < chars.len() && chars[i].is_ascii_digit() { i += 1; }
            // acepta tanto "4º" como "4.º"
            let (skip_dot, ord_char) = if chars.get(i) == Some(&'.') {
                (true, chars.get(i + 1).copied())
            } else {
                (false, chars.get(i).copied())
            };
            if ord_char == Some('\u{00BA}') || ord_char == Some('\u{00AA}') {
                let fem = ord_char == Some('\u{00AA}');
                let n: usize = chars[s..i].iter().collect::<String>().parse().unwrap_or(0);
                let tbl = if fem { FEM } else { MASC };
                if n >= 1 && n <= 10 { out.push_str(tbl[n]); }
                else { chars[s..i].iter().for_each(|ch| out.push(*ch)); }
                if skip_dot { i += 1; } // consumir el punto antes del ordinal (ej. "4.º")
                i += 1; // consumir indicador ordinal
                // consumir punto tras el ordinal (ej. "3º.") para evitar que TTS lo lea
                if i < chars.len() && chars[i] == '.' { i += 1; }
            } else {
                chars[s..i].iter().for_each(|ch| out.push(*ch));
            }
        } else if matches!(c,
            '-' | '|' | '_' | '\\' | '~' | '*' | '#' |
            '\u{00B7}' |  // · middle dot
            '\u{2013}' |  // – en dash
            '\u{2014}' |  // — em dash
            '\u{2015}' |  // ― horizontal bar
            '\u{2010}' |  // ‐ hyphen
            '\u{2011}' |  // ‑ non-breaking hyphen
            '\u{2012}' |  // ‒ figure dash
            '\u{2022}' |  // • bullet
            '\u{25E6}' |  // ◦ white bullet
            '\u{00A7}' |  // § section sign
            '\u{00B6}'    // ¶ pilcrow
        ) {
            out.push(' '); i += 1;
        } else {
            out.push(c); i += 1;
        }
    }
    out
}

// ── Normalización para Piper ─────────────────────────────────────────────────

fn normalize_for_piper(text: &str, lang: &str) -> String {
    let kmh = match lang {
        "en"           => "kilometres per hour",
        "fr"           => "kilomètres par heure",
        "de"           => "Kilometer pro Stunde",
        "pt"           => "quilómetros por hora",
        "it"           => "chilometri all'ora",
        "ca"           => "quilòmetres per hora",
        "ru"           => "километров в час",
        "zh"           => "公里每小时",
        "ar"           => "كيلومتر في الساعة",
        _              => "kilómetros por hora",
    };
    let mps = match lang {
        "en" => "metres per second",
        "fr" => "mètres par seconde",
        "de" => "Meter pro Sekunde",
        "pt" => "metros por segundo",
        "it" => "metri al secondo",
        _    => "metros por segundo",
    };
    text
        .replace("km/h", kmh).replace("Km/h", kmh).replace("KM/H", kmh)
        .replace("m/s",  mps)
        .replace('\u{00B7}', " ")   // · middle dot
        .replace('\u{2013}', " ")   // – en dash
        .replace('\u{2014}', " ")   // — em dash
        .replace('\u{2015}', " ")   // ― horizontal bar
        .replace('|', " ")
        .replace('_', " ")
}

// ── WAV engine helpers ───────────────────────────────────────────────────────

fn tmp_wav() -> String {
    let _ = std::fs::create_dir_all(CACHE_TMP_DIR);
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    format!("{CACHE_TMP_DIR}/tts_{}{:06}.wav", ts.as_secs(), ts.subsec_micros())
}

fn generate_piper_wav(voice_onnx: &str, text: &str, out_path: &str, num_threads: u32) {
    // Solo un proceso piper a la vez: el worker de la cola y say_piper comparten este mutex.
    let _plock = PIPER_PROC_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    use std::io::Write;
    let lang = std::path::Path::new(voice_onnx)
        .file_name().and_then(|n| n.to_str())
        .and_then(|n| n.split('_').next())
        .unwrap_or("es");
    let norm    = normalize_for_piper(text, lang);
    let bin     = format!("{APP_ROOT}/lib/piper");
    let lib_dir = format!("{APP_ROOT}/lib");
    let nt = num_threads.to_string();
    let shim = format!("{APP_ROOT}/lib/libpiper_limit.so");
    let mut cmd = std::process::Command::new(&bin);
    cmd.env("LD_LIBRARY_PATH", &lib_dir)
       .env("LD_PRELOAD", &shim)
       .env("OMP_NUM_THREADS", &nt)
       .env("GOMP_SPINCOUNT", "0")
       .arg("--model").arg(voice_onnx)
       .arg("--output_file").arg(out_path)
       .arg("--num-threads").arg(&nt)
       .stdin(std::process::Stdio::piped())
       .stdout(std::process::Stdio::null())
       .stderr(std::process::Stdio::piped());
    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => { log(&format!("piper spawn failed: {e}")); return; }
    };
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(norm.as_bytes());
    }
    let stderr_bytes = match child.wait_with_output() {
        Ok(out) => out.stderr,
        Err(e)  => { log(&format!("piper wait failed: {e}")); Vec::new() }
    };
    let sz = std::fs::metadata(out_path).map(|m| m.len()).unwrap_or(0);
    let err = String::from_utf8_lossy(&stderr_bytes);
    if !err.is_empty() { log(&format!("piper stderr: {}", err.trim())); }
    log(&format!("piper: bytes={sz} path={out_path}"));
}

fn say_piper(voice: &str, text: &str) {
    let tmp = tmp_wav();
    generate_piper_wav(voice, text, &tmp, 2);
    let sz = std::fs::metadata(&tmp).map(|m| m.len()).unwrap_or(0);
    if sz > 44 {
        let tmp_c = format!("{tmp}\0");
        unsafe { navius_play_wav(tmp_c.as_ptr()); }
        log(&format!("said (piper/{}): {:?}", voice, text));
    } else {
        log("piper failed → espeak fallback");
        say_espeak_voice("es", text);
    }
    let _ = std::fs::remove_file(&tmp);
}

fn say_pico(voice: &str, text: &str) {
    let bin      = format!("{APP_ROOT}/lib/pico2wave");
    let lang_dir = format!("{APP_ROOT}/lib/picotts-lang");
    let tmp      = tmp_wav();
    let lib_dir  = format!("{APP_ROOT}/lib");
    let pico_lang = voice.split('-').next().unwrap_or("es").to_lowercase();
    let norm     = normalize_for_pico(text, &pico_lang);
    log(&format!("pico2wave: WAV path={tmp}"));
    let result = std::process::Command::new(&bin)
        .env("NAVIUS_PICO_LANG", &lang_dir)
        .env("LD_LIBRARY_PATH", &lib_dir)
        .arg("-w").arg(&tmp)
        .arg("-l").arg(voice)
        .arg(&norm)
        .status();
    let exit_ok = result.as_ref().map(|s| s.success()).unwrap_or(false);
    let wav_size = std::fs::metadata(&tmp).map(|m| m.len()).unwrap_or(0);
    log(&format!("pico2wave: exit_ok={exit_ok} wav_bytes={wav_size} result={result:?}"));
    if exit_ok && wav_size > 44 {
        let tmp_c = format!("{tmp}\0");
        unsafe { navius_play_wav(tmp_c.as_ptr()); }
        log(&format!("said (pico/{voice}): {text:?}"));
    } else {
        log("pico2wave failed or empty WAV → espeak fallback");
        say_espeak_voice("es", text);
    }
    let _ = std::fs::remove_file(&tmp);
}

/// Expands isolated uppercase letter tokens to their Spanish names.
/// "TTS" → "te te ese", "GPS" → "ge pe ese", "T T S" → "te te ese"
fn expand_letters_es(text: &str) -> String {
    const NAMES: [&str; 26] = [
        "a","be","ce","de","e","efe","ge","hache","i","jota",
        "ka","ele","eme","ene","o","pe","cu","erre","ese","te",
        "u","uve","doble uve","equis","ye","zeta",
    ];
    let mut out = String::with_capacity(text.len() * 2);
    for (idx, word) in text.split_whitespace().enumerate() {
        if idx > 0 { out.push(' '); }
        if !word.is_empty() && word.chars().all(|c| c.is_ascii_uppercase()) {
            let parts: Vec<&str> = word.chars()
                .map(|c| NAMES[(c as u8 - b'A') as usize])
                .collect();
            out.push_str(&parts.join(" "));
        } else {
            out.push_str(word);
        }
    }
    out
}

/// Amplifies 16-bit PCM samples in a WAV file in-place.
fn amplify_wav(path: &str, gain: f32) {
    let Ok(mut data) = std::fs::read(path) else { return };
    if data.len() < 44 { return }
    // Locate "data" chunk (walk chunks after "WAVE" tag at offset 8)
    let mut pos = 12usize;
    let mut audio_start = 44usize;
    while pos + 8 <= data.len() {
        if &data[pos..pos+4] == b"data" { audio_start = pos + 8; break; }
        let chunk_len = u32::from_le_bytes(data[pos+4..pos+8].try_into().unwrap_or([0;4])) as usize;
        pos += 8 + chunk_len;
    }
    for chunk in data[audio_start..].chunks_exact_mut(2) {
        let s = i16::from_le_bytes([chunk[0], chunk[1]]);
        let boosted = (s as f32 * gain).clamp(-32768.0, 32767.0) as i16;
        let b = boosted.to_le_bytes();
        chunk[0] = b[0]; chunk[1] = b[1];
    }
    let _ = std::fs::write(path, &data);
}

fn mimic_generate(norm: &str, voice_path: &str, out_path: &str) -> bool {
    let bin = format!("{APP_ROOT}/lib/mimic_hts_es");
    let ok = std::process::Command::new(&bin)
        .arg(norm).arg(out_path).arg(voice_path)
        .status().map(|s| s.success()).unwrap_or(false);
    let sz = std::fs::metadata(out_path).map(|m| m.len()).unwrap_or(0);
    if ok && sz > 44 { amplify_wav(out_path, 3.5); true } else { false }
}

fn say_mimic_hts(voice_path: &str, text: &str) {
    let norm = expand_letters_es(&normalize_for_pico(text, "es"));
    let tmp  = tmp_wav();
    log(&format!("mimic_hts: wav={tmp} norm={norm:?}"));
    if mimic_generate(&norm, voice_path, &tmp) {
        let c = format!("{tmp}\0");
        unsafe { navius_play_wav(c.as_ptr()); }
        log(&format!("said (mimic_hts): {text:?}"));
    } else {
        log("mimic_hts failed → espeak fallback");
        say_espeak_voice("es", text);
    }
    let _ = std::fs::remove_file(&tmp);
}

/// Síntesis inmediata usando el motor activo. Para rutas de backup donde no hay WAV precacheado.
/// Prioridad: MimicHts → Piper directo → PicoTTS → espeak.
fn say_backup(engine: &Engine, voice: &str, norm: &str, base: &str, text: &str) {
    match engine {
        Engine::MimicHts => say_mimic_hts(voice, text),
        Engine::Piper    => say_piper(voice, text),
        _ => {
            if let Some((_, pv)) = try_picotts(norm, base) {
                say_pico(&pv, text);
            } else {
                say_espeak_voice(espeak_voice(norm), text);
            }
        }
    }
}

fn say_espeak_voice(voice: &str, text: &str) {
    let root = format!("{APP_ROOT}\0");
    let st = unsafe { cstr(navius_espeak_init(root.as_ptr())) };
    if st != "ok" { log(&format!("espeak_init failed: {st}")); return; }
    unsafe {
        navius_espeak_set_voice(voice.as_ptr(), voice.len());
        navius_espeak_say(text.as_ptr(), text.len());
    }
    log(&format!("said (espeak/{voice}): {text:?}"));
}

fn say_inner(text: String) {
    let (engine, voice) = {
        let st = tts_state().lock().unwrap_or_else(|e| e.into_inner());
        (st.engine.clone(), st.voice.clone())
    };
    match engine {
        Engine::Piper    => say_piper(&voice, &text),
        Engine::MimicHts => say_mimic_hts(&voice, &text),
        Engine::PicoTts  => say_pico(&voice, &text),
        Engine::Espeak   => say_espeak_voice(&voice, &text),
    }
}

fn beep_inner() {
    let st = unsafe { cstr(navius_pa_init()) };
    if st != "ok" { log(&format!("pa_init failed: {st}")); return; }
    unsafe { navius_beep(); }
}

// ── C++ / PulseAudio / espeak-ng ─────────────────────────────────────────────

cpp! {{
    #include <dlfcn.h>
    #include <string>
    #include <cstdint>
    #include <cstdio>
    #include <cstring>
    #include <cmath>
    #include <algorithm>
    #include <vector>

    // Rust function: returns true when play_round_then_instr wants to interrupt playback.
    extern "C" bool navius_is_cancelled();

    // ── espeak-ng types ──────────────────────────────────────────────────────
    typedef enum {
        AUDIO_OUTPUT_SYNCHRONOUS = 2,
    } espeak_AUDIO_OUTPUT;
    typedef struct { int type; unsigned int unique_identifier; void* user_data;
                     unsigned int text_position, length, audio_position, sample, id;
    } espeak_EVENT;
    typedef int (*t_espeak_callback)(short*, int, espeak_EVENT*);
    typedef int          (*espeak_Initialize_fn)(espeak_AUDIO_OUTPUT, int, const char*, int);
    typedef void         (*espeak_SetVoiceByName_fn)(const char*);
    typedef void         (*espeak_SetSynthCallback_fn)(t_espeak_callback);
    typedef unsigned int (*espeak_Synth_fn)(const void*, size_t, unsigned int, int,
                                             unsigned int, unsigned int, unsigned int*, void*);
    typedef int          (*espeak_Synchronize_fn)(void);
    typedef void         (*espeak_SetParameter_fn)(int, int, int);

    // ── PulseAudio simple API ────────────────────────────────────────────────
    typedef struct pa_simple pa_simple;
    typedef enum  { PA_STREAM_PLAYBACK = 1 } pa_stream_direction_t;
    typedef enum  { PA_SAMPLE_S16LE = 3  } pa_sample_format_t;
    typedef struct { pa_sample_format_t format; uint32_t rate; uint8_t channels; } pa_sample_spec;
    typedef pa_simple* (*pa_simple_new_fn)(const char*, const char*, pa_stream_direction_t,
                                            const char*, const char*, const pa_sample_spec*,
                                            const void*, const void*, int*);
    typedef int  (*pa_simple_write_fn)(pa_simple*, const void*, size_t, int*);
    typedef int  (*pa_simple_drain_fn)(pa_simple*, int*);
    typedef void (*pa_simple_free_fn)(pa_simple*);

    // ── globals ──────────────────────────────────────────────────────────────
    static espeak_Synth_fn        g_synth      = nullptr;
    static espeak_Synchronize_fn  g_sync       = nullptr;
    static pa_simple_new_fn       g_pa_new     = nullptr;
    static pa_simple_write_fn     g_pa_write   = nullptr;
    static pa_simple_drain_fn     g_pa_drain   = nullptr;
    static pa_simple_free_fn      g_pa_free    = nullptr;
    static pa_simple*             g_pa_stream  = nullptr;  // espeak + beep stream
    static unsigned int           g_sample_rate = 22050;
    static bool                   g_espeak_ok  = false;
    static bool                   g_pa_ok      = false;
    static espeak_SetVoiceByName_fn g_voice_fn = nullptr;
    static std::string            g_voice      = "es";

    static int espeak_cb(short* wav, int numsamples, espeak_EVENT*) {
        if (!wav || numsamples <= 0 || !g_pa_stream) return 0;
        int err = 0;
        g_pa_write(g_pa_stream, wav, numsamples * 2, &err);
        return 0;
    }

    static void pa_stream_open() {
        if (g_pa_stream) { g_pa_drain(g_pa_stream, nullptr); g_pa_free(g_pa_stream); g_pa_stream = nullptr; }
        pa_sample_spec ss; ss.format = PA_SAMPLE_S16LE; ss.rate = g_sample_rate; ss.channels = 1;
        int err = 0;
        g_pa_stream = g_pa_new(nullptr, "navius", PA_STREAM_PLAYBACK, nullptr, "tts", &ss, nullptr, nullptr, &err);
    }

    static const char* pa_init() {
        if (g_pa_ok) return "ok";
        void* pa_lib = dlopen("libpulse-simple.so.0", RTLD_LAZY | RTLD_GLOBAL);
        if (!pa_lib) return "no libpulse-simple";
        g_pa_new   = (pa_simple_new_fn)  dlsym(pa_lib, "pa_simple_new");
        g_pa_write = (pa_simple_write_fn)dlsym(pa_lib, "pa_simple_write");
        g_pa_drain = (pa_simple_drain_fn)dlsym(pa_lib, "pa_simple_drain");
        g_pa_free  = (pa_simple_free_fn) dlsym(pa_lib, "pa_simple_free");
        if (!g_pa_new || !g_pa_write || !g_pa_drain || !g_pa_free) return "missing pa syms";
        g_pa_ok = true;
        pa_stream_open();
        return "ok";
    }

    static void play_tone(unsigned int freq_hz, unsigned int dur_ms) {
        if (!g_pa_ok || !g_pa_stream) return;
        int n = (int)((long long)g_sample_rate * dur_ms / 1000);
        if (n <= 0) return;
        std::vector<short> buf(n, 0);
        if (freq_hz > 0) {
            const double vol = 0.55 * 32767.0;
            const double step = 2.0 * M_PI * freq_hz / g_sample_rate;
            for (int i = 0; i < n; i++) buf[i] = (short)(sin(step * i) * vol);
        }
        int err = 0;
        g_pa_write(g_pa_stream, buf.data(), n * 2, &err);
    }

    extern "C" const char* navius_pa_init() { return pa_init(); }

    extern "C" void navius_beep() {
        if (!g_pa_ok || !g_pa_stream) return;
        play_tone(220, 200);
        g_pa_drain(g_pa_stream, nullptr);
    }
    extern "C" void navius_alert_beep() {
        if (!g_pa_ok || !g_pa_stream) return;
        play_tone(880, 120); play_tone(0, 40); play_tone(880, 120);
        g_pa_drain(g_pa_stream, nullptr);
    }
    extern "C" void navius_reroute_beep() {
        if (!g_pa_ok || !g_pa_stream) return;
        play_tone(220, 150); play_tone(0, 40); play_tone(220, 150);
        g_pa_drain(g_pa_stream, nullptr);
    }

    // ── WAV file player ──────────────────────────────────────────────────────
    // Opens a dedicated PA stream at the WAV's native sample rate so the
    // main espeak/beep stream (g_pa_stream) is never disturbed.
    static void wav_log(const char* msg) {
        FILE* lf = fopen("/home/phablet/.local/share/navius.woodyst/debug/tts_debug.log", "a");
        if (lf) { fputs(msg, lf); fputc('\n', lf); fclose(lf); }
    }

    extern "C" void navius_play_wav(const char* path) {
        wav_log("navius_play_wav: enter");
        const char* perr = pa_init();
        if (perr[0] != 'o') {
            std::string m = std::string("navius_play_wav: pa_init failed: ") + perr;
            wav_log(m.c_str());
            return;
        }

        FILE* f = fopen(path, "rb");
        if (!f) {
            std::string m = std::string("navius_play_wav: fopen failed for: ") + path;
            wav_log(m.c_str());
            return;
        }

        char id[4]; uint32_t sz; char wave[4];
        if (fread(id, 1, 4, f) != 4 || memcmp(id, "RIFF", 4)) { fclose(f); return; }
        fread(&sz, 4, 1, f);
        if (fread(wave, 1, 4, f) != 4 || memcmp(wave, "WAVE", 4)) { fclose(f); return; }

        uint32_t sample_rate = 22050;
        uint16_t channels = 1;

        while (true) {
            if (fread(id, 1, 4, f) != 4) break;
            if (fread(&sz, 4, 1, f) != 1) break;  // fread returns element count (1), not bytes
            if (!memcmp(id, "fmt ", 4)) {
                uint16_t fmt, ch, bits; uint32_t br; uint16_t ba;
                fread(&fmt, 2, 1, f); fread(&ch, 2, 1, f);
                fread(&sample_rate, 4, 1, f); fread(&br, 4, 1, f);
                fread(&ba, 2, 1, f); fread(&bits, 2, 1, f);
                channels = ch;
                if (sz > 16) fseek(f, sz - 16, SEEK_CUR);
            } else if (!memcmp(id, "data", 4)) {
                pa_sample_spec ss;
                ss.format   = PA_SAMPLE_S16LE;
                ss.rate     = sample_rate;
                ss.channels = (uint8_t)channels;
                int err = 0;
                pa_simple* ws = g_pa_new(nullptr, "navius", PA_STREAM_PLAYBACK,
                                          nullptr, "tts_voice", &ss, nullptr, nullptr, &err);
                if (!ws) {
                    std::string m = std::string("navius_play_wav: pa_simple_new failed err=") + std::to_string(err);
                    wav_log(m.c_str());
                    fclose(f); return;
                }
                wav_log("navius_play_wav: streaming audio…");
                char buf[2048]; uint32_t rem = sz;
                while (rem > 0) {
                    if (navius_is_cancelled()) {
                        wav_log("navius_play_wav: cancelled");
                        break;
                    }
                    size_t n = fread(buf, 1, std::min((uint32_t)sizeof(buf), rem), f);
                    if (n == 0) break;
                    err = 0;
                    g_pa_write(ws, buf, n, &err);
                    rem -= (uint32_t)n;
                }
                if (!navius_is_cancelled()) g_pa_drain(ws, nullptr);
                g_pa_free(ws);
                fclose(f);
                return;
            } else {
                fseek(f, sz, SEEK_CUR);
            }
        }
        wav_log("navius_play_wav: loop ended (no data chunk reached)");
        fclose(f);
    }

    // ── espeak-ng ────────────────────────────────────────────────────────────
    extern "C" const char* navius_espeak_init(const char* app_root) {
        if (g_espeak_ok) return "ok";
        const char* pa_err = pa_init();
        if (pa_err[0] != 'o') return pa_err;

        std::string lib_path  = std::string(app_root) + "/lib/libespeak-ng.so.1";
        std::string data_path = std::string(app_root) + "/lib/espeak-ng-data";
        std::string sonic_path = std::string(app_root) + "/lib/libsonic.so.0";
        std::string pca_path   = std::string(app_root) + "/lib/libpcaudio.so.0";
        dlopen(sonic_path.c_str(), RTLD_LAZY | RTLD_GLOBAL);
        dlopen(pca_path.c_str(),  RTLD_LAZY | RTLD_GLOBAL);

        void* es_lib = dlopen(lib_path.c_str(), RTLD_LAZY | RTLD_GLOBAL);
        if (!es_lib) return dlerror();

        auto init_fn  = (espeak_Initialize_fn)     dlsym(es_lib, "espeak_Initialize");
        auto voice_fn = (espeak_SetVoiceByName_fn) dlsym(es_lib, "espeak_SetVoiceByName");
        auto cb_fn    = (espeak_SetSynthCallback_fn)dlsym(es_lib, "espeak_SetSynthCallback");
        auto param_fn = (espeak_SetParameter_fn)   dlsym(es_lib, "espeak_SetParameter");
        g_synth = (espeak_Synth_fn)       dlsym(es_lib, "espeak_Synth");
        g_sync  = (espeak_Synchronize_fn) dlsym(es_lib, "espeak_Synchronize");
        if (!init_fn || !voice_fn || !cb_fn || !param_fn || !g_synth || !g_sync)
            return "missing espeak syms";

        int sr = init_fn(AUDIO_OUTPUT_SYNCHRONOUS, 500, data_path.c_str(), 0);
        if (sr <= 0) return "espeak_Initialize failed";
        if ((unsigned int)sr != g_sample_rate) { g_sample_rate = (unsigned int)sr; pa_stream_open(); }

        g_voice_fn = voice_fn;
        cb_fn(espeak_cb);
        voice_fn(g_voice.c_str());
        param_fn(3, 130, 0);  // espeakRATE
        param_fn(4, 90,  0);  // espeakVOLUME
        g_espeak_ok = true;
        return "ok";
    }

    extern "C" void navius_espeak_set_voice(const uint8_t* data, uintptr_t len) {
        g_voice = std::string(reinterpret_cast<const char*>(data), len);
        if (g_espeak_ok && g_voice_fn && !g_voice.empty())
            g_voice_fn(g_voice.c_str());
    }

    extern "C" void navius_espeak_say(const uint8_t* data, uintptr_t len) {
        if (!g_espeak_ok || !g_pa_stream) return;
        std::string text(reinterpret_cast<const char*>(data), len);
        g_synth(text.c_str(), text.size() + 1, 0, 1, 0, 1, nullptr, nullptr);
        g_sync();
        g_pa_drain(g_pa_stream, nullptr);
    }

    // ── HTTP download via dlopen(libcurl) ────────────────────────────────────
    // No se usa exec() → AppArmor click lo permite; dlopen sí está permitido.
    typedef size_t (*curl_write_fn)(char*, size_t, size_t, void*);
    typedef void*  (*t_curl_init)();
    typedef int    (*t_curl_setopt_s) (void*, int, const char*);
    typedef int    (*t_curl_setopt_l) (void*, int, long);
    typedef int    (*t_curl_setopt_wf)(void*, int, curl_write_fn);
    typedef int    (*t_curl_setopt_dp)(void*, int, void*);
    typedef int    (*t_curl_perform)  (void*);
    typedef void   (*t_curl_cleanup)  (void*);
    typedef const char* (*t_curl_strerr)(int);

    static size_t navius_write_cb(char* ptr, size_t sz, size_t nm, void* ud) {
        return fwrite(ptr, sz, nm, (FILE*)ud);
    }

    // Retorna 0 si ok, código negativo si falla; escribe errores en log_path.
    extern "C" int navius_http_download(const char* url,
                                         const char* part_path,
                                         const char* log_path) {
        auto wlog = [&](const std::string& m) {
            FILE* lf = fopen(log_path, "a");
            if (lf) { fputs(m.c_str(), lf); fputc('\n', lf); fclose(lf); }
        };

        void* lib = dlopen("libcurl.so.4", RTLD_LAZY);
        if (!lib) { wlog("http_dl: dlopen libcurl.so.4 failed"); return -1; }

        auto curl_init    = (t_curl_init)    dlsym(lib, "curl_easy_init");
        auto curl_sopt_s  = (t_curl_setopt_s) dlsym(lib, "curl_easy_setopt");
        auto curl_sopt_l  = (t_curl_setopt_l) dlsym(lib, "curl_easy_setopt");
        auto curl_sopt_wf = (t_curl_setopt_wf)dlsym(lib, "curl_easy_setopt");
        auto curl_sopt_dp = (t_curl_setopt_dp)dlsym(lib, "curl_easy_setopt");
        auto curl_perform = (t_curl_perform) dlsym(lib, "curl_easy_perform");
        auto curl_cleanup = (t_curl_cleanup) dlsym(lib, "curl_easy_cleanup");
        auto curl_strerr  = (t_curl_strerr)  dlsym(lib, "curl_easy_strerror");

        if (!curl_init || !curl_sopt_s || !curl_perform || !curl_cleanup) {
            wlog("http_dl: dlsym failed"); dlclose(lib); return -2;
        }

        void* curl = curl_init();
        if (!curl) { wlog("http_dl: curl_easy_init null"); dlclose(lib); return -3; }

        FILE* f = fopen(part_path, "wb");
        if (!f) {
            wlog(std::string("http_dl: fopen failed: ") + part_path);
            curl_cleanup(curl); dlclose(lib); return -4;
        }

        curl_sopt_s (curl, 10002, url);              // CURLOPT_URL
        curl_sopt_l (curl, 52,    1L);               // CURLOPT_FOLLOWLOCATION
        curl_sopt_l (curl, 155,   600000L);          // CURLOPT_TIMEOUT_MS
        curl_sopt_wf(curl, 20011, navius_write_cb);  // CURLOPT_WRITEFUNCTION
        curl_sopt_dp(curl, 10001, (void*)f);         // CURLOPT_WRITEDATA

        int rc = curl_perform(curl);
        fclose(f);

        if (rc != 0)
            wlog(std::string("http_dl: perform rc=") + std::to_string(rc) +
                 (curl_strerr ? (std::string(" ") + curl_strerr(rc)) : ""));

        curl_cleanup(curl);
        dlclose(lib);
        return rc == 0 ? 0 : -5;
    }

    // ── Volumen de música vía PulseAudio pa_context ──────────────────────────
    // AalMediaPlayerService::setVolume (libaalmediaplayer.so) es un no-op cuando
    // hay sesión válida — nunca llama a nada en lomiri::MediaHub::Player porque
    // esa clase simplemente no expone setVolume(). La solución es acceder
    // directamente a libpulse.so.0 y aplicar el volumen al sink input de
    // "media-hub-server" por su proplist.
    //
    // Offsets de pa_sink_input_info para PulseAudio 16.x aarch64:
    //   index:                  offset 0   (uint32_t)
    //   channel_map.channels:   offset 40  (uint8_t)
    //   proplist:               offset 344 (pointer)
    #define NAVIUS_SI_CHANNELS_OFF 40
    #define NAVIUS_SI_PROPLIST_OFF 344
    #define NAVIUS_PA_CHANNELS_MAX 32U
    #define NAVIUS_PA_VOLUME_NORM  ((uint32_t)0x10000U)

    struct navius_pa_cvolume {
        uint8_t  channels;
        uint8_t  _pad[3];
        uint32_t values[NAVIUS_PA_CHANNELS_MAX];
    };

    struct navius_vol_data {
        float   vol;
        void*   ctx;
        void*   fn_set_vol;       // pa_context_set_sink_input_volume
        void*   fn_op_unref;      // pa_operation_unref
        void*   fn_proplist_gets; // pa_proplist_gets
    };

    static void navius_sink_input_vol_cb(void* /*c*/, const void* info, int eol, void* ud) {
        if (eol || !info) return;
        navius_vol_data* d = (navius_vol_data*)ud;

        uint32_t idx      = *(const uint32_t*)info;
        uint8_t  channels = *((const uint8_t*)info + NAVIUS_SI_CHANNELS_OFF);
        const void* plist = *(const void**)((const char*)info + NAVIUS_SI_PROPLIST_OFF);

        if (channels == 0 || channels > NAVIUS_PA_CHANNELS_MAX) channels = 2;

        typedef const char* (*pg_fn)(const void*, const char*);
        const char* app = ((pg_fn)d->fn_proplist_gets)(plist, "application.name");
        if (!app || strcmp(app, "media-hub-server") != 0) return;

        navius_pa_cvolume cvol;
        cvol.channels = channels;
        uint32_t v = (uint32_t)(d->vol * (float)NAVIUS_PA_VOLUME_NORM);
        for (unsigned i = 0; i < channels; i++) cvol.values[i] = v;

        typedef void* (*sv_fn)(void*, uint32_t, const void*, void*, void*);
        void* op = ((sv_fn)d->fn_set_vol)(d->ctx, idx, &cvol, nullptr, nullptr);
        if (op) {
            typedef void (*ou_fn)(void*);
            ((ou_fn)d->fn_op_unref)(op);
        }
    }

    extern "C" void navius_set_music_volume(float vol) {
        static void* pa_lib = nullptr;
        if (!pa_lib) {
            pa_lib = dlopen("libpulse.so.0", RTLD_LAZY | RTLD_GLOBAL);
            if (!pa_lib) return;
        }

        typedef void*        (*t_ml_new)();
        typedef void*        (*t_ml_api)(void*);
        typedef int          (*t_ml_iter)(void*, int, int*);
        typedef void         (*t_ml_free)(void*);
        typedef void*        (*t_ctx_new)(void*, const char*);
        typedef int          (*t_ctx_conn)(void*, const char*, int, void*);
        typedef void         (*t_ctx_disc)(void*);
        typedef void         (*t_ctx_uref)(void*);
        typedef int          (*t_ctx_stat)(const void*);
        typedef void*        (*t_ctx_list)(void*, void*, void*);
        typedef void*        (*t_ctx_svol)(void*, uint32_t, const void*, void*, void*);
        typedef int          (*t_op_stat)(const void*);
        typedef void         (*t_op_uref)(void*);
        typedef const char*  (*t_plist)(const void*, const char*);

        t_ml_new   pa_mainloop_new_                  = (t_ml_new)  dlsym(pa_lib, "pa_mainloop_new");
        t_ml_api   pa_mainloop_get_api_              = (t_ml_api)  dlsym(pa_lib, "pa_mainloop_get_api");
        t_ml_iter  pa_mainloop_iterate_              = (t_ml_iter) dlsym(pa_lib, "pa_mainloop_iterate");
        t_ml_free  pa_mainloop_free_                 = (t_ml_free) dlsym(pa_lib, "pa_mainloop_free");
        t_ctx_new  pa_context_new_                   = (t_ctx_new) dlsym(pa_lib, "pa_context_new");
        t_ctx_conn pa_context_connect_               = (t_ctx_conn)dlsym(pa_lib, "pa_context_connect");
        t_ctx_disc pa_context_disconnect_            = (t_ctx_disc)dlsym(pa_lib, "pa_context_disconnect");
        t_ctx_uref pa_context_unref_                 = (t_ctx_uref)dlsym(pa_lib, "pa_context_unref");
        t_ctx_stat pa_context_get_state_             = (t_ctx_stat)dlsym(pa_lib, "pa_context_get_state");
        t_ctx_list pa_context_get_sink_input_info_list_ = (t_ctx_list)dlsym(pa_lib, "pa_context_get_sink_input_info_list");
        t_ctx_svol pa_context_set_sink_input_volume_ = (t_ctx_svol)dlsym(pa_lib, "pa_context_set_sink_input_volume");
        t_op_stat  pa_operation_get_state_           = (t_op_stat) dlsym(pa_lib, "pa_operation_get_state");
        t_op_uref  pa_operation_unref_               = (t_op_uref) dlsym(pa_lib, "pa_operation_unref");
        t_plist    pa_proplist_gets_                 = (t_plist)   dlsym(pa_lib, "pa_proplist_gets");

        if (!pa_mainloop_new_ || !pa_mainloop_get_api_ || !pa_mainloop_iterate_ ||
            !pa_mainloop_free_ || !pa_context_new_ || !pa_context_connect_ ||
            !pa_context_disconnect_ || !pa_context_unref_ || !pa_context_get_state_ ||
            !pa_context_get_sink_input_info_list_ || !pa_context_set_sink_input_volume_ ||
            !pa_operation_get_state_ || !pa_operation_unref_ || !pa_proplist_gets_) return;

        // PA context state constants
        const int PA_CONTEXT_READY      = 4;
        const int PA_CONTEXT_FAILED     = 5;
        const int PA_CONTEXT_TERMINATED = 6;

        void* ml = pa_mainloop_new_();
        if (!ml) return;
        void* api = pa_mainloop_get_api_(ml);
        void* ctx = pa_context_new_(api, "navius-vol");
        if (!ctx) { pa_mainloop_free_(ml); return; }

        bool ready = false;
        if (pa_context_connect_(ctx, nullptr, 0, nullptr) >= 0) {
            for (int i = 0; i < 500; i++) {
                int s = pa_context_get_state_(ctx);
                if (s == PA_CONTEXT_READY)      { ready = true; break; }
                if (s == PA_CONTEXT_FAILED ||
                    s == PA_CONTEXT_TERMINATED) break;
                pa_mainloop_iterate_(ml, 1, nullptr);
            }
        }

        if (ready) {
            navius_vol_data d;
            d.vol = vol;
            d.ctx = ctx;
            d.fn_set_vol       = (void*)pa_context_set_sink_input_volume_;
            d.fn_op_unref      = (void*)pa_operation_unref_;
            d.fn_proplist_gets = (void*)pa_proplist_gets_;

            void* op = pa_context_get_sink_input_info_list_(
                           ctx, (void*)navius_sink_input_vol_cb, &d);
            if (op) {
                for (int i = 0; i < 200 && pa_operation_get_state_(op) == 0; i++)
                    pa_mainloop_iterate_(ml, 1, nullptr);
                pa_operation_unref_(op);
            }
        }

        pa_context_disconnect_(ctx);
        pa_context_unref_(ctx);
        pa_mainloop_free_(ml);
    }
}}

#[allow(dead_code)]
extern "C" {
    fn navius_pa_init()      -> *const std::os::raw::c_char;
    fn navius_espeak_init(app_root: *const u8) -> *const std::os::raw::c_char;
    fn navius_espeak_say(data: *const u8, len: usize);
    fn navius_espeak_set_voice(data: *const u8, len: usize);
    fn navius_play_wav(path: *const u8);
    fn navius_http_download(url: *const u8, part: *const u8, log: *const u8) -> i32;
    fn navius_beep();
    fn navius_alert_beep();
    fn navius_reroute_beep();
    fn navius_set_music_volume(vol: f32);
}

unsafe fn cstr(p: *const std::os::raw::c_char) -> String {
    std::ffi::CStr::from_ptr(p).to_string_lossy().into_owned()
}

// ── QObject NavTts ───────────────────────────────────────────────────────────

#[derive(QObject, Default)]
pub struct NavTts {
    base: qt_base_class!(trait QObject),

    /// Mute global (modo silencio). Cuando es true, NINGÚN sonido se reproduce
    /// (voz ni pitidos), pase lo que pase en los call-sites. Atado desde QML a
    /// `_soundCap === "silencio"`.
    pub muted: qt_property!(bool),

    /// Reproduce el texto con el motor TTS activo.
    pub say: qt_method!(fn say(&mut self, text: QString) {
        if self.muted { return; }
        let s: String = text.into();
        std::thread::spawn(move || {
            let _g = TTS_LOCK.lock().unwrap_or_else(|e| e.into_inner());
            say_inner(s);
        });
    }),

    /// Pitido de indicación de maniobra.
    pub beep: qt_method!(fn beep(&mut self) {
        if self.muted { return; }
        std::thread::spawn(|| {
            let _g = TTS_LOCK.lock().unwrap_or_else(|e| e.into_inner());
            beep_inner();
        });
    }),

    /// Pitido de alerta de radar/velocidad.
    pub alert_beep: qt_method!(fn alert_beep(&mut self) {
        if self.muted { return; }
        std::thread::spawn(|| {
            let _g = TTS_LOCK.lock().unwrap_or_else(|e| e.into_inner());
            let st = unsafe { cstr(navius_pa_init()) };
            if st != "ok" { log(&format!("pa_init failed: {st}")); return; }
            unsafe { navius_alert_beep(); }
        });
    }),

    /// Pitido de recálculo de ruta.
    pub reroute_beep: qt_method!(fn reroute_beep(&mut self) {
        if self.muted { return; }
        std::thread::spawn(|| {
            let _g = TTS_LOCK.lock().unwrap_or_else(|e| e.into_inner());
            let st = unsafe { cstr(navius_pa_init()) };
            if st != "ok" { log(&format!("pa_init failed: {st}")); return; }
            unsafe { navius_reroute_beep(); }
        });
    }),

    /// Aplica volumen (0.0–1.0) al sink input de media-hub-server via PulseAudio.
    /// Necesario porque AalMediaPlayerService::setVolume en libaalmediaplayer.so
    /// es un no-op cuando hay sesión válida (lomiri::MediaHub::Player no tiene setVolume).
    pub set_music_volume: qt_method!(fn set_music_volume(&self, vol: f32) {
        std::thread::spawn(move || {
            unsafe { navius_set_music_volume(vol); }
        });
    }),

    /// Selecciona el motor TTS más adecuado para el idioma dado.
    /// El estado se actualiza de forma síncrona (solo la init de espeak va en hilo).
    pub set_voice: qt_method!(fn set_voice(&mut self, lang: QString) {
        let lang: String = lang.into();
        // Resolve engine and voice with file-system lookups only (no TTS output needed).
        let (engine, voice) = select_engine(&lang);
        // Update tts_state immediately so pregenerate() sees the correct engine/voice
        // without waiting for any ongoing TTS playback (TTS_LOCK is NOT needed here).
        {
            let mut st = tts_state().lock().unwrap_or_else(|e| e.into_inner());
            st.engine = engine.clone();
            st.voice  = voice.clone();
        }
        log(&format!("set_voice: engine={} voice={voice}", engine_name(&engine)));
        // espeak requires one-time dlopen init; do it in background to avoid blocking QML.
        if engine == Engine::Espeak {
            std::thread::spawn(move || {
                let _g = TTS_LOCK.lock().unwrap_or_else(|e| e.into_inner());
                let root = format!("{APP_ROOT}\0");
                let st2 = unsafe { cstr(navius_espeak_init(root.as_ptr())) };
                if st2 != "ok" { log(&format!("espeak_init failed: {st2}")); }
                unsafe { navius_espeak_set_voice(voice.as_ptr(), voice.len()); }
            });
        }
    }),

    /// Reproduce el texto forzando temporalmente el idioma indicado (test/demo).
    pub say_with_lang: qt_method!(fn say_with_lang(&mut self, lang: QString, text: QString) {
        if self.muted { return; }
        let l: String = lang.into();
        let t: String = text.into();
        std::thread::spawn(move || {
            let _g = TTS_LOCK.lock().unwrap_or_else(|e| e.into_inner());
            let (engine, voice) = select_engine(&l);
            match engine {
                Engine::Piper    => say_piper(&voice, &t),
                Engine::MimicHts => say_mimic_hts(&voice, &t),
                Engine::PicoTts  => say_pico(&voice, &t),
                Engine::Espeak   => say_espeak_voice(&voice, &t),
            }
        });
    }),

    /// True si el binario del motor indicado está disponible.
    pub engine_available: qt_method!(fn engine_available(&self, name: QString) -> bool {
        let name: String = name.into();
        match name.as_str() {
            "piper"   => std::path::Path::new(&format!("{APP_ROOT}/lib/piper")).exists(),
            "mimic"   => std::path::Path::new(&format!("{APP_ROOT}/lib/mimic_hts_es")).exists(),
            "picotts" => std::path::Path::new(&format!("{APP_ROOT}/lib/pico2wave")).exists(),
            "espeak"  => true,
            _         => false,
        }
    }),

    /// True si la voz Piper del idioma indicado está instalada.
    pub voice_installed: qt_method!(fn voice_installed(&self, lang: QString) -> bool {
        let lang: String = lang.into();
        std::path::Path::new(&format!("{PIPER_VOICES_DIR}/{lang}.onnx")).exists()
    }),

    /// Lista las voces Piper instaladas para el prefijo de idioma dado (p.ej. "es").
    /// Devuelve IDs separados por coma (sin .onnx), ordenados alfabéticamente.
    pub installed_piper_voices: qt_method!(fn installed_piper_voices(&self, lang: QString) -> QString {
        let lang: String = lang.into();
        let dir = std::path::Path::new(PIPER_VOICES_DIR);
        if !dir.exists() { return "".into(); }
        let mut voices: Vec<String> = match std::fs::read_dir(dir) {
            Err(_) => return "".into(),
            Ok(rd) => rd.filter_map(|e| e.ok())
                .filter_map(|e| {
                    let n = e.file_name().to_string_lossy().to_string();
                    if !n.ends_with(".onnx") || n.ends_with(".part") { return None; }
                    let id = n.trim_end_matches(".onnx").to_string();
                    if id == lang { return Some(id); }
                    if id.starts_with(&lang) {
                        let rest = &id[lang.len()..];
                        if rest.starts_with('_') || rest.starts_with('-') || rest.starts_with('.') {
                            return Some(id);
                        }
                    }
                    None
                })
                .collect(),
        };
        voices.sort();
        voices.join(",").into()
    }),

    /// Voces PicoTTS disponibles para el idioma dado (separadas por coma).
    /// Devuelve "" si el binario no está o el idioma no tiene variantes.
    pub available_pico_voices: qt_method!(fn available_pico_voices(&self, lang: QString) -> QString {
        let lang: String = lang.into();
        let bin = format!("{APP_ROOT}/lib/pico2wave");
        if !std::path::Path::new(&bin).exists() { return "".into(); }
        let base = lang.split(|c: char| c == '_' || c == '-').next().unwrap_or(&lang);
        let voices: &[&str] = match base {
            "en" => &["en-US", "en-GB"],
            "de" => &["de-DE"],
            "es" => &["es-ES"],
            "fr" => &["fr-FR"],
            "it" => &["it-IT"],
            _    => &[],
        };
        voices.join(",").into()
    }),

    /// Voces espeak-ng disponibles para el idioma dado (separadas por coma).
    /// Devuelve "" si el idioma no tiene variantes seleccionables.
    pub available_espeak_voices: qt_method!(fn available_espeak_voices(&self, lang: QString) -> QString {
        let lang: String = lang.into();
        let base = lang.split(|c: char| c == '_' || c == '-').next().unwrap_or(&lang);
        let voices: &[&str] = match base {
            "es" => &["es", "es-la"],
            "en" => &["en-us", "en-gb", "en-sc", "en-wls"],
            "fr" => &["fr", "fr-be", "fr-ch"],
            "pt" => &["pt", "pt-pt"],
            _    => &[],
        };
        voices.join(",").into()
    }),

    /// Descarga voz Piper: primero el .onnx, luego el .onnx.json.
    pub download_voice: qt_method!(fn download_voice(&self, lang: QString, url: QString) {
        let lang: String = lang.into();
        let url: String  = url.into();
        std::thread::spawn(move || {
            let _ = std::fs::create_dir_all(PIPER_VOICES_DIR);
            let part     = format!("{PIPER_VOICES_DIR}/{lang}.onnx.part");
            let dest     = format!("{PIPER_VOICES_DIR}/{lang}.onnx");
            let err_file = format!("{PIPER_VOICES_DIR}/{lang}.error");
            let _ = std::fs::remove_file(&err_file);
            let _ = std::fs::remove_file(&part);
            log(&format!("piper voice download start: {lang} url={url}"));
            let log_c  = format!("{DATA_DIR}/debug/tts_debug.log\0");
            let url_c  = format!("{url}\0");
            let part_c = format!("{part}\0");
            let rc = unsafe {
                navius_http_download(url_c.as_ptr(), part_c.as_ptr(), log_c.as_ptr())
            };
            let sz = std::fs::metadata(&part).map(|m| m.len()).unwrap_or(0);
            log(&format!("piper voice download rc={rc} bytes={sz}"));
            if rc == 0 && sz > 0 {
                let _ = std::fs::rename(&part, &dest);
                log(&format!("piper voice installed: {lang}.onnx"));
                // Descarga el .json de configuración (mismo URL + ".json")
                let url_json = format!("{url}.json\0");
                let dest_json = format!("{PIPER_VOICES_DIR}/{lang}.onnx.json");
                let part_json = format!("{dest_json}.part\0");
                let rc2 = unsafe {
                    navius_http_download(url_json.as_ptr(), part_json.as_ptr(), log_c.as_ptr())
                };
                if rc2 == 0 {
                    let _ = std::fs::rename(part_json.trim_end_matches('\0'), &dest_json);
                    log(&format!("piper voice json installed: {lang}.onnx.json"));
                } else {
                    log(&format!("piper voice json failed rc={rc2}"));
                }
            } else {
                let _ = std::fs::remove_file(&part);
                let msg = format!("descarga fallida (rc={rc})");
                let _ = std::fs::write(&err_file, &msg);
                log(&format!("piper voice download failed ({lang}): {msg}"));
            }
        });
    }),

    /// Estado de descarga de voz Piper: "idle"|"downloading:N"|"installed"|"error:MSG".
    pub download_status: qt_method!(fn download_status(&self, lang: QString) -> QString {
        let lang: String = lang.into();
        if std::path::Path::new(&format!("{PIPER_VOICES_DIR}/{lang}.onnx")).exists() {
            return "installed".into();
        }
        let part = format!("{PIPER_VOICES_DIR}/{lang}.onnx.part");
        if std::path::Path::new(&part).exists() {
            let sz = std::fs::metadata(&part).map(|m| m.len()).unwrap_or(0);
            return format!("downloading:{sz}").into();
        }
        let err_file = format!("{PIPER_VOICES_DIR}/{lang}.error");
        if std::path::Path::new(&err_file).exists() {
            let msg = std::fs::read_to_string(&err_file).unwrap_or_default();
            return format!("error:{}", msg.trim()).into();
        }
        "idle".into()
    }),

    /// Elimina una voz Piper descargada. Devuelve true si se eliminó.
    pub delete_voice: qt_method!(fn delete_voice(&self, lang: QString) -> bool {
        let lang: String = lang.into();
        let a = std::fs::remove_file(format!("{PIPER_VOICES_DIR}/{lang}.onnx")).is_ok();
        let _ = std::fs::remove_file(format!("{PIPER_VOICES_DIR}/{lang}.onnx.json"));
        a
    }),

    /// Devuelve el motor que se usaría para el idioma dado. Valores: "piper"|"picotts"|"espeak".
    pub engine_for_lang: qt_method!(fn engine_for_lang(&self, lang: QString) -> QString {
        let lang: String = lang.into();
        let (engine, _) = select_engine(&lang);
        match engine {
            Engine::Piper    => "piper".into(),
            Engine::MimicHts => "mimic".into(),
            Engine::PicoTts  => "picotts".into(),
            Engine::Espeak   => "espeak".into(),
        }
    }),

    /// Fuerza el motor TTS: "auto"|"piper"|"mimic"|"picotts"|"espeak".
    pub set_engine_override: qt_method!(fn set_engine_override(&self, engine: QString) {
        let engine: String = engine.into();
        let ov = match engine.as_str() {
            "piper"   => Some(Engine::Piper),
            "mimic"   => Some(Engine::MimicHts),
            "picotts" => Some(Engine::PicoTts),
            "espeak"  => Some(Engine::Espeak),
            _         => None,
        };
        tts_state().lock().unwrap_or_else(|e| e.into_inner()).engine_override = ov;
        log(&format!("TTS: engine override → {engine}"));
    }),

    /// Pre-genera audio Piper en background sin bloquear reproducción.
    /// El job se encola en el worker FIFO; solo un proceso piper corre a la vez.
    pub pregenerate: qt_method!(fn pregenerate(&self, text: QString, lang: QString) -> QString {
        let text: String = text.into();
        let lang: String = lang.into();
        // Use the already-selected voice from tts_state so the correct Piper voice is used.
        let (engine, voice) = {
            let st = tts_state().lock().unwrap_or_else(|e| e.into_inner());
            (st.engine.clone(), st.voice.clone())
        };
        if !matches!(engine, Engine::Piper) { return "".into(); }
        let eng_name = engine_name(&engine);
        let key  = cache_key(eng_name, &lang, &text);
        let path = format!("{CACHE_LIVE_DIR}/{key}.wav");
        if !std::path::Path::new(&path).exists() {
            let _ = std::fs::create_dir_all(CACHE_LIVE_DIR);
            generating().lock().unwrap_or_else(|e| e.into_inner()).insert(key.clone());
            piper_enqueue(PiperJob { voice, text, out_path: path, key: key.clone() });
        }
        key.into()
    }),

    /// Reproduce audio pre-generado si está listo; si no, usa motor de backup inmediatamente.
    pub play_pregenerated: qt_method!(fn play_pregenerated(&self, key: QString, text: QString, lang: QString) {
        if self.muted { return; }
        let key: String  = key.into();
        let text: String = text.into();
        let lang: String = lang.into();
        std::thread::spawn(move || {
            let path = format!("{CACHE_LIVE_DIR}/{key}.wav");
            // Decisión instantánea: ¿está listo el WAV de Piper?
            let piper_ready = std::path::Path::new(&path).exists()
                && !generating().lock().unwrap_or_else(|e| e.into_inner()).contains(&key);
            // TTS_LOCK solo serializa reproducción (no generación)
            let _g = TTS_LOCK.lock().unwrap_or_else(|e| e.into_inner());
            if piper_ready && std::path::Path::new(&path).exists() {
                let path_c = format!("{path}\0");
                unsafe { navius_play_wav(path_c.as_ptr()); }
                log(&format!("played cached (piper): {key}"));
            } else {
                // Piper no listo → motor de backup inmediato
                log(&format!("piper not ready → backup: {key}"));
                let norm = lang.replace('-', "_");
                let base = norm.split('_').next().unwrap_or(&norm).to_string();
                if let Some((_, voice)) = try_picotts(&norm, &base) {
                    say_pico(&voice, &text);
                } else {
                    say_espeak_voice(espeak_voice(&norm), &text);
                }
            }
        });
    }),

    /// Reproduce frase de inicio de ruta y, opcionalmente, la primera instrucción.
    /// first_dist_m_raw=0 → no hay primera instrucción que decir (navBar lo gestionará pronto).
    pub play_start_route: qt_method!(fn play_start_route(
        &self, first_dist_m_raw: i32, first_key: QString, first_text: QString, lang: QString
    ) {
        if self.muted { return; }
        let first_key:  String = first_key.into();
        let first_text: String = first_text.into();
        let lang:       String = lang.into();
        std::thread::spawn(move || {
            let _g = TTS_LOCK.lock().unwrap_or_else(|e| e.into_inner());
            let norm = lang.replace('-', "_");
            let base = norm.split('_').next().unwrap_or(&norm).to_string();
            let (engine, voice) = {
                let st = tts_state().lock().unwrap_or_else(|e| e.into_inner());
                (st.engine.clone(), st.voice.clone())
            };

            // ── 0. Pitido previo ──────────────────────────────────────────────
            beep_inner();

            // ── 1. Frase de inicio ────────────────────────────────────────────
            let phrase      = start_phrase(&lang);
            let phrase_key  = cache_key(engine_name(&engine), &lang, phrase);
            let phrase_path = format!("{CACHE_ROUND_DIR}/{phrase_key}.wav");
            if matches!(engine, Engine::Piper)
                && std::path::Path::new(&phrase_path).exists()
                && !generating().lock().unwrap_or_else(|e| e.into_inner()).contains(&phrase_key) {
                let p = format!("{phrase_path}\0");
                unsafe { navius_play_wav(p.as_ptr()); }
                log("play_start_route: phrase (piper)");
            } else {
                say_backup(&engine, &voice, &norm, &base, phrase);
                log("play_start_route: phrase (backup)");
            }

            // ── 2. Primera instrucción (si procede) ───────────────────────────
            if first_dist_m_raw > 0 && !first_text.is_empty() {
                let first_dist_m = round_dist(first_dist_m_raw);
                let instr_path   = format!("{CACHE_LIVE_DIR}/{first_key}.wav");
                let instr_ready  = std::path::Path::new(&instr_path).exists()
                    && !generating().lock().unwrap_or_else(|e| e.into_inner()).contains(&first_key);

                if !instr_ready {
                    let full = format!("{}, {first_text}", format_dist_text(first_dist_m, &lang));
                    log(&format!("play_start_route: backup first instr dist={first_dist_m}m"));
                    say_backup(&engine, &voice, &norm, &base, &full);
                } else {
                    // Prefijo de distancia
                    let dist_text  = format_dist_text(first_dist_m, &lang);
                    let round_key  = cache_key(engine_name(&engine), &lang, &dist_text);
                    let round_path = format!("{CACHE_ROUND_DIR}/{round_key}.wav");
                    if std::path::Path::new(&round_path).exists()
                        && !generating().lock().unwrap_or_else(|e| e.into_inner()).contains(&round_key) {
                        let p = format!("{round_path}\0");
                        unsafe { navius_play_wav(p.as_ptr()); }
                    } else {
                        say_backup(&engine, &voice, &norm, &base, &dist_text);
                    }
                    // Instrucción desde caché
                    let p = format!("{instr_path}\0");
                    unsafe { navius_play_wav(p.as_ptr()); }
                    log(&format!("play_start_route: first instr dist={first_dist_m}m"));
                }
            } else {
                log("play_start_route: no first instr (navBar will handle)");
            }
        });
    }),

    /// Pre-genera todos los ficheros de distancia de redondeo para el idioma dado.
    /// Los jobs se encolan en el worker FIFO: un proceso piper a la vez.
    /// Solo aplica si el motor activo es Piper.
    pub pregenerate_round_dists: qt_method!(fn pregenerate_round_dists(&self, lang: QString) {
        let lang: String = lang.into();
        PREGEN_ACTIVE.store(true, Ordering::SeqCst);
        std::thread::spawn(move || {
            // Use the already-selected voice from tts_state so the correct Piper voice is used.
            let (engine, voice) = {
                let st = tts_state().lock().unwrap_or_else(|e| e.into_inner());
                (st.engine.clone(), st.voice.clone())
            };
            if !matches!(engine, Engine::Piper) {
                log(&format!("pregenerate_round_dists: engine={:?} no es Piper, skip", engine));
                PREGEN_ACTIVE.store(false, Ordering::SeqCst);
                return;
            }
            let _ = std::fs::create_dir_all(CACHE_ROUND_DIR);

            let mut tasks: Vec<(String, String, String)> = vec![];
            let phrase      = start_phrase(&lang);
            let phrase_key  = cache_key(engine_name(&engine), &lang, phrase);
            let phrase_path = format!("{CACHE_ROUND_DIR}/{phrase_key}.wav");
            if !std::path::Path::new(&phrase_path).exists() {
                tasks.push((phrase.to_string(), phrase_key, phrase_path));
            }
            for &dist_m in ROUND_DISTANCES {
                let text = format_dist_text(dist_m, &lang);
                let key  = cache_key(engine_name(&engine), &lang, &text);
                let path = format!("{CACHE_ROUND_DIR}/{key}.wav");
                if !std::path::Path::new(&path).exists() {
                    tasks.push((text, key, path));
                }
            }

            if tasks.is_empty() {
                PREGEN_ACTIVE.store(false, Ordering::SeqCst);
                log("pregenerate_round_dists: all cached");
                return;
            }

            PREGEN_TOTAL.store(tasks.len(), Ordering::SeqCst);
            PREGEN_DONE.store(0, Ordering::SeqCst);

            // Encolar todos los jobs; el worker los ejecuta de uno en uno.
            for (text, key, path) in tasks {
                generating().lock().unwrap_or_else(|e| e.into_inner()).insert(key.clone());
                piper_enqueue(PiperJob { voice: voice.clone(), text, out_path: path, key });
            }
            log("pregenerate_round_dists: jobs en cola");
        });
    }),

    /// Devuelve true mientras se están pre-generando las locuciones de distancia.
    pub is_pregen_active: qt_method!(fn is_pregen_active(&self) -> bool {
        PREGEN_ACTIVE.load(Ordering::SeqCst)
    }),

    /// Devuelve "X/Y" con el progreso de pre-generación, o "" si no está activa.
    pub pregen_progress: qt_method!(fn pregen_progress(&self) -> QString {
        if !PREGEN_ACTIVE.load(Ordering::SeqCst) { return "".into(); }
        let done  = PREGEN_DONE.load(Ordering::SeqCst);
        let total = PREGEN_TOTAL.load(Ordering::SeqCst);
        format!("{}/{}", done + 1, total).into()
    }),

    /// Reproduce: prefijo de distancia (si dist_m>0) + instrucción parte1 (key1) +
    /// opcionalmente parte2 (key2, solo en "ya"). Backup a PicoTTS/espeak si WAVs no listos.
    pub play_round_then_instr: qt_method!(fn play_round_then_instr(
        &self, dist_m: i32,
        key1: QString, text1: QString,
        key2: QString, text2: QString,
        lang: QString
    ) {
        if self.muted { return; }
        let key1:  String = key1.into();
        let text1: String = text1.into();
        let key2:  String = key2.into();
        let text2: String = text2.into();
        let lang:  String = lang.into();
        // Signal any ongoing WAV playback to stop immediately.
        PLAYBACK_CANCEL.store(true, Ordering::SeqCst);
        std::thread::spawn(move || {
            let instr_path = format!("{CACHE_LIVE_DIR}/{key1}.wav");
            let instr_ready = std::path::Path::new(&instr_path).exists()
                && !generating().lock().unwrap_or_else(|e| e.into_inner()).contains(&key1);
            let _g = TTS_LOCK.lock().unwrap_or_else(|e| e.into_inner());
            // We now own the lock – clear cancel so our own playback runs uninterrupted.
            PLAYBACK_CANCEL.store(false, Ordering::SeqCst);
            let norm = lang.replace('-', "_");
            let base = norm.split('_').next().unwrap_or(&norm).to_string();
            // Use tts_state for engine/voice so cache keys match what pregenerate produced.
            let (ts_engine, ts_voice) = {
                let st = tts_state().lock().unwrap_or_else(|e| e.into_inner());
                (st.engine.clone(), st.voice.clone())
            };

            if !instr_ready {
                // Instrucción no disponible en caché → backup TTS frase completa
                let full_instr = if text2.is_empty() { text1.clone() }
                                 else { format!("{text1}. {text2}") };
                let full = if dist_m > 0 {
                    format!("{}, {full_instr}", format_dist_text(dist_m, &lang))
                } else {
                    full_instr
                };
                log(&format!("backup full announce: dist_m={dist_m} key1={key1}"));
                say_backup(&ts_engine, &ts_voice, &norm, &base, &full);
                return;
            }

            // ── Instrucción lista en caché ────────────────────────────────────
            // Prefijo de distancia (si existe)
            if dist_m > 0 {
                let dist_text = format_dist_text(dist_m, &lang);
                let dist_played = if dist_m > 10000 {
                    if matches!(ts_engine, Engine::Piper | Engine::MimicHts) {
                        let live_key  = cache_key(engine_name(&ts_engine), &lang, &dist_text);
                        let live_path = format!("{CACHE_LIVE_DIR}/{live_key}.wav");
                        if !std::path::Path::new(&live_path).exists() {
                            let _ = std::fs::create_dir_all(CACHE_LIVE_DIR);
                            generate_to_cache(&ts_engine, &ts_voice, &dist_text, &live_path, 2);
                        }
                        if std::path::Path::new(&live_path).exists() {
                            let p = format!("{live_path}\0");
                            unsafe { navius_play_wav(p.as_ptr()); }
                            log(&format!("play_round: >10km live {dist_m}m"));
                            true
                        } else { false }
                    } else { false }
                } else {
                    let round_key  = cache_key(engine_name(&ts_engine), &lang, &dist_text);
                    let round_path = format!("{CACHE_ROUND_DIR}/{round_key}.wav");
                    if std::path::Path::new(&round_path).exists()
                        && !generating().lock().unwrap_or_else(|e| e.into_inner()).contains(&round_key) {
                        let p = format!("{round_path}\0");
                        unsafe { navius_play_wav(p.as_ptr()); }
                        log(&format!("play_round: {dist_m}m key={round_key}"));
                        true
                    } else { false }
                };
                if !dist_played {
                    log(&format!("round not ready → backup prefix: {dist_m}m"));
                    say_backup(&ts_engine, &ts_voice, &norm, &base, &dist_text);
                }
            }

            // Instrucción parte1 desde caché
            let p1 = format!("{instr_path}\0");
            unsafe { navius_play_wav(p1.as_ptr()); }
            log(&format!("play_instr part1: key1={key1}"));

            // Instrucción parte2 (solo "ya"): caché si lista, backup si no
            if !key2.is_empty() && !text2.is_empty() {
                let instr2_path = format!("{CACHE_LIVE_DIR}/{key2}.wav");
                if std::path::Path::new(&instr2_path).exists()
                    && !generating().lock().unwrap_or_else(|e| e.into_inner()).contains(&key2) {
                    let p2 = format!("{instr2_path}\0");
                    unsafe { navius_play_wav(p2.as_ptr()); }
                    log(&format!("play_instr part2: key2={key2}"));
                } else {
                    log(&format!("part2 not ready → backup: key2={key2}"));
                    say_backup(&ts_engine, &ts_voice, &norm, &base, &text2);
                }
            }
        });
    }),

    /// True si el TTS está ocupado generando o reproduciendo audio ahora mismo.
    pub is_tts_busy: qt_method!(fn is_tts_busy(&self) -> bool {
        TTS_LOCK.try_lock().is_err()
    }),

    pub stop_tts: qt_method!(fn stop_tts(&self) {
        PLAYBACK_CANCEL.store(true, Ordering::SeqCst);
    }),

    /// Borra solo la caché de instrucciones (tts_cache_live). Conserva tts_cache_round.
    pub clear_tts_cache: qt_method!(fn clear_tts_cache(&self) {
        fn rm_dir_contents(path: &str) {
            if let Ok(entries) = std::fs::read_dir(path) {
                for e in entries.flatten() { let _ = std::fs::remove_file(e.path()); }
            }
        }
        rm_dir_contents(CACHE_LIVE_DIR);
        rm_dir_contents(CACHE_TMP_DIR);
        log("tts live cache cleared");
    }),

    /// Borra toda la caché TTS (live + round + tmp). Llamar desde el botón manual en preferencias.
    pub clear_all_tts_cache: qt_method!(fn clear_all_tts_cache(&self) {
        fn rm_dir_contents(path: &str) {
            if let Ok(entries) = std::fs::read_dir(path) {
                for e in entries.flatten() { let _ = std::fs::remove_file(e.path()); }
            }
        }
        rm_dir_contents(CACHE_LIVE_DIR);
        rm_dir_contents(CACHE_ROUND_DIR);
        rm_dir_contents(CACHE_TMP_DIR);
        log("tts full cache cleared (live + round + tmp)");
    }),

    /// Devuelve true si el TTS está reproduciendo audio en este momento.
    /// Se comprueba intentando adquirir TTS_LOCK; si está tomado, hay reproducción activa.
    pub is_speaking: qt_method!(fn is_speaking(&self) -> bool {
        TTS_LOCK.try_lock().is_err()
    }),
}
