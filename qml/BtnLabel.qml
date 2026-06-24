import QtQuick 2.7
import Lomiri.Components 1.3

Item {
    property string text:      ""
    property real   fontSize:  units.gu(1.5)
    property bool   bold:      false
    property color  mainColor: "white"

    implicitWidth:  _main.implicitWidth
    implicitHeight: _main.implicitHeight

    Label {
        id: _main
        text:           parent.text
        font.pixelSize: parent.fontSize
        font.bold:      parent.bold
        color:          parent.mainColor
    }
}
