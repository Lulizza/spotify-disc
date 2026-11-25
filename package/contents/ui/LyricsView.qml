import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Letras via LRCLIB (https://lrclib.net), gratuito e sem chave.
// Com letra sincronizada, destaca a linha atual e clicar numa linha faz seek.
Item {
    id: lyrics

    property string track
    property string artist
    property string album
    property real lengthSec: 0
    property real positionSec: 0
    property color fg: "white"
    property color accent: fg
    property bool active: false

    signal seekRequested(real seconds)

    property var lines: []        // [{t: seg, text: str}] ; t = -1 em letra não sincronizada
    property bool synced: false
    property string status: ""    // "", "loading", "notfound", "error", "instrumental"
    property string _key: ""
    property var _cache: ({})

    readonly property int currentLine: {
        if (!synced) return -1
        let idx = -1
        const p = positionSec + 0.25
        for (let i = 0; i < lines.length; ++i) {
            if (lines[i].t <= p) idx = i
            else break
        }
        return idx
    }

    function parseLrc(text) {
        const out = []
        const re = /\[(\d+):(\d+(?:\.\d+)?)\]/g
        for (const raw of text.split("\n")) {
            const stamps = []
            let m
            re.lastIndex = 0
            while ((m = re.exec(raw)) !== null) stamps.push(parseInt(m[1]) * 60 + parseFloat(m[2]))
            const body = raw.replace(re, "").trim()
            for (const t of stamps) out.push({ t: t, text: body.length ? body : "♪" })
        }
        out.sort((a, b) => a.t - b.t)
        return out
    }

    function apply(res) {
        if (!res) { lines = []; synced = false; status = "notfound"; return }
        if (res.instrumental) { lines = []; synced = false; status = "instrumental"; return }
        if (res.syncedLyrics) {
            lines = parseLrc(res.syncedLyrics); synced = true; status = ""
        } else if (res.plainLyrics) {
            lines = res.plainLyrics.split("\n").map(l => ({ t: -1, text: l }))
            synced = false; status = ""
        } else {
            lines = []; synced = false; status = "notfound"
        }
    }

    function request(url, cb) {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                try { cb(JSON.parse(xhr.responseText)) } catch (e) { cb(undefined, true) }
            } else cb(null, xhr.status !== 404)
        }
        xhr.open("GET", url)
        xhr.setRequestHeader("User-Agent", "SpotifyDiscPlasmoid/1.0")
        xhr.send()
    }

    function fetchLyrics() {
        if (!track) { lines = []; status = ""; return }
        const key = artist + "\u0001" + track
        if (key === _key) return
        _key = key
        if (_cache[key] !== undefined) { apply(_cache[key]); return }
        lines = []; synced = false; status = "loading"
        const q = s => encodeURIComponent(s)
        const getUrl = `https://lrclib.net/api/get?track_name=${q(track)}&artist_name=${q(artist)}`
            + (album ? `&album_name=${q(album)}` : "")
            + (lengthSec > 0 ? `&duration=${Math.round(lengthSec)}` : "")
        request(getUrl, (res, failed) => {
            if (key !== _key) return
            if (res) { _cache[key] = res; apply(res); return }
            // fallback: busca aproximada
            const searchUrl = `https://lrclib.net/api/search?track_name=${q(track)}&artist_name=${q(artist)}`
            request(searchUrl, (list, failed2) => {
                if (key !== _key) return
                if (Array.isArray(list) && list.length) {
                    const best = list.find(r => r.syncedLyrics) || list[0]
                    _cache[key] = best; apply(best)
                } else if (failed && failed2) {
                    status = "error"; _key = ""   // permite tentar de novo
                } else {
                    _cache[key] = null; apply(null)
                }
            })
        })
    }

    // só busca quando a aba de letra está aberta (ou já foi aberta)
    onTrackChanged: if (active) Qt.callLater(fetchLyrics)
    onArtistChanged: if (active) Qt.callLater(fetchLyrics)
    onActiveChanged: if (active) Qt.callLater(fetchLyrics)

    QQC2.Label {
        anchors.centerIn: parent
        width: parent.width * 0.8
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        visible: lyrics.status !== "" || (lyrics.lines.length === 0 && lyrics.track === "")
        color: lyrics.fg
        opacity: 0.75
        text: lyrics.status === "loading" ? i18n("Buscando letra…")
            : lyrics.status === "notfound" ? i18n("Letra não encontrada")
            : lyrics.status === "instrumental" ? i18n("♪ Instrumental ♪")
            : lyrics.status === "error" ? i18n("Não foi possível buscar a letra")
            : i18n("Nada tocando")
    }

    ListView {
        id: list
        anchors.fill: parent
        clip: true
        model: lyrics.lines
        spacing: Kirigami.Units.smallSpacing
        visible: lyrics.status === ""
        boundsBehavior: Flickable.StopAtBounds
        currentIndex: lyrics.currentLine
        highlightRangeMode: lyrics.synced && !userScrolling.running ? ListView.ApplyRange : ListView.NoHighlightRange
        preferredHighlightBegin: height * 0.38
        preferredHighlightEnd: height * 0.38 + Kirigami.Units.gridUnit * 2
        highlightMoveDuration: 400
        highlightFollowsCurrentItem: true
        header: Item { height: list.height * 0.15 }
        footer: Item { height: list.height * 0.4 }

        onMovementStarted: userScrolling.restart()
        Timer { id: userScrolling; interval: 3000 }

        delegate: QQC2.Label {
            required property var modelData
            required property int index
            width: ListView.view.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: modelData.text
            color: current ? lyrics.accent : lyrics.fg
            Behavior on color { ColorAnimation { duration: 250 } }
            readonly property bool current: index === lyrics.currentLine
            font.bold: lyrics.synced
            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * (current ? 1.25 : 1.05)
            opacity: !lyrics.synced ? 0.95 : current ? 1.0 : (index < lyrics.currentLine ? 0.4 : 0.6)
            Behavior on opacity { NumberAnimation { duration: 250 } }
            Behavior on font.pixelSize { NumberAnimation { duration: 200 } }

            MouseArea {
                anchors.fill: parent
                enabled: lyrics.synced
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: { userScrolling.stop(); lyrics.seekRequested(modelData.t) }
            }
        }
    }
}
