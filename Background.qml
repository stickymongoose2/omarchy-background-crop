import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import qs.Ui

Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"

  property string currentBackground: ""
  property string displayedBackground: ""
  property string incomingBackground: ""
  property string oldBackground: ""
  property bool finishingTransition: false
  property int backgroundVersion: 0
  property int revealStartedVersion: -1
  property int pendingThemeVersion: -1
  property string pendingColorsRaw: ""
  property string pendingShellRaw: ""
  property real revealProgress: 1

  // Per-monitor, per-image crop (pan/zoom) overrides. Keyed as
  // cropData[monitorName][imagePath] = { zoom, offsetX, offsetY }, all three
  // in the same units CropImage.qml expects. Missing entries mean "centered,
  // no extra zoom" - identical to the stock PreserveAspectCrop behavior.
  property string cropStatePath: stateHome + "/omarchy/background-crop.json"
  property var cropData: ({})
  property bool cropEditing: false

  function imageUrl(path) {
    return Util.fileUrl(path)
  }

  function clamp01(value) {
    return Math.max(0, Math.min(1, value))
  }

  function cropFor(monitorName, imagePath) {
    const byMonitor = root.cropData[monitorName]
    const entry = byMonitor && byMonitor[imagePath]
    return entry || { zoom: 1, offsetX: 0.5, offsetY: 0.5 }
  }

  function saveCrop(monitorName, imagePath, crop) {
    if (!monitorName || !imagePath) return
    const next = JSON.parse(JSON.stringify(root.cropData))
    if (!next[monitorName]) next[monitorName] = {}
    next[monitorName][imagePath] = {
      zoom: Math.max(1, Math.min(4, crop.zoom)),
      offsetX: clamp01(crop.offsetX),
      offsetY: clamp01(crop.offsetY)
    }
    root.cropData = next
    cropSaveTimer.restart()
  }

  function resetCrop(monitorName, imagePath) {
    if (!monitorName || !imagePath) return
    if (!root.cropData[monitorName] || !(imagePath in root.cropData[monitorName])) return
    const next = JSON.parse(JSON.stringify(root.cropData))
    delete next[monitorName][imagePath]
    root.cropData = next
    cropSaveTimer.restart()
  }

  function setCropEditing(value) {
    root.cropEditing = value
  }

  function toggleCropEditing() {
    root.cropEditing = !root.cropEditing
  }

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function setBackground(path, instant) {
    transitionBackground("", path, path, instant, false)
  }

  function transitionBackground(fromPath, path, finalPath, instant, force) {
    path = String(path || "").trim()
    finalPath = String(finalPath || path).trim()
    fromPath = String(fromPath || "").trim()
    if (!path || (!force && finalPath === currentBackground)) return
    currentBackground = finalPath
    backgroundVersion += 1
    revealStartedVersion = -1

    revealAnimation.stop()
    finishingTransition = false

    if (instant || !displayedBackground) {
      oldBackground = ""
      incomingBackground = ""
      displayedBackground = path
      revealProgress = 1
      return
    }

    oldBackground = fromPath || displayedBackground
    incomingBackground = path
    revealProgress = 0
  }

  function setPendingTheme(colorsB64, shellB64) {
    pendingColorsRaw = Util.decodeBase64(colorsB64)
    pendingShellRaw = Util.decodeBase64(shellB64)
    pendingThemeVersion = backgroundVersion
    pendingThemeFallbackTimer.restart()
  }

  function applyPendingTheme() {
    // Background polling can advance backgroundVersion while a theme switch is
    // pending; the latest theme payload should still apply.
    if (pendingThemeVersion < 0) return
    pendingThemeFallbackTimer.stop()
    Color.loadColors(pendingColorsRaw)
    // Color.loadShell also refreshes Style so the type scale flips with the
    // background reveal instead of waiting for a separate reload path.
    Color.loadShell(pendingShellRaw)
    Style.scheduleRefresh()
    pendingThemeVersion = -1
    pendingColorsRaw = ""
    pendingShellRaw = ""
  }

  function transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64) {
    transitionBackground(fromPath, path, finalPath, false, true)
    setPendingTheme(colorsB64, shellB64)
    if (!incomingBackground || revealProgress >= 1) applyPendingTheme()
  }

  function startReveal(panel) {
    if (!incomingBackground) return
    panel.maskReady = true
    if (revealStartedVersion === backgroundVersion) return
    revealStartedVersion = backgroundVersion
    applyPendingTheme()
    revealAnimation.restart()
  }

  function openSelector() {
    if (!bgSwitchProc.running) bgSwitchProc.running = true
  }

  function openThemeSwitcher() {
    if (!themeSwitchProc.running) themeSwitchProc.running = true
  }

  Process {
    id: bgSwitchProc
    command: ["bash", "-c", "background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set \"$background\""]
    onExited: root.refreshBackground()
  }

  Process {
    id: themeSwitchProc
    command: ["bash", "-c", "theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set \"$theme\" >/dev/null 2>&1 &"]
    onExited: root.refreshBackground()
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      onStreamFinished: root.setBackground(String(text || "").trim(), false)
    }
  }

  FileView {
    id: cropFile
    path: root.cropStatePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        const parsed = JSON.parse(text())
        root.cropData = (parsed && typeof parsed === "object") ? parsed : {}
      } catch (e) {
        root.cropData = {}
      }
    }
    onLoadFailed: root.cropData = {}
  }

  Timer {
    id: cropSaveTimer
    interval: 400
    repeat: false
    onTriggered: cropFile.setText(JSON.stringify(root.cropData, null, 2) + "\n")
  }

  IpcHandler {
    target: "background"

    function refresh(): void {
      root.refreshBackground()
    }

    function set(path: string): void {
      root.setBackground(path, false)
    }

    function setInstant(path: string): void {
      root.setBackground(path, true)
    }

    function transition(fromPath: string, path: string): void {
      root.transitionBackground(fromPath, path, path, false, false)
    }

    function themeTransition(fromPath: string, path: string, finalPath: string, colorsB64: string, shellB64: string): void {
      root.transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64)
    }

    function cropEditToggle(): void {
      root.toggleCropEditing()
    }

    function cropEditStart(): void {
      root.setCropEditing(true)
    }

    function cropEditStop(): void {
      root.setCropEditing(false)
    }

    function cropReset(monitorName: string): void {
      root.resetCrop(monitorName, root.displayedBackground)
    }

    function cropResetAll(): void {
      for (const monitorName in root.cropData) {
        root.resetCrop(monitorName, root.displayedBackground)
      }
    }
  }

  Timer {
    id: pendingThemeFallbackTimer
    interval: 300
    repeat: false
    onTriggered: root.applyPendingTheme()
  }

  NumberAnimation {
    id: revealAnimation
    target: root
    property: "revealProgress"
    from: 0
    to: 1
    duration: 420
    easing.type: Easing.InOutCubic
    onFinished: {
      if (root.incomingBackground) {
        root.displayedBackground = root.currentBackground || root.incomingBackground
        root.finishingTransition = true
      }
      root.revealProgress = 1
    }
  }

  Component.onCompleted: refreshBackground()

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      visible: !remapGuard.remapping
      anchors { top: true; bottom: true; left: true; right: true }

      ScreenMoveRemap {
        id: remapGuard
        window: panel
      }
      color: "transparent"
      // Keep render updates enabled. The background layer has been observed to
      // lose its committed buffer while parked with updatesEnabled=false,
      // leaving a black desktop until omarchy-shell is restarted. The wallpaper
      // itself is static, so this favors correctness over a small render-loop
      // optimization.
      updatesEnabled: true

      property bool maskReady: false

      function maybeStartReveal() {
        if (!root.incomingBackground || root.revealProgress !== 0 || maskReady) return
        if (incomingFrame.status !== Image.Ready) return
        Qt.callLater(function() {
          if (!root.incomingBackground || root.revealProgress !== 0 || maskReady) return
          if (incomingFrame.status !== Image.Ready) return
          root.startReveal(panel)
        })
      }

      WlrLayershell.namespace: "omarchy-background"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      CropImage {
        id: base
        anchors.fill: parent
        source: root.imageUrl(root.displayedBackground)
        asynchronous: true
        cache: true
        zoom: root.cropFor(panel.modelData.name, root.displayedBackground).zoom
        offsetX: root.cropFor(panel.modelData.name, root.displayedBackground).offsetX
        offsetY: root.cropFor(panel.modelData.name, root.displayedBackground).offsetY
        onStatusChanged: {
          if (status === Image.Ready && root.finishingTransition) {
            root.incomingBackground = ""
            root.oldBackground = ""
            root.finishingTransition = false
          }
        }
      }

      CropImage {
        id: oldFrame
        anchors.fill: parent
        source: root.imageUrl(root.oldBackground)
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        zoom: root.cropFor(panel.modelData.name, root.oldBackground).zoom
        offsetX: root.cropFor(panel.modelData.name, root.oldBackground).offsetX
        offsetY: root.cropFor(panel.modelData.name, root.oldBackground).offsetY
        visible: root.oldBackground !== "" && root.revealProgress < 1
        onStatusChanged: panel.maybeStartReveal()
      }

      Item {
        id: incomingLayer
        anchors.fill: parent
        visible: root.incomingBackground !== "" && incomingFrame.status === Image.Ready && (root.revealProgress >= 1 || panel.maskReady)
        layer.enabled: root.incomingBackground !== "" && root.revealProgress < 1
        layer.smooth: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: revealMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 0.02
        }

        CropImage {
          id: incomingFrame
          anchors.fill: parent
          source: root.imageUrl(root.incomingBackground)
          asynchronous: true
          cache: false
          smooth: true
          mipmap: true
          zoom: root.cropFor(panel.modelData.name, root.incomingBackground).zoom
          offsetX: root.cropFor(panel.modelData.name, root.incomingBackground).offsetX
          offsetY: root.cropFor(panel.modelData.name, root.incomingBackground).offsetY
          onStatusChanged: panel.maybeStartReveal()
        }
      }

      Item {
        id: revealMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        readonly property real slant: -0.18
        readonly property real centerTop: width / 2 - slant * height / 2
        readonly property real centerBottom: width / 2 + slant * height / 2
        readonly property real reach: width / 2 + Math.abs(slant) * height / 2 + 4
        readonly property real spread: reach * root.revealProgress

        Shape {
          anchors.fill: parent
          antialiasing: true
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            fillColor: "white"
            strokeColor: "transparent"
            startX: revealMask.centerTop - revealMask.spread; startY: 0
            PathLine { x: revealMask.centerTop + revealMask.spread; y: 0 }
            PathLine { x: revealMask.centerBottom + revealMask.spread; y: revealMask.height }
            PathLine { x: revealMask.centerBottom - revealMask.spread; y: revealMask.height }
            PathLine { x: revealMask.centerTop - revealMask.spread; y: 0 }
          }
        }
      }

      Connections {
        target: root
        function onIncomingBackgroundChanged() {
          panel.maskReady = false
          panel.maybeStartReveal()
        }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onDoubleClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.openThemeSwitcher()
          else root.openSelector()
          mouse.accepted = true
        }
      }

      // Crop editing: drag to pan, scroll to zoom. Only active while
      // root.cropEditing is on, so it never steals the double-click handling
      // above during normal use.
      MouseArea {
        id: cropArea
        anchors.fill: parent
        enabled: root.cropEditing
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property real lastX: 0
        property real lastY: 0

        onPressed: function(mouse) {
          lastX = mouse.x
          lastY = mouse.y
        }

        onPositionChanged: function(mouse) {
          if (!pressed) return
          const dx = mouse.x - lastX
          const dy = mouse.y - lastY
          lastX = mouse.x
          lastY = mouse.y

          const crop = root.cropFor(panel.modelData.name, root.displayedBackground)
          const rangeX = panel.width - base.contentWidth
          const rangeY = panel.height - base.contentHeight
          root.saveCrop(panel.modelData.name, root.displayedBackground, {
            zoom: crop.zoom,
            offsetX: rangeX !== 0 ? crop.offsetX + dx / rangeX : crop.offsetX,
            offsetY: rangeY !== 0 ? crop.offsetY + dy / rangeY : crop.offsetY
          })
        }

        onWheel: function(wheel) {
          const crop = root.cropFor(panel.modelData.name, root.displayedBackground)
          const step = (wheel.angleDelta.y / 120) * 0.1
          root.saveCrop(panel.modelData.name, root.displayedBackground, {
            zoom: crop.zoom + step,
            offsetX: crop.offsetX,
            offsetY: crop.offsetY
          })
          wheel.accepted = true
        }
      }

      Rectangle {
        id: cropHud
        visible: root.cropEditing
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 32
        radius: 8
        color: "#cc1a1a1a"
        width: cropHudText.implicitWidth + 28
        height: cropHudText.implicitHeight + 18

        Text {
          id: cropHudText
          anchors.centerIn: parent
          color: "white"
          font.pixelSize: 14
          horizontalAlignment: Text.AlignHCenter
          text: {
            const crop = root.cropFor(panel.modelData.name, root.displayedBackground)
            return panel.modelData.name + "  ·  zoom " + crop.zoom.toFixed(2) + "x" +
              "  ·  pos " + Math.round(crop.offsetX * 100) + "%, " + Math.round(crop.offsetY * 100) + "%" +
              "\nDrag to pan · Scroll to zoom · Super+Ctrl+Alt+Shift+C resets · Super+Ctrl+Alt+C finishes"
          }
        }
      }
    }
  }
}
