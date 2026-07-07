// nav_power.rs — Inhibición de suspensión para Ubuntu Touch / Lomiri
//
// Lomiri implementa org.freedesktop.ScreenSaver sin el método Inhibit estándar,
// por lo que QtSystemInfo.ScreenSaver no funciona. Esta solución llama
// SimulateUserActivity periódicamente mientras la inhibición está activa.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use qmetaobject::*;

const SIMULATE_INTERVAL_S: u64 = 30;

#[derive(QObject, Default)]
pub struct NavPower {
    base:    qt_base_class!(trait QObject),
    inhibit: qt_property!(bool; WRITE set_inhibit),

    #[allow(dead_code)]
    _stop: Option<Arc<AtomicBool>>,
}

impl NavPower {
    fn set_inhibit(&mut self, value: bool) {
        // Detener hilo anterior si existe
        if let Some(flag) = self._stop.take() {
            flag.store(true, Ordering::Relaxed);
        }

        if !value {
            return;
        }

        // Llamada inmediata para no esperar el primer ciclo
        call_simulate();

        let stop = Arc::new(AtomicBool::new(false));
        self._stop = Some(stop.clone());

        thread::spawn(move || {
            loop {
                thread::sleep(Duration::from_secs(SIMULATE_INTERVAL_S));
                if stop.load(Ordering::Relaxed) {
                    break;
                }
                call_simulate();
            }
        });
    }
}

fn call_simulate() {
    let _ = std::process::Command::new("dbus-send")
        .args([
            "--session",
            "--type=method_call",
            "--dest=org.freedesktop.ScreenSaver",
            "/org/freedesktop/ScreenSaver",
            "org.freedesktop.ScreenSaver.SimulateUserActivity",
        ])
        .output();
}
