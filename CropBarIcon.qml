import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

// Bar icon for the background-crop service. Click toggles crop editing
// (same action as the "Crop background" keybinding / omarchy-background-crop
// edit), and the icon color reflects whether editing is currently on.
BarWidget {
  id: root
  moduleName: "stickymongoose2.background-crop"

  readonly property var backgroundService: bar?.shell?.serviceFor(root.moduleName)
  readonly property bool cropEditing: backgroundService ? backgroundService.cropEditing : false
  readonly property int cropGlyphCodePoint: 0xf019e

  // Same on/dim convention as the built-in bar icons (see Tailscale's
  // barIconColor): full accent while editing, a darkened bar foreground
  // otherwise, so the icon reads as "off" without ever being invisible.
  readonly property color iconColor: cropEditing ? Color.accent : Qt.darker(root.bar.barForeground, 1.55)

  implicitWidth: barSize
  implicitHeight: barSize

  Text {
    id: glyph
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: String.fromCodePoint(root.cropGlyphCodePoint)
    color: root.iconColor
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.body
    Behavior on color {
      enabled: !root.bar || root.bar.foregroundAnimationEnabled
      ColorAnimation { duration: 160 }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: if (root.backgroundService) root.backgroundService.toggleCropEditing()
    onEntered: if (root.bar) root.bar.showTooltip(root, root.cropEditing
      ? "Crop editing on - drag to pan, scroll to zoom"
      : "Click to edit background crop")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
