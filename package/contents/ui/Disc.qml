import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

// Disco estilo DVD/CD: capa recortada em anel, hub transparente,
// reflexo iridescente fixo (a luz não gira com o disco).
Item {
    id: disc

    property url source
    property bool spinning: false
    property bool spinEnabled: true
    property color accent: "#888"

    readonly property real r: Math.min(width, height) / 2
    readonly property real cx: width / 2
    readonly property real cy: height / 2
    // proporções reais de um disco de 120 mm: furo 15 mm, área de dados a partir de ~46 mm
    readonly property real holeR: r * 0.125
    readonly property real hubR: r * 0.36

    // círculo em 4 arcos de 90° (arcos de 180° em SVG são ambíguos e geram emenda)
    function circle(rr) {
        return `M ${cx + rr} ${cy} A ${rr} ${rr} 0 0 1 ${cx} ${cy + rr} A ${rr} ${rr} 0 0 1 ${cx - rr} ${cy}`
             + ` A ${rr} ${rr} 0 0 1 ${cx} ${cy - rr} A ${rr} ${rr} 0 0 1 ${cx + rr} ${cy} Z`
    }
    function ring(ro, ri) {
        return ri > 0 ? circle(ro) + " " + circle(ri) : circle(ro)
    }

    // sombra (fonte em anel, para não escurecer o furo central)
    Item {
        id: shadowSrc
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1; fillColor: "black"; fillRule: ShapePath.OddEvenFill
                PathSvg { path: disc.ring(disc.r * 0.985, disc.holeR) }
            }
        }
    }
    MultiEffect {
        anchors.fill: parent
        source: shadowSrc
        shadowEnabled: true
        shadowColor: Qt.rgba(0, 0, 0, 0.6)
        shadowBlur: 0.8
        shadowVerticalOffset: disc.r * 0.035
        paddingRect: Qt.rect(disc.r * 0.2, disc.r * 0.2, disc.r * 0.2, disc.r * 0.2)
        autoPaddingEnabled: false
    }

    // ---------------------------------------------------------------- girando
    Item {
        id: rotor
        anchors.fill: parent

        NumberAnimation on rotation {
            from: 0; to: 360
            duration: 9000
            loops: Animation.Infinite
            running: disc.spinEnabled
            paused: !disc.spinning
        }

        Image {
            id: cover
            anchors.fill: parent
            source: disc.source
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(512, 512)
            smooth: true
            mipmap: true
            asynchronous: true
            visible: false
        }

        // disco "vazio" quando não há capa
        Rectangle {
            id: blank
            anchors.fill: parent
            visible: false
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.lighter(disc.accent, 1.4) }
                GradientStop { position: 1; color: Qt.darker(disc.accent, 1.6) }
            }
        }

        Item {
            id: dataMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: -1; fillColor: "white"; fillRule: ShapePath.OddEvenFill
                    PathSvg { path: disc.ring(disc.r, disc.holeR) }
                }
            }
        }

        MultiEffect {
            anchors.fill: parent
            source: cover.status === Image.Ready ? cover : blank
            maskEnabled: true
            maskSource: dataMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        // hub de plástico transparente
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                fillRule: ShapePath.OddEvenFill
                fillGradient: RadialGradient {
                    centerX: disc.cx; centerY: disc.cy; centerRadius: disc.hubR
                    focalX: disc.cx; focalY: disc.cy
                    GradientStop { position: 0.30; color: Qt.rgba(1, 1, 1, 0.55) }
                    GradientStop { position: 0.55; color: Qt.rgba(0.85, 0.88, 0.92, 0.35) }
                    GradientStop { position: 1.00; color: Qt.rgba(1, 1, 1, 0.15) }
                }
                PathSvg { path: disc.ring(disc.hubR, disc.holeR) }
            }
            // anéis finos do hub
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.rgba(1, 1, 1, 0.55)
                strokeWidth: Math.max(1, disc.r * 0.008)
                PathSvg { path: disc.ring(disc.hubR, 0) }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.rgba(0, 0, 0, 0.25)
                strokeWidth: Math.max(1, disc.r * 0.006)
                PathSvg { path: disc.ring(disc.hubR * 0.62, 0) }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.rgba(1, 1, 1, 0.7)
                strokeWidth: Math.max(1, disc.r * 0.01)
                PathSvg { path: disc.ring(disc.holeR * 1.12, 0) }
            }
        }
    }

    // ---------------------------------------------- reflexo iridescente (fixo)
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillRule: ShapePath.OddEvenFill
            fillGradient: ConicalGradient {
                centerX: disc.cx; centerY: disc.cy; angle: 35
                GradientStop { position: 0.00; color: Qt.rgba(1, 1, 1, 0.00) }
                GradientStop { position: 0.06; color: Qt.rgba(0.6, 0.9, 1.0, 0.22) }
                GradientStop { position: 0.10; color: Qt.rgba(1.0, 0.6, 0.9, 0.28) }
                GradientStop { position: 0.14; color: Qt.rgba(1.0, 1.0, 0.7, 0.20) }
                GradientStop { position: 0.22; color: Qt.rgba(1, 1, 1, 0.00) }
                GradientStop { position: 0.50; color: Qt.rgba(1, 1, 1, 0.00) }
                GradientStop { position: 0.56; color: Qt.rgba(0.6, 1.0, 0.8, 0.20) }
                GradientStop { position: 0.60; color: Qt.rgba(0.7, 0.7, 1.0, 0.26) }
                GradientStop { position: 0.64; color: Qt.rgba(1.0, 0.8, 0.6, 0.18) }
                GradientStop { position: 0.72; color: Qt.rgba(1, 1, 1, 0.00) }
                GradientStop { position: 1.00; color: Qt.rgba(1, 1, 1, 0.00) }
            }
            PathSvg { path: disc.ring(disc.r, disc.hubR) }
        }
        // borda externa
        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(1, 1, 1, 0.35)
            strokeWidth: Math.max(1, disc.r * 0.012)
            PathSvg { path: disc.ring(disc.r - Math.max(1, disc.r * 0.006), 0) }
        }
    }
}
