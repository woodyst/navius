#![recursion_limit = "4096"]

/*
 * Copyright (C) 2026  Edi
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * navius is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#[macro_use]
extern crate cstr;
#[macro_use]
extern crate qmetaobject;

use std::env;
use std::path::PathBuf;

use gettextrs::{bindtextdomain, textdomain};
use qmetaobject::*;
use cpp::cpp;

mod nav_http;
mod nav_music;
mod nav_tracker;
mod nav_tts;
mod qrc;
mod satellite_model;

use nav_http::NavHttp;
use nav_tracker::NavTracker;
use nav_tts::NavTts;
use satellite_model::SatelliteModel;

fn main() {
    // Set library path so the bundled libQMapLibre.so.3 is found
    // when the QML engine dlopen()s the MapboxMap plugin.
    let app_root = "/opt/click.ubuntu.com/navius.woodyst/current";
    let lib_dir  = format!("{}/lib", app_root);
    env::set_var("LD_LIBRARY_PATH", &lib_dir);
    // Allow QML XMLHttpRequest to read/write local file:// URLs (debug command file).
    env::set_var("QML_XHR_ALLOW_FILE_READ", "1");
    env::set_var("QML_XHR_ALLOW_FILE_WRITE", "1");
    env::set_var("QML_DISABLE_DISK_CACHE", "1");

    init_gettext();
    unsafe {
        cpp! { {
            #include <QtCore/QCoreApplication>
            #include <QtCore/QString>
        }}
        cpp! {[]{
            QCoreApplication::setOrganizationName(QStringLiteral("navius.woodyst"));
            QCoreApplication::setOrganizationDomain(QStringLiteral("woodyst.navius"));
            QCoreApplication::setApplicationName(QStringLiteral("navius.woodyst"));
        }}
    }
    QQuickStyle::set_style("Suru");
    qrc::load();

    qml_register_type::<SatelliteModel>(
        cstr!("Navius"),
        1, 0,
        cstr!("SatelliteModel"),
    );
    qml_register_type::<NavHttp>(
        cstr!("Navius"),
        1, 0,
        cstr!("NavHttp"),
    );
    qml_register_type::<NavTracker>(
        cstr!("Navius"),
        1, 0,
        cstr!("NavTracker"),
    );
    qml_register_type::<NavTts>(
        cstr!("Navius"),
        1, 0,
        cstr!("NavTts"),
    );

    let mut engine = QmlEngine::new();
    // Add bundled QML plugin directory so `import MapboxMap 1.0` resolves.
    engine.add_import_path(format!("file://{}", lib_dir).into());
    // Explicitly add QRC QML directory so component types (CompassWidget etc.) are discoverable.
    engine.add_import_path("qrc:/qml".into());
    engine.load_file("qrc:/qml/Main.qml".into());
    engine.exec();
}

fn init_gettext() {
    let domain = "navius.woodyst";
    textdomain(domain).expect("Failed to set gettext domain");

    let mut app_dir_path = env::current_dir().expect("Failed to get the app working directory");
    if !app_dir_path.is_absolute() {
        app_dir_path = PathBuf::from("/usr");
    }

    let path = app_dir_path.join("share/locale");
    bindtextdomain(domain, path.to_str().unwrap()).expect("Failed to bind gettext domain");
}
