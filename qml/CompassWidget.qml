import QtQuick 2.7
import Lomiri.Components 1.3

Item {
    id: compassWidget
    width:  units.gu(14)
    height: units.gu(14)

    property real   bearing:     0
    property bool   nightMode:   false
    property string bearingMode: "north"
    property bool   hasArrow:    false
    property real   dispHeadRad: 0

    signal northUpRequested()
    signal headingUpRequested()

    // ── Background circle ─────────────────────────────────────────────────
    Rectangle { anchors.fill: parent; radius: width / 2; color: "#B3455A64" }

    // ── Compass ring ──────────────────────────────────────────────────────
    Canvas {
        id: compassCanvas
        anchors.fill: parent
        rotation: -compassWidget.bearing

        property bool nightMode: compassWidget.nightMode
        onNightModeChanged: requestPaint()
        Component.onCompleted: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var cx = width / 2, cy = height / 2
            var R  = width / 2

            var colN    = "#EF5350"
            var colCard = "rgba(255,255,255,0.90)"
            var colDim  = nightMode ? "rgba(255,255,255,0.35)" : "rgba(69,90,100,0.35)"

            // Inner button border circle (drawn first so labels appear on top)
            ctx.beginPath()
            ctx.arc(cx, cy, R * 0.50, 0, 2 * Math.PI)
            ctx.strokeStyle = colCard
            ctx.lineWidth   = 1.5
            ctx.stroke()

            // Thin outer ring
            ctx.beginPath()
            ctx.arc(cx, cy, R * 0.94, 0, 2 * Math.PI)
            ctx.strokeStyle = colDim
            ctx.lineWidth   = 1
            ctx.stroke()

            // Intermediate ticks (NE, SE, SO, NO)
            var halfs = [-3*Math.PI/4, -Math.PI/4, Math.PI/4, 3*Math.PI/4]
            for (var j = 0; j < halfs.length; j++) {
                var ah = halfs[j]
                ctx.beginPath()
                ctx.moveTo(cx + R*0.86*Math.cos(ah), cy + R*0.86*Math.sin(ah))
                ctx.lineTo(cx + R*0.94*Math.cos(ah), cy + R*0.94*Math.sin(ah))
                ctx.strokeStyle = colDim
                ctx.lineWidth   = 1.0
                ctx.stroke()
            }

            // Cardinal ticks and labels
            var cards = [
                {a: -Math.PI/2, lbl: "N", col: colN,    lw: 2.5, fs: R*0.22},
                {a:  0,         lbl: "E", col: colCard,  lw: 1.5, fs: R*0.18},
                {a:  Math.PI/2, lbl: "S", col: colCard,  lw: 1.5, fs: R*0.18},
                {a:  Math.PI,   lbl: "O", col: colCard,  lw: 1.5, fs: R*0.18}
            ]
            for (var i = 0; i < cards.length; i++) {
                var c = cards[i]
                var cosA = Math.cos(c.a), sinA = Math.sin(c.a)
                ctx.beginPath()
                ctx.moveTo(cx + R*0.78*cosA, cy + R*0.78*sinA)
                ctx.lineTo(cx + R*0.94*cosA, cy + R*0.94*sinA)
                ctx.strokeStyle = c.col
                ctx.lineWidth   = c.lw
                ctx.stroke()
                ctx.fillStyle    = c.col
                ctx.font         = "bold " + Math.round(c.fs) + "px sans-serif"
                ctx.textAlign    = "center"
                ctx.textBaseline = "middle"
                ctx.shadowColor   = "rgba(0,0,0,0.75)"
                ctx.shadowBlur    = 3
                ctx.shadowOffsetX = 1
                ctx.shadowOffsetY = 1
                ctx.fillText(c.lbl, cx + R*0.64*cosA, cy + R*0.64*sinA)
                ctx.shadowColor   = "transparent"
                ctx.shadowBlur    = 0
                ctx.shadowOffsetX = 0
                ctx.shadowOffsetY = 0
            }
        }
    }

    // ── Vehicle heading arrow (rotates to show travel direction) ─────────
    Canvas {
        id: headingArrow
        anchors.fill: parent
        visible: compassWidget.hasArrow
        rotation: compassWidget.dispHeadRad * 180 / Math.PI
        onVisibleChanged: requestPaint()
        Component.onCompleted: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var cx = width / 2, cy = height / 2, R = width / 2
            ctx.beginPath()
            ctx.moveTo(cx, cy - R * 0.95)
            ctx.lineTo(cx - R * 0.065, cy - R * 0.78)
            ctx.lineTo(cx + R * 0.065, cy - R * 0.78)
            ctx.closePath()
            ctx.fillStyle = "#4CAF50"
            ctx.shadowColor = "rgba(0,0,0,0.7)"
            ctx.shadowBlur  = 3
            ctx.fill()
        }
    }

    // ── Inner button ──────────────────────────────────────────────────────
    Rectangle {
        anchors.centerIn: parent
        width: units.gu(9); height: units.gu(9); radius: width / 2
        color: "transparent"

        Column {
            anchors.centerIn: parent; spacing: units.gu(0.1)
            BtnLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text: compassWidget.bearingMode === "heading" ? "↑" : "N"
                fontSize: units.gu(3.0); bold: true
            }
            BtnLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text: compassWidget.bearingMode === "heading" ? i18n.tr("Giro") : "↑"
                fontSize: units.gu(1.6)
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (compassWidget.bearingMode === "heading")
                    compassWidget.northUpRequested()
                else
                    compassWidget.headingUpRequested()
            }
        }
    }
}
