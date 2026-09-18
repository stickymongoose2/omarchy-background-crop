import QtQuick

// Image that fills its parent like Image.PreserveAspectCrop, but lets the
// crop be shifted (offsetX/offsetY, 0..1 each axis) and zoomed in
// (zoom >= 1) instead of always centering. zoom 1 / offset 0.5,0.5
// reproduces the stock centered crop exactly.
Item {
  id: root
  clip: true

  property alias source: img.source
  property alias asynchronous: img.asynchronous
  property alias cache: img.cache
  property alias smooth: img.smooth
  property alias mipmap: img.mipmap
  property alias status: img.status
  property alias contentWidth: img.width
  property alias contentHeight: img.height

  property real zoom: 1
  property real offsetX: 0.5
  property real offsetY: 0.5

  Image {
    id: img
    fillMode: Image.Stretch

    readonly property real natW: implicitWidth > 0 ? implicitWidth : root.width
    readonly property real natH: implicitHeight > 0 ? implicitHeight : root.height
    readonly property real minScale: (root.width > 0 && root.height > 0 && natW > 0 && natH > 0)
      ? Math.max(root.width / natW, root.height / natH) : 1
    readonly property real scaleFactor: minScale * Math.max(1, root.zoom)

    width: natW * scaleFactor
    height: natH * scaleFactor
    x: (root.width - width) * Math.max(0, Math.min(1, root.offsetX))
    y: (root.height - height) * Math.max(0, Math.min(1, root.offsetY))
  }
}
