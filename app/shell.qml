pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

ShellRoot {
    id: root
    property var settings: ({accent: "#c4d7bc", background: "#17201b", opacity: 0.9, position: "bottom-right", onTop: true, player: "auto", workspace: 0, monitor: "", accentEnd: "#8cbecb", backgroundEnd: "#28384c", accentGradient: false, backgroundGradient: false, gradientDirection: "horizontal"})
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
    property string openError: ""
    function openSoundCloud() {
        if (browserOpener.running) return;
        root.openError = "";
        browserOpener.running = true;
    }
    property string lastSnapshot: "none"
    property bool captureOverlay: false
    property var windowStyle: ({activeOpacity:1.0,inactiveOpacity:0.6})
    readonly property bool interacting: root.shown && root.workspaceVisible && (cardHover.hovered || (root.settingsOpen && card.Window.active))
    // One timeline drives native backdrop blur and the foreground opacity.
    property real focusProgress: root.interacting ? 1 : 0
    Behavior on focusProgress {
        NumberAnimation { duration: 280; easing.type: Easing.InOutCubic }
    }
    readonly property color accent: settings.accent
    readonly property color backgroundColor: settings.background
    readonly property color accentEnd: settings.accentGradient ? settings.accentEnd : settings.accent
    readonly property color backgroundEnd: settings.backgroundGradient ? settings.backgroundEnd : settings.background
    readonly property var pinnedScreen: Quickshell.screens.find(s => s.name === root.settings.monitor) || null
    readonly property var pinnedMonitor: Hyprland.monitors.values.find(m => m.name === root.settings.monitor) || null
    readonly property bool workspaceVisible: !!root.pinnedMonitor && root.pinnedMonitor.activeWorkspace?.id === root.settings.workspace
    function pinHere() {
        if (Hyprland.focusedWorkspace?.id > 0 && Hyprland.focusedMonitor) {
            root.setSetting("workspace", Hyprland.focusedWorkspace.id);
            root.setSetting("monitor", Hyprland.focusedMonitor.name);
        }
    }
    function withOpacity(c, alpha) { return Qt.rgba(c.r,c.g,c.b,alpha); }
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
    Timer { interval: 200; repeat: true; running: root.appliedConfigAck >= 0 && (root.settings.workspace === 0 || !root.settings.monitor); onTriggered: root.pinHere() }
    Timer { id: saveDebounce; interval: 180; onTriggered: root.send({cmd:"settings", settings:root.settings, serial:root.settingsSerial}) }
    Timer { id: volumeThrottle; interval: 80; onTriggered: root.send({cmd:"volume",value:root.pendingVolume}) }
    // URL launching and window activation must not wait for audio / MPRIS polling.
    Process {
        id: browserOpener
        command: ["python3", decodeURIComponent(Qt.resolvedUrl("open_soundcloud.py").toString().slice(7))]
        stderr: StdioCollector { id: browserOpenErrors }
        onExited: (code, status) => {
            if (code !== 0) root.openError = browserOpenErrors.text.trim() || "Не удалось открыть SoundCloud";
        }
    }
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
                        if (root.settings.workspace === 0 || !root.settings.monitor) root.pinHere();
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
        onStarted: { root.appliedConfigAck = -1; if (root.settingsSerial > 0) root.send({cmd:"settings",settings:root.settings,serial:root.settingsSerial}); }
    }
    Timer { id: retry; interval: 2500; onTriggered: bridge.running = true }
    IpcHandler {
        target: "player"
        function toggle(): void { root.shown = !root.shown; }
        function settings(): void {
            root.send({cmd:"focus-workspace"});
            root.shown = true; root.settingsOpen = !root.settingsOpen;
        }
        function pin(): void { root.pinHere(); }
        function palette(key: string): void {
            if (!["accent", "accentEnd", "background", "backgroundEnd"].includes(key)) return;
            root.settingsOpen = true;
            appearancePanel.chooseColor(key);
        }
        function state(): string { return JSON.stringify({nativeWorkspace:Hyprland.focusedWorkspace?.id,nativeMonitor:Hyprland.focusedMonitor?.name,nativeMonitors:Hyprland.monitors.values.map(m=>({name:m.name,workspace:m.activeWorkspace?.id})),settings:root.settings,workspaceVisible:root.workspaceVisible,visible:window.visible,screen:window.screen?.name,settingsOpen:root.settingsOpen,openingSoundCloud:browserOpener.running,openError:root.openError,media:root.media,audioStatus:root.audioStatus,maxWave:Math.max(0,...root.bars),hasStream:root.hasStream,error:root.backendError,hovered:cardHover.hovered,interacting:root.interacting,focusProgress:root.focusProgress,blurOpacity:blurWindow.HyprlandWindow.opacity,effectiveOpacity:card.opacity,windowStyle:root.windowStyle,barHeights:[waveRepeater.itemAt(0)?.height,waveRepeater.itemAt(10)?.height,waveRepeater.itemAt(20)?.height],barTargets:[root.bars[0],root.bars[10],root.bars[20]],snapshot:root.lastSnapshot}); }
        function configure(value: string): void { const v=JSON.parse(value); for (const key in v) root.setSetting(key,v[key]); }
        function control(action: string): void { if (action === "open") root.openSoundCloud(); else root.send({cmd:action}); }
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
    // Map the click-through blur surface first, then its sharp foreground.
    // Keeping it mapped at zero native opacity avoids hover remap animations.
    PanelWindow {
        id: blurWindow
        visible: root.shown && root.appliedConfigAck >= 0 && root.workspaceVisible
        screen: root.pinnedScreen
        implicitWidth: 350
        implicitHeight: content.implicitHeight + 40
        color: "transparent"
        anchors { right: root.settings.position.endsWith("right"); left: root.settings.position.endsWith("left"); top: root.settings.position.startsWith("top"); bottom: root.settings.position.startsWith("bottom") }
        margins { right: 24; left: 24; top: 86; bottom: 103 }
        exclusionMode: ExclusionMode.Ignore
        mask: Region {} // No mouse / keyboard interception by the backdrop.
        WlrLayershell.namespace: "soundcloud-widget-blur"
        WlrLayershell.layer: root.captureOverlay || root.settingsOpen ? WlrLayer.Overlay : (root.settings.onTop ? WlrLayer.Top : WlrLayer.Bottom)
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        // Unlike QML Item.opacity, this also fades compositor-applied blur.
        HyprlandWindow.opacity: 1 - root.focusProgress
        HyprlandWindow.visibleMask: Region { item: blurMask; radius: 17 }
        Rectangle {
            id: blurMask
            anchors.fill: parent; anchors.margins: 4; radius: 17
            // Minimal nonzero alpha above the scoped rule's ignore_alpha.
            color: "#01000000"
        }
    }
    PanelWindow {
        id: window
        visible: blurWindow.backingWindowVisible
        screen: root.pinnedScreen
        implicitWidth: 350
        implicitHeight: content.implicitHeight + 40
        color: "transparent"
        anchors { right: root.settings.position.endsWith("right"); left: root.settings.position.endsWith("left"); top: root.settings.position.startsWith("top"); bottom: root.settings.position.startsWith("bottom") }
        margins { right: 24; left: 24; top: 86; bottom: 103 }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "soundcloud-widget"
        WlrLayershell.layer: blurWindow.WlrLayershell.layer
        WlrLayershell.keyboardFocus: root.settingsOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        Rectangle {
            id: card
            anchors.fill: parent
            anchors.margins: 4
            radius: 17
            opacity: root.windowStyle.inactiveOpacity + (root.windowStyle.activeOpacity - root.windowStyle.inactiveOpacity) * root.focusProgress
            HoverHandler { id: cardHover }
            gradient: Gradient {
                orientation: root.settings.gradientDirection === "vertical" ? Gradient.Vertical : Gradient.Horizontal
                GradientStop { position: 0; color: root.withOpacity(root.backgroundColor, root.settings.opacity) }
                GradientStop { position: 1; color: root.withOpacity(root.backgroundEnd, root.settings.opacity) }
            }
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
                            id: playButton
                            implicitWidth: 36; implicitHeight: 36
                            padding: 0
                            Layout.alignment: Qt.AlignVCenter
                            enabled: root.media.playing ? !!root.media.canPause : !!root.media.canPlay
                            hoverEnabled: true
                            background: Rectangle {
                                radius: width / 2
                                color: playButton.enabled ? root.accent : "#596658"
                                scale: playButton.down ? .92 : (playButton.hovered ? 1.06 : 1)
                                Behavior on scale { NumberAnimation { duration: 120 } }
                            }
                            contentItem: Item {
                                Canvas {
                                    anchors.centerIn: parent; width: 18; height: 18
                                    property bool playing: !!root.media.playing
                                    property color ink: root.accent.hslLightness > .5 ? "#17251c" : "#eef3ec"
                                    onPlayingChanged: requestPaint()
                                    onInkChanged: requestPaint()
                                    onPaint: {
                                        const ctx = getContext("2d"); ctx.reset(); ctx.fillStyle = ink;
                                        if (playing) { ctx.fillRect(4,3,3,12); ctx.fillRect(11,3,3,12); }
                                        else { ctx.beginPath(); ctx.moveTo(5,2); ctx.lineTo(16,9); ctx.lineTo(5,16); ctx.closePath(); ctx.fill(); }
                                    }
                                }
                            }
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
                                gradient: Gradient {
                                    orientation: Gradient.Vertical
                                    GradientStop { position: 0; color: root.accent }
                                    GradientStop { position: 1; color: root.accentEnd }
                                }
                                opacity: .85
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
                    LabelText { text: root.openError || root.audioStatus; font.pixelSize: 9; color: root.muted; Layout.fillWidth: true; elide: Text.ElideRight }
                    SmallButton { text: browserOpener.running ? "…" : "↗"; enabled: !browserOpener.running; implicitWidth: 22; implicitHeight: 22; ToolTip.text: root.openError || "Открыть SoundCloud"; onClicked: root.openSoundCloud() }
                }
                SettingsPanel {
                    id: appearancePanel
                    visible: root.settingsOpen
                    Layout.fillWidth: true
                    controller: root
                    maxHeight: Math.max(260, (window.screen?.height || 1080) - 470)
                }
            }
        }
    }
}
