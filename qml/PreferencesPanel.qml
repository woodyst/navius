import QtQuick 2.7
import Lomiri.Components 1.3
import Qt.labs.settings 1.0

Rectangle {
    id: panel
    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }
    color: "#F2000000"

    // ── API ───────────────────────────────────────────────────────────────
    property var    cfg
    property var    ttsRef: null
    property var    trackerRef: null
    property var    vehicleMgr: null
    property bool   simSignalLost: false
    property bool   simFinished:   true
    property int    simSegIdx:     0
    property bool   navius:        false
    property string navMapStyles:  '["positron","bright","fiord","dark"]'

    readonly property var _mapStyleModes: {
        var base = [
            { key: "auto",      icon: "🗺",  label: i18n.tr("Auto")     },
            { key: "satellite", icon: "🛰",  label: i18n.tr("Satélite") }
        ]
        var extra = navius ? JSON.parse(navMapStyles) : ["positron", "bright"]
        var icons  = { positron: "☀", bright: "🌐", fiord: "🌊", dark: "🌙" }
        var labels = { positron: i18n.tr("Claro"), bright: i18n.tr("Vivo"),
                       fiord: i18n.tr("Fiord"),   dark: i18n.tr("Noche") }
        for (var i = 0; i < extra.length; i++)
            base.push({ key: extra[i], icon: icons[extra[i]] || "🗺",
                        label: labels[extra[i]] || extra[i] })
        return base
    }

    signal closed()
    signal soundTest(string mode, string context)
    signal langChanged(string lang)
    signal lightModeApplied()
    signal simToggled(bool active)
    signal signalLostToggled()
    signal debugOff()
    signal debugOn()
    signal debugFileDeleteRequested(string pattern)
    signal simRouteChanged(int idx)
    signal manualPosApplied(real lat, real lon)
    signal manualPosCleared()
    signal voicesRequested()
    signal voiceSelected(string voiceId)
    signal voicePicoSelected(string voiceId)
    signal voiceEspeakSelected(string voiceId)
    signal trackSimRequested(string trackId, string trackName, bool raw)
    signal trackGpxRequested(string trackId)
    signal trackAddToSim(string trackId, string trackName)
    signal trackRemovedFromSim(int simIdx)
    property bool ttsProcessing: false
    signal engineChanged(string engine)

    property real _kbdH: Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0
    Behavior on _kbdH { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    property Item _kbdFocusItem: null
    signal clearLiveCacheRequested()
    signal mapCacheClearRequested()
    signal googleMapsCacheClearRequested()
    signal allTracksClearRequested()
    signal osmScoutDetectRequested()

    property bool osmScoutActive: false

    // ── Estado secciones colapsables (persistido) ─────────────────────────
    Settings {
        id: secSettings
        category: "PrefPanelSections"
        property bool quick:      true
        property bool general:    false
        property bool servidor:   false
        property bool nav:        false
        property bool grabacion:  false
        property bool voz:        false
        property bool media:      false
        property bool cuenta:     false
        property bool ayuda:      false
        property bool debug:      false
    }

    Settings {
        id: tourSt
        category: "tour"
        property bool showOnStart: true
    }

    signal helpRequested()
    signal loginRequested()

    Settings {
        id: authSettings
        category: "auth"
        property string token: ""
        property string email: ""
    }
    signal aboutRequested()
    signal tourRequested()

    // ── Background ────────────────────────────────────────────────────────
    Rectangle { anchors.fill: parent; color: "#0D0D1A" }

    Rectangle {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: units.gu(6); color: "#1C1C2E"

        Label {
            anchors.centerIn: parent
            text: i18n.tr("Ajustes"); color: "white"
            fontSize: "large"; font.bold: true
        }

        Rectangle {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter
                      rightMargin: units.gu(2) }
            width: units.gu(4); height: units.gu(4)
            radius: width / 2; color: "#2A2A3E"
            Label { anchors.centerIn: parent; text: "✕"; color: "#90A4AE"; font.pixelSize: ts(1.8) }
            MouseArea { anchors.fill: parent; onClicked: panel.closed() }
        }
    }

    Flickable {
        id: prefsFlick
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.bottomMargin: panel._kbdH
        contentHeight: prefCol.implicitHeight + units.gu(4)
        clip: true

        onHeightChanged: {
            if (!panel._kbdFocusItem || !Qt.inputMethod.visible) return
            var pos        = panel._kbdFocusItem.mapToItem(contentItem, 0, 0)
            var itemTop    = pos.y - units.gu(1)
            var itemBottom = pos.y + panel._kbdFocusItem.height + units.gu(2)
            if (itemBottom > contentY + height)
                contentY = Math.min(itemBottom - height, contentHeight - height)
            else if (itemTop < contentY)
                contentY = Math.max(0, itemTop)
        }

    Column {
        id: prefCol
        anchors { left: parent.left; right: parent.right; leftMargin: units.gu(2); rightMargin: units.gu(2) }
        topPadding: units.gu(2)
        spacing: units.gu(1.5)

        // ── Restaurar valores por defecto ────────────────────────────────
        Rectangle {
            width: parent.width; height: units.gu(5)
            radius: units.gu(1); border.width: 1
            property bool _confirm: false
            property bool _done:    false
            color:        _confirm ? "#1A1200" : "#1A1A2E"
            border.color: _confirm ? "#F9A825" : (_done ? "#2E7D32" : "#37474F")
            Behavior on color        { ColorAnimation { duration: 120 } }
            Behavior on border.color { ColorAnimation { duration: 120 } }
            Timer { id: resetConfirmTimer; interval: 3000; onTriggered: parent._confirm = false }
            Timer { id: resetDoneTimer;    interval: 3000; onTriggered: parent._done    = false }
            Row {
                anchors.centerIn: parent
                spacing: units.gu(1)
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.parent._done ? "✓" : (parent.parent._confirm ? "⚠" : "↺")
                    color: parent.parent._done ? "#66BB6A" : (parent.parent._confirm ? "#F9A825" : "#90A4AE")
                    font.pixelSize: ts(2.2)
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.parent._done    ? i18n.tr("Restaurado")
                        : parent.parent._confirm ? i18n.tr("Toca de nuevo para confirmar")
                        :                          i18n.tr("Restaurar valores por defecto")
                    color: parent.parent._done ? "#66BB6A" : (parent.parent._confirm ? "#F9A825" : "#90A4AE")
                    font.pixelSize: ts(1.75)
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (!panel.cfg) return
                    if (!parent._confirm) {
                        parent._confirm = true
                        resetConfirmTimer.restart()
                        return
                    }
                    // Confirmado: restaurar
                    resetConfirmTimer.stop()
                    parent._confirm = false
                    panel.cfg.lightMode           = "auto"
                    panel.cfg.autoZoom            = true
                    panel.cfg.bearingMode         = "north"
                    panel.cfg.autoZoomSecs        = 15
                    panel.cfg.mapMode             = "2d"
                    panel.cfg.navMapMode          = "3d"
                    panel.cfg.pitch3d             = 60
                    panel.cfg.mapStyleMode        = "auto"
                    panel.cfg.show3dBuildings     = true
                    panel.cfg.showZoomSlider      = false
                    panel.cfg.textScale           = 1.0
                    panel.cfg.measureSystem       = "metric"
                    panel.cfg.speedAlertEnabled   = true
                    panel.cfg.speedAlertPct       = 2
                    panel.cfg.showRoadSpeedLimit  = false
                    panel.cfg.showRadarFijos      = true
                    panel.cfg.showRadarTramo      = true
                    panel.cfg.radarAlertDist      = 400
                    panel.cfg.useHardwareSpeed    = true
                    panel.cfg.drEnabled           = true
                    panel.cfg.drHz                = 20
                    panel.cfg.alertSound          = "tts"
                    panel.cfg.instrSound          = "tts"
                    panel.cfg.ttsLang             = "system"
                    panel.cfg.ttsEngine           = "auto"
                    panel.cfg.duckVolume          = 0.70
                    panel.cfg.routeAdjustZoom     = true
                    panel.cfg.routeAheadSecs      = 10
                    panel.cfg.maxPredictiveTurnDeg = 30
                    panel.cfg.snapToRouteEnabled  = true
                    panel.cfg.snapDistM           = 11
                    panel.cfg.offRouteDistM       = 11
                    panel.cfg.inhibitSuspend      = true
                    panel.cfg.preferOsmScout      = true
                    panel.cfg.valhallaUrl         = "https://valhalla.egpsistemas.com"
                    panel.cfg.overpassServer      = "navius"
                    panel.cfg.mapCacheMaxMb       = 500
                    panel.cfg.mapOnlineSource     = "mapbox"
                    panel.cfg.mapOfflineMode      = "cache"
                    panel.cfg.mapTileServer       = "navius"
                    panel.cfg.tracesEnabled       = false
                    panel.cfg.showChangesAtStartup = true
                    parent._done = true
                    resetDoneTimer.restart()
                }
            }
        }

        // ── Nivel de opciones ────────────────────────────────────────────
        Rectangle {
            width: parent.width; height: units.gu(5.5)
            color: "#1C1C2E"; radius: units.gu(1)
            Row {
                anchors { fill: parent; margins: units.gu(0.8) }
                spacing: units.gu(0.8)
                Repeater {
                    model: [
                        { level: 0, label: i18n.tr("Mínimo")   },
                        { level: 1, label: i18n.tr("Medio")    },
                        { level: 2, label: i18n.tr("Avanzado") }
                    ]
                    Rectangle {
                        property bool sel: panel.cfg && panel.cfg.prefLevel === modelData.level
                        width: (parent.width - 2 * units.gu(0.8)) / 3
                        height: parent.height; radius: units.gu(0.6)
                        color:        sel ? "#1E3A5F" : "#2A2A3E"
                        border.color: sel ? "#29B6F6" : "transparent"; border.width: units.gu(0.15)
                        Label {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: sel ? "#29B6F6" : "#78909C"
                            font.pixelSize: ts(1.7); font.bold: sel
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: if (panel.cfg) panel.cfg.prefLevel = modelData.level
                        }
                    }
                }
            }
        }

        // ════════════════════════════════════════════════════════════════
        // AJUSTES RÁPIDOS
        // ════════════════════════════════════════════════════════════════
        Rectangle {
            visible: quickCol.hasContent
            width: parent.width; height: units.gu(5.5)
            color: "#252535"; radius: units.gu(1)
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                text: i18n.tr("Ajustes rápidos")
                color: "#29B6F6"; font.pixelSize: ts(2.0); font.bold: true
            }
            Label {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: units.gu(2) }
                text: secSettings.quick ? "▲" : "▼"
                color: "#29B6F6"; font.pixelSize: ts(1.6)
            }
            MouseArea { anchors.fill: parent; onClicked: secSettings.quick = !secSettings.quick }
        }

        Column {
            id: quickCol
            property int  _sectionMinLevel: 0
            property bool hasContent: panel.cfg ? panel.cfg.prefLevel >= _sectionMinLevel : false
            visible: secSettings.quick && hasContent
            width: parent.width; spacing: units.gu(1.5)

            // ── Modo de luz ──────────────────────────────────────────────
            Rectangle {
                width: parent.width; height: units.gu(14)
                color: "#1C1C2E"; radius: units.gu(1)

                Column {
                    anchors { fill: parent; margins: units.gu(2) }
                    spacing: units.gu(1.5)

                    Label { text: i18n.tr("Modo de luz"); color: "#90A4AE"; font.pixelSize: ts(1.8) }

                    Row {
                        spacing: units.gu(1.5)
                        Repeater {
                            model: [
                                { key: "day",   icon: "☀", label: i18n.tr("Día") },
                                { key: "night", icon: "☽", label: i18n.tr("Noche") },
                                { key: "auto",  icon: "⊙", label: i18n.tr("Auto") + " ↺" }
                            ]
                            delegate: Rectangle {
                                width: (parent.parent.width - units.gu(3)) / 3
                                height: units.gu(7)
                                radius: units.gu(0.8)
                                color:  panel.cfg && panel.cfg.lightMode === modelData.key ? "#1E3A5F" : "#2A2A3E"
                                border.color: panel.cfg && panel.cfg.lightMode === modelData.key ? "#29B6F6" : "transparent"
                                border.width: units.gu(0.2)
                                Column {
                                    anchors.centerIn: parent; spacing: units.gu(0.3)
                                    Label {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.icon; color: "#29B6F6"; font.pixelSize: ts(2.2)
                                    }
                                    Label {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.label; color: "#90A4AE"; font.pixelSize: ts(1.8)
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (panel.cfg) panel.cfg.lightMode = modelData.key
                                        panel.lightModeApplied()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Estilo de mapa ───────────────────────────────────────────
            Rectangle {
                width: parent.width
                height: styleCol.implicitHeight + units.gu(4)
                color: "#1C1C2E"; radius: units.gu(1)

                Column {
                    id: styleCol
                    anchors { top: parent.top; left: parent.left; right: parent.right
                              margins: units.gu(2); topMargin: units.gu(2) }
                    spacing: units.gu(1)

                    Label { text: i18n.tr("Estilo de mapa"); color: "#90A4AE"; font.pixelSize: ts(1.8) }

                    Flow {
                        width: parent.width
                        spacing: units.gu(1)
                        Repeater {
                            model: panel._mapStyleModes
                            delegate: Rectangle {
                                width:  units.gu(10)
                                height: units.gu(7)
                                radius: units.gu(0.8)
                                color:  panel.cfg && panel.cfg.mapStyleMode === modelData.key ? "#1E3A5F" : "#2A2A3E"
                                border.color: panel.cfg && panel.cfg.mapStyleMode === modelData.key ? "#29B6F6" : "transparent"
                                border.width: units.gu(0.2)
                                Column {
                                    anchors.centerIn: parent; spacing: units.gu(0.3)
                                    Label {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.icon; font.pixelSize: ts(2.2)
                                    }
                                    Label {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.label + (modelData.key === "auto" ? " ↺" : "")
                                        color: "#90A4AE"; font.pixelSize: ts(1.6)
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (panel.cfg) panel.cfg.mapStyleMode = modelData.key
                                        panel.lightModeApplied()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Vehículos ────────────────────────────────────────────────
            Rectangle {
                id: vehiclesSection
                width: parent.width
                color: "#1C1C2E"; radius: units.gu(1)
                height: vehCol.implicitHeight + units.gu(4)

                property bool _addMode: false
                property int  _newTypeIdx: 0
                readonly property var _typeList: [
                    { label: "Coche",     value: "auto"          },
                    { label: "Moto",      value: "motorcycle"    },
                    { label: "Scooter",   value: "motor_scooter" },
                    { label: "Camión",    value: "truck"         },
                    { label: "Bicicleta", value: "bicycle"       }
                ]

                Column {
                    id: vehCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1.2)

                    Row {
                        width: parent.width
                        Label {
                            text: "🚗 " + i18n.tr("Vehículos")
                            font.pixelSize: ts(2.2); font.bold: true; color: "#29B6F6"
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - addVehBtn.width
                        }
                        Rectangle {
                            id: addVehBtn
                            width: units.gu(11); height: units.gu(5); radius: height / 2
                            color: vehiclesSection._addMode ? "#1A3A1A" : "#1E2A3A"
                            border.color: "#4CAF50"; border.width: 1
                            anchors.verticalCenter: parent.verticalCenter
                            Label {
                                anchors.centerIn: parent
                                text: vehiclesSection._addMode ? i18n.tr("Cancelar") : i18n.tr("+ Añadir")
                                color: "#4CAF50"; font.pixelSize: ts(1.9)
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    vehiclesSection._addMode = !vehiclesSection._addMode
                                    vehiclesSection._newTypeIdx = 0
                                }
                            }
                        }
                    }

                    Repeater {
                        model: panel.vehicleMgr.allVehicles()
                        delegate: Rectangle {
                            id: vehDelegate
                            width: parent.width; height: units.gu(6.5)
                            radius: units.gu(0.7)
                            color: modelData.id === panel.cfg.activeVehicleId ? "#1B2B3A" : "#14141F"
                            border.color: modelData.id === panel.cfg.activeVehicleId ? "#29B6F6" : "#37474F"
                            border.width: modelData.id === panel.cfg.activeVehicleId ? 2 : 1
                            property bool _askDel: false

                            Row {
                                anchors {
                                    left: parent.left; right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: units.gu(1.5); rightMargin: units.gu(1)
                                }
                                spacing: units.gu(1)

                                Rectangle {
                                    width: units.gu(1.2); height: units.gu(1.2); radius: width / 2
                                    color: modelData.id === panel.cfg.activeVehicleId ? "#29B6F6" : "transparent"
                                    border.color: "#29B6F6"; border.width: 1
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - units.gu(1.2) - units.gu(1) - delVehBtn.width - units.gu(1)
                                    Label {
                                        text: modelData.alias; color: "#ECEFF1"
                                        font.pixelSize: ts(2.1)
                                        wrapMode: Text.NoWrap; elide: Text.ElideRight; width: parent.width
                                    }
                                    Label {
                                        text: panel.vehicleMgr.costingLabel(modelData.costing)
                                              + (modelData.hasPark && modelData.costing !== "pedestrian" ? "  🅿" : "")
                                        color: "#B0BEC5"; font.pixelSize: ts(2.1)
                                        wrapMode: Text.NoWrap; elide: Text.ElideRight; width: parent.width
                                    }
                                }
                                Item {
                                    id: delVehBtn
                                    visible: modelData.costing !== "pedestrian"
                                             && panel.vehicleMgr.allVehicles().length > 2
                                    width: vehDelegate._askDel ? units.gu(14) : units.gu(7)
                                    height: units.gu(4.5)
                                    anchors.verticalCenter: parent.verticalCenter

                                    Rectangle {
                                        visible: !vehDelegate._askDel
                                        anchors.fill: parent; radius: height / 2
                                        color: "#3A1414"; border.color: "#EF5350"; border.width: 1
                                        Label {
                                            anchors.centerIn: parent; text: i18n.tr("Borrar")
                                            color: "#EF5350"; font.pixelSize: ts(1.7)
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: vehDelegate._askDel = true
                                        }
                                    }
                                    Row {
                                        visible: vehDelegate._askDel
                                        anchors.fill: parent; spacing: units.gu(0.5)
                                        Rectangle {
                                            width: (parent.width - units.gu(0.5)) / 2; height: parent.height
                                            radius: height / 2
                                            color: "#3A1414"; border.color: "#EF5350"; border.width: 1
                                            Label {
                                                anchors.centerIn: parent; text: i18n.tr("Sí")
                                                color: "#EF5350"; font.pixelSize: ts(1.7)
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: {
                                                    vehDelegate._askDel = false
                                                    panel.vehicleMgr.removeVehicle(modelData.id)
                                                }
                                            }
                                        }
                                        Rectangle {
                                            width: (parent.width - units.gu(0.5)) / 2; height: parent.height
                                            radius: height / 2
                                            color: "#1E2A3A"; border.color: "#90A4AE"; border.width: 1
                                            Label {
                                                anchors.centerIn: parent; text: i18n.tr("No")
                                                color: "#90A4AE"; font.pixelSize: ts(1.7)
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: vehDelegate._askDel = false
                                            }
                                        }
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                z: -1
                                onClicked: panel.vehicleMgr.setActive(modelData.id)
                            }
                        }
                    }

                    Column {
                        visible: vehiclesSection._addMode
                        width: parent.width; spacing: units.gu(1)

                        Label { text: i18n.tr("Nombre"); color: "#90A4AE"; font.pixelSize: ts(1.7) }
                        Rectangle {
                            width: parent.width; height: units.gu(5)
                            color: "#252540"; radius: units.gu(0.7)
                            border.color: newVehName.activeFocus ? "#29B6F6" : "#37474F"; border.width: 1
                            TextInput {
                                id: newVehName
                                anchors {
                                    left: parent.left; right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: units.gu(1.2); rightMargin: units.gu(1.2)
                                }
                                text: "Mi vehículo"; color: "#ECEFF1"; font.pixelSize: ts(2.0)
                                selectionColor: "#29B6F6"
                                onActiveFocusChanged: if (activeFocus) panel._kbdFocusItem = this
                            }
                        }
                        Label { text: i18n.tr("Tipo"); color: "#90A4AE"; font.pixelSize: ts(1.7) }
                        Flow {
                            width: parent.width; spacing: units.gu(0.6)
                            Repeater {
                                model: vehiclesSection._typeList
                                Rectangle {
                                    width: (vehCol.width - 2 * units.gu(0.6)) / 3
                                    height: units.gu(5); radius: height / 2
                                    color:  vehiclesSection._newTypeIdx === index ? "#29B6F6" : "#1E2A3A"
                                    border.color: "#29B6F6"; border.width: 1
                                    Label {
                                        anchors.centerIn: parent; text: modelData.label
                                        color: vehiclesSection._newTypeIdx === index ? "#0A0A1A" : "#90A4AE"
                                        font.pixelSize: ts(1.8)
                                        font.bold: vehiclesSection._newTypeIdx === index
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: vehiclesSection._newTypeIdx = index
                                    }
                                }
                            }
                        }
                        Rectangle {
                            width: units.gu(16); height: units.gu(5.5); radius: height / 2; color: "#29B6F6"
                            Label {
                                anchors.centerIn: parent; text: i18n.tr("Crear vehículo")
                                color: "#0A0A1A"; font.pixelSize: ts(2.0); font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    var name = newVehName.text.trim()
                                    if (name.length === 0) return
                                    var id = panel.vehicleMgr.addVehicle(
                                        name,
                                        vehiclesSection._typeList[vehiclesSection._newTypeIdx].value)
                                    panel.vehicleMgr.setActive(id)
                                    vehiclesSection._addMode = false
                                    newVehName.text = "Mi vehículo"
                                }
                            }
                        }
                    }
                }
            }
        } // Column Ajustes rápidos

        // ════════════════════════════════════════════════════════════════
        // GENERAL
        // ════════════════════════════════════════════════════════════════
        Rectangle {
            visible: generalCol.hasContent
            width: parent.width; height: units.gu(5.5)
            color: "#252535"; radius: units.gu(1)
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                text: i18n.tr("General")
                color: "#29B6F6"; font.pixelSize: ts(2.0); font.bold: true
            }
            Label {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: units.gu(2) }
                text: secSettings.general ? "▲" : "▼"
                color: "#29B6F6"; font.pixelSize: ts(1.6)
            }
            MouseArea { anchors.fill: parent; onClicked: secSettings.general = !secSettings.general }
        }

        Column {
            id: generalCol
            property int  _sectionMinLevel: 0
            property bool hasContent: panel.cfg ? panel.cfg.prefLevel >= _sectionMinLevel : false
            visible: secSettings.general && hasContent
            width: parent.width; spacing: units.gu(1.5)

            // ── Tamaño de texto ──────────────────────────────────────────
            Rectangle {
                width: parent.width; height: tsCol.implicitHeight + units.gu(4)
                color: "#1C1C2E"; radius: units.gu(1)
                Column {
                    id: tsCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(0.8)
                    Row {
                        width: parent.width
                        Label { text: i18n.tr("Tamaño de texto"); color: "white"; font.pixelSize: ts(1.8); anchors.verticalCenter: parent.verticalCenter }
                        Item { width: parent.width - textSizeLbl.width - units.gu(16); height: 1 }
                        Label {
                            id: textSizeLbl
                            textFormat: Text.RichText
                            text: panel.cfg ? ("<b>" + Math.round(panel.cfg.textScale * 100) + "%</b> <font color='#546E7A'>↺ 100%</font>") : "100%"
                            color: "#29B6F6"; font.pixelSize: ts(1.7)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Item {
                        id: tsCtrl
                        width: parent.width; height: units.gu(4)
                        property int _dir: 0
                        Timer { interval: 200; repeat: true; running: tsCtrl._dir !== 0
                            onTriggered: if (panel.cfg) panel.cfg.textScale = Math.max(0.7, Math.min(1.5, Math.round((panel.cfg.textScale + 0.05 * tsCtrl._dir) / 0.05) * 0.05))
                        }
                        Rectangle {
                            id: tsMinusBtn
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            width: units.gu(5); height: units.gu(4); radius: units.gu(0.6)
                            color: tsMinus.pressed ? "#1E3A5F" : "#2A2A3E"; border.color: "#37474F"; border.width: 1
                            Label { anchors.centerIn: parent; text: "−"; color: "#29B6F6"; font.pixelSize: ts(2.5); font.bold: true }
                            MouseArea {
                                id: tsMinus; anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.textScale = Math.max(0.7, Math.min(1.5, Math.round((panel.cfg.textScale - 0.05) / 0.05) * 0.05))
                                onPressAndHold: tsCtrl._dir = -1
                                onReleased: tsCtrl._dir = 0
                            }
                        }
                        Rectangle {
                            anchors { left: tsMinusBtn.right; right: tsPlusBtn.left; verticalCenter: parent.verticalCenter; margins: units.gu(1) }
                            height: units.gu(0.5); radius: height / 2; color: "#37474F"
                            Rectangle {
                                width: panel.cfg ? (panel.cfg.textScale - 0.7) / 0.8 * parent.width : 0
                                height: parent.height; radius: parent.radius; color: "#29B6F6"
                            }
                        }
                        Rectangle {
                            id: tsPlusBtn
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: units.gu(5); height: units.gu(4); radius: units.gu(0.6)
                            color: tsPlus.pressed ? "#1E3A5F" : "#2A2A3E"; border.color: "#37474F"; border.width: 1
                            Label { anchors.centerIn: parent; text: "+"; color: "#29B6F6"; font.pixelSize: ts(2.5); font.bold: true }
                            MouseArea {
                                id: tsPlus; anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.textScale = Math.max(0.7, Math.min(1.5, Math.round((panel.cfg.textScale + 0.05) / 0.05) * 0.05))
                                onPressAndHold: tsCtrl._dir = 1
                                onReleased: tsCtrl._dir = 0
                            }
                        }
                    }
                }
            }

            // ── Sistema de unidades ──────────────────────────────────────
            Rectangle {
                width: parent.width
                height: medCol.implicitHeight + units.gu(4)
                color: "#1C1C2E"; radius: units.gu(1)
                Column {
                    id: medCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(0.8)
                    Label { text: i18n.tr("Sistema de medidas"); color: "white"; font.pixelSize: ts(1.8) }
                    Row {
                        spacing: units.gu(1)
                        Repeater {
                            model: [["metric", "km / m"], ["imperial", "mi / ft"]]
                            Rectangle {
                                property bool sel: panel.cfg && panel.cfg.measureSystem === modelData[0]
                                width: ts(8); height: ts(4); radius: units.gu(0.6)
                                color:        sel ? "#1E3A5F" : "#2A2A3E"
                                border.color: sel ? "#29B6F6" : "transparent"; border.width: units.gu(0.15)
                                Label {
                                    anchors.centerIn: parent
                                    text: modelData[1] + (modelData[0] === "metric" ? " ↺" : "")
                                    color: sel ? "#29B6F6" : "#78909C"
                                    font.pixelSize: ts(1.7); font.bold: sel
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: { if (panel.cfg) panel.cfg.measureSystem = modelData[0] }
                                }
                            }
                        }
                    }
                }
            }

            // ── Mostrar novedades al inicio ──────────────────────────────
            Rectangle {
                width: parent.width; height: units.gu(6)
                color: "#1C1C2E"; radius: units.gu(1)

                Row {
                    anchors { fill: parent; margins: units.gu(2) }
                    spacing: units.gu(1.5)

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - toggleNovedades.width - units.gu(1.5)
                        Label { text: i18n.tr("Mostrar novedades al inicio"); color: "white"; font.pixelSize: ts(1.8) }
                        Label { text: i18n.tr("Pantalla de cambios en cada deploy") + "  · ↺ act."; color: "#90A4AE"; font.pixelSize: ts(1.8) }
                    }

                    Rectangle {
                        id: toggleNovedades
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(5.5); height: units.gu(3); radius: height / 2
                        color: panel.cfg && panel.cfg.showChangesAtStartup ? "#29B6F6" : "#37474F"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Rectangle {
                            width: units.gu(2.4); height: units.gu(2.4); radius: width / 2; color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                            x: panel.cfg && panel.cfg.showChangesAtStartup
                               ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                            Behavior on x { NumberAnimation { duration: 120 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: if (panel.cfg) panel.cfg.showChangesAtStartup = !panel.cfg.showChangesAtStartup
                        }
                    }
                }
            }
        } // Column General

        // ════════════════════════════════════════════════════════════════
        // SERVIDOR DE RUTAS
        // ════════════════════════════════════════════════════════════════
        Rectangle {
            visible: srvColContent.hasContent
            width: parent.width; height: units.gu(5.5)
            color: "#252535"; radius: units.gu(1)
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                text: i18n.tr("Servidor de rutas")
                color: "#29B6F6"; font.pixelSize: ts(2.0); font.bold: true
            }
            Label {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: units.gu(2) }
                text: secSettings.servidor ? "▲" : "▼"
                color: "#29B6F6"; font.pixelSize: ts(1.6)
            }
            MouseArea { anchors.fill: parent; onClicked: secSettings.servidor = !secSettings.servidor }
        }

        Column {
            id: srvColContent
            property int  _sectionMinLevel: 0
            property bool hasContent: panel.cfg ? panel.cfg.prefLevel >= _sectionMinLevel : false
            visible: secSettings.servidor && hasContent
            width: parent.width; spacing: units.gu(1.5)

            Rectangle {
                id: vhSection
                width: parent.width
                color: "#1C1C2E"; radius: units.gu(1)
                height: vhCol.implicitHeight + units.gu(4)

                property var _custom: {
                    try { return JSON.parse(panel.cfg ? panel.cfg.valhallaCustomServers : "[]") }
                    catch(e) { return [] }
                }
                property bool _showForm: false

                function _setUrl(url) { if (panel.cfg) panel.cfg.valhallaUrl = url }
                function _saveCustom(lst) {
                    if (!panel.cfg) return
                    panel.cfg.valhallaCustomServers = JSON.stringify(lst)
                }

                Column {
                    id: vhCol
                    anchors { left: parent.left; right: parent.right; margins: units.gu(2) }
                    y: units.gu(2)
                    spacing: units.gu(1.2)

                    Label { text: i18n.tr("Servidor de rutas"); color: "#90A4AE"; font.pixelSize: ts(1.8) }

                    // Toggle: preferir OSM Scout
                    Row {
                        width: parent.width; spacing: units.gu(1.5)
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - units.gu(7)
                            Label { text: i18n.tr("Preferir OSM Scout Server si disponible"); color: "white"; font.pixelSize: ts(1.8); wrapMode: Text.WordWrap; width: parent.width }
                            Label { text: i18n.tr("Enrutamiento offline · se detecta al arrancar") + "  · ↺ act."; color: "#90A4AE"; font.pixelSize: ts(1.6); wrapMode: Text.WordWrap; width: parent.width }
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: units.gu(5.5); height: units.gu(3); radius: height / 2
                            color: panel.cfg && panel.cfg.preferOsmScout ? "#1565C0" : "#37474F"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Rectangle {
                                width: units.gu(2.4); height: units.gu(2.4); radius: width / 2; color: "white"
                                anchors.verticalCenter: parent.verticalCenter
                                x: panel.cfg && panel.cfg.preferOsmScout ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                                Behavior on x { NumberAnimation { duration: 150 } }
                            }
                            MouseArea { anchors.fill: parent; onClicked: if (panel.cfg) panel.cfg.preferOsmScout = !panel.cfg.preferOsmScout }
                        }
                    }

                    // OSM Scout Server (dispositivo)
                    Rectangle {
                        width: parent.width; height: units.gu(5.5); radius: units.gu(0.8)
                        color: panel.cfg && panel.cfg.valhallaUrl === "http://127.0.0.1:8553/v2" ? "#1A3A6A" : "#2A2A3E"
                        Row {
                            anchors { fill: parent; leftMargin: units.gu(1.5); rightMargin: units.gu(1.5) }
                            spacing: units.gu(1)
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - units.gu(10)
                                Label { text: "OSM Scout Server (dispositivo)"; color: "white"; font.pixelSize: ts(1.8); font.bold: true }
                                Label {
                                    text: panel.osmScoutActive ? "✓ activo · puerto 8553 · offline" : "✗ no detectado · puerto 8553"
                                    color: panel.osmScoutActive ? "#66BB6A" : "#EF5350"
                                    font.pixelSize: ts(1.5)
                                }
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: units.gu(8.5); height: units.gu(3.5); radius: units.gu(0.8); color: "#263238"
                                Label { anchors.centerIn: parent; text: i18n.tr("Detectar"); color: "#29B6F6"; font.pixelSize: ts(1.6) }
                                MouseArea { anchors.fill: parent; onClicked: panel.osmScoutDetectRequested() }
                            }
                        }
                        MouseArea {
                            anchors { fill: parent; rightMargin: units.gu(10) }
                            onClicked: vhSection._setUrl("http://127.0.0.1:8553/v2")
                        }
                    }

                    // valhalla.egpsistemas.com (servidor principal)
                    Rectangle {
                        width: parent.width; height: units.gu(5.5); radius: units.gu(0.8)
                        color: panel.cfg && panel.cfg.valhallaUrl === "https://valhalla.egpsistemas.com" ? "#1A3A6A" : "#2A2A3E"
                        Row {
                            anchors { fill: parent; leftMargin: units.gu(1.5); rightMargin: units.gu(1.5) }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter; width: parent.width
                                Label { text: i18n.tr("Servidor Navius"); color: "white"; font.pixelSize: ts(1.8); font.bold: true }
                                Label { text: "https://valhalla.egpsistemas.com · servidor propio"; color: "#90A4AE"; font.pixelSize: ts(1.5) }
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: vhSection._setUrl("https://valhalla.egpsistemas.com") }
                    }

                    // OpenStreetMap.de
                    Rectangle {
                        width: parent.width; height: units.gu(5.5); radius: units.gu(0.8)
                        color: panel.cfg && panel.cfg.valhallaUrl === "https://valhalla1.openstreetmap.de" ? "#1A3A6A" : "#2A2A3E"
                        Row {
                            anchors { fill: parent; leftMargin: units.gu(1.5); rightMargin: units.gu(1.5) }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter; width: parent.width
                                Label { text: "OpenStreetMap.de"; color: "white"; font.pixelSize: ts(1.8); font.bold: true }
                                Label { text: "https://valhalla1.openstreetmap.de · gratuito online"; color: "#90A4AE"; font.pixelSize: ts(1.5) }
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: vhSection._setUrl("https://valhalla1.openstreetmap.de") }
                    }

                    // Servidores personalizados
                    Repeater {
                        model: vhSection._custom
                        Rectangle {
                            width: vhCol.width; height: units.gu(5.5); radius: units.gu(0.8)
                            color: panel.cfg && panel.cfg.valhallaUrl === modelData.url ? "#1A3A6A" : "#2A2A3E"
                            Row {
                                anchors { fill: parent; leftMargin: units.gu(1.5); rightMargin: units.gu(1.5) }
                                spacing: units.gu(1)
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - units.gu(5)
                                    Label { text: modelData.label; color: "white"; font.pixelSize: ts(1.8); font.bold: true; elide: Text.ElideRight; width: parent.width }
                                    Label { text: modelData.url;   color: "#90A4AE"; font.pixelSize: ts(1.5); elide: Text.ElideRight; width: parent.width }
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(3.5); height: units.gu(3.5); radius: width / 2; color: "#37474F"
                                    Label { anchors.centerIn: parent; text: "✕"; color: "#EF5350"; font.pixelSize: ts(1.8) }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            var lst = vhSection._custom.slice()
                                            var delUrl = lst[index].url
                                            lst.splice(index, 1)
                                            vhSection._saveCustom(lst)
                                            if (panel.cfg && panel.cfg.valhallaUrl === delUrl)
                                                vhSection._setUrl("https://valhalla1.openstreetmap.de")
                                        }
                                    }
                                }
                            }
                            MouseArea {
                                anchors { fill: parent; rightMargin: units.gu(5) }
                                onClicked: vhSection._setUrl(modelData.url)
                            }
                        }
                    }

                    // Botón añadir servidor
                    Rectangle {
                        visible: !vhSection._showForm
                        width: parent.width; height: units.gu(4.5); radius: units.gu(0.8); color: "#2A2A3E"
                        Label { anchors.centerIn: parent; text: "+ " + i18n.tr("Añadir servidor"); color: "#29B6F6"; font.pixelSize: ts(1.8) }
                        MouseArea { anchors.fill: parent; onClicked: vhSection._showForm = true }
                    }

                    // Formulario añadir servidor
                    Column {
                        visible: vhSection._showForm
                        width: parent.width; spacing: units.gu(1)

                        Rectangle {
                            width: parent.width; height: units.gu(5); radius: units.gu(0.8); color: "#2A2A3E"
                            Label {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: units.gu(1.5) }
                                text: i18n.tr("Nombre (ej. Mi servidor)"); color: "#90A4AE"; font.pixelSize: ts(1.8)
                                visible: vhLabelIn.text.length === 0
                            }
                            TextInput {
                                id: vhLabelIn
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: units.gu(1.5) }
                                color: "white"; font.pixelSize: ts(1.8); selectionColor: "#29B6F6"
                                onActiveFocusChanged: if (activeFocus) panel._kbdFocusItem = this
                            }
                        }

                        Rectangle {
                            width: parent.width; height: units.gu(5); radius: units.gu(0.8); color: "#2A2A3E"
                            Label {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: units.gu(1.5) }
                                text: "https://mi-valhalla.local"; color: "#90A4AE"; font.pixelSize: ts(1.8)
                                visible: vhUrlIn.text.length === 0
                            }
                            TextInput {
                                id: vhUrlIn
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: units.gu(1.5) }
                                color: "white"; font.pixelSize: ts(1.8); selectionColor: "#29B6F6"
                                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                                onActiveFocusChanged: if (activeFocus) panel._kbdFocusItem = this
                            }
                        }

                        Row {
                            width: parent.width; spacing: units.gu(1)
                            Rectangle {
                                width: (parent.width - units.gu(1)) / 2; height: units.gu(4.5)
                                color: "#37474F"; radius: units.gu(0.8)
                                Label { anchors.centerIn: parent; text: i18n.tr("Cancelar"); color: "#90A4AE"; font.pixelSize: ts(1.8) }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: { vhSection._showForm = false; vhLabelIn.text = ""; vhUrlIn.text = "" }
                                }
                            }
                            Rectangle {
                                width: (parent.width - units.gu(1)) / 2; height: units.gu(4.5)
                                color: vhUrlIn.text.trim().length > 7 ? "#1565C0" : "#263238"
                                radius: units.gu(0.8)
                                Label { anchors.centerIn: parent; text: i18n.tr("Guardar"); color: "white"; font.pixelSize: ts(1.8); font.bold: true }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        var url = vhUrlIn.text.trim()
                                        if (url.length < 8) return
                                        if (url[url.length - 1] === "/") url = url.slice(0, -1)
                                        var lbl = vhLabelIn.text.trim() || url
                                        var lst = vhSection._custom.slice()
                                        lst.push({ label: lbl, url: url })
                                        vhSection._saveCustom(lst)
                                        vhSection._setUrl(url)
                                        vhSection._showForm = false
                                        vhLabelIn.text = ""; vhUrlIn.text = ""
                                    }
                                }
                            }
                        }
                    }
                }
            }
            // ── Tiles de mapa ─────────────────────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.prefLevel >= 1
                width: parent.width
                color: "#1C1C2E"; radius: units.gu(1)
                height: mapTilesCol.implicitHeight + units.gu(4)

                Column {
                    id: mapTilesCol
                    anchors { left: parent.left; right: parent.right; margins: units.gu(2) }
                    y: units.gu(2)
                    spacing: units.gu(1.5)

                    // ── Mapa online ───────────────────────────────────────
                    Label { text: i18n.tr("Mapa online"); color: "#90A4AE"; font.pixelSize: ts(1.8) }

                    Row {
                        width: parent.width; spacing: units.gu(1)
                        property string _src: panel.cfg ? panel.cfg.mapOnlineSource : "mapbox"

                        Rectangle {
                            property bool _sel: parent._src === "mapbox"
                            width: (parent.width - units.gu(1)) / 2; height: units.gu(4.5)
                            radius: units.gu(0.8)
                            color: _sel ? "#1E3A5F" : "#2A2A3E"
                            border.color: _sel ? "#29B6F6" : "#37474F"; border.width: units.gu(0.15)
                            Label {
                                anchors.centerIn: parent
                                text: "Mapbox ↺"
                                color: parent._sel ? "#29B6F6" : "white"
                                font.pixelSize: ts(1.7); font.bold: parent._sel
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.mapOnlineSource = "mapbox"
                            }
                        }

                        Rectangle {
                            property bool _sel: parent._src === "osmscout"
                            property bool _avail: panel.osmScoutActive
                            width: (parent.width - units.gu(1)) / 2; height: units.gu(4.5)
                            radius: units.gu(0.8)
                            color: _sel ? "#1A3A1A" : "#2A2A3E"
                            border.color: _sel ? "#66BB6A" : "#37474F"; border.width: units.gu(0.15)
                            opacity: _avail ? 1.0 : 0.45
                            Label {
                                anchors.centerIn: parent
                                text: "OSM Scout"
                                color: parent._sel ? "#66BB6A" : "white"
                                font.pixelSize: ts(1.7); font.bold: parent._sel
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: parent._avail
                                onClicked: if (panel.cfg) panel.cfg.mapOnlineSource = "osmscout"
                            }
                        }
                    }

                    // ── Servidor de tiles ─────────────────────────────────
                    Label {
                        text: i18n.tr("Servidor de tiles")
                        color: "#90A4AE"; font.pixelSize: ts(1.8)
                        visible: panel.cfg && panel.cfg.mapOnlineSource === "mapbox"
                    }

                    Row {
                        visible: panel.cfg && panel.cfg.mapOnlineSource === "mapbox"
                        width: parent.width; spacing: units.gu(1)
                        property string _srv: panel.cfg ? panel.cfg.mapTileServer : "external"

                        Rectangle {
                            property bool _sel: parent._srv === "navius"
                            width: (parent.width - units.gu(1)) / 2; height: units.gu(4.5)
                            radius: units.gu(0.8)
                            color: _sel ? "#1A3A2A" : "#2A2A3E"
                            border.color: _sel ? "#66BB6A" : "#37474F"; border.width: units.gu(0.15)
                            Column {
                                anchors.centerIn: parent; spacing: units.gu(0.2)
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Navius ↺"
                                    color: parent.parent._sel ? "#66BB6A" : "white"
                                    font.pixelSize: ts(1.7); font.bold: parent.parent._sel
                                }
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "navius-maps"
                                    color: "#607D8B"; font.pixelSize: ts(1.3)
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.mapTileServer = "navius"
                            }
                        }

                        Rectangle {
                            property bool _sel: parent._srv === "external"
                            width: (parent.width - units.gu(1)) / 2; height: units.gu(4.5)
                            radius: units.gu(0.8)
                            color: _sel ? "#1E3A5F" : "#2A2A3E"
                            border.color: _sel ? "#29B6F6" : "#37474F"; border.width: units.gu(0.15)
                            Column {
                                anchors.centerIn: parent; spacing: units.gu(0.2)
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: i18n.tr("Externo")
                                    color: parent.parent._sel ? "#29B6F6" : "white"
                                    font.pixelSize: ts(1.7); font.bold: parent.parent._sel
                                }
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "OpenFreeMap"
                                    color: "#607D8B"; font.pixelSize: ts(1.3)
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.mapTileServer = "external"
                            }
                        }
                    }

                    // ── Estilo día (solo servidor Navius) ─────────────────
                    Label {
                        text: i18n.tr("Tema de día")
                        color: "#90A4AE"; font.pixelSize: ts(1.8)
                        visible: panel.cfg && panel.cfg.mapOnlineSource === "mapbox"
                                           && panel.cfg.mapTileServer === "navius"
                    }

                    Flickable {
                        visible: panel.cfg && panel.cfg.mapOnlineSource === "mapbox"
                                           && panel.cfg.mapTileServer === "navius"
                        width: parent.width; height: units.gu(4.5)
                        contentWidth: mapStyleRow.implicitWidth
                        flickableDirection: Flickable.HorizontalFlick; clip: true

                        Row {
                            id: mapStyleRow
                            spacing: units.gu(0.8)
                            property var _styles: [
                                { id: "liberty",  label: "Liberty",  desc: "día"    },
                                { id: "positron", label: "Positron", desc: "claro"  },
                                { id: "bright",   label: "Bright",   desc: "vivo"   },
                                { id: "fiord",    label: "Fiord",    desc: "azul"   }
                            ]
                            Repeater {
                                model: parent._styles
                                delegate: Rectangle {
                                    property bool _sel: panel.cfg && panel.cfg.mapNaviusDayStyle === modelData.id
                                    height: units.gu(4.5); width: units.gu(9); radius: height / 2
                                    color: _sel ? "#1A3A2A" : "#2A2A3E"
                                    border.color: _sel ? "#66BB6A" : "#37474F"; border.width: units.gu(0.15)
                                    Column {
                                        anchors.centerIn: parent; spacing: units.gu(0.1)
                                        Label {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.label
                                            color: parent.parent._sel ? "#66BB6A" : "white"
                                            font.pixelSize: ts(1.6); font.bold: parent.parent._sel
                                        }
                                        Label {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.desc
                                            color: "#607D8B"; font.pixelSize: ts(1.3)
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: if (panel.cfg) panel.cfg.mapNaviusDayStyle = modelData.id
                                    }
                                }
                            }
                        }
                    }

                    // ── Servidor de POIs y radares (Overpass) ────────────
                    Label {
                        text: i18n.tr("Servidor de POIs y radares")
                        color: "#90A4AE"; font.pixelSize: ts(1.8)
                        visible: panel.cfg && panel.cfg.mapOnlineSource === "mapbox"
                    }

                    Row {
                        visible: panel.cfg && panel.cfg.mapOnlineSource === "mapbox"
                        width: parent.width; spacing: units.gu(1)
                        property string _srv: panel.cfg ? panel.cfg.overpassServer : "external"

                        Rectangle {
                            property bool _sel: parent._srv === "navius"
                            width: (parent.width - units.gu(1)) / 2; height: units.gu(4.5)
                            radius: units.gu(0.8)
                            color: _sel ? "#1A3A2A" : "#2A2A3E"
                            border.color: _sel ? "#66BB6A" : "#37474F"; border.width: units.gu(0.15)
                            Column {
                                anchors.centerIn: parent; spacing: units.gu(0.2)
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Navius"
                                    color: parent.parent._sel ? "#66BB6A" : "white"
                                    font.pixelSize: ts(1.7); font.bold: parent.parent._sel
                                }
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "navius-maps"
                                    color: "#607D8B"; font.pixelSize: ts(1.3)
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.overpassServer = "navius"
                            }
                        }

                        Rectangle {
                            property bool _sel: parent._srv === "external"
                            width: (parent.width - units.gu(1)) / 2; height: units.gu(4.5)
                            radius: units.gu(0.8)
                            color: _sel ? "#1E3A5F" : "#2A2A3E"
                            border.color: _sel ? "#29B6F6" : "#37474F"; border.width: units.gu(0.15)
                            Column {
                                anchors.centerIn: parent; spacing: units.gu(0.2)
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: i18n.tr("Externo") + " ↺"
                                    color: parent.parent._sel ? "#29B6F6" : "white"
                                    font.pixelSize: ts(1.7); font.bold: parent.parent._sel
                                }
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "openstreetmap.fr"
                                    color: "#607D8B"; font.pixelSize: ts(1.3)
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.overpassServer = "external"
                            }
                        }
                    }

                    // ── Sin internet ──────────────────────────────────────
                    Label {
                        text: i18n.tr("Sin internet")
                        color: "#90A4AE"; font.pixelSize: ts(1.8)
                        // solo relevante cuando online source es Mapbox
                        visible: panel.cfg && panel.cfg.mapOnlineSource === "mapbox"
                    }

                    Row {
                        width: parent.width; spacing: units.gu(1)
                        visible: panel.cfg && panel.cfg.mapOnlineSource === "mapbox"
                        property string _mode: panel.cfg ? panel.cfg.mapOfflineMode : "cache"

                        Rectangle {
                            property bool _sel: parent._mode === "cache"
                            width: (parent.width - units.gu(1)) / 2; height: units.gu(4.5)
                            radius: units.gu(0.8)
                            color: _sel ? "#1E3A5F" : "#2A2A3E"
                            border.color: _sel ? "#29B6F6" : "#37474F"; border.width: units.gu(0.15)
                            Label {
                                anchors.centerIn: parent
                                text: i18n.tr("Caché") + " ↺"
                                color: parent._sel ? "#29B6F6" : "white"
                                font.pixelSize: ts(1.7); font.bold: parent._sel
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.mapOfflineMode = "cache"
                            }
                        }

                        Rectangle {
                            property bool _sel: parent._mode === "osmscout"
                            property bool _avail: panel.osmScoutActive
                            width: (parent.width - units.gu(1)) / 2; height: units.gu(4.5)
                            radius: units.gu(0.8)
                            color: _sel ? "#1A3A1A" : "#2A2A3E"
                            border.color: _sel ? "#66BB6A" : "#37474F"; border.width: units.gu(0.15)
                            opacity: _avail ? 1.0 : 0.45
                            Label {
                                anchors.centerIn: parent
                                text: "OSM Scout"
                                color: parent._sel ? "#66BB6A" : "white"
                                font.pixelSize: ts(1.7); font.bold: parent._sel
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: parent._avail
                                onClicked: if (panel.cfg) panel.cfg.mapOfflineMode = "osmscout"
                            }
                        }
                    }

                    // ── Caché: tamaño + limpiar ───────────────────────────
                    Column {
                        // visible cuando se usa caché (Mapbox online o fallback caché sin internet)
                        visible: panel.cfg && (panel.cfg.mapOnlineSource === "mapbox")
                        width: parent.width; spacing: units.gu(1)

                        Label {
                            text: i18n.tr("Espacio máximo en disco")
                            color: "white"; font.pixelSize: ts(1.8)
                        }

                        Flickable {
                            width: parent.width; height: units.gu(4)
                            contentWidth: cacheMbRow.implicitWidth
                            flickableDirection: Flickable.HorizontalFlick; clip: true
                            Row {
                                id: cacheMbRow
                                spacing: units.gu(0.8)
                                Repeater {
                                    model: [100, 250, 500, 1000, 2000]
                                    delegate: Rectangle {
                                        property bool _sel: panel.cfg && panel.cfg.mapCacheMaxMb === modelData
                                        height: units.gu(4); width: modelData === 500 ? units.gu(9.5) : units.gu(7.5); radius: height / 2
                                        color: _sel ? "#1E3A5F" : "#2A2A3E"
                                        border.color: _sel ? "#29B6F6" : "#37474F"; border.width: units.gu(0.15)
                                        Label {
                                            anchors.centerIn: parent
                                            text: (modelData >= 1000 ? (modelData / 1000) + " GB" : modelData + " MB") + (modelData === 500 ? " ↺" : "")
                                            color: _sel ? "#29B6F6" : "#90A4AE"
                                            font.pixelSize: ts(1.6); font.bold: _sel
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: if (panel.cfg) panel.cfg.mapCacheMaxMb = modelData
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: mapCacheBtn
                            width: parent.width; height: units.gu(4.5); radius: units.gu(0.8)
                            color: _confirm ? "#4A1010" : "#2A2A3E"
                            property bool _confirm: false
                            property bool _done: false
                            Timer { interval: 4000; running: parent._confirm && !parent._done; onTriggered: parent._confirm = false }
                            Timer { interval: 2500; running: parent._done; onTriggered: parent._done = false }
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Label {
                                anchors.centerIn: parent
                                text:  mapCacheBtn._done    ? "✓ " + i18n.tr("Caché eliminada")
                                     : mapCacheBtn._confirm ? "⚠ " + i18n.tr("Toca de nuevo para confirmar")
                                     :                        i18n.tr("Limpiar caché de mapas")
                                color: mapCacheBtn._done    ? "#66BB6A"
                                     : mapCacheBtn._confirm ? "#FFCC02"
                                     :                       "#EF5350"
                                font.pixelSize: ts(1.8)
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (mapCacheBtn._confirm) { panel.mapCacheClearRequested(); mapCacheBtn._done = true; mapCacheBtn._confirm = false }
                                    else { mapCacheBtn._confirm = true }
                                }
                            }
                        }

                        Rectangle {
                            id: gmapsCacheBtn
                            width: parent.width; height: units.gu(4.5); radius: units.gu(0.8)
                            color: _confirm ? "#4A1010" : "#2A2A3E"
                            property bool _confirm: false
                            property bool _done: false
                            Timer { interval: 4000; running: parent._confirm && !parent._done; onTriggered: parent._confirm = false }
                            Timer { interval: 2500; running: parent._done; onTriggered: parent._done = false }
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Label {
                                anchors.centerIn: parent
                                text:  gmapsCacheBtn._done    ? "✓ " + i18n.tr("Caché eliminada")
                                     : gmapsCacheBtn._confirm ? "⚠ " + i18n.tr("Toca de nuevo para confirmar")
                                     :                          i18n.tr("Limpiar caché Google Maps")
                                color: gmapsCacheBtn._done    ? "#66BB6A"
                                     : gmapsCacheBtn._confirm ? "#FFCC02"
                                     :                         "#EF5350"
                                font.pixelSize: ts(1.8)
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (gmapsCacheBtn._confirm) { panel.googleMapsCacheClearRequested(); gmapsCacheBtn._done = true; gmapsCacheBtn._confirm = false }
                                    else { gmapsCacheBtn._confirm = true }
                                }
                            }
                        }
                    }
                }
            }
        } // Column Servidor de rutas

        // ════════════════════════════════════════════════════════════════
        // NAVEGACIÓN
        // ════════════════════════════════════════════════════════════════
        Rectangle {
            visible: navCol.hasContent
            width: parent.width; height: units.gu(5.5)
            color: "#252535"; radius: units.gu(1)
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                text: i18n.tr("Navegación")
                color: "#29B6F6"; font.pixelSize: ts(2.0); font.bold: true
            }
            Label {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: units.gu(2) }
                text: secSettings.nav ? "▲" : "▼"
                color: "#29B6F6"; font.pixelSize: ts(1.6)
            }
            MouseArea { anchors.fill: parent; onClicked: secSettings.nav = !secSettings.nav }
        }

        Column {
            id: navCol
            property int  _sectionMinLevel: 0
            property bool hasContent: panel.cfg ? panel.cfg.prefLevel >= _sectionMinLevel : false
            visible: secSettings.nav && hasContent
            width: parent.width; spacing: units.gu(1.5)

            // ── Sonido de alertas ────────────────────────────────────────
            Rectangle {
                width: parent.width; height: units.gu(11)
                color: "#1C1C2E"; radius: units.gu(1)
                Column {
                    anchors { fill: parent; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Label { text: i18n.tr("Sonido de alertas"); color: "white"; font.pixelSize: ts(1.8) }
                    Row {
                        spacing: units.gu(1)
                        Repeater {
                            model: [
                                { key: "tts",  label: i18n.tr("Voz")    },
                                { key: "beep", label: i18n.tr("Pitido") },
                                { key: "off",  label: i18n.tr("No")     }
                            ]
                            delegate: Rectangle {
                                property string k: modelData.key
                                width: (parent.parent.width - units.gu(2)) / 3
                                height: units.gu(4.5); radius: units.gu(0.6)
                                color:        panel.cfg && panel.cfg.alertSound === k ? "#1E3A5F" : "#2A2A3E"
                                border.color: panel.cfg && panel.cfg.alertSound === k ? "#29B6F6" : "transparent"
                                border.width: units.gu(0.15)
                                Label {
                                    anchors.centerIn: parent
                                    text: modelData.label + (modelData.key === "tts" ? " ↺" : "")
                                    color: panel.cfg && panel.cfg.alertSound === k ? "#29B6F6" : "#78909C"
                                    font.pixelSize: ts(1.8)
                                    font.bold: panel.cfg && panel.cfg.alertSound === k
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (!panel.cfg) return
                                        panel.cfg.alertSound = k
                                        if (k !== "off") panel.soundTest(k, "alertas")
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Sonido de indicaciones ───────────────────────────────────
            Rectangle {
                width: parent.width; height: units.gu(11)
                color: "#1C1C2E"; radius: units.gu(1)
                Column {
                    anchors { fill: parent; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Label { text: i18n.tr("Sonido de indicaciones"); color: "white"; font.pixelSize: ts(1.8) }
                    Row {
                        spacing: units.gu(1)
                        Repeater {
                            model: [
                                { key: "tts",  label: i18n.tr("Voz")    },
                                { key: "beep", label: i18n.tr("Pitido") },
                                { key: "off",  label: i18n.tr("No")     }
                            ]
                            delegate: Rectangle {
                                property string k: modelData.key
                                width: (parent.parent.width - units.gu(2)) / 3
                                height: units.gu(4.5); radius: units.gu(0.6)
                                color:        panel.cfg && panel.cfg.instrSound === k ? "#1E3A5F" : "#2A2A3E"
                                border.color: panel.cfg && panel.cfg.instrSound === k ? "#29B6F6" : "transparent"
                                border.width: units.gu(0.15)
                                Label {
                                    anchors.centerIn: parent
                                    text: modelData.label + (modelData.key === "tts" ? " ↺" : "")
                                    color: panel.cfg && panel.cfg.instrSound === k ? "#29B6F6" : "#78909C"
                                    font.pixelSize: ts(1.8)
                                    font.bold: panel.cfg && panel.cfg.instrSound === k
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (!panel.cfg) return
                                        panel.cfg.instrSound = k
                                        if (k !== "off") panel.soundTest(k, "indicaciones")
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Radares fijos ────────────────────────────────────────────
            Rectangle {
                width: parent.width; height: units.gu(8)
                color: "#1C1C2E"; radius: units.gu(1)
                Row {
                    anchors { fill: parent; margins: units.gu(2) }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(7)
                        Label { text: i18n.tr("Radares fijos"); color: "white"; font.pixelSize: ts(1.8) }
                        Label {
                            text: i18n.tr("Iconos y alertas de radares de velocidad fijos") + "  · ↺ act."
                            color: "#90A4AE"; font.pixelSize: ts(1.8)
                            wrapMode: Text.WordWrap; width: parent.width
                        }
                    }
                    Item { width: units.gu(1); height: 1 }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(5.5); height: units.gu(3); radius: height / 2
                        color: panel.cfg && panel.cfg.showRadarFijos ? "#E53935" : "#37474F"
                        Rectangle {
                            width: units.gu(2.4); height: units.gu(2.4); radius: width / 2; color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                            x: panel.cfg && panel.cfg.showRadarFijos ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        MouseArea { anchors.fill: parent; onClicked: if (panel.cfg) panel.cfg.showRadarFijos = !panel.cfg.showRadarFijos }
                    }
                }
            }

            // ── Radares de tramo ─────────────────────────────────────────
            Rectangle {
                width: parent.width; height: units.gu(8)
                color: "#1C1C2E"; radius: units.gu(1)
                Row {
                    anchors { fill: parent; margins: units.gu(2) }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(7)
                        Label { text: i18n.tr("Radares de tramo"); color: "white"; font.pixelSize: ts(1.8) }
                        Label {
                            text: i18n.tr("Zonas de control de velocidad media + barra de progreso") + "  · ↺ act."
                            color: "#90A4AE"; font.pixelSize: ts(1.8)
                            wrapMode: Text.WordWrap; width: parent.width
                        }
                    }
                    Item { width: units.gu(1); height: 1 }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(5.5); height: units.gu(3); radius: height / 2
                        color: panel.cfg && panel.cfg.showRadarTramo ? "#FF6F00" : "#37474F"
                        Rectangle {
                            width: units.gu(2.4); height: units.gu(2.4); radius: width / 2; color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                            x: panel.cfg && panel.cfg.showRadarTramo ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        MouseArea { anchors.fill: parent; onClicked: if (panel.cfg) panel.cfg.showRadarTramo = !panel.cfg.showRadarTramo }
                    }
                }
            }

            // ── Aviso de exceso de velocidad ─────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.prefLevel >= 2
                width: parent.width; height: units.gu(8)
                color: "#1C1C2E"; radius: units.gu(1)
                Row {
                    anchors { fill: parent; margins: units.gu(2) }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(7)
                        Label { text: i18n.tr("Aviso de exceso de velocidad"); color: "white"; font.pixelSize: ts(1.8) }
                        Label {
                            text: i18n.tr("Parpadeo al superar el límite") + "  · ↺ act."
                            color: "#90A4AE"; font.pixelSize: ts(1.8)
                            wrapMode: Text.WordWrap; width: parent.width
                        }
                    }
                    Item { width: units.gu(1); height: 1 }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(5.5); height: units.gu(3); radius: height / 2
                        color: panel.cfg && panel.cfg.speedAlertEnabled ? "#29B6F6" : "#37474F"
                        Rectangle {
                            width: units.gu(2.4); height: units.gu(2.4); radius: width / 2; color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                            x: panel.cfg && panel.cfg.speedAlertEnabled ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        MouseArea { anchors.fill: parent; onClicked: if (panel.cfg) panel.cfg.speedAlertEnabled = !panel.cfg.speedAlertEnabled }
                    }
                }
            }

            // ── Margen exceso de velocidad ───────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.prefLevel >= 2
                width: parent.width
                height: marginSpeedCol.implicitHeight + units.gu(4)
                color: "#1C1C2E"; radius: units.gu(1)
                Column {
                    id: marginSpeedCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Label { text: i18n.tr("Margen exceso de velocidad"); color: "white"; font.pixelSize: ts(1.8) }
                    Grid {
                        columns: 3; spacing: units.gu(1); width: parent.width
                        Repeater {
                            model: [1, 2, 5, 10, 15, 20]
                            Rectangle {
                                property int pct: modelData
                                property bool sel: panel.cfg && panel.cfg.speedAlertEnabled && panel.cfg.speedAlertPct === pct
                                width: (parent.width - 2 * units.gu(1)) / 3
                                height: units.gu(4.5); radius: units.gu(0.6)
                                color:        sel ? "#1E3A5F" : "#2A2A3E"
                                border.color: sel ? "#29B6F6" : "transparent"
                                border.width: units.gu(0.15)
                                Label {
                                    anchors.centerIn: parent
                                    text: "+" + pct + "%" + (pct === 2 ? " ↺" : "")
                                    color: sel ? "#29B6F6" : "#78909C"
                                    font.pixelSize: ts(1.8); font.bold: sel
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (!panel.cfg) return
                                        panel.cfg.speedAlertPct     = pct
                                        panel.cfg.speedAlertEnabled = true
                                    }
                                }
                            }
                        }
                    }
                    Rectangle {
                        property bool sel: panel.cfg && panel.cfg.speedAlertEnabled && panel.cfg.speedAlertPct === 0
                        width: parent.width; height: units.gu(4.5); radius: units.gu(0.6)
                        color:        sel ? "#1E3A5F" : "#2A2A3E"
                        border.color: sel ? "#29B6F6" : "transparent"
                        border.width: units.gu(0.15)
                        Label {
                            anchors.centerIn: parent; text: i18n.tr("Sin Margen")
                            color: parent.sel ? "#29B6F6" : "#78909C"
                            font.pixelSize: ts(1.8); font.bold: parent.sel
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (!panel.cfg) return
                                panel.cfg.speedAlertPct     = 0
                                panel.cfg.speedAlertEnabled = true
                            }
                        }
                    }
                }
            }

            // ── Zoom automático ──────────────────────────────────────────
            Rectangle {
                width: parent.width; height: units.gu(8)
                color: "#1C1C2E"; radius: units.gu(1)
                Row {
                    anchors { fill: parent; margins: units.gu(2) }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(7)
                        Label { text: i18n.tr("Zoom automático"); color: "white"; font.pixelSize: ts(1.8) }
                        Label {
                            text: i18n.tr("Ajusta el zoom según la velocidad") + "  · ↺ act."
                            color: "#90A4AE"; font.pixelSize: ts(1.8)
                            wrapMode: Text.WordWrap; width: parent.width
                        }
                    }
                    Item { width: units.gu(1); height: 1 }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(5.5); height: units.gu(3); radius: height / 2
                        color: panel.cfg && panel.cfg.autoZoom ? "#29B6F6" : "#37474F"
                        Rectangle {
                            width: units.gu(2.4); height: units.gu(2.4); radius: width / 2; color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                            x: panel.cfg && panel.cfg.autoZoom ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        MouseArea { anchors.fill: parent; onClicked: if (panel.cfg) panel.cfg.autoZoom = !panel.cfg.autoZoom }
                    }
                }
            }

            // ── Anticipación zoom automático ─────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.prefLevel >= 1
                width: parent.width; height: azCol.implicitHeight + units.gu(4)
                color: "#1C1C2E"; radius: units.gu(1)
                Column {
                    id: azCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Row {
                        width: parent.width
                        Label {
                            text: i18n.tr("Anticipación zoom automático")
                            color: "white"; font.pixelSize: ts(1.8)
                            width: parent.width - horizLabel.width
                        }
                        Label {
                            id: horizLabel
                            textFormat: Text.RichText
                            text: panel.cfg ? ("<b>" + panel.cfg.autoZoomSecs + " s</b> <font color='#546E7A'>↺ 15 s</font>") : ""
                            color: "#29B6F6"; font.pixelSize: ts(1.8)
                        }
                    }
                    Label {
                        text: i18n.tr("Ajuste de zoom automático para que se vea al menos la distancia a recorrer en este tiempo")
                        color: "#90A4AE"; font.pixelSize: ts(1.6)
                        wrapMode: Text.WordWrap; width: parent.width
                    }
                    Item {
                        id: azCtrl
                        width: parent.width; height: units.gu(4)
                        property int _dir: 0; property int _step: 1
                        Timer { interval: 180; repeat: true; running: azCtrl._dir !== 0
                            onTriggered: if (panel.cfg) panel.cfg.autoZoomSecs = Math.max(5, Math.min(60, panel.cfg.autoZoomSecs + azCtrl._step * azCtrl._dir))
                        }
                        Rectangle {
                            id: azM5Btn
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            width: units.gu(5); height: units.gu(4); radius: units.gu(0.6)
                            color: azM5.pressed ? "#1E3A5F" : "#2A2A3E"; border.color: "#37474F"; border.width: 1
                            Label { anchors.centerIn: parent; text: "−5"; color: "#78909C"; font.pixelSize: ts(1.7); font.bold: true }
                            MouseArea { id: azM5; anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.autoZoomSecs = Math.max(5, panel.cfg.autoZoomSecs - 5)
                                onPressAndHold: { azCtrl._step = 5; azCtrl._dir = -1 }
                                onReleased: azCtrl._dir = 0 }
                        }
                        Rectangle {
                            id: azM1Btn
                            anchors { left: azM5Btn.right; leftMargin: units.gu(0.5); verticalCenter: parent.verticalCenter }
                            width: units.gu(4.5); height: units.gu(4); radius: units.gu(0.6)
                            color: azM1.pressed ? "#1E3A5F" : "#2A2A3E"; border.color: "#37474F"; border.width: 1
                            Label { anchors.centerIn: parent; text: "−1"; color: "#29B6F6"; font.pixelSize: ts(1.7); font.bold: true }
                            MouseArea { id: azM1; anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.autoZoomSecs = Math.max(5, panel.cfg.autoZoomSecs - 1)
                                onPressAndHold: { azCtrl._step = 1; azCtrl._dir = -1 }
                                onReleased: azCtrl._dir = 0 }
                        }
                        Rectangle {
                            anchors { left: azM1Btn.right; right: azP1Btn.left; verticalCenter: parent.verticalCenter; margins: units.gu(0.8) }
                            height: units.gu(0.5); radius: height / 2; color: "#37474F"
                            Rectangle {
                                width: panel.cfg ? (panel.cfg.autoZoomSecs - 5) / 55 * parent.width : 0
                                height: parent.height; radius: parent.radius; color: "#29B6F6"
                            }
                        }
                        Rectangle {
                            id: azP1Btn
                            anchors { right: azP5Btn.left; rightMargin: units.gu(0.5); verticalCenter: parent.verticalCenter }
                            width: units.gu(4.5); height: units.gu(4); radius: units.gu(0.6)
                            color: azP1.pressed ? "#1E3A5F" : "#2A2A3E"; border.color: "#37474F"; border.width: 1
                            Label { anchors.centerIn: parent; text: "+1"; color: "#29B6F6"; font.pixelSize: ts(1.7); font.bold: true }
                            MouseArea { id: azP1; anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.autoZoomSecs = Math.min(60, panel.cfg.autoZoomSecs + 1)
                                onPressAndHold: { azCtrl._step = 1; azCtrl._dir = 1 }
                                onReleased: azCtrl._dir = 0 }
                        }
                        Rectangle {
                            id: azP5Btn
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: units.gu(5); height: units.gu(4); radius: units.gu(0.6)
                            color: azP5.pressed ? "#1E3A5F" : "#2A2A3E"; border.color: "#37474F"; border.width: 1
                            Label { anchors.centerIn: parent; text: "+5"; color: "#78909C"; font.pixelSize: ts(1.7); font.bold: true }
                            MouseArea { id: azP5; anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.autoZoomSecs = Math.min(60, panel.cfg.autoZoomSecs + 5)
                                onPressAndHold: { azCtrl._step = 5; azCtrl._dir = 1 }
                                onReleased: azCtrl._dir = 0 }
                        }
                    }
                }
            }

            // ── Ajustar movimiento a ruta ────────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.prefLevel >= 1
                width: parent.width; height: units.gu(8)
                color: "#1C1C2E"; radius: units.gu(1)
                Row {
                    anchors { fill: parent; margins: units.gu(2) }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(7)
                        Label { text: i18n.tr("Ajustar movimiento a ruta"); color: "white"; font.pixelSize: ts(1.8) }
                        Label {
                            text: i18n.tr("Zoom según velocidades Valhalla de los tramos por delante") + "  · ↺ act."
                            color: "#90A4AE"; font.pixelSize: ts(1.8)
                            wrapMode: Text.WordWrap; width: parent.width
                        }
                    }
                    Item { width: units.gu(1); height: 1 }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(5.5); height: units.gu(3); radius: height / 2
                        color: panel.cfg && panel.cfg.routeAdjustZoom ? "#29B6F6" : "#37474F"
                        Rectangle {
                            width: units.gu(2.4); height: units.gu(2.4); radius: width / 2; color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                            x: panel.cfg && panel.cfg.routeAdjustZoom ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        MouseArea { anchors.fill: parent; onClicked: if (panel.cfg) panel.cfg.routeAdjustZoom = !panel.cfg.routeAdjustZoom }
                    }
                }
            }

            // ── Anticipación giro de ruta ────────────────────────────────
            Rectangle {
                width: parent.width; height: raCol.implicitHeight + units.gu(4)
                color: "#1C1C2E"; radius: units.gu(1)
                visible: panel.cfg && panel.cfg.routeAdjustZoom && panel.cfg.prefLevel >= 2
                Column {
                    id: raCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Row {
                        width: parent.width
                        Label {
                            text: i18n.tr("Anticipación giro de ruta")
                            color: "white"; font.pixelSize: ts(1.8)
                            width: parent.width - routeAheadLabel.width
                        }
                        Label {
                            id: routeAheadLabel
                            textFormat: Text.RichText
                            text: panel.cfg ? ("<b>" + panel.cfg.routeAheadSecs + " s</b> <font color='#546E7A'>↺ 10 s</font>") : ""
                            color: "#29B6F6"; font.pixelSize: ts(1.8)
                        }
                    }
                    Label {
                        text: i18n.tr("Segundos de ruta por delante para anticipar el giro del mapa")
                        color: "#90A4AE"; font.pixelSize: ts(1.6)
                        wrapMode: Text.WordWrap; width: parent.width
                    }
                    Item {
                        id: raCtrl
                        width: parent.width; height: units.gu(4)
                        property int _dir: 0; property int _step: 1
                        Timer { interval: 180; repeat: true; running: raCtrl._dir !== 0
                            onTriggered: if (panel.cfg) panel.cfg.routeAheadSecs = Math.max(1, Math.min(45, panel.cfg.routeAheadSecs + raCtrl._step * raCtrl._dir))
                        }
                        Rectangle {
                            id: raM5Btn
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            width: units.gu(5); height: units.gu(4); radius: units.gu(0.6)
                            color: raM5.pressed ? "#1E3A5F" : "#2A2A3E"; border.color: "#37474F"; border.width: 1
                            Label { anchors.centerIn: parent; text: "−5"; color: "#78909C"; font.pixelSize: ts(1.7); font.bold: true }
                            MouseArea { id: raM5; anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.routeAheadSecs = Math.max(1, panel.cfg.routeAheadSecs - 5)
                                onPressAndHold: { raCtrl._step = 5; raCtrl._dir = -1 }
                                onReleased: raCtrl._dir = 0 }
                        }
                        Rectangle {
                            id: raM1Btn
                            anchors { left: raM5Btn.right; leftMargin: units.gu(0.5); verticalCenter: parent.verticalCenter }
                            width: units.gu(4.5); height: units.gu(4); radius: units.gu(0.6)
                            color: raM1.pressed ? "#1E3A5F" : "#2A2A3E"; border.color: "#37474F"; border.width: 1
                            Label { anchors.centerIn: parent; text: "−1"; color: "#29B6F6"; font.pixelSize: ts(1.7); font.bold: true }
                            MouseArea { id: raM1; anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.routeAheadSecs = Math.max(1, panel.cfg.routeAheadSecs - 1)
                                onPressAndHold: { raCtrl._step = 1; raCtrl._dir = -1 }
                                onReleased: raCtrl._dir = 0 }
                        }
                        Rectangle {
                            anchors { left: raM1Btn.right; right: raP1Btn.left; verticalCenter: parent.verticalCenter; margins: units.gu(0.8) }
                            height: units.gu(0.5); radius: height / 2; color: "#37474F"
                            Rectangle {
                                width: panel.cfg ? (panel.cfg.routeAheadSecs - 1) / 44 * parent.width : 0
                                height: parent.height; radius: parent.radius; color: "#29B6F6"
                            }
                        }
                        Rectangle {
                            id: raP1Btn
                            anchors { right: raP5Btn.left; rightMargin: units.gu(0.5); verticalCenter: parent.verticalCenter }
                            width: units.gu(4.5); height: units.gu(4); radius: units.gu(0.6)
                            color: raP1.pressed ? "#1E3A5F" : "#2A2A3E"; border.color: "#37474F"; border.width: 1
                            Label { anchors.centerIn: parent; text: "+1"; color: "#29B6F6"; font.pixelSize: ts(1.7); font.bold: true }
                            MouseArea { id: raP1; anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.routeAheadSecs = Math.min(45, panel.cfg.routeAheadSecs + 1)
                                onPressAndHold: { raCtrl._step = 1; raCtrl._dir = 1 }
                                onReleased: raCtrl._dir = 0 }
                        }
                        Rectangle {
                            id: raP5Btn
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: units.gu(5); height: units.gu(4); radius: units.gu(0.6)
                            color: raP5.pressed ? "#1E3A5F" : "#2A2A3E"; border.color: "#37474F"; border.width: 1
                            Label { anchors.centerIn: parent; text: "+5"; color: "#78909C"; font.pixelSize: ts(1.7); font.bold: true }
                            MouseArea { id: raP5; anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.routeAheadSecs = Math.min(45, panel.cfg.routeAheadSecs + 5)
                                onPressAndHold: { raCtrl._step = 5; raCtrl._dir = 1 }
                                onReleased: raCtrl._dir = 0 }
                        }
                    }
                }
            }

            // ── Ángulo máximo de giro predictivo ─────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.prefLevel >= 2
                width: parent.width; height: mtCol.implicitHeight + units.gu(4)
                color: "#1C1C2E"; radius: units.gu(1)
                Column {
                    id: mtCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Row {
                        width: parent.width
                        Label {
                            text: i18n.tr("Ángulo máximo de giro predictivo")
                            color: "white"; font.pixelSize: ts(1.8)
                            width: parent.width - maxTurnLabel.width
                        }
                        Label {
                            id: maxTurnLabel
                            textFormat: Text.RichText
                            text: panel.cfg ? ("<b>" + panel.cfg.maxPredictiveTurnDeg + "°</b> <font color='#546E7A'>↺ 30°</font>") : ""
                            color: "#29B6F6"; font.pixelSize: ts(1.8)
                        }
                    }
                    Label {
                        text: i18n.tr("Máximo desvío angular del mapa respecto al heading real en modo giro")
                        color: "#90A4AE"; font.pixelSize: ts(1.6)
                        wrapMode: Text.WordWrap; width: parent.width
                    }
                    Item {
                        id: mtCtrl
                        width: parent.width; height: units.gu(4)
                        property int _dir: 0; property int _step: 5
                        Timer { interval: 180; repeat: true; running: mtCtrl._dir !== 0
                            onTriggered: if (panel.cfg) panel.cfg.maxPredictiveTurnDeg = Math.max(0, Math.min(90, panel.cfg.maxPredictiveTurnDeg + mtCtrl._step * mtCtrl._dir))
                        }
                        Rectangle {
                            id: mtM5Btn
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            width: units.gu(5); height: units.gu(4); radius: units.gu(0.6)
                            color: mtM5.pressed ? "#1E3A5F" : "#2A2A3E"; border.color: "#37474F"; border.width: 1
                            Label { anchors.centerIn: parent; text: "−5"; color: "#78909C"; font.pixelSize: ts(1.7); font.bold: true }
                            MouseArea { id: mtM5; anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.maxPredictiveTurnDeg = Math.max(0, panel.cfg.maxPredictiveTurnDeg - 5)
                                onPressAndHold: { mtCtrl._step = 5; mtCtrl._dir = -1 }
                                onReleased: mtCtrl._dir = 0 }
                        }
                        Rectangle {
                            id: mtM1Btn
                            anchors { left: mtM5Btn.right; leftMargin: units.gu(0.5); verticalCenter: parent.verticalCenter }
                            width: units.gu(4.5); height: units.gu(4); radius: units.gu(0.6)
                            color: mtM1.pressed ? "#1E3A5F" : "#2A2A3E"; border.color: "#37474F"; border.width: 1
                            Label { anchors.centerIn: parent; text: "−1"; color: "#29B6F6"; font.pixelSize: ts(1.7); font.bold: true }
                            MouseArea { id: mtM1; anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.maxPredictiveTurnDeg = Math.max(0, panel.cfg.maxPredictiveTurnDeg - 1)
                                onPressAndHold: { mtCtrl._step = 1; mtCtrl._dir = -1 }
                                onReleased: mtCtrl._dir = 0 }
                        }
                        Rectangle {
                            anchors { left: mtM1Btn.right; right: mtP1Btn.left; verticalCenter: parent.verticalCenter; margins: units.gu(0.8) }
                            height: units.gu(0.5); radius: height / 2; color: "#37474F"
                            Rectangle {
                                width: panel.cfg ? panel.cfg.maxPredictiveTurnDeg / 90 * parent.width : 0
                                height: parent.height; radius: parent.radius; color: "#29B6F6"
                            }
                        }
                        Rectangle {
                            id: mtP1Btn
                            anchors { right: mtP5Btn.left; rightMargin: units.gu(0.5); verticalCenter: parent.verticalCenter }
                            width: units.gu(4.5); height: units.gu(4); radius: units.gu(0.6)
                            color: mtP1.pressed ? "#1E3A5F" : "#2A2A3E"; border.color: "#37474F"; border.width: 1
                            Label { anchors.centerIn: parent; text: "+1"; color: "#29B6F6"; font.pixelSize: ts(1.7); font.bold: true }
                            MouseArea { id: mtP1; anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.maxPredictiveTurnDeg = Math.min(90, panel.cfg.maxPredictiveTurnDeg + 1)
                                onPressAndHold: { mtCtrl._step = 1; mtCtrl._dir = 1 }
                                onReleased: mtCtrl._dir = 0 }
                        }
                        Rectangle {
                            id: mtP5Btn
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: units.gu(5); height: units.gu(4); radius: units.gu(0.6)
                            color: mtP5.pressed ? "#1E3A5F" : "#2A2A3E"; border.color: "#37474F"; border.width: 1
                            Label { anchors.centerIn: parent; text: "+5"; color: "#78909C"; font.pixelSize: ts(1.7); font.bold: true }
                            MouseArea { id: mtP5; anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.maxPredictiveTurnDeg = Math.min(90, panel.cfg.maxPredictiveTurnDeg + 5)
                                onPressAndHold: { mtCtrl._step = 5; mtCtrl._dir = 1 }
                                onReleased: mtCtrl._dir = 0 }
                        }
                    }
                }
            }

            // ── Ajuste de posición a la ruta ─────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.prefLevel >= 1
                width: parent.width; height: units.gu(8)
                color: "#1C1C2E"; radius: units.gu(1)
                Row {
                    anchors { fill: parent; margins: units.gu(2) }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(7)
                        Label { text: i18n.tr("Ajuste de posición a la ruta"); color: "white"; font.pixelSize: ts(1.8) }
                        Label {
                            text: i18n.tr("Centrar el vehículo sobre el shape de la ruta") + "  · ↺ act."
                            color: "#90A4AE"; font.pixelSize: ts(1.6)
                            wrapMode: Text.WordWrap; width: parent.width
                        }
                    }
                    Item { width: units.gu(1); height: 1 }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(5.5); height: units.gu(3); radius: height / 2
                        color: panel.cfg && panel.cfg.snapToRouteEnabled ? "#29B6F6" : "#37474F"
                        Rectangle {
                            width: units.gu(2.4); height: units.gu(2.4); radius: width / 2; color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                            x: panel.cfg && panel.cfg.snapToRouteEnabled ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        MouseArea { anchors.fill: parent; onClicked: if (panel.cfg) panel.cfg.snapToRouteEnabled = !panel.cfg.snapToRouteEnabled }
                    }
                }
            }

            // ── Distancia máxima de ajuste ────────────────────────────────
            Rectangle {
                width: parent.width; height: sdCol.implicitHeight + units.gu(4)
                color: "#1C1C2E"; radius: units.gu(1)
                visible: panel.cfg && panel.cfg.snapToRouteEnabled && panel.cfg.prefLevel >= 2
                Column {
                    id: sdCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Row {
                        width: parent.width
                        Label {
                            text: i18n.tr("Distancia máxima de ajuste")
                            color: "white"; font.pixelSize: ts(1.8)
                            width: parent.width - snapDistLabel.width
                        }
                        Label {
                            id: snapDistLabel
                            textFormat: Text.RichText
                            text: panel.cfg ? ("<b>" + panel.cfg.snapDistM + " m</b> <font color='#546E7A'>↺ 11 m</font>") : ""
                            color: "#29B6F6"; font.pixelSize: ts(1.8)
                        }
                    }
                    Label {
                        text: i18n.tr("Ajustar posición visual si el GPS está a menos de esta distancia de la ruta")
                        color: "#90A4AE"; font.pixelSize: ts(1.6)
                        wrapMode: Text.WordWrap; width: parent.width
                    }
                    Item {
                        id: sdCtrl
                        width: parent.width; height: units.gu(4)
                        property int _dir: 0
                        Timer { interval: 200; repeat: true; running: sdCtrl._dir !== 0
                            onTriggered: if (panel.cfg) panel.cfg.snapDistM = Math.max(5, Math.min(15, panel.cfg.snapDistM + sdCtrl._dir))
                        }
                        Rectangle {
                            id: sdMinusBtn
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            width: units.gu(5); height: units.gu(4); radius: units.gu(0.6)
                            color: sdMinus.pressed ? "#1E3A5F" : "#2A2A3E"; border.color: "#37474F"; border.width: 1
                            Label { anchors.centerIn: parent; text: "−"; color: "#29B6F6"; font.pixelSize: ts(2.5); font.bold: true }
                            MouseArea { id: sdMinus; anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.snapDistM = Math.max(5, panel.cfg.snapDistM - 1)
                                onPressAndHold: sdCtrl._dir = -1
                                onReleased: sdCtrl._dir = 0 }
                        }
                        Rectangle {
                            anchors { left: sdMinusBtn.right; right: sdPlusBtn.left; verticalCenter: parent.verticalCenter; margins: units.gu(1) }
                            height: units.gu(0.5); radius: height / 2; color: "#37474F"
                            Rectangle {
                                width: panel.cfg ? (panel.cfg.snapDistM - 5) / 10 * parent.width : 0
                                height: parent.height; radius: parent.radius; color: "#29B6F6"
                            }
                        }
                        Rectangle {
                            id: sdPlusBtn
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: units.gu(5); height: units.gu(4); radius: units.gu(0.6)
                            color: sdPlus.pressed ? "#1E3A5F" : "#2A2A3E"; border.color: "#37474F"; border.width: 1
                            Label { anchors.centerIn: parent; text: "+"; color: "#29B6F6"; font.pixelSize: ts(2.5); font.bold: true }
                            MouseArea { id: sdPlus; anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.snapDistM = Math.min(15, panel.cfg.snapDistM + 1)
                                onPressAndHold: sdCtrl._dir = 1
                                onReleased: sdCtrl._dir = 0 }
                        }
                    }
                }
            }

            // ── Distancia de desvío antes de recalcular ruta ─────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.prefLevel >= 1
                width: parent.width; height: orCol.implicitHeight + units.gu(4)
                color: "#1C1C2E"; radius: units.gu(1)
                Column {
                    id: orCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Row {
                        width: parent.width
                        Label {
                            text: i18n.tr("Desvío para recalcular ruta")
                            color: "white"; font.pixelSize: ts(1.8)
                            width: parent.width - offRouteDistLabel.width
                        }
                        Label {
                            id: offRouteDistLabel
                            textFormat: Text.RichText
                            text: panel.cfg ? ("<b>" + panel.cfg.offRouteDistM + " m</b> <font color='#546E7A'>↺ 11 m</font>") : ""
                            color: "#29B6F6"; font.pixelSize: ts(1.8)
                        }
                    }
                    Label {
                        text: i18n.tr("Distancia fuera de la ruta antes de recalcular")
                        color: "#90A4AE"; font.pixelSize: ts(1.6)
                        wrapMode: Text.WordWrap; width: parent.width
                    }
                    Item {
                        id: orCtrl
                        width: parent.width; height: units.gu(4)
                        property int _dir: 0
                        Timer { interval: 200; repeat: true; running: orCtrl._dir !== 0
                            onTriggered: if (panel.cfg) panel.cfg.offRouteDistM = Math.max(5, Math.min(15, panel.cfg.offRouteDistM + orCtrl._dir))
                        }
                        Rectangle {
                            id: orMinusBtn
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            width: units.gu(5); height: units.gu(4); radius: units.gu(0.6)
                            color: orMinus.pressed ? "#1E3A5F" : "#2A2A3E"; border.color: "#37474F"; border.width: 1
                            Label { anchors.centerIn: parent; text: "−"; color: "#29B6F6"; font.pixelSize: ts(2.5); font.bold: true }
                            MouseArea { id: orMinus; anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.offRouteDistM = Math.max(5, panel.cfg.offRouteDistM - 1)
                                onPressAndHold: orCtrl._dir = -1
                                onReleased: orCtrl._dir = 0 }
                        }
                        Rectangle {
                            anchors { left: orMinusBtn.right; right: orPlusBtn.left; verticalCenter: parent.verticalCenter; margins: units.gu(1) }
                            height: units.gu(0.5); radius: height / 2; color: "#37474F"
                            Rectangle {
                                width: panel.cfg ? (panel.cfg.offRouteDistM - 5) / 10 * parent.width : 0
                                height: parent.height; radius: parent.radius; color: "#29B6F6"
                            }
                        }
                        Rectangle {
                            id: orPlusBtn
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: units.gu(5); height: units.gu(4); radius: units.gu(0.6)
                            color: orPlus.pressed ? "#1E3A5F" : "#2A2A3E"; border.color: "#37474F"; border.width: 1
                            Label { anchors.centerIn: parent; text: "+"; color: "#29B6F6"; font.pixelSize: ts(2.5); font.bold: true }
                            MouseArea { id: orPlus; anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.offRouteDistM = Math.min(15, panel.cfg.offRouteDistM + 1)
                                onPressAndHold: orCtrl._dir = 1
                                onReleased: orCtrl._dir = 0 }
                        }
                    }
                }
            }

            // ── Suavizado GPS ────────────────────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.prefLevel >= 1
                width: parent.width; height: units.gu(8)
                color: "#1C1C2E"; radius: units.gu(1)
                Row {
                    anchors { fill: parent; margins: units.gu(2) }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(7)
                        Label { text: i18n.tr("Suavizado GPS"); color: "white"; font.pixelSize: ts(1.8) }
                        Label {
                            text: i18n.tr("Suavizar el movimiento del vehículo y el mapa entre ticks GPS") + "  · ↺ act."
                            color: "#90A4AE"; font.pixelSize: ts(1.8)
                            wrapMode: Text.WordWrap; width: parent.width
                        }
                    }
                    Item { width: units.gu(1); height: 1 }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(5.5); height: units.gu(3); radius: height / 2
                        color: panel.cfg && panel.cfg.drEnabled ? "#29B6F6" : "#37474F"
                        Rectangle {
                            width: units.gu(2.4); height: units.gu(2.4); radius: width / 2; color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                            x: panel.cfg && panel.cfg.drEnabled ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        MouseArea { anchors.fill: parent; onClicked: if (panel.cfg) panel.cfg.drEnabled = !panel.cfg.drEnabled }
                    }
                }
            }

            // ── Frecuencia de suavizado ──────────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.drEnabled && panel.cfg.prefLevel >= 2
                width: parent.width; height: units.gu(11)
                color: "#1C1C2E"; radius: units.gu(1)
                Column {
                    anchors { fill: parent; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Label { text: i18n.tr("Frecuencia de suavizado"); color: "white"; font.pixelSize: ts(1.8) }
                    Row {
                        spacing: units.gu(1)
                        Repeater {
                            model: [10, 20, 30]
                            Rectangle {
                                property int hz: modelData
                                width: units.gu(8); height: units.gu(4.5); radius: units.gu(0.6)
                                color:        panel.cfg && panel.cfg.drHz === hz ? "#1E3A5F" : "#2A2A3E"
                                border.color: panel.cfg && panel.cfg.drHz === hz ? "#29B6F6" : "transparent"
                                border.width: units.gu(0.15)
                                Label {
                                    anchors.centerIn: parent
                                    text: hz + " Hz" + (hz === 20 ? " ↺" : "")
                                    color: panel.cfg && panel.cfg.drHz === hz ? "#29B6F6" : "#78909C"
                                    font.pixelSize: ts(1.7)
                                    font.bold: panel.cfg && panel.cfg.drHz === hz
                                    elide: Text.ElideRight
                                    width: parent.width - units.gu(0.4)
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                MouseArea { anchors.fill: parent; onClicked: if (panel.cfg) panel.cfg.drHz = hz }
                            }
                        }
                    }
                }
            }

            // ── Slider de zoom ───────────────────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.prefLevel >= 1
                width: parent.width; height: units.gu(8)
                color: "#1C1C2E"; radius: units.gu(1)
                Row {
                    anchors { fill: parent; margins: units.gu(2) }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(7)
                        Label { text: i18n.tr("Slider de zoom"); color: "white"; font.pixelSize: ts(1.8) }
                        Label {
                            text: i18n.tr("Barra lateral para ajustar el zoom") + "  · ↺ act."
                            color: "#90A4AE"; font.pixelSize: ts(1.8)
                            wrapMode: Text.WordWrap; width: parent.width
                        }
                    }
                    Item { width: units.gu(1); height: 1 }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(5.5); height: units.gu(3); radius: height / 2
                        color: panel.cfg && panel.cfg.showZoomSlider ? "#29B6F6" : "#37474F"
                        Rectangle {
                            width: units.gu(2.4); height: units.gu(2.4); radius: width / 2; color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                            x: panel.cfg && panel.cfg.showZoomSlider ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        MouseArea { anchors.fill: parent; onClicked: if (panel.cfg) panel.cfg.showZoomSlider = !panel.cfg.showZoomSlider }
                    }
                }
            }

            // ── Inhibir suspensión durante navegación ────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.prefLevel >= 2
                width: parent.width; height: units.gu(10)
                color: "#1C1C2E"; radius: units.gu(1)
                Row {
                    anchors { fill: parent; margins: units.gu(2) }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(7)
                        Label { text: i18n.tr("Inhibir suspensión durante la navegación"); color: "white"; font.pixelSize: ts(1.8); wrapMode: Text.WordWrap; width: parent.width }
                        Label {
                            text: i18n.tr("Mantiene la pantalla encendida mientras navegas") + "  · ↺ act."
                            color: "#90A4AE"; font.pixelSize: ts(1.6)
                            wrapMode: Text.WordWrap; width: parent.width
                        }
                    }
                    Item { width: units.gu(1); height: 1 }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(5.5); height: units.gu(3); radius: height / 2
                        color: panel.cfg && panel.cfg.inhibitSuspend ? "#29B6F6" : "#37474F"
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Rectangle {
                            width: units.gu(2.4); height: units.gu(2.4); radius: width / 2; color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                            x: panel.cfg && panel.cfg.inhibitSuspend ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        MouseArea { anchors.fill: parent; onClicked: if (panel.cfg) panel.cfg.inhibitSuspend = !panel.cfg.inhibitSuspend }
                    }
                }
            }

            // ── Mostrar velocidad máxima de la vía ───────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.prefLevel >= 2
                width: parent.width; height: units.gu(10)
                color: "#1C1C2E"; radius: units.gu(1)
                Row {
                    anchors { fill: parent; margins: units.gu(2) }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(7)
                        Label { text: i18n.tr("Mostrar velocidad máxima de la vía"); color: "white"; font.pixelSize: ts(1.8); wrapMode: Text.WordWrap; width: parent.width }
                        Label {
                            text: i18n.tr("Fuente no fiable (OSM/Valhalla). Solo activa si hay radar comunitario") + "  · ↺ desact."
                            color: "#90A4AE"; font.pixelSize: ts(1.6)
                            wrapMode: Text.WordWrap; width: parent.width
                        }
                    }
                    Item { width: units.gu(1); height: 1 }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(5.5); height: units.gu(3); radius: height / 2
                        color: panel.cfg && panel.cfg.showRoadSpeedLimit ? "#29B6F6" : "#37474F"
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Rectangle {
                            width: units.gu(2.4); height: units.gu(2.4); radius: width / 2; color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                            x: panel.cfg && panel.cfg.showRoadSpeedLimit ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        MouseArea { anchors.fill: parent; onClicked: if (panel.cfg) panel.cfg.showRoadSpeedLimit = !panel.cfg.showRoadSpeedLimit }
                    }
                }
            }

            // ── Velocidad GPS hardware (Doppler) ─────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.prefLevel >= 1
                width: parent.width; height: units.gu(10)
                color: "#1C1C2E"; radius: units.gu(1)
                Row {
                    anchors { fill: parent; margins: units.gu(2) }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(7)
                        Label { text: i18n.tr("Velocidad GPS Doppler"); color: "white"; font.pixelSize: ts(1.8) }
                        Label {
                            text: i18n.tr("Usa la velocidad Doppler del chip GPS en vez de calcularla por diferencia de posiciones. Más precisa a baja velocidad y en aceleraciones. Desactiva si notas velocidades erráticas.") + "  · ↺ act."
                            color: "#90A4AE"; font.pixelSize: ts(1.6)
                            wrapMode: Text.WordWrap; width: parent.width
                        }
                    }
                    Item { width: units.gu(1); height: 1 }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(5.5); height: units.gu(3); radius: height / 2
                        color: panel.cfg && panel.cfg.useHardwareSpeed ? "#29B6F6" : "#37474F"
                        Rectangle {
                            width: units.gu(2.4); height: units.gu(2.4); radius: width / 2; color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                            x: panel.cfg && panel.cfg.useHardwareSpeed ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        MouseArea { anchors.fill: parent; onClicked: if (panel.cfg) panel.cfg.useHardwareSpeed = !panel.cfg.useHardwareSpeed }
                    }
                }
            }

        } // Column Navegación

        // ════════════════════════════════════════════════════════════════
        // GRABACIÓN DE RUTAS
        // ════════════════════════════════════════════════════════════════
        Rectangle {
            visible: grabacionCol.hasContent
            width: parent.width; height: units.gu(5.5)
            color: "#252535"; radius: units.gu(1)
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                text: i18n.tr("Grabación de rutas")
                color: "#29B6F6"; font.pixelSize: ts(2.0); font.bold: true
            }
            Label {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: units.gu(2) }
                text: secSettings.grabacion ? "▲" : "▼"
                color: "#29B6F6"; font.pixelSize: ts(1.6)
            }
            MouseArea { anchors.fill: parent; onClicked: secSettings.grabacion = !secSettings.grabacion }
        }

        Column {
            id: grabacionCol
            property int  _sectionMinLevel: 0
            property bool hasContent: panel.cfg ? panel.cfg.prefLevel >= _sectionMinLevel : false
            visible: secSettings.grabacion && hasContent
            width: parent.width; spacing: units.gu(1.5)

        // ── Grabación GPS + Rutas grabadas ───────────────────────────
        Rectangle {
            id: tracksSection
            width: parent.width
            color: "#1C1C2E"; radius: units.gu(1)
            height: tracksCol.implicitHeight + units.gu(4)

            property var    _tracks:    []
            property string _renameId:  ""
            property string _deleteId:  ""
            property string _addSimId:  ""
            property string _addSimName: ""
            property string _gpxMsg:    ""

            function _refresh() {
                if (!panel.trackerRef) { _tracks = []; return }
                panel.trackerRef.list_tracks_async()
            }

            onVisibleChanged: if (visible) _refresh()
            Timer {
                id: trackSaveTimer
                interval: 1200; repeat: false
                onTriggered: tracksSection._refresh()
            }
            Connections {
                target: panel.trackerRef
                function onRecording_changed() {
                    if (panel.trackerRef && !panel.trackerRef.recording)
                        trackSaveTimer.restart()
                    else
                        Qt.callLater(function() { tracksSection._refresh() })
                }
                function onTracks_ready(json) {
                    try { tracksSection._tracks = JSON.parse(json) }
                    catch(e) { tracksSection._tracks = [] }
                }
                function onTrack_deleted(id) {
                    tracksSection._refresh()
                }
                function onGpx_ready(id, path) {
                    tracksSection._gpxMsg = path !== "" ? "✓ GPX: " + path.split("/").pop() : "✗ Error al exportar"
                    gpxMsgTimer.restart()
                }
            }
            Timer {
                id: gpxMsgTimer
                interval: 4000; repeat: false
                onTriggered: tracksSection._gpxMsg = ""
            }

            Column {
                id: tracksCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                spacing: units.gu(1)

                // Toggle grabación
                Row {
                    width: parent.width
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(7)
                        Label { text: i18n.tr("Grabación GPS"); color: "white"; font.pixelSize: ts(1.8) }
                        Label {
                            text: panel.cfg && panel.cfg.gpsTracking
                                  ? (panel.trackerRef
                                     ? i18n.tr("Grabando") + " · " + panel.trackerRef.get_point_count() + " pts"
                                     : i18n.tr("Grabando…"))
                                  : i18n.tr("Graba posición y velocidad")
                            color: panel.cfg && panel.cfg.gpsTracking ? "#EF5350" : "#546E7A"
                            font.pixelSize: ts(1.6); wrapMode: Text.WordWrap; width: parent.width
                        }
                    }
                    Item { width: units.gu(1); height: 1 }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(5.5); height: units.gu(3); radius: height / 2
                        color: panel.cfg && panel.cfg.gpsTracking ? "#EF5350" : "#37474F"
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Rectangle {
                            width: units.gu(2.4); height: units.gu(2.4); radius: width / 2; color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                            x: panel.cfg && panel.cfg.gpsTracking ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { if (panel.cfg) panel.cfg.gpsTracking = !panel.cfg.gpsTracking }
                        }
                    }
                }

                // Borrar todas las rutas
                Rectangle {
                    id: allTracksBtn
                    width: parent.width; height: units.gu(4.5); radius: units.gu(0.8)
                    color: _confirm ? "#4A1010" : "#2A2A3E"
                    property bool _confirm: false
                    property bool _done: false
                    Timer { interval: 4000; running: parent._confirm && !parent._done; onTriggered: parent._confirm = false }
                    Timer { interval: 2500; running: parent._done; onTriggered: parent._done = false }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Label {
                        anchors.centerIn: parent
                        text:  allTracksBtn._done    ? "✓ " + i18n.tr("Rutas eliminadas")
                             : allTracksBtn._confirm ? "⚠ " + i18n.tr("Toca de nuevo para confirmar")
                             :                         i18n.tr("Borrar todas las rutas grabadas")
                        color: allTracksBtn._done    ? "#66BB6A"
                             : allTracksBtn._confirm ? "#FFCC02"
                             :                        "#EF5350"
                        font.pixelSize: ts(1.8)
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (allTracksBtn._confirm) {
                                panel.allTracksClearRequested()
                                allTracksBtn._done = true; allTracksBtn._confirm = false
                            } else { allTracksBtn._confirm = true }
                        }
                    }
                }

                // Lista de rutas
                Label {
                    visible: true
                    text: i18n.tr("Rutas grabadas"); color: "white"; font.pixelSize: ts(1.8)
                }
                Label {
                    visible: tracksSection._gpxMsg !== ""
                    text: tracksSection._gpxMsg
                    color: tracksSection._gpxMsg.charAt(0) === "✓" ? "#66BB6A" : "#EF5350"
                    font.pixelSize: ts(1.6)
                    wrapMode: Text.WordWrap; width: parent.width
                }
                Label {
                    visible: tracksSection._tracks.length === 0
                    text: i18n.tr("Ninguna ruta grabada aún")
                    color: "#90A4AE"; font.pixelSize: ts(1.8)
                }

                Repeater {
                    model: tracksSection._tracks
                    delegate: Rectangle {
                        id: trackDelegate
                        property var td: modelData
                        width: tracksCol.width
                        height: tdMain.implicitHeight
                                + (deleteRow.visible ? deleteRow.height + units.gu(0.8) : 0)
                                + (renameRow.visible ? renameRow.height + units.gu(0.8) : 0)
                                + (addSimRow.visible ? addSimRow.height + units.gu(0.8) : 0)
                                + units.gu(1.5)
                        color: "#151525"; radius: units.gu(0.6)
                        border.color: "#22334455"; border.width: units.gu(0.1)

                        Column {
                            id: tdMain
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(1) }
                            spacing: units.gu(0.4)
                            Label {
                                width: parent.width; text: td.name
                                color: "white"; font.pixelSize: ts(1.7); font.bold: true
                                elide: Text.ElideRight
                            }
                            Label {
                                text: td.date + "  ·  " + td.dur + "  ·  " + td.dist + "  ·  " + td.npts + " pts"
                                      + (td.has_route ? "  ·  con ruta" : "")
                                color: "#B0BEC5"; font.pixelSize: ts(1.5)
                                wrapMode: Text.WordWrap; width: parent.width
                            }
                            Row {
                                spacing: units.gu(0.6)
                                Rectangle {
                                    width: units.gu(7.5); height: units.gu(4); radius: units.gu(0.5)
                                    color: td.has_route ? "#1565C3" : "#37474F"
                                    Label {
                                        anchors.centerIn: parent
                                        text: i18n.tr("Simular")
                                        color: td.has_route ? "white" : "#90A4AE"
                                        font.pixelSize: ts(1.6)
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: panel.trackSimRequested(td.id, td.name, false) }
                                }
                                Rectangle {
                                    width: units.gu(9); height: units.gu(4); radius: units.gu(0.5); color: "#37474F"
                                    Label { anchors.centerIn: parent; text: i18n.tr("GPS crudo"); color: "#FFB74D"; font.pixelSize: ts(1.5) }
                                    MouseArea { anchors.fill: parent; onClicked: panel.trackSimRequested(td.id, td.name, true) }
                                }
                                Rectangle {
                                    width: units.gu(5.5); height: units.gu(4); radius: units.gu(0.5); color: "#2A2A3E"
                                    Label { anchors.centerIn: parent; text: "GPX"; color: "#4CAF50"; font.pixelSize: ts(1.6); font.bold: true }
                                    MouseArea { anchors.fill: parent; onClicked: panel.trackGpxRequested(td.id) }
                                }
                                Rectangle {
                                    width: units.gu(8); height: units.gu(4); radius: units.gu(0.5); color: "#2A2A3E"
                                    Label { anchors.centerIn: parent; text: "+ Sim"; color: "#9C27B0"; font.pixelSize: ts(1.6) }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            tracksSection._addSimId   = td.id
                                            tracksSection._addSimName = td.name
                                        }
                                    }
                                }
                                Rectangle {
                                    width: units.gu(5.5); height: units.gu(4); radius: units.gu(0.5); color: "#2A2A3E"
                                    Label { anchors.centerIn: parent; text: "✎"; color: "#29B6F6"; font.pixelSize: ts(1.8) }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: tracksSection._renameId = (tracksSection._renameId === td.id ? "" : td.id)
                                    }
                                }
                                Rectangle {
                                    width: units.gu(4); height: units.gu(4); radius: units.gu(0.5)
                                    color: tracksSection._deleteId === td.id ? "#4A1010" : "#2A2A3E"
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Label { anchors.centerIn: parent; text: "✕"; color: "#EF5350"; font.pixelSize: ts(1.8) }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: tracksSection._deleteId = (tracksSection._deleteId === td.id ? "" : td.id)
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: deleteRow
                            visible: tracksSection._deleteId === td.id
                            anchors { left: parent.left; right: parent.right; top: tdMain.bottom
                                      margins: units.gu(1); topMargin: units.gu(0.8) }
                            height: units.gu(4.5); radius: units.gu(0.5); color: "#2C1010"
                            border.color: "#EF5350"; border.width: units.gu(0.1)
                            Row {
                                anchors.centerIn: parent; spacing: units.gu(1)
                                Rectangle {
                                    width: units.gu(12); height: units.gu(3.5); radius: units.gu(0.5); color: "#37474F"
                                    Label { anchors.centerIn: parent; text: i18n.tr("Cancelar"); color: "white"; font.pixelSize: ts(1.7) }
                                    MouseArea { anchors.fill: parent; onClicked: tracksSection._deleteId = "" }
                                }
                                Rectangle {
                                    width: units.gu(12); height: units.gu(3.5); radius: units.gu(0.5); color: "#C62828"
                                    Label { anchors.centerIn: parent; text: i18n.tr("Eliminar"); color: "white"; font.pixelSize: ts(1.7) }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (panel.trackerRef) panel.trackerRef.delete_track_async(td.id)
                                            tracksSection._deleteId = ""
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: renameRow
                            visible: tracksSection._renameId === td.id
                            anchors { left: parent.left; right: parent.right; top: tdMain.bottom
                                      margins: units.gu(1); topMargin: units.gu(0.8) }
                            height: units.gu(4.5); radius: units.gu(0.5); color: "#1C2030"
                            border.color: "#29B6F6"; border.width: units.gu(0.1)
                            Row {
                                anchors { fill: parent; margins: units.gu(0.8) }
                                spacing: units.gu(0.6)
                                TextInput {
                                    id: renameInput
                                    width: parent.width - units.gu(6)
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: "white"; font.pixelSize: ts(1.7)
                                    text: tracksSection._renameId === td.id ? td.name : ""
                                    selectionColor: "#29B6F6"
                                    onActiveFocusChanged: if (activeFocus) panel._kbdFocusItem = this
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(5); height: units.gu(3.5); radius: units.gu(0.5); color: "#1565C3"
                                    Label { anchors.centerIn: parent; text: i18n.tr("OK"); color: "white"; font.pixelSize: ts(1.6); font.bold: true }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            var n = renameInput.text.trim()
                                            if (n.length > 0 && panel.trackerRef) {
                                                panel.trackerRef.rename_track(td.id, n)
                                                // Actualizar nombre localmente sin ir a BD (evita race con hilo rename)
                                                var arr = tracksSection._tracks
                                                for (var k = 0; k < arr.length; k++) {
                                                    if (arr[k].id === td.id) { arr[k].name = n; break }
                                                }
                                                tracksSection._tracks = arr.slice()
                                            }
                                            tracksSection._renameId = ""
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: addSimRow
                            visible: tracksSection._addSimId === td.id
                            anchors { left: parent.left; right: parent.right
                                      top: renameRow.visible ? renameRow.bottom : tdMain.bottom
                                      margins: units.gu(1); topMargin: units.gu(0.8) }
                            height: units.gu(4.5); radius: units.gu(0.5); color: "#1C2030"
                            border.color: "#9C27B0"; border.width: units.gu(0.1)
                            Row {
                                anchors { fill: parent; margins: units.gu(0.8) }
                                spacing: units.gu(0.6)
                                TextInput {
                                    id: addSimInput
                                    width: parent.width - units.gu(6)
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: "white"; font.pixelSize: ts(1.7)
                                    text: tracksSection._addSimId === td.id ? td.name : ""
                                    selectionColor: "#9C27B0"
                                    onActiveFocusChanged: if (activeFocus) panel._kbdFocusItem = this
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(5); height: units.gu(3.5); radius: units.gu(0.5); color: "#9C27B0"
                                    Label { anchors.centerIn: parent; text: "+ Sim"; color: "white"; font.pixelSize: ts(1.5); font.bold: true }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            var n = addSimInput.text.trim() || td.name
                                            panel.trackAddToSim(td.id, n)
                                            tracksSection._addSimId = ""
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        } // Column Grabación de rutas

        // ════════════════════════════════════════════════════════════════
        // VOZ
        // ════════════════════════════════════════════════════════════════
        Rectangle {
            visible: vozCol.hasContent
            width: parent.width; height: units.gu(5.5)
            color: "#252535"; radius: units.gu(1)
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                text: i18n.tr("Voz")
                color: "#29B6F6"; font.pixelSize: ts(2.0); font.bold: true
            }
            Label {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: units.gu(2) }
                text: secSettings.voz ? "▲" : "▼"
                color: "#29B6F6"; font.pixelSize: ts(1.6)
            }
            MouseArea { anchors.fill: parent; onClicked: secSettings.voz = !secSettings.voz }
        }

        Column {
            id: vozCol
            property int  _sectionMinLevel: 0
            property bool hasContent: panel.cfg ? panel.cfg.prefLevel >= _sectionMinLevel : false
            visible: secSettings.voz && hasContent
            width: parent.width; spacing: units.gu(1.5)

            // ── Idioma de voz + Motor TTS ────────────────────────────────
            Rectangle {
                width: parent.width
                height: ttsColumn.implicitHeight + units.gu(4)
                color: "#1C1C2E"; radius: units.gu(1)

                property var  _piperVoices:  []
                property var  _picoVoices:   []
                property var  _espeakVoices: []
                property string _effLang: {
                    if (!panel.cfg) return ""
                    var l = panel.cfg.ttsLang
                    return l === "system" ? Qt.locale().name.split("_")[0] : l
                }

                function _refreshVoices() {
                    if (!panel.ttsRef || !panel.cfg) {
                        _piperVoices = []; _picoVoices = []; _espeakVoices = []; return
                    }
                    var raw = panel.ttsRef.installed_piper_voices(_effLang)
                    _piperVoices = raw ? raw.split(",").filter(function(v) { return v.length > 0 }) : []
                    var rawPico = panel.ttsRef.available_pico_voices(_effLang)
                    _picoVoices = rawPico ? rawPico.split(",").filter(function(v) { return v.length > 0 }) : []
                    var rawEspeak = panel.ttsRef.available_espeak_voices(_effLang)
                    _espeakVoices = rawEspeak ? rawEspeak.split(",").filter(function(v) { return v.length > 0 }) : []
                }
                function _voiceLabel(id) {
                    var d = id.indexOf("-"); if (d < 0) return id
                    var rest = id.substring(d + 1)
                    var ld   = rest.lastIndexOf("-")
                    var name = ld >= 0 ? rest.substring(0, ld)  : rest
                    var qual = ld >= 0 ? rest.substring(ld + 1) : ""
                    var prefix = id.substring(0, d)
                    var u      = prefix.indexOf("_")
                    var locale = u >= 0 ? prefix.substring(u + 1) : ""
                    return locale ? name + " (" + locale + " · " + qual + ")"
                                  : name + " (" + qual + ")"
                }
                function _picoVoiceLabel(id) {
                    var map = {
                        "en-US": "English (US)", "en-GB": "English (GB)",
                        "de-DE": "Deutsch",      "es-ES": "Español",
                        "fr-FR": "Français",     "it-IT": "Italiano"
                    }
                    return map[id] || id
                }
                function _espeakVoiceLabel(id) {
                    var map = {
                        "es": "Español",           "es-la": "Español (Latino)",
                        "en-us": "English (US)",   "en-gb": "English (GB)",
                        "en-sc": "English (Scotland)", "en-wls": "English (Wales)",
                        "fr": "Français",          "fr-be": "Français (Belgique)",
                        "fr-ch": "Français (Suisse)",
                        "pt": "Português (BR)",    "pt-pt": "Português (PT)"
                    }
                    return map[id] || id
                }

                onVisibleChanged: if (visible) _refreshVoices()
                on_EffLangChanged: _refreshVoices()

                Column {
                    id: ttsColumn
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1)

                    // ── Idioma de voz ──────────────────────────────────────
                    Label { text: i18n.tr("Idioma de voz"); color: "white"; font.pixelSize: ts(1.8) }

                    Grid {
                        id: langGrid
                        columns: 3; spacing: units.gu(0.8); width: parent.width
                        Repeater {
                            model: [
                                { key: "system", label: i18n.tr("Sistema") },
                                { key: "es",     label: "Español"   },
                                { key: "en",     label: "English"   },
                                { key: "fr",     label: "Français"  },
                                { key: "de",     label: "Deutsch"   },
                                { key: "pt",     label: "Português" },
                                { key: "it",     label: "Italiano"  },
                                { key: "ca",     label: "Català"    },
                                { key: "eu",     label: "Euskera"   },
                                { key: "ru",     label: "Русский"   },
                                { key: "zh",     label: "中文"      },
                                { key: "ar",     label: "العربية"   },
                                { key: "fa",     label: "فارسی"     }
                            ]
                            delegate: Rectangle {
                                property string k: modelData.key
                                width: (langGrid.width - 2 * units.gu(0.8)) / 3
                                height: units.gu(4.5); radius: units.gu(0.6)
                                color:        panel.cfg && panel.cfg.ttsLang === k ? "#1E3A5F" : "#2A2A3E"
                                border.color: panel.cfg && panel.cfg.ttsLang === k ? "#29B6F6" : "transparent"
                                border.width: units.gu(0.15)
                                Label {
                                    anchors.centerIn: parent
                                    text: modelData.label + (modelData.key === "system" ? " ↺" : "")
                                    color: panel.cfg && panel.cfg.ttsLang === k ? "#29B6F6" : "#78909C"
                                    font.pixelSize: ts(1.8)
                                    font.bold: panel.cfg && panel.cfg.ttsLang === k
                                    elide: Text.ElideRight
                                    width: parent.width - units.gu(0.6)
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (!panel.cfg) return
                                        panel.cfg.ttsLang = k
                                        panel.langChanged(k)
                                    }
                                }
                            }
                        }
                    }

                    // ── Selector voz Piper ─────────────────────────────────
                    Column {
                        id: voiceSel
                        property var  _r:    parent.parent
                        property bool _open: false
                        width: parent.width; spacing: units.gu(0.5)
                        visible: panel.cfg && panel.cfg.prefLevel >= 1
                                 && _r && _r._piperVoices && _r._piperVoices.length > 1
                                 && (panel.cfg.ttsEngine === "auto" || panel.cfg.ttsEngine === "piper")

                        Label { text: i18n.tr("Voz Piper"); color: "white"; font.pixelSize: ts(1.8) }

                        Rectangle {
                            width: parent.width; height: units.gu(5); radius: units.gu(0.6)
                            color: "#1A2535"; border.color: "#29B6F6"; border.width: units.gu(0.12)
                            Row {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                                          leftMargin: units.gu(1.2); rightMargin: units.gu(1) }
                                Label {
                                    width: parent.width - units.gu(2.5)
                                    text: {
                                        if (!panel.cfg || panel.cfg.ttsVoice === "") return i18n.tr("Automático")
                                        return voiceSel._r ? voiceSel._r._voiceLabel(panel.cfg.ttsVoice) : panel.cfg.ttsVoice
                                    }
                                    color: "#29B6F6"; font.pixelSize: ts(1.7); elide: Text.ElideRight
                                }
                                Label { text: voiceSel._open ? "▲" : "▼"; color: "#29B6F6"; font.pixelSize: ts(1.4)
                                        anchors.verticalCenter: parent.verticalCenter }
                            }
                            MouseArea { anchors.fill: parent; onClicked: voiceSel._open = !voiceSel._open }
                        }

                        Column {
                            visible: voiceSel._open
                            width: parent.width; spacing: units.gu(0.3)
                            Repeater {
                                model: voiceSel._r ? voiceSel._r._piperVoices : []
                                delegate: Rectangle {
                                    property string vid: modelData
                                    property bool   sel: panel.cfg && panel.cfg.ttsVoice === vid
                                    width: parent.width; height: units.gu(4.5); radius: units.gu(0.5)
                                    color:        sel ? "#1E3A5F" : "#151525"
                                    border.color: sel ? "#29B6F6" : "#22334455"; border.width: units.gu(0.1)
                                    Row {
                                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(1) }
                                        spacing: units.gu(0.6)
                                        Label { text: sel ? "●" : "○"; color: sel ? "#29B6F6" : "#546E7A"
                                                font.pixelSize: ts(1.4); anchors.verticalCenter: parent.verticalCenter }
                                        Label {
                                            text: voiceSel._r ? voiceSel._r._voiceLabel(vid) : vid
                                            color: sel ? "#29B6F6" : "#90A4AE"
                                            font.pixelSize: ts(1.6); font.bold: sel
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (!panel.cfg) return
                                            panel.cfg.ttsVoice = vid
                                            panel.voiceSelected(vid)
                                            voiceSel._open = false
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Selector voz PicoTTS ───────────────────────────────
                    Column {
                        id: picoVoiceSel
                        property var  _r:    parent.parent
                        property bool _open: false
                        width: parent.width; spacing: units.gu(0.5)
                        visible: panel.cfg && panel.cfg.prefLevel >= 1
                                 && _r && _r._picoVoices && _r._picoVoices.length > 0
                                 && panel.cfg.ttsEngine === "picotts"

                        Label { text: i18n.tr("Voz PicoTTS"); color: "white"; font.pixelSize: ts(1.8) }

                        Rectangle {
                            width: parent.width; height: units.gu(5); radius: units.gu(0.6)
                            color: "#1A2535"; border.color: "#29B6F6"; border.width: units.gu(0.12)
                            Row {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                                          leftMargin: units.gu(1.2); rightMargin: units.gu(1) }
                                Label {
                                    width: parent.width - units.gu(2.5)
                                    text: {
                                        if (!panel.cfg || panel.cfg.ttsVoicePico === "") return i18n.tr("Automático")
                                        return picoVoiceSel._r ? picoVoiceSel._r._picoVoiceLabel(panel.cfg.ttsVoicePico)
                                                               : panel.cfg.ttsVoicePico
                                    }
                                    color: "#29B6F6"; font.pixelSize: ts(1.7); elide: Text.ElideRight
                                }
                                Label { text: picoVoiceSel._open ? "▲" : "▼"; color: "#29B6F6"; font.pixelSize: ts(1.4)
                                        anchors.verticalCenter: parent.verticalCenter }
                            }
                            MouseArea { anchors.fill: parent; onClicked: picoVoiceSel._open = !picoVoiceSel._open }
                        }

                        Column {
                            visible: picoVoiceSel._open
                            width: parent.width; spacing: units.gu(0.3)
                            Repeater {
                                model: picoVoiceSel._r ? picoVoiceSel._r._picoVoices : []
                                delegate: Rectangle {
                                    property string vid: modelData
                                    property bool   sel: panel.cfg && panel.cfg.ttsVoicePico === vid
                                    width: parent.width; height: units.gu(4.5); radius: units.gu(0.5)
                                    color:        sel ? "#1E3A5F" : "#151525"
                                    border.color: sel ? "#29B6F6" : "#22334455"; border.width: units.gu(0.1)
                                    Row {
                                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(1) }
                                        spacing: units.gu(0.6)
                                        Label { text: sel ? "●" : "○"; color: sel ? "#29B6F6" : "#546E7A"
                                                font.pixelSize: ts(1.4); anchors.verticalCenter: parent.verticalCenter }
                                        Label {
                                            text: picoVoiceSel._r ? picoVoiceSel._r._picoVoiceLabel(vid) : vid
                                            color: sel ? "#29B6F6" : "#90A4AE"
                                            font.pixelSize: ts(1.6); font.bold: sel
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (!panel.cfg) return
                                            panel.cfg.ttsVoicePico = vid
                                            panel.voicePicoSelected(vid)
                                            picoVoiceSel._open = false
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Selector voz espeak-ng ─────────────────────────────
                    Column {
                        id: espeakVoiceSel
                        property var  _r:    parent.parent
                        property bool _open: false
                        width: parent.width; spacing: units.gu(0.5)
                        visible: panel.cfg && panel.cfg.prefLevel >= 1
                                 && _r && _r._espeakVoices && _r._espeakVoices.length > 0
                                 && panel.cfg.ttsEngine === "espeak"

                        Label { text: i18n.tr("Voz espeak-ng"); color: "white"; font.pixelSize: ts(1.8) }

                        Rectangle {
                            width: parent.width; height: units.gu(5); radius: units.gu(0.6)
                            color: "#1A2535"; border.color: "#29B6F6"; border.width: units.gu(0.12)
                            Row {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                                          leftMargin: units.gu(1.2); rightMargin: units.gu(1) }
                                Label {
                                    width: parent.width - units.gu(2.5)
                                    text: {
                                        if (!panel.cfg || panel.cfg.ttsVoiceEspeak === "") return i18n.tr("Automático")
                                        return espeakVoiceSel._r ? espeakVoiceSel._r._espeakVoiceLabel(panel.cfg.ttsVoiceEspeak)
                                                                 : panel.cfg.ttsVoiceEspeak
                                    }
                                    color: "#29B6F6"; font.pixelSize: ts(1.7); elide: Text.ElideRight
                                }
                                Label { text: espeakVoiceSel._open ? "▲" : "▼"; color: "#29B6F6"; font.pixelSize: ts(1.4)
                                        anchors.verticalCenter: parent.verticalCenter }
                            }
                            MouseArea { anchors.fill: parent; onClicked: espeakVoiceSel._open = !espeakVoiceSel._open }
                        }

                        Column {
                            visible: espeakVoiceSel._open
                            width: parent.width; spacing: units.gu(0.3)
                            Repeater {
                                model: espeakVoiceSel._r ? espeakVoiceSel._r._espeakVoices : []
                                delegate: Rectangle {
                                    property string vid: modelData
                                    property bool   sel: panel.cfg && panel.cfg.ttsVoiceEspeak === vid
                                    width: parent.width; height: units.gu(4.5); radius: units.gu(0.5)
                                    color:        sel ? "#1E3A5F" : "#151525"
                                    border.color: sel ? "#29B6F6" : "#22334455"; border.width: units.gu(0.1)
                                    Row {
                                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(1) }
                                        spacing: units.gu(0.6)
                                        Label { text: sel ? "●" : "○"; color: sel ? "#29B6F6" : "#546E7A"
                                                font.pixelSize: ts(1.4); anchors.verticalCenter: parent.verticalCenter }
                                        Label {
                                            text: espeakVoiceSel._r ? espeakVoiceSel._r._espeakVoiceLabel(vid) : vid
                                            color: sel ? "#29B6F6" : "#90A4AE"
                                            font.pixelSize: ts(1.6); font.bold: sel
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (!panel.cfg) return
                                            panel.cfg.ttsVoiceEspeak = vid
                                            panel.voiceEspeakSelected(vid)
                                            espeakVoiceSel._open = false
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Indicador procesando voz ───────────────────────────
                    Rectangle {
                        width: parent.width
                        height: panel.ttsProcessing ? units.gu(4) : 0
                        clip: true; color: "transparent"
                        Behavior on height { NumberAnimation { duration: 180 } }
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: units.gu(1)
                            ActivityIndicator {
                                running: panel.ttsProcessing
                                width: units.gu(2.2); height: units.gu(2.2)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Label {
                                text: i18n.tr("Procesando voz…")
                                color: "#29B6F6"; font.pixelSize: ts(1.6)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    // ── Motor TTS ──────────────────────────────────────────
                    Label {
                        visible: panel.cfg && panel.cfg.prefLevel >= 1
                        text: i18n.tr("Motor TTS"); color: "white"; font.pixelSize: ts(1.8)
                    }

                    Column {
                        visible: panel.cfg && panel.cfg.prefLevel >= 1
                        width: parent.width; spacing: units.gu(0.8)
                        Row {
                            width: parent.width; spacing: units.gu(0.8)
                            Repeater {
                                model: [
                                    { key: "auto",  label: "Auto ↺" },
                                    { key: "piper", label: "Piper"   },
                                    { key: "mimic", label: "Mimic"   }
                                ]
                                delegate: Rectangle {
                                    property string k:   modelData.key
                                    property bool   sel: panel.cfg && panel.cfg.ttsEngine === k
                                    width: (parent.width - 2 * units.gu(0.8)) / 3
                                    height: units.gu(4.5); radius: units.gu(0.6)
                                    color:        sel ? "#1E3A5F" : "#2A2A3E"
                                    border.color: sel ? "#29B6F6" : "transparent"; border.width: units.gu(0.15)
                                    Label {
                                        anchors.centerIn: parent; text: modelData.label
                                        color: sel ? "#29B6F6" : "#78909C"
                                        font.pixelSize: ts(1.7); font.bold: sel
                                        elide: Text.ElideRight
                                        width: parent.width - units.gu(0.4)
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (!panel.cfg) return
                                            panel.cfg.ttsEngine = k
                                            panel.engineChanged(k)
                                        }
                                    }
                                }
                            }
                        }
                        Row {
                            width: parent.width; spacing: units.gu(0.8)
                            Repeater {
                                model: [
                                    { key: "picotts", label: "PicoTTS"   },
                                    { key: "espeak",  label: "espeak-ng" }
                                ]
                                delegate: Rectangle {
                                    property string k:   modelData.key
                                    property bool   sel: panel.cfg && panel.cfg.ttsEngine === k
                                    width: (parent.width - units.gu(0.8)) / 2
                                    height: units.gu(4.5); radius: units.gu(0.6)
                                    color:        sel ? "#1E3A5F" : "#2A2A3E"
                                    border.color: sel ? "#29B6F6" : "transparent"; border.width: units.gu(0.15)
                                    Label {
                                        anchors.centerIn: parent; text: modelData.label
                                        color: sel ? "#29B6F6" : "#78909C"
                                        font.pixelSize: ts(1.7); font.bold: sel
                                        elide: Text.ElideRight
                                        width: parent.width - units.gu(0.4)
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (!panel.cfg) return
                                            panel.cfg.ttsEngine = k
                                            panel.engineChanged(k)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Botones ────────────────────────────────────────────
                    Rectangle {
                        visible: panel.cfg && panel.cfg.prefLevel >= 0
                        width: parent.width; height: units.gu(5); radius: units.gu(0.8); color: "#1565C3"
                        Label { anchors.centerIn: parent; text: i18n.tr("Gestionar voces TTS"); color: "white"; font.pixelSize: ts(1.9) }
                        MouseArea { anchors.fill: parent; onClicked: panel.voicesRequested() }
                    }

                    Rectangle {
                        visible: panel.cfg && panel.cfg.prefLevel >= 1
                        id: audioCacheBtn
                        width: parent.width; height: units.gu(5); radius: units.gu(0.8)
                        color: _confirm ? "#4A3010" : "#37474F"
                        property bool _confirm: false
                        property bool _done: false
                        Timer { interval: 4000; running: parent._confirm && !parent._done; onTriggered: parent._confirm = false }
                        Timer { interval: 2500; running: parent._done; onTriggered: parent._done = false }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Label {
                            anchors.centerIn: parent
                            text:  audioCacheBtn._done    ? "✓ " + i18n.tr("Caché eliminada")
                                 : audioCacheBtn._confirm ? "⚠ " + i18n.tr("Toca de nuevo para confirmar")
                                 :                          i18n.tr("Limpiar caché audio en ruta")
                            color: audioCacheBtn._done    ? "#66BB6A"
                                 : audioCacheBtn._confirm ? "#FFCC02"
                                 :                         "white"
                            font.pixelSize: ts(1.9)
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (audioCacheBtn._confirm) { panel.clearLiveCacheRequested(); audioCacheBtn._done = true; audioCacheBtn._confirm = false }
                                else { audioCacheBtn._confirm = true }
                            }
                        }
                    }
                }
            }
        } // Column Voz

        // ════════════════════════════════════════════════════════════════
        // MEDIA
        // ════════════════════════════════════════════════════════════════
        Rectangle {
            visible: mediaColContent.hasContent
            width: parent.width; height: units.gu(5.5)
            color: "#252535"; radius: units.gu(1)
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                text: i18n.tr("Media")
                color: "#29B6F6"; font.pixelSize: ts(2.0); font.bold: true
            }
            Label {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: units.gu(2) }
                text: secSettings.media ? "▲" : "▼"
                color: "#29B6F6"; font.pixelSize: ts(1.6)
            }
            MouseArea { anchors.fill: parent; onClicked: secSettings.media = !secSettings.media }
        }

        Column {
            id: mediaColContent
            property int  _sectionMinLevel: 1
            property bool hasContent: panel.cfg ? panel.cfg.prefLevel >= _sectionMinLevel : false
            visible: secSettings.media && hasContent
            width: parent.width; spacing: units.gu(1.5)

            // ── Volumen durante locuciones ────────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.prefLevel >= 1
                width: parent.width; height: dvCol.implicitHeight + units.gu(4)
                color: "#1C1C2E"; radius: units.gu(1)
                Column {
                    id: dvCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(0.8)
                    Row {
                        width: parent.width
                        Label {
                            text: i18n.tr("Volumen al hablar")
                            color: "white"; font.pixelSize: ts(1.8)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Item { width: parent.width - duckPctLbl.width - units.gu(16); height: 1 }
                        Label {
                            id: duckPctLbl
                            textFormat: Text.RichText
                            text: panel.cfg ? ("<b>" + Math.round(panel.cfg.duckVolume * 100) + "%</b> <font color='#546E7A'>↺ 70%</font>") : "70%"
                            color: "#29B6F6"; font.pixelSize: ts(1.7)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Item {
                        id: dvCtrl
                        width: parent.width; height: units.gu(4)
                        property int _dir: 0
                        Timer { interval: 200; repeat: true; running: dvCtrl._dir !== 0
                            onTriggered: if (panel.cfg) panel.cfg.duckVolume = Math.max(0.10, Math.min(1.00, Math.round((panel.cfg.duckVolume + 0.05 * dvCtrl._dir) / 0.05) * 0.05))
                        }
                        Rectangle {
                            id: dvMinusBtn
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            width: units.gu(5); height: units.gu(4); radius: units.gu(0.6)
                            color: dvMinus.pressed ? "#1E3A5F" : "#2A2A3E"; border.color: "#37474F"; border.width: 1
                            Label { anchors.centerIn: parent; text: "−"; color: "#29B6F6"; font.pixelSize: ts(2.5); font.bold: true }
                            MouseArea { id: dvMinus; anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.duckVolume = Math.max(0.10, Math.min(1.00, Math.round((panel.cfg.duckVolume - 0.05) / 0.05) * 0.05))
                                onPressAndHold: dvCtrl._dir = -1
                                onReleased: dvCtrl._dir = 0 }
                        }
                        Rectangle {
                            anchors { left: dvMinusBtn.right; right: dvPlusBtn.left; verticalCenter: parent.verticalCenter; margins: units.gu(1) }
                            height: units.gu(0.5); radius: height / 2; color: "#37474F"
                            Rectangle {
                                width: panel.cfg ? (panel.cfg.duckVolume - 0.10) / 0.90 * parent.width : 0
                                height: parent.height; radius: parent.radius; color: "#29B6F6"
                            }
                        }
                        Rectangle {
                            id: dvPlusBtn
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: units.gu(5); height: units.gu(4); radius: units.gu(0.6)
                            color: dvPlus.pressed ? "#1E3A5F" : "#2A2A3E"; border.color: "#37474F"; border.width: 1
                            Label { anchors.centerIn: parent; text: "+"; color: "#29B6F6"; font.pixelSize: ts(2.5); font.bold: true }
                            MouseArea { id: dvPlus; anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.duckVolume = Math.max(0.10, Math.min(1.00, Math.round((panel.cfg.duckVolume + 0.05) / 0.05) * 0.05))
                                onPressAndHold: dvCtrl._dir = 1
                                onReleased: dvCtrl._dir = 0 }
                        }
                    }
                }
            }
        } // Column Media

        // ════════════════════════════════════════════════════════════════
        // CUENTA NAVIUS
        // ════════════════════════════════════════════════════════════════
        Rectangle {
            visible: cuentaCol.hasContent
            width: parent.width; height: units.gu(5.5)
            color: "#252535"; radius: units.gu(1)
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                text: i18n.tr("Cuenta Navius")
                color: "#29B6F6"; font.pixelSize: ts(2.0); font.bold: true
            }
            Label {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: units.gu(2) }
                text: secSettings.cuenta ? "▲" : "▼"
                color: "#29B6F6"; font.pixelSize: ts(1.6)
            }
            MouseArea { anchors.fill: parent; onClicked: secSettings.cuenta = !secSettings.cuenta }
        }

        Column {
            id: cuentaCol
            property int  _sectionMinLevel: 0
            property bool hasContent: panel.cfg ? panel.cfg.prefLevel >= _sectionMinLevel : false
            visible: secSettings.cuenta && hasContent
            width: parent.width; spacing: units.gu(1.5)

            // Estado de sesión
            Rectangle {
                width: parent.width; height: units.gu(6)
                color: "#131F2E"; radius: units.gu(0.8)
                border.color: "#1E3A5F"
                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                    spacing: units.gu(1.5)
                    Label { text: authSettings.token !== "" ? "✅" : "👤"; font.pixelSize: ts(2.5); anchors.verticalCenter: parent.verticalCenter }
                    Label {
                        text: authSettings.token !== "" ? authSettings.email : i18n.tr("No identificado")
                        color: authSettings.token !== "" ? "#66BB6A" : "#90A4AE"
                        font.pixelSize: ts(2.0); anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // Botón entrar / cerrar sesión
            Rectangle {
                width: parent.width; height: units.gu(5.5); radius: units.gu(0.8)
                color: cuentaAccMa.pressed ? "#1A2535" : "#131F2E"
                border.color: "#1E3A5F"
                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                    spacing: units.gu(1.5)
                    Label { text: authSettings.token !== "" ? "🚪" : "🔑"; font.pixelSize: ts(2.2); anchors.verticalCenter: parent.verticalCenter }
                    Label {
                        text: authSettings.token !== "" ? i18n.tr("Cerrar sesión") : i18n.tr("Iniciar sesión / Registro")
                        color: "white"; font.pixelSize: ts(1.9); anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Label {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: units.gu(2) }
                    text: "▶"; color: "#29B6F6"; font.pixelSize: ts(1.6)
                }
                MouseArea {
                    id: cuentaAccMa; anchors.fill: parent
                    onClicked: {
                        if (authSettings.token !== "") {
                            authSettings.token = ""
                            authSettings.email = ""
                        } else {
                            panel.loginRequested()
                        }
                    }
                }
            }
        } // Column cuenta

        // ════════════════════════════════════════════════════════════════
        // AYUDA
        // ════════════════════════════════════════════════════════════════
        Rectangle {
            visible: ayudaCol.hasContent
            width: parent.width; height: units.gu(5.5)
            color: "#252535"; radius: units.gu(1)
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                text: i18n.tr("Ayuda")
                color: "#29B6F6"; font.pixelSize: ts(2.0); font.bold: true
            }
            Label {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: units.gu(2) }
                text: secSettings.ayuda ? "▲" : "▼"
                color: "#29B6F6"; font.pixelSize: ts(1.6)
            }
            MouseArea { anchors.fill: parent; onClicked: secSettings.ayuda = !secSettings.ayuda }
        }

        Column {
            id: ayudaCol
            property int  _sectionMinLevel: 0
            property bool hasContent: panel.cfg ? panel.cfg.prefLevel >= _sectionMinLevel : false
            visible: secSettings.ayuda && hasContent
            width: parent.width; spacing: units.gu(1.5)

            // ── Manual de usuario ─────────────────────────────────────────
            Rectangle {
                width: parent.width; height: units.gu(5.5); radius: units.gu(0.8)
                color: helpMa.pressed ? "#1A2535" : "#131F2E"
                border.color: "#1E3A5F"; border.width: 1

                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                    spacing: units.gu(1.5)
                    Label { text: "📖"; font.pixelSize: ts(2.2); anchors.verticalCenter: parent.verticalCenter }
                    Label {
                        text: i18n.tr("Manual de usuario")
                        color: "white"; font.pixelSize: ts(1.9)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Label {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: units.gu(2) }
                    text: "▶"; color: "#29B6F6"; font.pixelSize: ts(1.6)
                }
                MouseArea { id: helpMa; anchors.fill: parent; onClicked: panel.helpRequested() }
            }

            // ── Asistente de bienvenida ───────────────────────────────────
            Rectangle {
                width: parent.width; height: units.gu(5.5); radius: units.gu(0.8)
                color: tourMa.pressed ? "#1A2535" : "#131F2E"
                border.color: "#1E3A5F"; border.width: 1

                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                    spacing: units.gu(1.5)
                    Label { text: "🧭"; font.pixelSize: ts(2.2); anchors.verticalCenter: parent.verticalCenter }
                    Label {
                        text: i18n.tr("Abrir asistente")
                        color: "white"; font.pixelSize: ts(1.9)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Label {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: units.gu(2) }
                    text: "▶"; color: "#29B6F6"; font.pixelSize: ts(1.6)
                }
                MouseArea { id: tourMa; anchors.fill: parent; onClicked: panel.tourRequested() }
            }

            // ── Mostrar asistente al inicio ───────────────────────────────
            Rectangle {
                width: parent.width; height: units.gu(5.5); radius: units.gu(0.8)
                color: "#131F2E"; border.color: "#1E3A5F"; border.width: 1

                Row {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: units.gu(2); rightMargin: units.gu(1.5) }
                    spacing: units.gu(1)
                    Label {
                        text: i18n.tr("Mostrar asistente al inicio")
                        color: "#CFD8DC"; font.pixelSize: ts(1.8)
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(9)
                        wrapMode: Text.WordWrap
                    }
                    Switch {
                        id: tourStartSwitch
                        anchors.verticalCenter: parent.verticalCenter
                        checked: tourSt.showOnStart
                        onCheckedChanged: tourSt.showOnStart = checked
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        tourSt.showOnStart = !tourSt.showOnStart
                        tourStartSwitch.checked = tourSt.showOnStart
                    }
                }
            }

            // ── Acerca de… ────────────────────────────────────────────────
            Rectangle {
                width: parent.width; height: units.gu(5.5); radius: units.gu(0.8)
                color: aboutMa.pressed ? "#1A2535" : "#131F2E"
                border.color: "#1E3A5F"; border.width: 1

                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                    spacing: units.gu(1.5)
                    Label { text: "ℹ️"; font.pixelSize: ts(2.2); anchors.verticalCenter: parent.verticalCenter }
                    Label {
                        text: i18n.tr("Acerca de…")
                        color: "white"; font.pixelSize: ts(1.9)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Label {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: units.gu(2) }
                    text: "▶"; color: "#29B6F6"; font.pixelSize: ts(1.6)
                }
                MouseArea { id: aboutMa; anchors.fill: parent; onClicked: panel.aboutRequested() }
            }

        } // Column Ayuda

        // ════════════════════════════════════════════════════════════════
        // DEBUG
        // ════════════════════════════════════════════════════════════════
        Rectangle {
            visible: debugCol.hasContent
            width: parent.width; height: units.gu(5.5)
            color: "#252535"; radius: units.gu(1)
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                text: i18n.tr("Debug")
                color: "#29B6F6"; font.pixelSize: ts(2.0); font.bold: true
            }
            Label {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: units.gu(2) }
                text: secSettings.debug ? "▲" : "▼"
                color: "#29B6F6"; font.pixelSize: ts(1.6)
            }
            MouseArea { anchors.fill: parent; onClicked: secSettings.debug = !secSettings.debug }
        }

        Column {
            id: debugCol
            property int  _sectionMinLevel: 2
            property bool hasContent: panel.cfg ? panel.cfg.prefLevel >= _sectionMinLevel : false
            visible: secSettings.debug && hasContent
            width: parent.width; spacing: units.gu(1.5)

            // ── Modo debug ───────────────────────────────────────────────
            Rectangle {
                width: parent.width; height: units.gu(8)
                color: "#1C1C2E"; radius: units.gu(1)
                Row {
                    anchors { fill: parent; margins: units.gu(2) }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(7)
                        Label { text: i18n.tr("Modo Debug"); color: "white"; font.pixelSize: ts(1.8) }
                        Label {
                            text: i18n.tr("Sim GPS, POI")
                            color: "#90A4AE"; font.pixelSize: ts(1.8)
                            wrapMode: Text.WordWrap; width: parent.width
                        }
                    }
                    Item { width: units.gu(1); height: 1 }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(5.5); height: units.gu(3); radius: height / 2
                        color: panel.cfg && panel.cfg.debugMode ? "#1565C0" : "#37474F"
                        Rectangle {
                            width: units.gu(2.4); height: units.gu(2.4); radius: width / 2; color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                            x: panel.cfg && panel.cfg.debugMode ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (!panel.cfg) return
                                panel.cfg.debugMode = !panel.cfg.debugMode
                                if (!panel.cfg.debugMode) {
                                    panel.cfg.simMode = false
                                    if (panel.cfg.manualPosActive) panel.manualPosCleared()
                                    panel.debugOff()
                                } else {
                                    panel.debugOn()
                                }
                            }
                        }
                    }
                }
            }

            // ── Activar trazas y TUI ─────────────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.debugMode
                width: parent.width; height: units.gu(8)
                color: "#1C1C2E"; radius: units.gu(1)
                Row {
                    anchors { fill: parent; margins: units.gu(2) }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(7)
                        Label { text: i18n.tr("Activar trazas y TUI"); color: "white"; font.pixelSize: ts(1.8) }
                        Label {
                            text: i18n.tr("net_debug.log · tts_debug.log · piper_limit.log · control remoto")
                            color: "#90A4AE"; font.pixelSize: ts(1.5)
                            wrapMode: Text.WordWrap; width: parent.width
                        }
                    }
                    Item { width: units.gu(1); height: 1 }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(5.5); height: units.gu(3); radius: height / 2
                        color: panel.cfg && panel.cfg.tracesEnabled ? "#1565C0" : "#37474F"
                        Rectangle {
                            width: units.gu(2.4); height: units.gu(2.4); radius: width / 2; color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                            x: panel.cfg && panel.cfg.tracesEnabled ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { if (panel.cfg) panel.cfg.tracesEnabled = !panel.cfg.tracesEnabled }
                        }
                    }
                }
            }

            // ── Simulación GPS ───────────────────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.debugMode
                width: parent.width; height: units.gu(11)
                color: "#1C1C2E"; radius: units.gu(1)
                Row {
                    anchors { fill: parent; margins: units.gu(2) }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(7)
                        Label { text: i18n.tr("Simulación GPS"); color: "white"; font.pixelSize: ts(1.8) }
                        Label { text: i18n.tr("Muntaner → Gran Via (Barcelona)"); color: "#90A4AE"; font.pixelSize: ts(1.8) }
                        Label {
                            text: i18n.tr("Sustituye al GPS real para pruebas en interior")
                            color: "#90A4AE"; font.pixelSize: ts(1.8)
                            wrapMode: Text.WordWrap; width: parent.width
                        }
                    }
                    Item { width: units.gu(1); height: 1 }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(5.5); height: units.gu(3); radius: height / 2
                        color: panel.cfg && panel.cfg.simMode ? "#9C27B0" : "#37474F"
                        Rectangle {
                            width: units.gu(2.4); height: units.gu(2.4); radius: width / 2; color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                            x: panel.cfg && panel.cfg.simMode ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (!panel.cfg) return
                                panel.cfg.simMode = !panel.cfg.simMode
                                if (!panel.cfg.simMode && panel.cfg.manualPosActive) panel.manualPosCleared()
                                panel.simToggled(panel.cfg.simMode)
                            }
                        }
                    }
                }
            }

            // ── Ruta de simulación ───────────────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.debugMode && panel.cfg.simMode
                width: parent.width
                height: routeSelCol.implicitHeight + units.gu(4)
                color: "#1C1C2E"; radius: units.gu(1)
                Column {
                    id: routeSelCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Label { text: i18n.tr("Ruta de simulación"); color: "white"; font.pixelSize: ts(1.8) }
                    OptionSelector {
                        id: routeSelector
                        width: parent.width
                        model: [
                            "Muntaner → Gran Via (BCN)",
                            "Test radar fijo 1",
                            "Test radar fijo 2",
                            "Test radar tramo",
                            "Ruta del usuario"
                        ]
                        selectedIndex: panel.cfg ? panel.cfg.simRouteIdx : 0
                        onSelectedIndexChanged: {
                            if (panel.cfg && selectedIndex !== panel.cfg.simRouteIdx)
                                panel.simRouteChanged(selectedIndex)
                        }
                    }
                    Rectangle {
                        width: parent.width; height: units.gu(5); radius: units.gu(0.6); color: "#1565C3"
                        Label { anchors.centerIn: parent; text: i18n.tr("Aplicar ruta"); color: "white"; font.pixelSize: ts(1.8); font.bold: true }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { if (panel.cfg) panel.simRouteChanged(routeSelector.selectedIndex) }
                        }
                    }
                    Label {
                        text: i18n.tr("Grabaciones en sim"); color: "#90A4AE"; font.pixelSize: ts(1.6)
                        visible: {
                            try { return JSON.parse(panel.cfg ? panel.cfg.customSimTracks : "[]").length > 0 }
                            catch(e) { return false }
                        }
                    }
                    Repeater {
                        id: customSimRepeater
                        model: {
                            try { return JSON.parse(panel.cfg ? panel.cfg.customSimTracks : "[]") }
                            catch(e) { return [] }
                        }
                        delegate: Rectangle {
                            width: routeSelCol.width; height: units.gu(5); radius: units.gu(0.6)
                            color: panel.cfg && panel.cfg.simRouteIdx === (5 + index) ? "#1E3A5F" : "#2A2A3E"
                            border.color: panel.cfg && panel.cfg.simRouteIdx === (5 + index) ? "#29B6F6" : "transparent"
                            border.width: units.gu(0.12)
                            Row {
                                anchors { fill: parent; leftMargin: units.gu(1.2); rightMargin: units.gu(1) }
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - units.gu(4.5)
                                    text: modelData.name
                                    color: panel.cfg && panel.cfg.simRouteIdx === (5 + index) ? "#29B6F6" : "white"
                                    font.pixelSize: ts(1.7); elide: Text.ElideRight
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(3.5); height: units.gu(3.5); radius: width / 2; color: "#37474F"
                                    Label { anchors.centerIn: parent; text: "✕"; color: "#EF5350"; font.pixelSize: ts(1.8) }
                                    MouseArea { anchors.fill: parent; onClicked: panel.trackRemovedFromSim(index) }
                                }
                            }
                            MouseArea {
                                anchors { fill: parent; rightMargin: units.gu(5) }
                                onClicked: panel.simRouteChanged(5 + index)
                            }
                        }
                    }
                }
            }

            // ── Perder señal GPS ─────────────────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.debugMode && panel.cfg.simMode
                width: parent.width; height: units.gu(8)
                color: "#1C1C2E"; radius: units.gu(1)
                Row {
                    anchors { fill: parent; margins: units.gu(2) }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(7)
                        Label {
                            text: panel.simSignalLost ? i18n.tr("Señal perdida (simulado)") : i18n.tr("Perder señal GPS")
                            color: panel.simSignalLost ? "#FF5252" : "white"; font.pixelSize: ts(1.8)
                        }
                        Label {
                            text: panel.simSignalLost ? i18n.tr("El vehículo sigue avanzando internamente")
                                                      : i18n.tr("Simula túnel o zona sin cobertura")
                            color: "#90A4AE"; font.pixelSize: ts(1.8)
                            wrapMode: Text.WordWrap; width: parent.width
                        }
                    }
                    Item { width: units.gu(1); height: 1 }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(5.5); height: units.gu(3); radius: height / 2
                        color: panel.simSignalLost ? "#C62828" : "#37474F"
                        Rectangle {
                            width: units.gu(2.4); height: units.gu(2.4); radius: width / 2; color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                            x: panel.simSignalLost ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        MouseArea { anchors.fill: parent; onClicked: panel.signalLostToggled() }
                    }
                }
            }

            // ── Deslizable posición en ruta sim ──────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.debugMode && panel.cfg.simMode
                width: parent.width; height: units.gu(8)
                color: "#1C1C2E"; radius: units.gu(1)
                Row {
                    anchors { fill: parent; margins: units.gu(2) }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(7)
                        Label { text: i18n.tr("Deslizable posición en ruta sim"); color: "white"; font.pixelSize: ts(1.8) }
                        Label {
                            text: i18n.tr("Desplegable lateral para mover la posición GPS simulada")
                            color: "#90A4AE"; font.pixelSize: ts(1.8)
                            wrapMode: Text.WordWrap; width: parent.width
                        }
                    }
                    Item { width: units.gu(1); height: 1 }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(5.5); height: units.gu(3); radius: height / 2
                        color: panel.cfg && panel.cfg.showSimScrubber ? "#9C27B0" : "#37474F"
                        Rectangle {
                            width: units.gu(2.4); height: units.gu(2.4); radius: width / 2; color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                            x: panel.cfg && panel.cfg.showSimScrubber ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { if (panel.cfg) panel.cfg.showSimScrubber = !panel.cfg.showSimScrubber }
                        }
                    }
                }
            }

            // ── Velocidad mínima sim (km/h) ──────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.debugMode && panel.cfg.simMode
                width: parent.width
                height: minSpeedCol.implicitHeight + units.gu(4)
                color: "#1C1C2E"; radius: units.gu(1)
                Column {
                    id: minSpeedCol
                    anchors { fill: parent; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Label { text: i18n.tr("Velocidad mínima sim (km/h)"); color: "white"; font.pixelSize: ts(1.8) }
                    Row {
                        spacing: units.gu(1)
                        Repeater {
                            model: [0, 30, 50, 80, 120, 200]
                            Rectangle {
                                property int spd: modelData
                                property bool sel: panel.cfg && panel.cfg.simMinSpeedKmh === spd
                                width: units.gu(6.5); height: units.gu(4.5); radius: units.gu(0.6)
                                color:        sel ? "#1E3A5F" : "#2A2A3E"
                                border.color: sel ? "#9C27B0" : "transparent"; border.width: units.gu(0.15)
                                Label {
                                    anchors.centerIn: parent
                                    text: spd === 0 ? i18n.tr("Off") : spd
                                    color: sel ? "#CE93D8" : "#78909C"
                                    font.pixelSize: ts(1.8); font.bold: sel
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: { if (panel.cfg) panel.cfg.simMinSpeedKmh = spd }
                                }
                            }
                        }
                    }
                }
            }

            // ── Posición manual ──────────────────────────────────────────
            Rectangle {
                visible: panel.cfg && (panel.cfg.debugMode || panel.cfg.simMode)
                width: parent.width
                height: visible ? manPosCol.implicitHeight + units.gu(4) : 0
                color: "#1C1C2E"; radius: units.gu(1)
                Column {
                    id: manPosCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1.2)
                    Label { text: i18n.tr("Posición manual"); color: "white"; font.pixelSize: ts(1.8) }
                    Label {
                        visible: panel.cfg && panel.cfg.manualPosActive
                        width: parent.width
                        text: panel.cfg ? (panel.cfg.manualLat.toFixed(6) + ",  " + panel.cfg.manualLon.toFixed(6)) : ""
                        color: "#4CAF50"; font.pixelSize: ts(1.8); font.bold: true
                    }
                    TextField {
                        id: manLatField
                        width: parent.width
                        placeholderText: "Latitud  (ej. 40.322130)"
                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                        onActiveFocusChanged: if (activeFocus) panel._kbdFocusItem = this
                    }
                    TextField {
                        id: manLonField
                        width: parent.width
                        placeholderText: "Longitud  (ej. -3.515801)"
                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                        onActiveFocusChanged: if (activeFocus) panel._kbdFocusItem = this
                    }
                    Row {
                        width: parent.width; spacing: units.gu(1)
                        Rectangle {
                            width: (parent.width - units.gu(1)) / 2; height: units.gu(5)
                            radius: units.gu(0.6); color: "#1565C3"
                            Label { anchors.centerIn: parent; text: i18n.tr("Fijar"); color: "white"; font.pixelSize: ts(1.8); font.bold: true }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    var lat = parseFloat(manLatField.text)
                                    var lon = parseFloat(manLonField.text)
                                    if (!isNaN(lat) && !isNaN(lon) && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180)
                                        panel.manualPosApplied(lat, lon)
                                }
                            }
                        }
                        Rectangle {
                            width: (parent.width - units.gu(1)) / 2; height: units.gu(5)
                            radius: units.gu(0.6)
                            color: panel.cfg && panel.cfg.manualPosActive ? "#C62828" : "#37474F"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Label { anchors.centerIn: parent; text: i18n.tr("Liberar GPS"); color: "white"; font.pixelSize: ts(1.8); font.bold: true }
                            MouseArea { anchors.fill: parent; onClicked: panel.manualPosCleared() }
                        }
                    }
                }
            }

            // ── Panel debug velocidades (v_sim) ──────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.debugMode && panel.cfg.simMode
                width: parent.width; height: units.gu(8)
                color: "#1C1C2E"; radius: units.gu(1)
                Row {
                    anchors { fill: parent; margins: units.gu(2) }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(7)
                        Label { text: i18n.tr("Panel debug velocidades (v_sim)"); color: "white"; font.pixelSize: ts(1.8) }
                        Label {
                            text: i18n.tr("Muestra vValhalla, límite y velocidad genérica")
                            color: "#90A4AE"; font.pixelSize: ts(1.5)
                            wrapMode: Text.WordWrap; width: parent.width
                        }
                    }
                    Item { width: units.gu(1); height: 1 }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(5.5); height: units.gu(3); radius: height / 2
                        color: panel.cfg && panel.cfg.showVSimDebug ? "#9C27B0" : "#37474F"
                        Rectangle {
                            width: units.gu(2.4); height: units.gu(2.4); radius: width / 2; color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                            x: panel.cfg && panel.cfg.showVSimDebug ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { if (panel.cfg) panel.cfg.showVSimDebug = !panel.cfg.showVSimDebug }
                        }
                    }
                }
            }

            // ── Overlay límites de velocidad por tramo ───────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.debugMode
                width: parent.width; height: units.gu(8)
                color: "#1C1C2E"; radius: units.gu(1)
                Row {
                    anchors { fill: parent; margins: units.gu(2) }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(7)
                        Label { text: i18n.tr("Overlay límites de velocidad"); color: "white"; font.pixelSize: ts(1.8) }
                        Label {
                            text: i18n.tr("Muestra límite, velocidad Valhalla y fuente por tramo")
                            color: "#90A4AE"; font.pixelSize: ts(1.5)
                            wrapMode: Text.WordWrap; width: parent.width
                        }
                    }
                    Item { width: units.gu(1); height: 1 }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(5.5); height: units.gu(3); radius: height / 2
                        color: panel.cfg && panel.cfg.showSlDebug ? "#9C27B0" : "#37474F"
                        Rectangle {
                            width: units.gu(2.4); height: units.gu(2.4); radius: width / 2; color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                            x: panel.cfg && panel.cfg.showSlDebug ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { if (panel.cfg) panel.cfg.showSlDebug = !panel.cfg.showSlDebug }
                        }
                    }
                }
            }

            // ── Mostrar ticks GPS ────────────────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.debugMode
                width: parent.width; height: units.gu(8)
                color: "#1C1C2E"; radius: units.gu(1)
                Row {
                    anchors { fill: parent; margins: units.gu(2) }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(7)
                        Label { text: i18n.tr("Mostrar ticks GPS (isReal)"); color: "white"; font.pixelSize: ts(1.8) }
                        Label {
                            text: i18n.tr("Puntos cian en el mapa por cada fix real")
                            color: "#90A4AE"; font.pixelSize: ts(1.5)
                            wrapMode: Text.WordWrap; width: parent.width
                        }
                    }
                    Item { width: units.gu(1); height: 1 }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(5.5); height: units.gu(3); radius: height / 2
                        color: panel.cfg && panel.cfg.showGpsTicks ? "#00838F" : "#37474F"
                        Rectangle {
                            width: units.gu(2.4); height: units.gu(2.4); radius: width / 2; color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                            x: panel.cfg && panel.cfg.showGpsTicks ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { if (panel.cfg) panel.cfg.showGpsTicks = !panel.cfg.showGpsTicks }
                        }
                    }
                }
            }

            // ── Simulación de fallos GPS ─────────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.debugMode && panel.cfg.simMode
                width: parent.width
                height: visible ? gpsFailCol.implicitHeight + units.gu(4) : 0
                color: "#1C1C2E"; radius: units.gu(1)
                Column {
                    id: gpsFailCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1.2)
                    // Toggle
                    Row {
                        width: parent.width
                        Label {
                            text: i18n.tr("Simulación fallos GPS")
                            color: "white"; font.pixelSize: ts(1.8)
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - units.gu(7)
                        }
                        Item { width: units.gu(1); height: 1 }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: units.gu(5.5); height: units.gu(3); radius: height / 2
                            color: panel.cfg && panel.cfg.gpsFailEnabled ? "#1565C0" : "#37474F"
                            Rectangle {
                                width: units.gu(2.4); height: units.gu(2.4); radius: width / 2; color: "white"
                                anchors.verticalCenter: parent.verticalCenter
                                x: panel.cfg && panel.cfg.gpsFailEnabled ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                                Behavior on x { NumberAnimation { duration: 150 } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { if (panel.cfg) panel.cfg.gpsFailEnabled = !panel.cfg.gpsFailEnabled }
                            }
                        }
                    }
                    // Probabilidad
                    Label { text: i18n.tr("Probabilidad de fallo (%)"); color: "#90CAF9"; font.pixelSize: ts(1.6) }
                    TextField {
                        id: gpsFailProbField
                        width: parent.width
                        placeholderText: "ej. 5.00"
                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                        text: panel.cfg ? panel.cfg.gpsFailProb.toFixed(2) : "5.00"
                        onActiveFocusChanged: if (activeFocus) panel._kbdFocusItem = this
                        onTextChanged: {
                            var v = parseFloat(text)
                            if (!isNaN(v) && v >= 0 && v <= 100 && panel.cfg)
                                panel.cfg.gpsFailProb = v
                        }
                    }
                    // Distancia
                    Label { text: i18n.tr("Distancia de desvío (m)"); color: "#90CAF9"; font.pixelSize: ts(1.6) }
                    TextField {
                        id: gpsFailDistField
                        width: parent.width
                        placeholderText: "ej. 50"
                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                        text: panel.cfg ? panel.cfg.gpsFailDist.toFixed(0) : "50"
                        onActiveFocusChanged: if (activeFocus) panel._kbdFocusItem = this
                        onTextChanged: {
                            var v = parseFloat(text)
                            if (!isNaN(v) && v >= 0 && panel.cfg)
                                panel.cfg.gpsFailDist = v
                        }
                    }
                    // Ticks
                    Label { text: i18n.tr("Ticks sin señal (isReal=true)"); color: "#90CAF9"; font.pixelSize: ts(1.6) }
                    TextField {
                        id: gpsFailTicksField
                        width: parent.width
                        placeholderText: "ej. 3"
                        inputMethodHints: Qt.ImhDigitsOnly
                        text: panel.cfg ? panel.cfg.gpsFailTicks.toString() : "3"
                        onActiveFocusChanged: if (activeFocus) panel._kbdFocusItem = this
                        onTextChanged: {
                            var v = parseInt(text)
                            if (!isNaN(v) && v >= 1 && panel.cfg)
                                panel.cfg.gpsFailTicks = v
                        }
                    }
                }
            }

            // ── Test TTS ─────────────────────────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.debugMode
                width: parent.width
                height: units.gu(8); color: "#1C1C2E"; radius: units.gu(1)
                property string _ttsText: ""
                Row {
                    anchors { fill: parent; margins: units.gu(1.5) }
                    spacing: units.gu(1)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - ttsSayBtn.width - units.gu(1)
                        height: units.gu(5); radius: units.gu(0.6)
                        color: "#0D1B2A"; border.color: "#37474F"; border.width: 1
                        TextInput {
                            id: ttsTestInput
                            anchors { fill: parent; leftMargin: units.gu(1); rightMargin: units.gu(1) }
                            verticalAlignment: TextInput.AlignVCenter
                            color: "white"; font.pixelSize: ts(1.9)
                            onTextChanged: parent.parent.parent._ttsText = text
                            onAccepted: if (panel.ttsRef && parent.parent.parent._ttsText.length > 0)
                                            panel.ttsRef.say(parent.parent.parent._ttsText)
                            onActiveFocusChanged: if (activeFocus) panel._kbdFocusItem = this
                        }
                        Label {
                            anchors { fill: parent; leftMargin: units.gu(1) }
                            verticalAlignment: Text.AlignVCenter
                            visible: ttsTestInput.text.length === 0
                            text: i18n.tr("Texto para reproducir…")
                            color: "#90A4AE"; font.pixelSize: ts(1.9)
                        }
                    }
                    Rectangle {
                        id: ttsSayBtn
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(8); height: units.gu(5); radius: units.gu(0.6)
                        color: ttsSayMa.pressed ? "#1B5E20" : "#2E7D32"
                        Label { anchors.centerIn: parent; text: "▶ " + i18n.tr("Decir")
                                color: "white"; font.pixelSize: ts(1.9); font.bold: true }
                        MouseArea {
                            id: ttsSayMa; anchors.fill: parent
                            onClicked: if (panel.ttsRef && parent.parent.parent._ttsText.length > 0)
                                           panel.ttsRef.say(parent.parent.parent._ttsText)
                        }
                    }
                }
            }

            // ── Ficheros debug ────────────────────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.debugMode
                width: parent.width
                height: units.gu(4); color: "#1C1C2E"; radius: units.gu(1)
                Label {
                    anchors { left: parent.left; leftMargin: units.gu(2); verticalCenter: parent.verticalCenter }
                    text: i18n.tr("Ficheros debug")
                    color: "#90CAF9"; font.pixelSize: ts(2); font.bold: true
                }
            }

            // Borrar al salir
            Rectangle {
                visible: panel.cfg && panel.cfg.debugMode
                width: parent.width; height: units.gu(6.5); color: "#1C1C2E"; radius: units.gu(1)
                Row {
                    anchors { fill: parent; margins: units.gu(1.5) }
                    spacing: units.gu(1.5)
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - cleanExitToggle.width - units.gu(1.5)
                        text: i18n.tr("Borrar todos los ficheros debug al salir")
                        color: "white"; font.pixelSize: ts(1.9); wrapMode: Text.WordWrap
                    }
                    Rectangle {
                        id: cleanExitToggle
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(5.5); height: units.gu(3); radius: height / 2
                        color: panel.cfg && panel.cfg.debugCleanOnExit ? "#1565C0" : "#37474F"
                        Rectangle {
                            width: units.gu(2.4); height: units.gu(2.4); radius: width / 2; color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                            x: panel.cfg && panel.cfg.debugCleanOnExit ? parent.width - width - units.gu(0.3) : units.gu(0.3)
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { if (panel.cfg) panel.cfg.debugCleanOnExit = !panel.cfg.debugCleanOnExit }
                        }
                    }
                }
            }

            // Borrar todos
            Rectangle {
                id: dbgAllBtn
                visible: panel.cfg && panel.cfg.debugMode
                width: parent.width; height: units.gu(6.5); color: "#1C1C2E"; radius: units.gu(1)
                property bool _done: false
                Timer { interval: 2500; running: parent._done; onTriggered: parent._done = false }
                Row {
                    anchors { fill: parent; margins: units.gu(1.5) }
                    spacing: units.gu(1.5)
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * 0.55
                        text: i18n.tr("Todos los ficheros debug")
                        color: "white"; font.pixelSize: ts(1.9); wrapMode: Text.WordWrap
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - parent.width * 0.55 - units.gu(1.5); height: units.gu(4.5)
                        radius: units.gu(0.6)
                        color: dbgAllBtn._done ? "#2E7D32" : (dbgAllMa.pressed ? "#7B1FA2" : "#6A1B9A")
                        Label {
                            anchors.centerIn: parent
                            text: dbgAllBtn._done ? "✓ " + i18n.tr("Borrados") : i18n.tr("Borrar todo")
                            color: dbgAllBtn._done ? "#66BB6A" : "white"
                            font.pixelSize: ts(1.8); font.bold: true
                        }
                        MouseArea {
                            id: dbgAllMa; anchors.fill: parent
                            onClicked: { panel.debugFileDeleteRequested("all"); dbgAllBtn._done = true }
                        }
                    }
                }
            }

            Repeater {
                visible: panel.cfg && panel.cfg.debugMode
                model: panel.cfg && panel.cfg.debugMode ? [
                    { label: "navius_ack",         pattern: "navius_ack" },
                    { label: "navius_autostart",    pattern: "navius_autostart" },
                    { label: "navius_cmd",          pattern: "navius_cmd" },
                    { label: "navius_route",        pattern: "navius_route" },
                    { label: "navius_sl_debug.txt", pattern: "navius_sl_debug.txt" },
                    { label: "navius_trace*",       pattern: "navius_trace" },
                    { label: "net_debug.log",       pattern: "net_debug.log" },
                    { label: "piper_limit.log",     pattern: "piper_limit.log" },
                    { label: "tts_debug.log",       pattern: "tts_debug.log" }
                ] : []
                delegate: Rectangle {
                    visible: panel.cfg && panel.cfg.debugMode
                    width: parent ? parent.width : 0; height: units.gu(6); color: "#1C1C2E"; radius: units.gu(1)
                    property bool _done: false
                    Timer { interval: 2500; running: _done; onTriggered: _done = false }
                    Row {
                        anchors { fill: parent; margins: units.gu(1.5) }
                        spacing: units.gu(1.5)
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width * 0.62
                            text: modelData.label
                            color: "#B0BEC5"; font.pixelSize: ts(1.75)
                            elide: Text.ElideRight
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - parent.width * 0.62 - units.gu(1.5); height: units.gu(4)
                            radius: units.gu(0.6)
                            color: parent.parent._done ? "#1B5E20" : (delMa.pressed ? "#B71C1C" : "#C62828")
                            Label {
                                anchors.centerIn: parent
                                text: parent.parent.parent._done ? "✓ " + i18n.tr("Borrado") : i18n.tr("Borrar")
                                color: parent.parent.parent._done ? "#66BB6A" : "white"
                                font.pixelSize: ts(1.75); font.bold: true
                            }
                            MouseArea {
                                id: delMa; anchors.fill: parent
                                onClicked: {
                                    panel.debugFileDeleteRequested(modelData.pattern)
                                    parent.parent.parent._done = true
                                }
                            }
                        }
                    }
                }
            }

        } // Column Debug

    }
    } // Flickable
}
