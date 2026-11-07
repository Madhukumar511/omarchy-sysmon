import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "atomic.sysmon"
  ipcTarget: "atomic.sysmon"
  manageIpc: false

  ShellIpc {
    target: "atomic.sysmon"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function next(): string { root.nextMode(); return "ok" }
    function prev(): string { root.prevMode(); return "ok" }
  }

  // Accurate Hardware Stats Model (Initialized with 0/empty to prevent stale flash)
  property var stats: ({
    "cpu_model": "Processor",
    "gpu_model": "Graphics",
    "cpu_pct": 0.0,
    "cpu_temp": 40.0,
    "cpu_freq": 1.8,
    "cores": [],
    "gpu_mhz": 300,
    "gpu_max_mhz": 1150,
    "gpu_pct": 0,
    "fan_rpm": 0,
    "fan_max": 7000,
    "fan_pct": 0,
    "fan_status": "Passive / Off",
    "mem_used": 0.0,
    "mem_total": 15.4,
    "mem_pct": 0,
    "load_1m": 0.50
  })

  // Mode 0: Overview, 1: Thermals, 2: Clocks, 3: Memory
  property int displayMode: 0
  property int pendingMode: 0
  property bool scrollUp: false

  readonly property color accentColor: Commons.Color.accent
  readonly property color secondaryColor: Commons.Color.accent
  readonly property color barTextColor: bar ? bar.barForeground : Commons.Color.bar.text
  readonly property color surfaceBg: Commons.Color.popups.background
  readonly property string barFont: bar ? bar.fontFamily : Style.font.family

  function nextMode() {
    displayMode = (displayMode + 1) % 4
  }

  function prevMode() {
    displayMode = (displayMode + 3) % 4
  }

  property bool tempInFahrenheit: false

  function metricColor(pct) {
    if (pct >= 85) return "#ef4444"
    if (pct >= 65) return "#f59e0b"
    return accentColor
  }

  function tempColor(temp) {
    if (temp >= 90) return "#ef4444"
    if (temp >= 75) return "#f59e0b"
    return accentColor
  }

  function refresh() {
    if (!statsProc.running) {
      statsProc.running = true
    }
  }

  // Live Accurate Hardware Stats Process
  Process {
    id: statsProc
    command: ["/usr/bin/python3", Qt.resolvedUrl("scripts/get_stats.py").toString().replace(/^file:\/\//, "")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          if (data && data.cpu_pct !== undefined) {
            root.stats = data
          }
        } catch (e) {}
      }
    }
  }

  // Periodic refresh: 1s when detailed popup is open, 2s on the bar
  Timer {
    interval: root.opened ? 1000 : 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: root.refresh()

  // Open panel indicator aligns with the button label
  readonly property real openPanelIndicatorWidth: button.labelWidth

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string fanText: {
    if (root.stats.fan_rpm > 1000) return (root.stats.fan_rpm / 1000.0).toFixed(1) + "k"
    if (root.stats.fan_rpm > 0) return root.stats.fan_rpm + ""
    return "Off"
  }

  readonly property string barDisplayText: {
    if (root.displayMode === 1) {
      // Mode 1: Thermals
      return " " + Math.round(root.stats.cpu_temp) + "°C   󰈐 " + fanText
    }
    if (root.displayMode === 2) {
      // Mode 2: Frequencies
      return " " + root.stats.cpu_freq.toFixed(2) + " GHz   󰢮 " + root.stats.gpu_mhz + " MHz"
    }
    if (root.displayMode === 3) {
      // Mode 3: Memory & Load
      return " " + root.stats.mem_used + "G (" + root.stats.mem_pct + "%)   󰓅 " + root.stats.load_1m.toFixed(2)
    }
    // Mode 0: Overview (CPU % · GPU % · Fan)
    return " " + Math.round(root.stats.cpu_pct) + "%   󰢮 " + Math.round(root.stats.gpu_pct) + "%   󰈐 " + fanText
  }

  readonly property string barTooltipText: {
    var modeNames = ["Overview", "Thermals", "Clocks", "Memory & Load"]
    var t = "Hardware Monitor (" + modeNames[root.displayMode] + ")\n\n"
    t += "• CPU:  " + Math.round(root.stats.cpu_pct) + "%  (" + root.stats.cpu_freq.toFixed(2) + " GHz, " + Math.round(root.stats.cpu_temp) + "°C)\n"
    t += "• GPU:  " + Math.round(root.stats.gpu_pct) + "%  (" + root.stats.gpu_mhz + " MHz)\n"
    t += "• Fan:  " + (root.stats.fan_rpm > 0 ? root.stats.fan_rpm + " RPM" : "Off (Passive)") + "\n"
    t += "• RAM:  " + root.stats.mem_used + "G / " + root.stats.mem_total + "G (" + root.stats.mem_pct + "%)\n"
    t += "• Load: " + root.stats.load_1m.toFixed(2) + " (1 min)\n\n"
    t += "Click: Open Telemetry Panel\n"
    t += "Right-click or Scroll: Switch View"
    return t
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barDisplayText
    active: root.stats.cpu_temp >= 85 || root.stats.cpu_pct >= 90
    useActiveColor: true
    activeColor: bar ? bar.urgent : Commons.Color.urgent
    horizontalMargin: 8.5
    tooltipText: root.barTooltipText

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) {
        root.nextMode()
      } else {
        root.toggle()
      }
    }

    onWheelMoved: function(delta) {
      if (delta > 0) root.prevMode()
      else if (delta < 0) root.nextMode()
    }
  }

  // Detailed Interactive Hardware Telemetry Popup Card
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(cardContent.implicitHeight + Style.space(20))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      focus: true
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_B) {
          if (root.bar) root.bar.run("omarchy launch or focus tui btop")
          else Quickshell.execDetached(["omarchy-launch-or-focus-tui", "btop"])
          root.close()
          event.accepted = true
        } else if (event.key === Qt.Key_R) {
          root.refresh()
          event.accepted = true
        } else if (event.key === Qt.Key_Tab) {
          root.nextMode()
          event.accepted = true
        }
      }

      Column {
        id: cardContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // Header Title & Interactive Refresh Trigger
        RowLayout {
          width: parent.width

          Row {
            spacing: Style.space(8)
            Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter

            // Futuristic Live Pulsing Dot with Expanding Radar Ripple
            Item {
              width: 14
              height: 14
              anchors.verticalCenter: parent.verticalCenter

              // Expanding Ripple Ring
              Rectangle {
                anchors.centerIn: parent
                width: 8
                height: 8
                radius: 4
                color: "transparent"
                border.width: 1.5
                border.color: root.accentColor
                scale: 1.0
                opacity: 0.8
                ParallelAnimation on scale {
                  loops: Animation.Infinite
                  NumberAnimation { from: 1.0; to: 2.3; duration: Style.duration(1400); easing.type: Easing.OutCubic }
                }
                ParallelAnimation on opacity {
                  loops: Animation.Infinite
                  NumberAnimation { from: 0.8; to: 0.0; duration: Style.duration(1400); easing.type: Easing.OutCubic }
                }
              }

              // Solid Center Dot
              Rectangle {
                anchors.centerIn: parent
                width: 7
                height: 7
                radius: 3.5
                color: root.accentColor
                SequentialAnimation on opacity {
                  loops: Animation.Infinite
                  NumberAnimation { from: 0.5; to: 1.0; duration: Style.duration(700); easing.type: Easing.InOutSine }
                  NumberAnimation { from: 1.0; to: 0.5; duration: Style.duration(700); easing.type: Easing.InOutSine }
                }
              }
            }

            Text {
              text: "HARDWARE TELEMETRY"
              textFormat: Text.PlainText
              renderType: Text.NativeRendering
              color: root.barTextColor
              font.family: root.barFont
              font.bold: true
              font.pixelSize: Style.font.subtitle
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Item { Layout.fillWidth: true }

          // Interactive Fan Status Badge / Refresh Trigger
          BorderSurface {
            id: fanBadge
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            implicitHeight: 22
            implicitWidth: fanBadgeRow.implicitWidth + Style.space(14)
            radius: 11
            color: badgeHover.containsMouse ? Util.alpha(root.accentColor, 0.25) : Util.alpha(root.accentColor, 0.12)
            borderSpec: Border.flat(badgeHover.containsMouse ? root.accentColor : Util.alpha(root.accentColor, 0.40), 1)
            scale: badgeMouse.pressed ? 0.94 : (badgeHover.containsMouse ? 1.03 : 1.0)

            Behavior on color { ColorAnimation { duration: Style.duration(120) } }
            Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

            Row {
              id: fanBadgeRow
              anchors.centerIn: parent
              spacing: Style.space(4)

              Text {
                text: "󰑐"
                font.family: root.barFont
                font.pixelSize: Style.font.caption
                color: root.accentColor
                anchors.verticalCenter: parent.verticalCenter
                rotation: statsProc.running ? 360 : 0
                Behavior on rotation {
                  NumberAnimation { duration: Style.duration(500); easing.type: Easing.OutCubic }
                }
              }

              Text {
                text: root.stats.fan_status
                textFormat: Text.PlainText
                renderType: Text.NativeRendering
                color: root.accentColor
                font.family: root.barFont
                font.bold: true
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            HoverHandler { id: badgeHover }
            MouseArea {
              id: badgeMouse
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.refresh()
            }
          }
        }

        PanelSeparator { foreground: root.barTextColor }

        // --- SECTION 1: INTERACTIVE CPU CARD ---
        BorderSurface {
          id: cpuCard
          width: parent.width
          implicitHeight: cpuCol.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: cpuHover.containsMouse ? Util.alpha(root.accentColor, 0.08) : Util.alpha(Commons.Color.background, 0.35)
          borderSpec: Border.flat(cpuHover.containsMouse ? Util.alpha(root.accentColor, 0.35) : Util.alpha(root.barTextColor, 0.08), 1)
          scale: cpuMouse.pressed ? 0.99 : (cpuHover.containsMouse ? 1.006 : 1.0)

          Behavior on color { ColorAnimation { duration: Style.duration(140) } }
          Behavior on scale { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }

          Column {
            id: cpuCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(8)
            spacing: Style.space(6)

            RowLayout {
              width: parent.width
              Row {
                spacing: Style.space(6)
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Text {
                  text: ""
                  color: root.metricColor(root.stats.cpu_pct)
                  font.family: root.barFont
                  font.pixelSize: Style.font.body
                  renderType: Text.NativeRendering
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  text: "CPU: " + (root.stats.cpu_model || "Processor")
                  color: root.barTextColor
                  font.family: root.barFont
                  font.bold: true
                  font.pixelSize: Style.font.body
                  renderType: Text.NativeRendering
                  elide: Text.ElideRight
                  width: Style.space(200)
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
              Item { Layout.fillWidth: true }
              Text {
                text: root.stats.cpu_pct.toFixed(1) + "% (" + root.stats.cpu_freq.toFixed(2) + " GHz)"
                color: root.metricColor(root.stats.cpu_pct)
                font.family: root.barFont
                font.bold: true
                font.pixelSize: Style.font.body
                renderType: Text.NativeRendering
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
              }
            }

            // Animated Dynamic Progress Bar with Glowing Tip
            Item {
              width: parent.width
              height: Style.space(6)

              Rectangle {
                anchors.fill: parent
                radius: 3
                color: Util.alpha(root.barTextColor, 0.12)
              }

              Rectangle {
                height: parent.height
                width: Math.max(6, parent.width * (root.stats.cpu_pct / 100.0))
                radius: 3
                color: root.metricColor(root.stats.cpu_pct)

                Behavior on width { NumberAnimation { duration: Style.duration(320); easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: Style.duration(200) } }

                Rectangle {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(6)
                  height: Style.space(6)
                  radius: 3
                  color: "#ffffff"
                  opacity: 0.75
                }
              }
            }

            // Interactive Cores & Thermals grid
            Row {
              width: parent.width
              spacing: Style.space(8)

              Repeater {
                model: root.stats.cores.length > 0 ? root.stats.cores : [
                  {"name": "Core 0", "temp": root.stats.cpu_temp},
                  {"name": "Core 1", "temp": root.stats.cpu_temp},
                  {"name": "Core 2", "temp": root.stats.cpu_temp},
                  {"name": "Core 3", "temp": root.stats.cpu_temp}
                ]

                BorderSurface {
                  implicitHeight: 24
                  implicitWidth: (cpuCol.width - Style.space(24)) / 4
                  radius: 6
                  color: chipHover.containsMouse ? Util.alpha(root.tempColor(modelData.temp), 0.22) : Util.alpha(Commons.Color.background, 0.40)
                  borderSpec: Border.flat(chipHover.containsMouse ? root.tempColor(modelData.temp) : Util.alpha(root.barTextColor, 0.15), 1)
                  scale: chipMouse.pressed ? 0.92 : (chipHover.containsMouse ? 1.04 : 1.0)

                  Behavior on color { ColorAnimation { duration: Style.duration(120) } }
                  Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

                  Row {
                    anchors.centerIn: parent
                    spacing: 4
                    Text {
                      text: modelData.name.replace("Core ", "C") + ":"
                      color: root.barTextColor
                      opacity: 0.6
                      font.family: root.barFont
                      font.pixelSize: Style.font.caption
                      renderType: Text.NativeRendering
                      verticalAlignment: Text.AlignVCenter
                    }
                    Text {
                      text: root.tempInFahrenheit ? Math.round(modelData.temp * 9/5 + 32) + "°F" : Math.round(modelData.temp) + "°"
                      color: root.tempColor(modelData.temp)
                      font.family: root.barFont
                      font.bold: true
                      font.pixelSize: Style.font.caption
                      renderType: Text.NativeRendering
                      verticalAlignment: Text.AlignVCenter
                    }
                  }

                  HoverHandler { id: chipHover }
                  MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.tempInFahrenheit = !root.tempInFahrenheit
                    }
                  }
                }
              }
            }
          }

          HoverHandler { id: cpuHover }
          MouseArea {
            id: cpuMouse
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.bar) root.bar.run("omarchy launch or focus tui btop")
              else Quickshell.execDetached(["omarchy-launch-or-focus-tui", "btop"])
            }
          }
        }

        // --- SECTION 2: INTERACTIVE GPU CARD ---
        BorderSurface {
          id: gpuCard
          width: parent.width
          implicitHeight: gpuCol.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: gpuHover.containsMouse ? Util.alpha(root.accentColor, 0.08) : Util.alpha(Commons.Color.background, 0.35)
          borderSpec: Border.flat(gpuHover.containsMouse ? Util.alpha(root.accentColor, 0.35) : Util.alpha(root.barTextColor, 0.08), 1)
          scale: gpuMouse.pressed ? 0.99 : (gpuHover.containsMouse ? 1.006 : 1.0)

          Behavior on color { ColorAnimation { duration: Style.duration(140) } }
          Behavior on scale { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }

          Column {
            id: gpuCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(8)
            spacing: Style.space(6)

            RowLayout {
              width: parent.width
              Row {
                spacing: Style.space(6)
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Text {
                  text: "󰢮"
                  color: root.metricColor(root.stats.gpu_pct)
                  font.family: root.barFont
                  font.pixelSize: Style.font.body
                  renderType: Text.NativeRendering
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  text: "GPU: " + (root.stats.gpu_model || "Graphics")
                  color: root.barTextColor
                  font.family: root.barFont
                  font.bold: true
                  font.pixelSize: Style.font.body
                  renderType: Text.NativeRendering
                  elide: Text.ElideRight
                  width: Style.space(200)
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
              Item { Layout.fillWidth: true }
              Text {
                text: root.stats.gpu_pct.toFixed(1) + "% (" + root.stats.gpu_mhz + " MHz)"
                color: root.metricColor(root.stats.gpu_pct)
                font.family: root.barFont
                font.bold: true
                font.pixelSize: Style.font.body
                renderType: Text.NativeRendering
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
              }
            }

            // Animated GPU Utilization Bar
            Item {
              width: parent.width
              height: Style.space(6)

              Rectangle {
                anchors.fill: parent
                radius: 3
                color: Util.alpha(root.barTextColor, 0.12)
              }

              Rectangle {
                height: parent.height
                width: Math.max(root.stats.gpu_pct > 0 ? 6 : 0, parent.width * (root.stats.gpu_pct / 100.0))
                radius: 3
                color: root.metricColor(root.stats.gpu_pct)

                Behavior on width { NumberAnimation { duration: Style.duration(320); easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: Style.duration(200) } }

                Rectangle {
                  visible: root.stats.gpu_pct > 0
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(6)
                  height: Style.space(6)
                  radius: 3
                  color: "#ffffff"
                  opacity: 0.75
                }
              }
            }

            // GPU Clock Frequency Subtitle
            RowLayout {
              width: parent.width
              Text {
                text: "Clock: " + root.stats.gpu_mhz + " MHz  (Min " + (root.stats.gpu_min_mhz || 300) + " · Max " + (root.stats.gpu_max_mhz || 1150) + " MHz)"
                color: root.barTextColor
                opacity: 0.60
                font.family: root.barFont
                font.pixelSize: Style.font.caption
                renderType: Text.NativeRendering
              }
            }
          }

          HoverHandler { id: gpuHover }
          MouseArea {
            id: gpuMouse
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.bar) root.bar.run("omarchy launch or focus tui btop")
              else Quickshell.execDetached(["omarchy-launch-or-focus-tui", "btop"])
            }
          }
        }

        // --- SECTION 3: INTERACTIVE ACTIVE COOLING FAN CARD ---
        BorderSurface {
          id: fanCard
          width: parent.width
          implicitHeight: fanCol.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: fanHover.containsMouse ? Util.alpha(root.accentColor, 0.08) : Util.alpha(Commons.Color.background, 0.35)
          borderSpec: Border.flat(fanHover.containsMouse ? Util.alpha(root.accentColor, 0.35) : Util.alpha(root.barTextColor, 0.08), 1)
          scale: fanMouse.pressed ? 0.99 : (fanHover.containsMouse ? 1.006 : 1.0)

          Behavior on color { ColorAnimation { duration: Style.duration(140) } }
          Behavior on scale { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }

          Column {
            id: fanCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(8)
            spacing: Style.space(6)

            RowLayout {
              width: parent.width
              Row {
                spacing: Style.space(8)
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter

                Text {
                  id: fanIcon
                  text: "󰈐"
                  color: root.stats.fan_rpm > 5000 ? "#ef4444" : (root.stats.fan_rpm > 0 ? root.accentColor : root.barTextColor)
                  opacity: root.stats.fan_rpm > 0 ? 1.0 : 0.65
                  font.family: root.barFont
                  font.pixelSize: Style.font.title
                  renderType: Text.NativeRendering
                  anchors.verticalCenter: parent.verticalCenter

                  RotationAnimation on rotation {
                    running: root.stats.fan_rpm > 0
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: Math.max(250, 2200 - Math.min(1950, root.stats.fan_rpm * 0.35))
                  }
                }

                Text {
                  text: "Active Cooling Fan"
                  color: root.barTextColor
                  font.family: root.barFont
                  font.bold: true
                  font.pixelSize: Style.font.body
                  renderType: Text.NativeRendering
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
              Item { Layout.fillWidth: true }
              Text {
                text: root.stats.fan_rpm > 0 
                  ? root.stats.fan_rpm + " RPM (" + root.stats.fan_pct + "%)"
                  : "Passive Cooling (Off)"
                color: root.stats.fan_rpm > 5000 ? "#ef4444" : root.accentColor
                font.family: root.barFont
                font.bold: true
                font.pixelSize: Style.font.body
                renderType: Text.NativeRendering
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
              }
            }

            // Animated Fan Speed Bar
            Item {
              width: parent.width
              height: Style.space(6)

              Rectangle {
                anchors.fill: parent
                radius: 3
                color: Util.alpha(root.barTextColor, 0.12)
              }

              Rectangle {
                height: parent.height
                width: Math.max(root.stats.fan_pct > 0 ? 6 : 0, parent.width * (root.stats.fan_pct / 100.0))
                radius: 3
                color: root.stats.fan_rpm > 5000 ? "#ef4444" : root.accentColor

                Behavior on width { NumberAnimation { duration: Style.duration(320); easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: Style.duration(200) } }

                Rectangle {
                  visible: root.stats.fan_pct > 0
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(6)
                  height: Style.space(6)
                  radius: 3
                  color: "#ffffff"
                  opacity: 0.75
                }
              }
            }
          }

          HoverHandler { id: fanHover }
          MouseArea {
            id: fanMouse
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.refresh()
          }
        }

        // --- SECTION 4: INTERACTIVE MEMORY & LOAD CARD ---
        BorderSurface {
          id: memCard
          width: parent.width
          implicitHeight: memCol.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: memHover.containsMouse ? Util.alpha(root.accentColor, 0.08) : Util.alpha(Commons.Color.background, 0.35)
          borderSpec: Border.flat(memHover.containsMouse ? Util.alpha(root.accentColor, 0.35) : Util.alpha(root.barTextColor, 0.08), 1)
          scale: memMouse.pressed ? 0.99 : (memHover.containsMouse ? 1.006 : 1.0)

          Behavior on color { ColorAnimation { duration: Style.duration(140) } }
          Behavior on scale { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }

          Column {
            id: memCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(8)
            spacing: Style.space(6)

            RowLayout {
              width: parent.width
              Row {
                spacing: Style.space(6)
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Text {
                  text: ""
                  color: root.metricColor(root.stats.mem_pct)
                  font.family: root.barFont
                  font.pixelSize: Style.font.body
                  renderType: Text.NativeRendering
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  text: "Memory: " + root.stats.mem_used + "G / " + root.stats.mem_total + "G"
                  color: root.barTextColor
                  font.family: root.barFont
                  font.bold: true
                  font.pixelSize: Style.font.body
                  renderType: Text.NativeRendering
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
              Item { Layout.fillWidth: true }
              Text {
                text: root.stats.mem_pct + "% · Load " + root.stats.load_1m.toFixed(2)
                color: root.metricColor(root.stats.mem_pct)
                font.family: root.barFont
                font.bold: true
                font.pixelSize: Style.font.body
                renderType: Text.NativeRendering
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
              }
            }

            // Animated RAM Progress Bar
            Item {
              width: parent.width
              height: Style.space(6)

              Rectangle {
                anchors.fill: parent
                radius: 3
                color: Util.alpha(root.barTextColor, 0.12)
              }

              Rectangle {
                height: parent.height
                width: Math.max(6, parent.width * (root.stats.mem_pct / 100.0))
                radius: 3
                color: root.metricColor(root.stats.mem_pct)

                Behavior on width { NumberAnimation { duration: Style.duration(320); easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: Style.duration(200) } }

                Rectangle {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(6)
                  height: Style.space(6)
                  radius: 3
                  color: "#ffffff"
                  opacity: 0.75
                }
              }
            }
          }

          HoverHandler { id: memHover }
          MouseArea {
            id: memMouse
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.bar) root.bar.run("omarchy launch or focus tui btop")
              else Quickshell.execDetached(["omarchy-launch-or-focus-tui", "btop"])
            }
          }
        }

        PanelSeparator { foreground: root.barTextColor }

        // --- SECTION 5: INTERACTIVE FOOTER ACTIONS ---
        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          // Switch Bar Metric Mode Quick Button
          Button {
            Layout.fillWidth: true
            text: {
              var names = ["Overview", "Thermals", "Clocks", "RAM & Load"]
              return "󰑐 View: " + names[root.displayMode]
            }
            fontSize: Style.font.bodySmall
            foreground: root.barTextColor
            fontFamily: root.barFont
            bordered: true
            onClicked: root.nextMode()
          }

          // Launch Btop Terminal Dashboard Button
          Button {
            Layout.fillWidth: true
            text: "Launch Btop"
            iconText: "󰄬"
            fontSize: Style.font.bodySmall
            foreground: root.barTextColor
            fontFamily: root.barFont
            bordered: true
            active: true
            onClicked: {
              if (root.bar) root.bar.run("omarchy launch or focus tui btop")
              else Quickshell.execDetached(["omarchy-launch-or-focus-tui", "btop"])
              root.close()
            }
          }
        }
      }
    }
  }
}
