import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

ShellRoot {
    id: root
    property var settings: ({accent: "#c4d7bc", background: "#17201b", opacity: 0.9, position: "bottom-right", onTop: true, player: "auto"})
    property var media: ({})
    property var players: []
    property var bars: []
    property string audioStatus: "Подключение к браузеру…"
    property real volume: 65
    property bool hasStream: false
    property bool settingsOpen: false
    property bool shown: true
    property int settingsSerial: 0
    property int appliedConfigAck: -1
    property real pendingVolume: 65
    property string backendError: ""
    property string lastSnapshot: "none"
    property bool captureOverlay: false
    property var windowStyle: ({activeOpacity:1.0,inactiveOpacity:0.6})
    readonly property bool interacting: root.shown && (cardHover.hovered || (root.settingsOpen && card.Window.active) || accentPicker.visible || backgroundPicker.visible)
    onInteractingChanged: interactionDebounce.restart()
    readonly property color accent: settings.accent
    readonly property color backgroundColor: settings.background
    readonly property color foreground: backgroundColor.hslLightness > .6 ? "#18251c" : "#e1e8df"
    readonly property color muted: backgroundColor.hslLightness > .6 ? "#51634d" : "#a4b1a5"
    function send(value) { if (bridge.running) bridge.write(JSON.stringify(value) + "\n"); }
    function setSetting(key, value) {
        let next = Object.assign({}, settings); next[key] = value; settings = next;
        settingsSerial++; saveDebounce.restart();
    }
    function timeText(seconds) {
        if (!isFinite(seconds) || seconds < 0) return "--:--";
        return Math.floor(seconds / 60) + ":" + ("0" + Math.floor(seconds % 60)).slice(-2);
    }
    Timer { id: saveDebounce; interval: 180; onTriggered: root.send({cmd:"settings", settings:root.settings, serial:root.settingsSerial}) }
    Timer { id: volumeThrottle; interval: 80; onTriggered: root.send({cmd:"volume",value:root.pendingVolume}) }
    Timer { id: interactionDebounce; interval: root.interacting ? 150 : 25; onTriggered: root.send({cmd:"interaction",active:root.interacting}) }
    Process {
        id: bridge
        command: ["python3", "-u", decodeURIComponent(Qt.resolvedUrl("backend.py").toString().slice(7))]
        stdinEnabled: true
        running: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    const value = JSON.parse(data);
                    if (!saveDebounce.running && value.configAck >= root.settingsSerial && value.configAck !== root.appliedConfigAck) {
                        root.settings = value.settings;
                        root.appliedConfigAck = value.configAck;
                    }
                    root.media = value.media; root.players = value.players; root.bars = value.bars;
                    root.audioStatus = value.audioStatus; root.volume = value.volume;
                    root.hasStream = value.hasStream; root.backendError = value.error || "";
                    if (value.windowStyle) root.windowStyle = value.windowStyle;
                } catch(e) { console.warn("Invalid audio state", e); }
            }
        }
        stderr: SplitParser { onRead: data => console.warn("SoundCloud backend:", data) }
        onExited: (code, status) => { root.audioStatus = "Переподключение…"; retry.restart(); }
        onStarted: { root.appliedConfigAck = -1; interactionDebounce.restart(); if (root.settingsSerial > 0) root.send({cmd:"settings",settings:root.settings,serial:root.settingsSerial}); }
    }
    Timer { id: retry; interval: 2500; onTriggered: bridge.running = true }
    IpcHandler {
        target: "player"
        function toggle(): void { root.shown = !root.shown; }
        function settings(): void { root.shown = true; root.settingsOpen = !root.settingsOpen; }
        function state(): string { return JSON.stringify({settings:root.settings,media:root.media,audioStatus:root.audioStatus,maxWave:Math.max(0,...root.bars),hasStream:root.hasStream,error:root.backendError,hovered:cardHover.hovered,interacting:root.interacting,effectiveOpacity:card.opacity,windowStyle:root.windowStyle,barHeights:[waveRepeater.itemAt(0)?.height,waveRepeater.itemAt(10)?.height,waveRepeater.itemAt(20)?.height],barTargets:[root.bars[0],root.bars[10],root.bars[20]],snapshot:root.lastSnapshot}); }
        function configure(value: string): void { const v=JSON.parse(value); for (const key in v) root.setSetting(key,v[key]); }
        function control(action: string): void { root.send({cmd:action}); }
        function snapshot(): void {
            root.captureOverlay = true;
            root.lastSnapshot = "requested";
            captureReset.restart();
            captureTimer.restart();
        }
    }
    Timer { id: captureReset; interval: 800; onTriggered: root.captureOverlay = false }
    Timer {
        id: captureTimer; interval: 160
        onTriggered: {
            const ok = card.grabToImage(function(result) {
                const path = Quickshell.env("HOME") + "/.local/state/soundcloud-widget/preview.png";
                root.lastSnapshot = result.saveToFile(path) ? path : "save failed";
                root.captureOverlay = false;
            });
            if (!ok) { root.lastSnapshot = "grab failed"; root.captureOverlay = false; }
        }
    }
    ColorDialog { id: accentPicker; title: "Цвет акцента"; selectedColor: root.accent; onAccepted: root.setSetting("accent",selectedColor.toString()) }
    ColorDialog { id: backgroundPicker; title: "Цвет фона"; selectedColor: root.backgroundColor; onAccepted: root.setSetting("background",selectedColor.toString()) }
    component SmallButton: Button {
        id: b
        property color ink: root.muted
        implicitWidth: 28; implicitHeight: 28
        hoverEnabled: true
        background: Rectangle { color: b.hovered ? "#18ffffff" : "transparent"; radius: 8 }
        contentItem: Text { text: b.text; textFormat: Text.PlainText; font.family: "DejaVu Sans"; font.pixelSize: 16; color: b.enabled ? b.ink : "#526052"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
        ToolTip.visible: hovered && ToolTip.text.length > 0
    }
    component LabelText: Text { color: root.foreground; font.family: "Noto Sans"; font.pixelSize: 12; textFormat: Text.PlainText }
    PanelWindow {
        id: window
        visible: root.shown
        implicitWidth: 350
        implicitHeight: content.implicitHeight + 40
        color: "transparent"
        anchors { right: root.settings.position.endsWith("right"); left: root.settings.position.endsWith("left"); top: root.settings.position.startsWith("top"); bottom: root.settings.position.startsWith("bottom") }
        margins { right: 24; left: 24; top: 86; bottom: 103 }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "soundcloud-widget"
        WlrLayershell.layer: root.captureOverlay ? WlrLayer.Overlay : (root.settings.onTop ? WlrLayer.Top : WlrLayer.Bottom)
        WlrLayershell.keyboardFocus: root.settingsOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        Rectangle {
            id: card
            anchors.fill: parent
            anchors.margins: 4
            radius: 17
            opacity: root.interacting ? root.windowStyle.activeOpacity : root.windowStyle.inactiveOpacity
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            HoverHandler { id: cardHover }
            color: Qt.rgba(root.backgroundColor.r,root.backgroundColor.g,root.backgroundColor.b,root.settings.opacity)
            border.width: 1
            border.color: "#3b58604e"
            ColumnLayout {
                id: content
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true; spacing: 6
                    Text { text: "☁"; color: root.accent; font.pixelSize: 18 }
                    LabelText { text: root.media.soundcloud ? "SOUNDCLOUD" : "BROWSER PLAYER"; color: root.muted; font.pixelSize: 9; font.letterSpacing: .8 }
                    Item { Layout.fillWidth: true }
                    Rectangle { width: 4; height: 4; radius: 2; color: root.media.playing ? root.accent : "#687368" }
                    LabelText { text: root.media.playing ? "PLAYING" : "PAUSED"; font.pixelSize: 8; color: root.muted; font.letterSpacing: .6 }
                    SmallButton { text: "⚙"; implicitWidth: 24; implicitHeight: 22; ToolTip.text: "Оформление"; onClicked: root.settingsOpen = !root.settingsOpen }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 11
                    ClippingRectangle {
                        width: 48; height: 48; radius: 9; color: Qt.darker(root.accent,2.5); clip: true
                        Rectangle { anchors.fill: parent; gradient: Gradient { GradientStop { position: 0; color: Qt.darker(root.accent,1.7) } GradientStop { position: 1; color: "#18251c" } } }
                        Text { anchors.centerIn: parent; text: "♪"; color: root.accent; font.pixelSize: 25 }
                        Image { anchors.fill: parent; source: root.media.art || ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; visible: status === Image.Ready }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 4
                        LabelText { text: root.media.title || "Открой SoundCloud"; font.pixelSize: 14; font.weight: Font.Medium; Layout.fillWidth: true; elide: Text.ElideRight }
                        LabelText { text: root.media.artist || (root.media.identity || "и включи музыку в браузере"); font.pixelSize: 10; color: root.muted; Layout.fillWidth: true; elide: Text.ElideRight }
                    }
                    RowLayout {
                        spacing: 2
                        SmallButton { text: "⏮"; implicitWidth: 22; enabled: !!root.media.canPrevious; ToolTip.text: "Предыдущий"; onClicked: root.send({cmd:"previous"}) }
                        Button {
                            implicitWidth: 34; implicitHeight: 34
                            enabled: root.media.playing ? !!root.media.canPause : !!root.media.canPlay
                            background: Rectangle { radius: 17; color: parent.enabled ? root.accent : "#596658" }
                            contentItem: Text { text: root.media.playing ? "Ⅱ" : "▶"; color: root.accent.hslLightness > .5 ? "#17251c" : "#eef3ec"; font.pixelSize: 14; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            onClicked: root.send({cmd:"toggle"})
                        }
                        SmallButton { text: "⏭"; implicitWidth: 22; enabled: !!root.media.canNext; ToolTip.text: "Следующий"; onClicked: root.send({cmd:"next"}) }
                    }
                }
                Item {
                    Layout.fillWidth: true; implicitHeight: 34
                    Row {
                        anchors.fill: parent; spacing: 3
                        Repeater {
                            id: waveRepeater
                            model: 44
                            Rectangle {
                                required property int index
                                width: Math.max(1,(parent.width-43*3)/44)
                                height: Math.max(2,(root.bars[index] || 0)*32)
                                y: (34-height)/2; radius: 2
                                color: root.accent; opacity: .85
                                Behavior on height { NumberAnimation { duration: 115; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                    MouseArea { anchors.fill: parent; enabled: !!root.media.canSeek && root.media.length > 0; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: mouse => root.send({cmd:"seek",seconds:mouse.x/width*root.media.length}) }
                }
                RowLayout {
                    Layout.fillWidth: true
                    LabelText { text: root.media.id ? root.timeText(root.media.position) : "--:--"; color: root.muted; font.pixelSize: 9 }
                    Item { Layout.fillWidth: true }
                    LabelText { text: root.media.length > 0 && root.media.length < 604800 ? root.timeText(root.media.length) : (root.media.id ? "LIVE" : "--:--"); color: root.muted; font.pixelSize: 9 }
                }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#20ffffff" }
                RowLayout {
                    Layout.fillWidth: true; spacing: 5
                    LabelText { text: "♪"; color: root.muted; font.pixelSize: 13 }
                    Slider {
                        id: volumeSlider
                        Layout.preferredWidth: 69; Layout.preferredHeight: 22; from: 0; to: 100; enabled: root.hasStream
                        onMoved: { root.pendingVolume = value; if (!volumeThrottle.running) volumeThrottle.start(); }
                        onPressedChanged: if (!pressed && root.hasStream) root.send({cmd:"volume",value:value})
                        Binding { target: volumeSlider; property: "value"; value: root.volume; when: !volumeSlider.pressed; restoreMode: Binding.RestoreNone }
                        background: Rectangle { x: 0; y: volumeSlider.height/2-1; width: volumeSlider.width; height: 2; radius: 1; color: Qt.rgba(root.accent.r,root.accent.g,root.accent.b,.2); Rectangle { width: volumeSlider.visualPosition*parent.width; height: 2; radius: 1; color: root.accent } }
                        handle: Rectangle { x: volumeSlider.visualPosition*(volumeSlider.width-width); y: volumeSlider.height/2-4; width: 8; height: 8; radius: 4; color: root.accent; opacity: volumeSlider.enabled ? 1 : .3 }
                    }
                    LabelText { text: root.audioStatus; font.pixelSize: 9; color: root.muted; Layout.fillWidth: true; elide: Text.ElideRight }
                    SmallButton { text: "↗"; implicitWidth: 22; implicitHeight: 22; ToolTip.text: "Открыть SoundCloud"; onClicked: root.send({cmd:"open"}) }
                }
                ColumnLayout {
                    visible: root.settingsOpen; Layout.fillWidth: true; spacing: 10
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#20ffffff" }
                    LabelText { text: "Оформление"; font.weight: Font.DemiBold }
                    RowLayout {
                        LabelText { text: "Акцент"; Layout.preferredWidth: 62 }
                        Rectangle { width: 22; height: 22; radius: 5; color: root.accent; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: accentPicker.open() } }
                        TextField { Layout.fillWidth: true; text: root.settings.accent; maximumLength: 7; placeholderText: "#c4d7bc"; onEditingFinished: if (/^#[0-9a-f]{6}$/i.test(text)) root.setSetting("accent",text.toLowerCase()); }
                    }
                    RowLayout {
                        LabelText { text: "Фон"; Layout.preferredWidth: 62 }
                        Rectangle { width: 22; height: 22; radius: 5; color: root.settings.background; border.color: "#526052"; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: backgroundPicker.open() } }
                        TextField { Layout.fillWidth: true; text: root.settings.background; maximumLength: 7; onEditingFinished: if (/^#[0-9a-f]{6}$/i.test(text)) root.setSetting("background",text.toLowerCase()); }
                    }
                    RowLayout {
                        LabelText { text: "Плотность фона"; Layout.fillWidth: true }
                        LabelText { text: Math.round(root.settings.opacity*100)+"%"; color: root.muted }
                    }
                    Slider { Layout.fillWidth: true; from: .25; to: 1; value: root.settings.opacity; onMoved: root.setSetting("opacity",value) }
                    RowLayout {
                        Repeater {
                            model: [{name:"Sage",a:"#c4d7bc",b:"#17201b"},{name:"Amber",a:"#f59a63",b:"#252019"},{name:"Ice",a:"#99c8e8",b:"#17222c"}]
                            Button { required property var modelData; text: modelData.name; Layout.fillWidth: true; onClicked: {root.setSetting("accent",modelData.a);root.setSetting("background",modelData.b);} }
                        }
                    }
                    ComboBox { Layout.fillWidth: true; model: ["Справа внизу","Справа вверху","Слева внизу","Слева вверху"]; currentIndex: ["bottom-right","top-right","bottom-left","top-left"].indexOf(root.settings.position); onActivated: root.setSetting("position",["bottom-right","top-right","bottom-left","top-left"][currentIndex]) }
                    CheckBox { text: "Поверх окон"; checked: root.settings.onTop; onToggled: root.setSetting("onTop",checked) }
                    LabelText { text: "Цвета и прозрачность сохраняются автоматически"; color: root.muted; font.pixelSize: 9 }
                }
            }
        }
    }
}
