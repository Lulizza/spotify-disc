import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as P5Support

KCM.SimpleKCM {
    id: page

    property alias cfg_clientId: clientField.text
    property alias cfg_spinDisc: spinBox.checked
    property alias cfg_anyPlayer: anyBox.checked

    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("../code/spotify_like.py").toString().replace(/^file:\/\//, ""))
    readonly property bool validId: /^[0-9a-fA-F]{32}$/.test(clientField.text.trim())
    property string authStatus: ""
    property bool busy: false

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source)
            page.busy = false
            let res = null
            try { res = JSON.parse((data["stdout"] || "").trim().split("\n").pop()) } catch (e) {}
            if (res && res.ok) page.authStatus = source.indexOf(" logout") >= 0 ? i18n("Desconectado.") : i18n("✔ Conectado ao Spotify!")
            else page.authStatus = i18n("Falhou: %1", res && res.error ? res.error : (data["stderr"] || "?"))
        }
    }

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: spinBox
            Kirigami.FormData.label: i18n("Disco:")
            text: i18n("Girar enquanto toca")
        }
        QQC2.CheckBox {
            id: anyBox
            Kirigami.FormData.label: i18n("Player:")
            text: i18n("Usar outro player se o Spotify não estiver aberto")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Botão Curtir (Spotify Web API)")
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 26
            wrapMode: Text.WordWrap
            textFormat: Text.RichText
            onLinkActivated: link => Qt.openUrlExternally(link)
            text: i18n("O MPRIS não permite curtir músicas, então o widget usa a Web API do Spotify:<br>"
                + "1. Crie um app em <a href='https://developer.spotify.com/dashboard'>developer.spotify.com/dashboard</a> (marque <i>Web API</i>).<br>"
                + "2. Adicione o Redirect URI: <b>http://127.0.0.1:8898/callback</b><br>"
                + "3. Cole o Client ID abaixo e clique em Conectar.")
        }
        QQC2.TextField {
            id: clientField
            Kirigami.FormData.label: i18n("Client ID:")
            placeholderText: "32 caracteres hexadecimais"
            Layout.preferredWidth: Kirigami.Units.gridUnit * 18
        }
        RowLayout {
            QQC2.Button {
                text: i18n("Conectar ao Spotify")
                icon.name: "network-connect"
                enabled: page.validId && !page.busy
                onClicked: {
                    page.busy = true
                    page.authStatus = i18n("Aguardando login no navegador…")
                    exec.connectSource("python3 '" + page.helper + "' auth " + clientField.text.trim())
                }
            }
            QQC2.Button {
                text: i18n("Desconectar")
                icon.name: "network-disconnect"
                enabled: !page.busy
                onClicked: exec.connectSource("python3 '" + page.helper + "' logout")
            }
        }
        QQC2.Label {
            visible: page.authStatus !== ""
            text: page.authStatus
            wrapMode: Text.WordWrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 26
        }
    }
}
