import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Controls as QQC2
import QtQuick.Effects

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.mpris as Mpris
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    // ------------------------------------------------------------- player
    Mpris.Mpris2Model { id: mpris2Model }

    // fonte grafite gerada a partir da foto (tools/build_font.py)
    FontLoader { id: tagFont; source: Qt.resolvedUrl("../fonts/SpotifyDiscTag.otf") }
    readonly property string tagFamily: tagFont.status === FontLoader.Ready ? tagFont.font.family : Kirigami.Theme.defaultFont.family

    property var player: null

    function pickPlayer() {
        let found = null
        for (let i = 0; i < players.count; ++i) {
            const o = players.objectAt(i)
            if (!o || o.multiplexer || !o.c) continue
            if (/spotify/i.test(o.de) || /spotify/i.test(o.ident)) { found = o.c; break }
        }
        if (!found && Plasmoid.configuration.anyPlayer) found = mpris2Model.currentPlayer
        player = found
    }

    Instantiator {
        id: players
        model: mpris2Model
        delegate: QtObject {
            property var c: model.container
            property string de: model.desktopEntry || ""
            property string ident: model.identity || ""
            property bool multiplexer: !!model.isMultiplexer
            onCChanged: Qt.callLater(root.pickPlayer)
            onDeChanged: Qt.callLater(root.pickPlayer)
            onIdentChanged: Qt.callLater(root.pickPlayer)
        }
        onObjectAdded: Qt.callLater(root.pickPlayer)
        onObjectRemoved: Qt.callLater(root.pickPlayer)
    }
    Connections {
        target: Plasmoid.configuration
        function onAnyPlayerChanged() { root.pickPlayer() }
    }
    Connections {
        target: mpris2Model
        function onCurrentPlayerChanged() { if (Plasmoid.configuration.anyPlayer) root.pickPlayer() }
    }

    readonly property bool hasPlayer: player !== null
    readonly property bool playing: hasPlayer && player.playbackStatus === Mpris.PlaybackStatus.Playing

    // sem player, mostra a última música tocada (salva na configuração)
    readonly property var cfg: Plasmoid.configuration
    readonly property string track: hasPlayer ? (player.track || "") : cfg.lastTrack
    readonly property string artist: hasPlayer ? (player.artist || "") : cfg.lastArtist
    readonly property string album: hasPlayer ? (player.album || "") : cfg.lastAlbum
    readonly property string artUrl: hasPlayer ? (player.artUrl || "") : cfg.lastArtUrl
    readonly property real lengthSec: hasPlayer ? Math.max(0, player.length / 1e6) : cfg.lastLength
    readonly property bool showingLast: !hasPlayer && track !== ""

    // posição interpolada localmente (o MPRIS não emite mudanças contínuas)
    property real posStamp: Date.now()
    property real tick: Date.now()
    readonly property real livePositionSec: {
        if (!hasPlayer) return 0
        let p = player.position / 1e6
        if (playing) p += Math.max(0, tick - posStamp) / 1000 * (player.rate || 1)
        return lengthSec > 0 ? Math.min(p, lengthSec) : p
    }
    readonly property real positionSec: hasPlayer ? livePositionSec : Math.min(cfg.lastPosition, lengthSec)
    Connections {
        target: root.player
        ignoreUnknownSignals: true
        function onPositionChanged() { root.posStamp = Date.now(); root.tick = root.posStamp }
        function onPlaybackStatusChanged() {
            root.posStamp = Date.now(); root.tick = root.posStamp
            root.player.updatePosition()
            Qt.callLater(root.saveLastPosition)
        }
    }

    // ---------------------------------------------------- última música
    function saveLastTrack() {
        if (!hasPlayer || !player.track) return
        if (cfg.lastTrack !== track || cfg.lastArtist !== artist) {
            cfg.lastTrackId = ""   // o id é preenchido pelo helper do like
            cfg.lastPosition = 0
        }
        cfg.lastTrack = track
        cfg.lastArtist = artist
        cfg.lastAlbum = album
        if (artUrl) cfg.lastArtUrl = artUrl
        if (lengthSec > 0) cfg.lastLength = lengthSec
    }
    function saveLastPosition() {
        if (hasPlayer && player.track && cfg.lastTrack === track) cfg.lastPosition = livePositionSec
    }
    Timer { id: saveDebounce; interval: 500; onTriggered: root.saveLastTrack() }
    onArtUrlChanged: if (hasPlayer) saveDebounce.restart()
    onAlbumChanged: if (hasPlayer) saveDebounce.restart()
    onLengthSecChanged: if (hasPlayer) saveDebounce.restart()
    Timer {
        // guarda a posição de tempos em tempos para sobreviver ao fechamento do Spotify
        interval: 5000; repeat: true
        running: root.playing
        onTriggered: root.saveLastPosition()
    }
    Timer {
        interval: 250; repeat: true
        running: root.playing && (root.expanded || Plasmoid.formFactor === PlasmaCore.Types.Planar)
        onTriggered: root.tick = Date.now()
    }
    Timer {
        interval: 2000; repeat: true; triggeredOnStart: true
        running: root.playing
        onTriggered: root.player.updatePosition()
    }

    function seekTo(sec) {
        if (!hasPlayer || !player.canSeek) return
        player.position = Math.round(Math.max(0, Math.min(sec, lengthSec)) * 1e6)
        posStamp = Date.now(); tick = posStamp
    }

    function fmt(sec) {
        sec = Math.max(0, Math.floor(sec))
        const m = Math.floor(sec / 60), s = sec % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    // --------------------------------------------------------------- cores
    // MP3 player antigo: corpo de plástico cinza + LCD verde-acinzentado
    readonly property color bodyTop: "#D5D8DC"
    readonly property color bodyBottom: "#A8ACB2"
    readonly property color bodyEdge: "#7A7E85"
    readonly property color engrave: "#5E6269"
    readonly property color bezel: "#2F3237"
    readonly property color lcdTop: "#BEC7AD"
    readonly property color lcdBottom: "#A6AF95"
    readonly property color ink: "#1E2619"        // pixels "ligados" do LCD
    readonly property color inkSoft: "#4B5741"
    readonly property color likedColor: "#D2343F"

    // ---------------------------------------------------------------- like
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("../code/spotify_like.py").toString().replace(/^file:\/\//, ""))
    property string likeState: "unknown"     // unknown | liked | notliked | noauth | busy | error

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        property var callbacks: ({})
        onNewData: (source, data) => {
            const cb = callbacks[source]
            delete callbacks[source]
            disconnectSource(source)
            let res = null
            try { res = JSON.parse((data["stdout"] || "").trim().split("\n").pop()) } catch (e) { res = { error: data["stderr"] || "falha" } }
            if (cb) cb(res)
        }
        function run(cmd, cb) {
            if (callbacks[cmd] !== undefined) return
            callbacks[cmd] = cb
            connectSource(cmd)
        }
    }

    function handleLike(res) {
        if (!res || res.error) {
            likeState = res && (res.error === "noauth") ? "noauth"
                      : res && (res.error === "notrack") ? "unknown" : "error"
            if (res && res.error && res.error !== "noauth" && res.error !== "notrack")
                console.warn("spotifydisc:", res.error)
            return
        }
        likeState = res.liked ? "liked" : "notliked"
        if (hasPlayer && validTrackId(res.trackId) && cfg.lastTrack === track) cfg.lastTrackId = res.trackId
    }
    function validTrackId(id) { return /^[A-Za-z0-9]{22}$/.test(id || "") }
    // com o Spotify fechado, consulta/alterna pelo id salvo da última música
    function trackArg() { return !hasPlayer && validTrackId(cfg.lastTrackId) ? " " + cfg.lastTrackId : "" }
    function refreshLike() {
        if (!track || (!hasPlayer && !validTrackId(cfg.lastTrackId))) { likeState = "unknown"; return }
        exec.run("python3 '" + helper + "' status" + trackArg(), handleLike)
    }
    function toggleLike() {
        if (likeState === "noauth") { Plasmoid.internalAction("configure").trigger(); return }
        if (likeState === "busy" || !track) return
        if (!hasPlayer && !validTrackId(cfg.lastTrackId)) return
        const prev = likeState
        likeState = "busy"
        exec.run("python3 '" + helper + "' toggle" + trackArg(), res => {
            handleLike(res)
            if (likeState === "error") likeState = prev
        })
    }
    // ------------------------------------------------------ abrir Spotify
    // tenta o .desktop do Flatpak, depois o nativo, depois o binário
    property bool launching: false
    function openSpotify() {
        if (hasPlayer || launching) return
        launching = true
        launchTimeout.restart()
        exec.run("sh -c 'kstart --application com.spotify.Client || kstart --application spotify || spotify' >/dev/null 2>&1 &", null)
    }
    Timer { id: launchTimeout; interval: 20000; onTriggered: root.launching = false }

    Timer { id: likeDebounce; interval: 800; onTriggered: root.refreshLike() }
    onTrackChanged: { likeDebounce.restart(); if (hasPlayer) saveDebounce.restart() }
    onArtistChanged: { likeDebounce.restart(); if (hasPlayer) saveDebounce.restart() }
    onHasPlayerChanged: { likeDebounce.restart(); if (hasPlayer) launching = false }

    // ----------------------------------------------------------- plasmoide
    property bool showLyrics: false

    Plasmoid.icon: "media-optical-audio"
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.status: hasPlayer ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus
    toolTipMainText: track || i18n("Spotify")
    toolTipSubText: hasPlayer ? artist
        : showingLast ? i18n("%1 · Spotify fechado", artist) : i18n("Spotify não está aberto")
    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar ? fullRepresentation : compactRepresentation

    compactRepresentation: MouseArea {
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton && root.hasPlayer) root.player.PlayPause()
            else root.expanded = !root.expanded
        }
        Image {
            anchors.fill: parent
            anchors.margins: 2
            source: root.artUrl
            fillMode: Image.PreserveAspectCrop
            visible: status === Image.Ready
            sourceSize: Qt.size(64, 64)
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: compactMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
            Rectangle {
                id: compactMask
                anchors.fill: parent; radius: width / 2
                visible: false; layer.enabled: true
            }
        }
        Kirigami.Icon {
            anchors.fill: parent
            source: "media-optical-audio"
            visible: root.artUrl === ""
        }
    }

    fullRepresentation: Item {
        id: full
        Layout.preferredWidth: Kirigami.Units.gridUnit * 17
        Layout.preferredHeight: Kirigami.Units.gridUnit * 30
        Layout.minimumWidth: Kirigami.Units.gridUnit * 12
        Layout.minimumHeight: Kirigami.Units.gridUnit * 22

        // ------------------------------------------------ corpo de plástico
        Rectangle {
            id: body
            anchors.fill: parent
            radius: Kirigami.Units.gridUnit * 0.6
            border.color: root.bodyEdge
            border.width: 1
            gradient: Gradient {
                GradientStop { position: 0; color: root.bodyTop }
                GradientStop { position: 0.5; color: Qt.darker(root.bodyTop, 1.04) }
                GradientStop { position: 1; color: root.bodyBottom }
            }
            layer.enabled: Plasmoid.formFactor === PlasmaCore.Types.Planar
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.45)
                shadowBlur: 0.6
                shadowVerticalOffset: 3
            }
            // chanfro: luz em cima, sombra embaixo
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.55)
                border.width: 1
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: parent.radius - 2
                color: "transparent"
                border.color: Qt.rgba(0, 0, 0, 0.06)
                border.width: 2
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.gridUnit * 0.9
            spacing: Kirigami.Units.smallSpacing * 2

            // ------------------------------------- LED + selo MP3
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                Item { Layout.fillWidth: true }
                Rectangle {
                    // LED: verde tocando, apagado parado
                    implicitWidth: 7; implicitHeight: 7; radius: 3.5
                    color: root.playing ? "#5CFF7A" : "#4C5A4F"
                    border.color: Qt.rgba(0, 0, 0, 0.35)
                    Behavior on color { ColorAnimation { duration: 200 } }
                    layer.enabled: root.playing
                    layer.effect: MultiEffect {
                        shadowEnabled: true; shadowColor: "#5CFF7A"
                        shadowBlur: 0.5; shadowHorizontalOffset: 0; shadowVerticalOffset: 0
                    }
                }
                Rectangle {
                    implicitWidth: mp3Label.implicitWidth + 8
                    implicitHeight: mp3Label.implicitHeight + 2
                    radius: 3
                    color: "transparent"
                    border.color: root.engrave
                    QQC2.Label {
                        id: mp3Label
                        anchors.centerIn: parent
                        text: "MP3"
                        color: root.engrave
                        font.bold: true
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize * 0.85
                    }
                }
            }

            // ---------------------------------------- moldura + tela LCD
            Rectangle {
                id: bezelRect
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Kirigami.Units.gridUnit * 12
                radius: Kirigami.Units.gridUnit * 0.3
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.darker(root.bezel, 1.2) }
                    GradientStop { position: 1; color: root.bezel }
                }
                border.color: Qt.rgba(1, 1, 1, 0.5)   // borda de luz onde a moldura encontra o plástico
                border.width: 1

                Rectangle {
                    id: lcd
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.gridUnit * 0.45
                    radius: 3
                    clip: true
                    gradient: Gradient {
                        GradientStop { position: 0; color: root.lcdTop }
                        GradientStop { position: 1; color: root.lcdBottom }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.gridUnit * 0.5
                        spacing: Kirigami.Units.smallSpacing

                        // barra de status do LCD
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon {
                                implicitWidth: 12; implicitHeight: 12
                                source: root.playing ? "media-playback-start" : "media-playback-pause"
                                isMask: true; color: root.ink
                                opacity: root.hasPlayer ? 1 : 0.35
                            }
                            QQC2.Label {
                                text: root.showLyrics ? "LRC" : "CD"
                                color: root.ink
                                font.bold: true
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize * 0.85
                            }
                            QQC2.Label {
                                text: "♥"
                                visible: root.likeState === "liked"
                                color: root.ink
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            }
                            Item { Layout.fillWidth: true }
                            // bateria (decorativa)
                            Row {
                                spacing: 0
                                Rectangle {
                                    width: 18; height: 9
                                    color: "transparent"
                                    border.color: root.ink; border.width: 1
                                    Row {
                                        anchors.fill: parent; anchors.margins: 2
                                        spacing: 1
                                        Repeater {
                                            model: 3
                                            Rectangle { width: 4; height: parent.height; color: root.ink }
                                        }
                                    }
                                }
                                Rectangle { width: 2; height: 4; anchors.verticalCenter: parent.verticalCenter; color: root.ink }
                            }
                        }
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.alpha(root.ink, 0.4) }

                        // disco / letra
                        Item {
                            id: box
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: Kirigami.Units.gridUnit * 5

                            Disc {
                                id: disc
                                readonly property real side: Math.min(box.width, box.height) - Kirigami.Units.gridUnit * 0.6
                                width: side; height: side
                                anchors.centerIn: parent
                                source: root.artUrl
                                spinning: root.playing
                                spinEnabled: Plasmoid.configuration.spinDisc
                                accent: "#8A9099"
                                opacity: root.showLyrics ? 0 : 1
                                visible: opacity > 0
                                scale: root.showLyrics ? 0.85 : 1
                                Behavior on opacity { NumberAnimation { duration: 300 } }
                                Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            }

                            LyricsView {
                                anchors.fill: parent
                                track: root.track
                                artist: root.artist
                                album: root.album
                                lengthSec: root.lengthSec
                                positionSec: root.positionSec
                                fg: root.inkSoft
                                accent: root.ink
                                active: root.showLyrics
                                opacity: root.showLyrics ? 1 : 0
                                visible: opacity > 0
                                Behavior on opacity { NumberAnimation { duration: 300 } }
                                onSeekRequested: s => root.seekTo(s)
                            }

                            // sem Spotify aberto, clicar na tela abre o Spotify
                            MouseArea {
                                anchors.fill: parent
                                enabled: !root.hasPlayer && !root.showLyrics
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openSpotify()
                                QQC2.ToolTip.visible: containsMouse && !root.launching
                                QQC2.ToolTip.text: i18n("Abrir Spotify")
                                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                hoverEnabled: true
                            }
                        }

                        // título/artista
                        QQC2.Label {
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            text: root.launching ? i18n("Abrindo Spotify…")
                                : root.track || (root.hasPlayer ? i18n("Sem título") : i18n("Spotify não está aberto"))
                            color: root.ink
                            font.family: root.tagFamily
                            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.5
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            text: root.artist
                            visible: text !== ""
                            color: root.inkSoft
                            font.family: root.tagFamily
                            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.1
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: i18n("Última tocada · Spotify fechado")
                            visible: root.showingLast
                            color: root.inkSoft
                            font: Kirigami.Theme.smallFont
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }

                        // equalizer (visual apenas: o MPRIS não expõe o áudio, então as
                        // barras são animadas com alturas aleatórias enquanto toca)
                        Item {
                            id: eq
                            Layout.fillWidth: true
                            implicitHeight: Kirigami.Units.gridUnit * 0.9

                            readonly property real barW: 3
                            readonly property real gap: 2
                            readonly property int count: Math.max(1, Math.floor((width + gap) / (barW + gap)))
                            readonly property real step: count > 1 ? (width - barW) / (count - 1) : 0
                            // segmentos de LCD: alturas em degraus
                            readonly property int segments: 5
                            readonly property real segH: height / segments
                            property int seed: 0

                            Timer {
                                interval: 140; repeat: true
                                running: root.playing && (root.expanded || Plasmoid.formFactor === PlasmaCore.Types.Planar)
                                onTriggered: eq.seed++
                            }

                            Repeater {
                                model: eq.count
                                Rectangle {
                                    required property int index
                                    readonly property real pos: eq.count > 1 ? index / (eq.count - 1) : 0
                                    readonly property real envelope: 0.45 + 0.55 * Math.pow(1 - pos, 1.4)
                                    readonly property real level: {
                                        eq.seed
                                        return root.playing ? (0.15 + 0.85 * Math.random()) * envelope : 0
                                    }
                                    x: index * eq.step
                                    width: eq.barW
                                    height: Math.max(1, Math.ceil(level * eq.segments)) * eq.segH
                                    anchors.bottom: parent.bottom
                                    color: root.playing ? root.ink : Qt.alpha(root.ink, 0.35)
                                }
                            }
                            // linhas na cor do LCD cortando as barras em segmentos
                            Repeater {
                                model: eq.segments - 1
                                Rectangle {
                                    required property int index
                                    width: eq.width; height: 1
                                    y: (index + 1) * eq.segH - 0.5
                                    color: root.lcdBottom
                                }
                            }
                        }

                        // progresso
                        Item {
                            id: progress
                            Layout.fillWidth: true
                            implicitHeight: Kirigami.Units.gridUnit * 0.8
                            enabled: root.hasPlayer && root.player.canSeek && root.lengthSec > 0

                            readonly property real frac: dragArea.pressed ? dragArea.dragFrac
                                : (root.lengthSec > 0 ? root.positionSec / root.lengthSec : 0)

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width; height: 8
                                color: "transparent"
                                border.color: root.ink; border.width: 1
                                Rectangle {
                                    x: 2; y: 2
                                    width: (parent.width - 4) * Math.max(0, Math.min(1, progress.frac))
                                    height: parent.height - 4
                                    color: root.ink
                                }
                            }
                            Rectangle {
                                width: 4; height: 14
                                color: root.ink
                                anchors.verticalCenter: parent.verticalCenter
                                x: progress.width * Math.max(0, Math.min(1, progress.frac)) - width / 2
                                visible: progress.enabled && (dragArea.containsMouse || dragArea.pressed)
                            }
                            MouseArea {
                                id: dragArea
                                anchors.fill: parent
                                anchors.topMargin: -4; anchors.bottomMargin: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                property real dragFrac: 0
                                function fracAt(x) { return Math.max(0, Math.min(1, x / width)) }
                                onPressed: mouse => dragFrac = fracAt(mouse.x)
                                onPositionChanged: mouse => { if (pressed) dragFrac = fracAt(mouse.x) }
                                onReleased: mouse => root.seekTo(fracAt(mouse.x) * root.lengthSec)
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            QQC2.Label {
                                text: root.fmt(dragArea.pressed ? dragArea.dragFrac * root.lengthSec : root.positionSec)
                                color: root.ink
                                font.family: root.tagFamily
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize * 1.1
                            }
                            Item { Layout.fillWidth: true }
                            QQC2.Label {
                                text: "-" + root.fmt(Math.max(0, root.lengthSec - (dragArea.pressed ? dragArea.dragFrac * root.lengthSec : root.positionSec)))
                                color: root.ink
                                font.family: root.tagFamily
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize * 1.1
                            }
                        }
                    }

                    // sombra interna no topo (tela afundada) + reflexo do vidro
                    Rectangle {
                        anchors.top: parent.top
                        width: parent.width; height: 8
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.22) }
                            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0) }
                        }
                    }
                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeWidth: -1
                            fillGradient: LinearGradient {
                                x1: 0; y1: 0; x2: lcd.width * 0.5; y2: lcd.height * 0.5
                                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.22) }
                                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
                            }
                            startX: 0; startY: 0
                            PathLine { x: lcd.width * 0.75; y: 0 }
                            PathLine { x: 0; y: lcd.height * 0.55 }
                            PathLine { x: 0; y: 0 }
                        }
                    }
                }
            }

            // ------------------------------------------------- direcional
            DPad {
                readonly property real side: Math.min(full.width * 0.6, full.height * 0.3, Kirigami.Units.gridUnit * 9)
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Kirigami.Units.smallSpacing
                Layout.bottomMargin: Kirigami.Units.smallSpacing * 2
                Layout.preferredWidth: side
                Layout.preferredHeight: side

                playing: root.playing
                canPrev: root.hasPlayer && root.player.canGoPrevious
                canNext: root.hasPlayer && root.player.canGoNext
                canPlayPause: !root.hasPlayer ? !root.launching
                    : (root.playing ? root.player.canPause : root.player.canPlay)
                playerOpen: root.hasPlayer
                canLike: root.track !== "" && (root.hasPlayer || root.validTrackId(root.cfg.lastTrackId))
                liked: root.likeState === "liked"
                likeBusy: root.likeState === "busy"
                heartColor: root.likedColor
                showLyrics: root.showLyrics
                likeTip: root.likeState === "noauth" ? i18n("Conecte sua conta do Spotify nas configurações")
                    : root.likeState === "liked" ? i18n("Remover das Músicas Curtidas")
                    : root.likeState === "error" ? i18n("Erro ao falar com o Spotify")
                    : i18n("Salvar em Músicas Curtidas")

                onPlayClicked: root.hasPlayer ? root.player.PlayPause() : root.openSpotify()
                onPrevClicked: root.player.Previous()
                onNextClicked: root.player.Next()
                onLikeClicked: root.toggleLike()
                onLyricsClicked: root.showLyrics = !root.showLyrics
            }
        }
    }
}
