import QtQuick

// A lucide icon by name (see Icons.qml), drawn as SVG so it stays crisp at
// fractional DPI scales.
Item {
    id: root
    property string name: "info"
    property color color: Theme.text
    property real strokeWidth: 2
    property bool filled: false
    implicitWidth: 18
    implicitHeight: 18

    function bodyFor(icon) {
        return Icons.paths[icon] || Icons.paths.info;
    }

    function svgSource() {
        const stroke = String(root.color);
        const key = root.name + "|" + stroke + "|" + root.strokeWidth + "|" + root.filled;
        const cache = Icons.sources;
        const cached = cache.urls[key];
        if (cached) return cached;
        const iconFill = root.filled ? stroke : "none";
        const svg = "<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24' fill='" + iconFill
                + "' stroke='" + stroke + "' stroke-width='" + root.strokeWidth
                + "' stroke-linecap='round' stroke-linejoin='round'>" + root.bodyFor(root.name) + "</svg>";
        // Color animations would grow the cache without end; start it over.
        if (++cache.count > 2000) { cache.urls = {}; cache.count = 1; }
        return cache.urls[key] = "data:image/svg+xml;utf8," + encodeURIComponent(svg);
    }

    Image {
        anchors.fill: parent
        // Nothing to decode for an icon that isn't showing.
        source: root.name.length ? root.svgSource() : ""
        // Keep headroom for the canvas' 1.8x zoom and fractional Windows DPI.
        sourceSize.width: Math.max(1, Math.round(root.width * Icons.density * 2))
        sourceSize.height: Math.max(1, Math.round(root.height * Icons.density * 2))
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }
}
