import QtQuick 2.7
import Lomiri.Components 1.3

// Texto blanco con sombra negra simulada (sin style:Text.Outline — crash Adreno 618)
Item {
    property string text:      ""
    property real   fontSize:  units.gu(1.5)
    property bool   bold:      false
    property color  mainColor: "white"

    implicitWidth:  _main.implicitWidth  + 1
    implicitHeight: _main.implicitHeight + 1

    Label {
        text:           parent.text
        font.pixelSize: parent.fontSize
        font.bold:      parent.bold
        color:          "#CC000000"
        x: 1; y: 1
    }
    Label {
        id: _main
        text:           parent.text
        font.pixelSize: parent.fontSize
        font.bold:      parent.bold
        color:          parent.mainColor
    }
}
