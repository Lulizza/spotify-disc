import QtQuick
import QtQuick.Shapes
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Direcional de borracha de MP3 antigo: anel com 4 zonas + botão central.
//   cima = curtir · direita = próxima · baixo = letra · esquerda = anterior · centro = tocar/pausar
Item {
    id: pad

    property bool playing: false
    property bool canPrev: false
    property bool canNext: false
    property bool canPlayPause: false
    property bool playerOpen: true      // false: o centro abre o Spotify
    property bool canLike: false
    property bool liked: false
    property bool likeBusy: false
    property bool showLyrics: false
    property string likeTip
    property color ink: "#363A40"
    property color heartColor: "#D2343F"

    signal prevClicked()
    signal nextClicked()
    signal playClicked()
    signal likeClicked()
    signal lyricsClicked()

    readonly property real r: Math.min(width, height) / 2
    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real innerR: r * 0.42
    readonly property real iconDist: (r + innerR) / 2

    property string hoverZone: ""
    property string pressZone: ""

    function zoneAt(x, y) {
        const dx = x - cx, dy = y - cy
        const d = Math.hypot(dx, dy)
        if (d > r) return ""
        if (d <= innerR) return "play"
        if (Math.abs(dx) > Math.abs(dy)) return dx < 0 ? "prev" : "next"
        return dy < 0 ? "like" : "lyrics"
    }
    function zoneEnabled(z) {
        return z === "play" ? canPlayPause : z === "prev" ? canPrev : z === "next" ? canNext
             : z === "like" ? canLike : z === "lyrics"
    }
    function tipFor(z) {
        return z === "play" ? (!playerOpen ? i18n("Abrir Spotify") : playing ? i18n("Pausar") : i18n("Tocar"))
             : z === "prev" ? i18n("Anterior")
             : z === "next" ? i18n("Próxima")
             : z === "like" ? likeTip
             : z === "lyrics" ? (showLyrics ? i18n("Mostrar capa") : i18n("Mostrar letra"))
             : ""
    }
    // setor de 90° do anel, centrado no ângulo `a` (graus, 0 = direita)
    function sector(a, ro, ri) {
        const p = (rad, deg) => {
            const t = deg * Math.PI / 180
            return `${cx + rad * Math.cos(t)} ${cy + rad * Math.sin(t)}`
        }
        return `M ${p(ro, a - 45)} A ${ro} ${ro} 0 0 1 ${p(ro, a + 45)} L ${p(ri, a + 45)}`
             + ` A ${ri} ${ri} 0 0 0 ${p(ri, a - 45)} Z`
    }
    readonly property var zoneAngle: ({ next: 0, lyrics: 90, prev: 180, like: 270 })

    // rebaixo do corpo onde o direcional encaixa
    Rectangle {
        anchors.centerIn: parent
        width: pad.r * 2; height: width; radius: width / 2
        gradient: Gradient {
            GradientStop { position: 0; color: "#8C9097" }
            GradientStop { position: 1; color: "#E2E4E7" }
        }
    }

    // anel de borracha
    Rectangle {
        id: ring
        anchors.centerIn: parent
        width: pad.r * 2 - 4; height: width; radius: width / 2
        border.color: "#6C7077"
        border.width: 1
        gradient: Gradient {
            GradientStop { position: 0; color: "#B5B9BE" }
            GradientStop { position: 1; color: "#8F949A" }
        }
    }
    // brilho superior do anel
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: pad.cy - pad.r * 0.9
        width: pad.r * 0.8; height: pad.r * 0.3; radius: height / 2
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.35) }
            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        // divisões diagonais entre as zonas
        ShapePath {
            strokeColor: Qt.rgba(0, 0, 0, 0.16)
            strokeWidth: 1
            fillColor: "transparent"
            PathSvg {
                path: {
                    let s = ""
                    for (const a of [45, 135, 225, 315]) {
                        const t = a * Math.PI / 180
                        s += `M ${pad.cx + (pad.innerR + 3) * Math.cos(t)} ${pad.cy + (pad.innerR + 3) * Math.sin(t)} `
                           + `L ${pad.cx + (pad.r - 5) * Math.cos(t)} ${pad.cy + (pad.r - 5) * Math.sin(t)} `
                    }
                    return s
                }
            }
        }
        // zona pressionada escurece
        ShapePath {
            strokeWidth: -1
            fillColor: pad.pressZone !== "" && pad.pressZone !== "play" ? Qt.rgba(0, 0, 0, 0.18) : "transparent"
            PathSvg {
                path: pad.pressZone !== "" && pad.pressZone !== "play"
                    ? pad.sector(pad.zoneAngle[pad.pressZone], pad.r - 3, pad.innerR + 2) : ""
            }
        }
    }

    // ícones das 4 zonas
    component ZoneIcon: Kirigami.Icon {
        required property string zone
        readonly property real a: pad.zoneAngle[zone] * Math.PI / 180
        readonly property real shift: pad.pressZone === zone ? 1 : 0
        width: Math.round(pad.r * 0.24); height: width
        x: pad.cx + pad.iconDist * Math.cos(a) - width / 2 + shift * Math.cos(a)
        y: pad.cy + pad.iconDist * Math.sin(a) - height / 2 + shift * Math.sin(a)
        isMask: true
        color: pad.ink
        opacity: pad.zoneEnabled(zone) ? 0.9 : 0.3
    }
    ZoneIcon { zone: "prev"; source: "media-skip-backward" }
    ZoneIcon { zone: "next"; source: "media-skip-forward" }
    ZoneIcon { zone: "lyrics"; source: pad.showLyrics ? "media-optical-audio" : "view-media-lyrics" }

    Shape {
        readonly property real s: pad.r * 0.26
        width: 24; height: 24
        x: pad.cx - width / 2
        y: pad.cy - pad.iconDist - height / 2 - (pad.pressZone === "like" ? 1 : 0) + 1
        scale: s / 24
        preferredRendererType: Shape.CurveRenderer
        opacity: !pad.zoneEnabled("like") ? 0.3 : pad.likeBusy ? 0.5 : 0.95
        ShapePath {
            fillColor: pad.liked ? pad.heartColor : "transparent"
            strokeColor: pad.liked ? Qt.darker(pad.heartColor, 1.3) : pad.ink
            strokeWidth: 2.2
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M12 20.6l-1.3-1.2C6 15.2 3 12.4 3 8.9 3 6.1 5.2 4 7.9 4c1.6 0 3.1.7 4.1 1.9C13 4.7 14.5 4 16.1 4 18.8 4 21 6.1 21 8.9c0 3.5-3 6.3-7.7 10.5L12 20.6z" }
        }
    }

    // botão central (plástico convexo)
    Rectangle {
        id: center
        anchors.centerIn: parent
        width: pad.innerR * 2 - 4; height: width; radius: width / 2
        border.color: "#6C7077"
        border.width: 1
        scale: pad.pressZone === "play" ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: 80 } }
        gradient: Gradient {
            GradientStop { position: 0; color: pad.pressZone === "play" ? "#B4B8BD" : "#EEF0F2" }
            GradientStop { position: 1; color: pad.pressZone === "play" ? "#E2E4E7" : "#B0B4BA" }
        }
        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.round(parent.width * 0.42); height: width
            source: pad.playing ? "media-playback-pause" : "media-playback-start"
            isMask: true
            color: pad.ink
            opacity: pad.canPlayPause ? 0.9 : 0.3
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: pad.hoverZone !== "" && pad.zoneEnabled(pad.hoverZone) ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPositionChanged: m => pad.hoverZone = pad.zoneAt(m.x, m.y)
        onExited: pad.hoverZone = ""
        onPressed: m => {
            const z = pad.zoneAt(m.x, m.y)
            pad.pressZone = pad.zoneEnabled(z) ? z : ""
        }
        onCanceled: pad.pressZone = ""
        onReleased: m => {
            const z = pad.pressZone
            pad.pressZone = ""
            if (z === "" || pad.zoneAt(m.x, m.y) !== z) return
            if (z === "play") pad.playClicked()
            else if (z === "prev") pad.prevClicked()
            else if (z === "next") pad.nextClicked()
            else if (z === "like") pad.likeClicked()
            else if (z === "lyrics") pad.lyricsClicked()
        }
    }

    QQC2.ToolTip {
        visible: pad.hoverZone !== "" && !mouse.pressed && text !== ""
        text: pad.tipFor(pad.hoverZone)
        delay: Kirigami.Units.toolTipDelay
    }
}
