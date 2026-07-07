// nav_power.rs — Inhibición de suspensión para Ubuntu Touch / Lomiri
//
// Usa com.canonical.Unity.Screen.keepDisplayOn (bus del sistema) vía Qt D-Bus.
// Requiere policy group "keep-display-on" en navius.apparmor.

use cpp::cpp;
use qmetaobject::*;

cpp! {{
    #include <QtDBus/QDBusConnection>
    #include <QtDBus/QDBusInterface>
    #include <QtDBus/QDBusReply>

    static int g_displayCookie = -1;

    extern "C" void navius_power_keep_on() {
        if (g_displayCookie >= 0) return;
        QDBusInterface iface(
            "com.canonical.Unity.Screen",
            "/com/canonical/Unity/Screen",
            "com.canonical.Unity.Screen",
            QDBusConnection::systemBus()
        );
        if (!iface.isValid()) {
            qWarning() << "[NavPower] Unity.Screen not available";
            return;
        }
        QDBusReply<int> reply = iface.call("keepDisplayOn");
        if (reply.isValid()) {
            g_displayCookie = reply.value();
            qDebug() << "[NavPower] keepDisplayOn cookie=" << g_displayCookie;
        } else {
            qWarning() << "[NavPower] keepDisplayOn failed:" << reply.error().message();
        }
    }

    extern "C" void navius_power_release() {
        if (g_displayCookie < 0) return;
        QDBusInterface iface(
            "com.canonical.Unity.Screen",
            "/com/canonical/Unity/Screen",
            "com.canonical.Unity.Screen",
            QDBusConnection::systemBus()
        );
        if (iface.isValid()) {
            iface.call("removeDisplayOnRequest", g_displayCookie);
            qDebug() << "[NavPower] removeDisplayOnRequest cookie=" << g_displayCookie;
        }
        g_displayCookie = -1;
    }
}}

extern "C" {
    fn navius_power_keep_on();
    fn navius_power_release();
}

#[derive(QObject, Default)]
pub struct NavPower {
    base:    qt_base_class!(trait QObject),
    inhibit: qt_property!(bool; WRITE set_inhibit),
}

impl NavPower {
    fn set_inhibit(&mut self, value: bool) {
        if value {
            unsafe { navius_power_keep_on() };
        } else {
            unsafe { navius_power_release() };
        }
    }
}
