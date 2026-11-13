pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: colorEditor
    required property color accent
    property color initialColor: "#c4d7bc"
    property real hue: 0.25
    property real saturation: 0.3
    property real brightness: 0.8
    readonly property color selectedColor: Qt.hsva(hue, saturation, brightness, 1)
    signal accepted(color chosen)
    signal dismissed()
    function load(c) {
        // Preserve a useful hue when editing grey or black.
        hue = c.hsvHue < 0 ? .25 : c.hsvHue;
        saturation = c.hsvSaturation; brightness = c.hsvValue;
    }
    onInitialColorChanged: load(initialColor)
    Component.onCompleted: load(initialColor)
    color: "#111a19"; radius: 15
    border.color: "#30413b"
    implicitHeight: body.implicitHeight + 28
    ColumnLayout {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            Text { text: "ПАЛИТРА"; color: "#a3b5ac"; font.family: "Noto Sans"; font.pixelSize: 9; font.letterSpacing: 1.5 }
            Item { Layout.fillWidth: true }
            Rectangle { implicitWidth: 36; implicitHeight: 20; radius: 6; color: colorEditor.selectedColor; border.color: "#50ffffff" }
            Text { text: colorEditor.selectedColor.toString().toUpperCase(); color: "#e3ece7"; font.family: "Noto Sans Mono"; font.pixelSize: 11 }
        }
        Rectangle {
            id: spectrum
            Layout.fillWidth: true; implicitHeight: 128; radius: 8
            color: Qt.hsva(colorEditor.hue, 1, 1, 1)
            Rectangle {
                anchors.fill: parent; radius: 8
                gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "white" } GradientStop { position: 1; color: "#00ffffff" } }
            }
            Rectangle {
                anchors.fill: parent; radius: 8
                gradient: Gradient { GradientStop { position: 0; color: "#00000000" } GradientStop { position: 1; color: "black" } }
            }
            Rectangle {
                x: colorEditor.saturation * (spectrum.width - 12)
                y: (1 - colorEditor.brightness) * (spectrum.height - 12)
                width: 12; height: 12; radius: 6; color: "transparent"; border.width: 2; border.color: "white"
                Rectangle { anchors.fill: parent; anchors.margins: -1; radius: 7; color: "transparent"; border.color: "#70000000" }
            }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.CrossCursor
                function updateColor(mouse) { colorEditor.saturation = Math.max(0,Math.min(1,(mouse.x-6)/(width-12))); colorEditor.brightness = 1-Math.max(0,Math.min(1,(mouse.y-6)/(height-12))); }
                onPressed: mouse => updateColor(mouse)
                onPositionChanged: mouse => { if (pressed) updateColor(mouse); }
            }
        }
        Slider {
            id: hueSlider
            Layout.fillWidth: true; implicitHeight: 22
            from: 0; to: 1; value: colorEditor.hue; onMoved: colorEditor.hue = value
            leftPadding: 6; rightPadding: 6
            background: Rectangle {
                x: 0; y: 5; width: hueSlider.width; height: 12; radius: 6
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#ff0000" } GradientStop { position: .167; color: "#ffff00" }
                    GradientStop { position: .333; color: "#00ff00" } GradientStop { position: .5; color: "#00ffff" }
                    GradientStop { position: .667; color: "#0000ff" } GradientStop { position: .833; color: "#ff00ff" }
                    GradientStop { position: 1; color: "#ff0000" }
                }
            }
            handle: Rectangle { x: hueSlider.leftPadding + hueSlider.visualPosition*hueSlider.availableWidth - width/2; y: 2; width: 18; height: 18; radius: 9; color: Qt.hsva(colorEditor.hue,1,1,1); border.width: 3; border.color: "#edf4ef" }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 7
            Repeater {
                model: ["#c4d7bc","#f59a63","#99c8e8","#d8b4ed","#f49eae","#e7d69b","#eff3ef","#17201b"]
                delegate: Rectangle {
                    required property string modelData
                    Layout.fillWidth: true; implicitHeight: 22; radius: 7; color: modelData
                    border.color: swatchMouse.containsMouse ? "white" : "#40ffffff"
                    MouseArea { id: swatchMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: colorEditor.load(Qt.color(parent.modelData)) }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Repeater {
                model: ["Отмена", "Применить"]
                delegate: Button {
                    id: choice
                    required property string modelData
                    required property int index
                    Layout.fillWidth: true; implicitHeight: 34; padding: 0; hoverEnabled: true
                    background: Rectangle { radius: 11; color: choice.index === 1 ? colorEditor.accent : (choice.hovered ? "#30423b" : "#23312c") }
                    contentItem: Text { text: choice.modelData; color: choice.index === 1 ? "#12211b" : "#dce7df"; font.family: "Noto Sans"; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    onClicked: { if (index === 1) colorEditor.accepted(colorEditor.selectedColor); else colorEditor.dismissed(); }
                }
            }
        }
    }
}
