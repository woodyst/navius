use cpp::cpp;
use qmetaobject::*;

cpp! {{
    #include <QtDBus/QDBusConnection>
    #include <QtDBus/QDBusInterface>
    #include <QtDBus/QDBusReply>
}}

#[derive(QObject)]
pub struct NavPower {
    base:    qt_base_class!(trait QObject),
    inhibit: qt_property!(bool; WRITE set_inhibit),
    _cookie: i32,
}

impl Default for NavPower {
    fn default() -> Self {
        NavPower { base: Default::default(), inhibit: Default::default(), _cookie: -1 }
    }
}

impl NavPower {
    fn set_inhibit(&mut self, value: bool) {
        if value && self._cookie < 0 {
            let cookie = unsafe { cpp!([] -> i32 as "int" {
                QDBusInterface iface(
                    QStringLiteral("com.canonical.Unity.Screen"),
                    QStringLiteral("/com/canonical/Unity/Screen"),
                    QStringLiteral("com.canonical.Unity.Screen"),
                    QDBusConnection::systemBus()
                );
                if (!iface.isValid()) {
                    qWarning() << "[NavPower] Unity.Screen not available";
                    return -1;
                }
                QDBusReply<int> reply = iface.call(QStringLiteral("keepDisplayOn"));
                if (reply.isValid()) {
                    qDebug() << "[NavPower] keepDisplayOn cookie=" << reply.value();
                    return reply.value();
                }
                qWarning() << "[NavPower] keepDisplayOn failed:" << reply.error().message();
                return -1;
            })};
            self._cookie = cookie;
        } else if !value && self._cookie >= 0 {
            let c = self._cookie;
            unsafe { cpp!([c as "int"] {
                QDBusInterface iface(
                    QStringLiteral("com.canonical.Unity.Screen"),
                    QStringLiteral("/com/canonical/Unity/Screen"),
                    QStringLiteral("com.canonical.Unity.Screen"),
                    QDBusConnection::systemBus()
                );
                if (iface.isValid()) {
                    iface.call(QStringLiteral("removeDisplayOnRequest"), c);
                    qDebug() << "[NavPower] removeDisplayOnRequest cookie=" << c;
                }
            })};
            self._cookie = -1;
        }
    }
}
