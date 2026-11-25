import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

QQC2.AbstractButton {
    id: btn
    property real size: Kirigami.Units.gridUnit * 2
    property string iconName
    property color fg: "white"
    property color bgColor: Qt.alpha(fg, 0.15)
    property bool filled: false
    property string tooltip

    implicitWidth: size
    implicitHeight: size
    hoverEnabled: true
    opacity: enabled ? 1 : 0.4

    QQC2.ToolTip.visible: hovered && tooltip !== ""
    QQC2.ToolTip.text: tooltip
    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay

    background: Rectangle {
        radius: width / 2
        color: btn.filled ? btn.bgColor : (btn.hovered ? Qt.alpha(btn.fg, 0.12) : "transparent")
        scale: btn.pressed ? 0.9 : (btn.hovered && btn.filled ? 1.05 : 1)
        Behavior on scale { NumberAnimation { duration: 120 } }
        Behavior on color { ColorAnimation { duration: 150 } }
    }
    contentItem: Item {
        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.round(btn.size * 0.5)
            height: width
            source: btn.iconName
            color: btn.fg
            isMask: true
            scale: btn.pressed ? 0.9 : 1
        }
    }
}
