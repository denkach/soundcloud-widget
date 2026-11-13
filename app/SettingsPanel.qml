pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: panel
    required property var controller
    property real maxHeight: 560
    property string colorTarget: ""
    property color pickerInitial: "#c4d7bc"
    readonly property var config: controller.settings
    readonly property color accent: controller.accent
    implicitHeight: Math.min(body.implicitHeight + 10, maxHeight)
    contentHeight: body.implicitHeight + 10
    contentWidth: width
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    ScrollBar.vertical: ScrollBar { policy: panel.contentHeight > panel.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
    function chooseColor(key) {
        pickerInitial = Qt.color(config[key]);
        colorTarget = key;
        Qt.callLater(() => panel.contentY = Math.max(0, Math.min(colorChooser.y - 8, panel.contentHeight - panel.height)));
    }
    component Caption: Text {
        color: "#a5b7ac"; font.family: "Noto Sans"; font.pixelSize: 9; font.letterSpacing: 1.2
    }
    component Copy: Text { color: "#e3ece6"; font.family: "Noto Sans"; font.pixelSize: 11 }
    component Pill: Button {
        id: pill
        property bool selected: false
        implicitHeight: 34; padding: 0; hoverEnabled: true
        background: Rectangle {
            radius: 11
            color: pill.selected ? Qt.rgba(panel.accent.r,panel.accent.g,panel.accent.b,.18) : (pill.hovered ? "#30433a" : "#202d27")
            border.width: 1; border.color: pill.selected ? panel.accent : (pill.hovered ? "#60776a" : "#35473d")
            Behavior on color { ColorAnimation { duration: 100 } }
        }
        contentItem: Text { text: pill.text; color: pill.selected ? panel.accent : "#d0ddd4"; font.family: "Noto Sans"; font.pixelSize: 11; font.weight: pill.selected ? Font.DemiBold : Font.Normal; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
    }
    component Field: TextField {
        id: field
        implicitHeight: 34; leftPadding: 11; rightPadding: 11; topPadding: 0; bottomPadding: 0
        color: "#e0eae3"; placeholderTextColor: "#768f80"; selectionColor: panel.accent; selectedTextColor: "#15221a"
        font.family: "Noto Sans Mono"; font.pixelSize: 11; verticalAlignment: TextInput.AlignVCenter
        background: Rectangle { radius: 10; color: "#121e18"; border.color: field.acceptableInput ? (field.activeFocus ? panel.accent : "#3b5042") : "#e09b8d"; border.width: 1 }
    }
    component SettingSlider: Slider {
        id: slider
        implicitHeight: 24; leftPadding: 7; rightPadding: 7
        background: Rectangle {
            x: slider.leftPadding; y: slider.height/2-2; width: slider.availableWidth; height: 4; radius: 2; color: "#35473c"
            Rectangle { width: slider.visualPosition*parent.width; height: 4; radius: 2; color: panel.accent }
        }
        handle: Rectangle { x: slider.leftPadding+slider.visualPosition*slider.availableWidth-width/2; y: slider.height/2-height/2; width: slider.pressed ? 16 : 13; height: width; radius: width/2; color: panel.accent; border.color: "#e6efe4"; border.width: 1 }
    }
    component ColorRow: RowLayout {
        id: row
        required property string caption
        required property string settingKey
        Layout.fillWidth: true; spacing: 8
        Button {
            id: swatch
            implicitWidth: 34; implicitHeight: 34; padding: 0
            background: Rectangle { color: Qt.color(panel.config[row.settingKey]); radius: 10; border.color: swatch.hovered ? "#edf5ed" : "#60766a"; border.width: 1 }
            onClicked: panel.chooseColor(row.settingKey)
            ToolTip.visible: hovered; ToolTip.text: "Открыть палитру"
        }
        Copy { text: row.caption; Layout.preferredWidth: 40 }
        Field {
            Layout.fillWidth: true; maximumLength: 7
            text: panel.config[row.settingKey].toUpperCase()
            validator: RegularExpressionValidator { regularExpression: /^#[0-9a-fA-F]{6}$/ }
            onEditingFinished: {
                if (acceptableInput) panel.controller.setSetting(row.settingKey,text.toLowerCase());
                else text = panel.config[row.settingKey].toUpperCase();
            }
        }
    }
    component Surface: Rectangle {
        color: "#e618241e"; radius: 14; border.color: "#35483c"
        Layout.fillWidth: true
    }
    ColumnLayout {
        id: body
        width: panel.width - 5
        spacing: 12
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#34483a" }
        RowLayout {
            Layout.fillWidth: true
            Text { text: "Твой плеер"; color: "#edf4ee"; font.family: "Noto Sans"; font.pixelSize: 15; font.weight: Font.DemiBold }
            Item { Layout.fillWidth: true }
            Caption { text: "НАСТРОЙКИ" }
        }
        Surface {
            implicitHeight: workspaceBody.implicitHeight + 24
            ColumnLayout {
                id: workspaceBody
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 9
                Caption { text: "РАБОЧИЙ СТОЛ" }
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Field {
                        Layout.preferredWidth: 62; horizontalAlignment: TextInput.AlignHCenter
                        text: String(panel.config.workspace)
                        validator: IntValidator { bottom: 1; top: 9999 }
                        inputMethodHints: Qt.ImhDigitsOnly
                        onEditingFinished: { if (acceptableInput) panel.controller.setSetting("workspace",Number(text)); else text=String(panel.config.workspace); }
                    }
                    Pill { text: "На текущем столе"; Layout.fillWidth: true; onClicked: panel.controller.pinHere() }
                }
                Copy { text: "Только стол " + panel.config.workspace + " · " + panel.config.monitor; color: "#8fa899"; font.pixelSize: 9; Layout.fillWidth: true; elide: Text.ElideRight }
            }
        }
        Surface {
            implicitHeight: colorBody.implicitHeight + 24
            ColumnLayout {
                id: colorBody
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 10
                RowLayout {
                    Layout.fillWidth: true; spacing: 7
                    Caption { text: "АКЦЕНТ"; Layout.fillWidth: true }
                    Pill { text: "Цвет"; implicitWidth: 59; implicitHeight: 28; selected: !panel.config.accentGradient; onClicked: panel.controller.setSetting("accentGradient",false) }
                    Pill { text: "Градиент"; implicitWidth: 77; implicitHeight: 28; selected: panel.config.accentGradient; onClicked: panel.controller.setSetting("accentGradient",true) }
                }
                ColorRow { caption: panel.config.accentGradient ? "Старт" : "Цвет"; settingKey: "accent" }
                ColorRow { visible: panel.config.accentGradient; caption: "Финиш"; settingKey: "accentEnd" }
                Rectangle {
                    visible: panel.config.accentGradient; Layout.fillWidth: true; implicitHeight: 8; radius: 4
                    gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: panel.config.accent } GradientStop { position: 1; color: panel.config.accentEnd } }
                }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#33473a" }
                RowLayout {
                    Layout.fillWidth: true; spacing: 7
                    Caption { text: "ФОН"; Layout.fillWidth: true }
                    Pill { text: "Цвет"; implicitWidth: 59; implicitHeight: 28; selected: !panel.config.backgroundGradient; onClicked: panel.controller.setSetting("backgroundGradient",false) }
                    Pill { text: "Градиент"; implicitWidth: 77; implicitHeight: 28; selected: panel.config.backgroundGradient; onClicked: panel.controller.setSetting("backgroundGradient",true) }
                }
                ColorRow { caption: panel.config.backgroundGradient ? "Старт" : "Цвет"; settingKey: "background" }
                ColorRow { visible: panel.config.backgroundGradient; caption: "Финиш"; settingKey: "backgroundEnd" }
                RowLayout {
                    visible: panel.config.backgroundGradient
                    Layout.fillWidth: true; spacing: 7
                    Pill { text: "→ Вправо"; Layout.fillWidth: true; selected: panel.config.gradientDirection === "horizontal"; onClicked: panel.controller.setSetting("gradientDirection","horizontal") }
                    Pill { text: "↓ Вниз"; Layout.fillWidth: true; selected: panel.config.gradientDirection === "vertical"; onClicked: panel.controller.setSetting("gradientDirection","vertical") }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Copy { text: "Плотность фона"; Layout.fillWidth: true; color: "#a8bdaf" }
                    Copy { text: Math.round(panel.config.opacity*100)+"%"; color: panel.accent }
                }
                SettingSlider { Layout.fillWidth: true; from: .25; to: 1; value: panel.config.opacity; onMoved: panel.controller.setSetting("opacity",value) }
            }
        }
        ColorPalette {
            id: colorChooser
            visible: panel.colorTarget !== ""
            Layout.fillWidth: true
            accent: panel.accent; initialColor: panel.pickerInitial
            onAccepted: chosen => { panel.controller.setSetting(panel.colorTarget,chosen.toString()); panel.colorTarget=""; }
            onDismissed: panel.colorTarget=""
        }
        Caption { text: "ГОТОВЫЕ ПАЛИТРЫ" }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Repeater {
                model: [{name:"Sage",a:"#c4d7bc",b:"#17201b"},{name:"Amber",a:"#f59a63",b:"#252019"},{name:"Ice",a:"#99c8e8",b:"#17222c"}]
                delegate: Pill {
                    required property var modelData
                    Layout.fillWidth: true; implicitHeight: 40
                    text: "●  " + modelData.name
                    selected: panel.config.accent === modelData.a && panel.config.background === modelData.b && !panel.config.accentGradient && !panel.config.backgroundGradient
                    onClicked: {
                        panel.controller.setSetting("accent",modelData.a); panel.controller.setSetting("background",modelData.b);
                        panel.controller.setSetting("accentGradient",false); panel.controller.setSetting("backgroundGradient",false);
                    }
                }
            }
        }
        Caption { text: "РАСПОЛОЖЕНИЕ" }
        GridLayout {
            columns: 2; Layout.fillWidth: true; rowSpacing: 8; columnSpacing: 8
            Repeater {
                model: [{label:"↖  Слева вверху",key:"top-left"},{label:"Справа вверху  ↗",key:"top-right"},{label:"↙  Слева внизу",key:"bottom-left"},{label:"Справа внизу  ↘",key:"bottom-right"}]
                delegate: Pill {
                    required property var modelData
                    text: modelData.label; Layout.fillWidth: true; selected: panel.config.position === modelData.key
                    onClicked: panel.controller.setSetting("position",modelData.key)
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Copy { text: "Поверх окон"; Layout.fillWidth: true }
            Switch {
                id: topSwitch
                checked: panel.config.onTop
                implicitWidth: 42; implicitHeight: 28; padding: 0
                indicator: Rectangle {
                    x: 0; y: 3; width: 42; height: 22; radius: 11
                    color: topSwitch.checked ? panel.accent : "#3b4c41"
                    Rectangle { x: topSwitch.checked ? 23 : 3; y: 3; width: 16; height: 16; radius: 8; color: topSwitch.checked ? "#18251d" : "#c9d6ce"; Behavior on x { NumberAnimation { duration: 130 } } }
                }
                onToggled: panel.controller.setSetting("onTop",checked)
            }
        }
        Copy { text: "Сохраняется автоматически"; font.pixelSize: 9; color: "#8fa899"; Layout.alignment: Qt.AlignHCenter }
    }
}
