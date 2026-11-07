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

  // Real Hardware Stats Model
  property var stats: ({
    "cpu_model": "Processor",
    "gpu_model": "Graphics",
    "cpu_pct": 0.0,
    "cpu_temp": 40.0,
    "cpu_freq": 1.8,
    "cores": [],
    "gpu_mhz": 300,
    "gpu_max_mhz": 1150,
    "gpu_pct": 0.0,
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
  property bool tempInFahrenheit: false

  readonly property color foreground: bar ? bar.barForeground : Commons.Color.popups.text
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color fainter: Qt.darker(foreground, 2.1)
  readonly property color accentColor: Commons.Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function mix(from, to, t) {
    var r = from.r + (to.r - from.r) * t
    var g = from.g + (to.g - from.g) * t
    var b = from.b + (to.b - from.b) * t
    return Qt.rgba(r, g, b, 1)
  }

  function nextMode() {
    displayMode = (displayMode + 1) % 4
  }

  function prevMode() {
    displayMode = (displayMode + 3) % 4
  }

  function metricColor(pct) {
    if (pct >= 85) return "#ef4444"
    if (pct >= 65) return "#f59e0b"
    return accentColor
  }

  function tempColor(temp) {
    if (temp >= 85) return "#ef4444"
    if (temp >= 70) return "#f59e0b"
    return accentColor
  }

  function formatTemp(tempC) {
    if (root.tempInFahrenheit) {
      return Math.round(tempC * 9 / 5 + 32) + "°F"
    }
    return Math.round(tempC) + "°C"
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

  // Periodic refresh: 1.2s when popup is open, 2.5s on the bar
  Timer {
    interval: root.opened ? 1200 : 2500
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: root.refresh()

  // Open panel indicator aligns with button
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

  // World-Clock (Elsewhen) Inspired Hardware Telemetry Popup Panel
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

        // ---- HERO SECTION (Elsewhen Hero Style) ----
        Column {
          width: parent.width
          spacing: Style.space(3)

          // Subtitle Specs Caption
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: (root.stats.cpu_model || "Hardware") + " · " + (root.stats.gpu_model || "GPU")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            maximumLineCount: 1
          }

          // Centered Hero Title with Interactive Spinning Icon
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(8)

            Text {
              text: "Hardware"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.weight: Font.DemiBold
              anchors.verticalCenter: parent.verticalCenter
            }

            Item {
              id: heroIconBox
              width: Math.round(Style.font.title * 1.3)
              height: width
              anchors.verticalCenter: parent.verticalCenter

              Text {
                id: heroGlyph
                anchors.centerIn: parent
                text: "󰍛"
                color: root.accentColor
                font.family: root.fontFamily
                font.pixelSize: Math.round(parent.width * 0.95)
                rotation: 0
                transformOrigin: Item.Center

                RotationAnimation on rotation {
                  from: 0
                  to: 360
                  duration: Style.duration(1000)
                  loops: Animation.Infinite
                  running: (statsProc.running || heroMouse.containsMouse) && !Style.reduceMotion
                }
              }

              MouseArea {
                id: heroMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.refresh()
              }
            }

            Text {
              text: "Telemetry"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.weight: Font.DemiBold
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // ---- HARDWARE ROWS (Styled after Elsewhen CityRow + DaylightStrip) ----

        // 1. CPU ROW
        Rectangle {
          id: cpuRow
          width: parent.width
          implicitHeight: cpuCol.implicitHeight + Style.space(22)
          radius: Style.cornerRadius
          color: root.mix(Commons.Color.popups.background, root.foreground, cpuHover.hovered ? 0.12 : 0.065)
          scale: cpuMouse.pressed ? 0.985 : (cpuHover.hovered ? 1.008 : 1.0)

          Behavior on color { ColorAnimation { duration: Style.duration(140) } }
          Behavior on scale { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }

          Column {
            id: cpuCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(11)
            spacing: Style.space(8)

            // Top Header: Label + Live Usage
            RowLayout {
              width: parent.width

              Column {
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                spacing: Style.space(2)

                Row {
                  spacing: Style.space(6)
                  Text {
                    text: ""
                    color: root.metricColor(root.stats.cpu_pct)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Text {
                    text: "Processor"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.weight: Font.DemiBold
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Text {
                  text: root.stats.cpu_freq.toFixed(2) + " GHz · " + root.formatTemp(root.stats.cpu_temp)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Item { Layout.fillWidth: true }

              Text {
                text: root.stats.cpu_pct.toFixed(1) + "%"
                color: root.metricColor(root.stats.cpu_pct)
                font.family: root.fontFamily
                font.weight: Font.DemiBold
                font.pixelSize: Style.font.title
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
              }
            }

            // Per-Core Thermal Chips (Clickable to switch °C / °F)
            Row {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.stats.cores.length > 0 ? root.stats.cores : [
                  {"name": "Core 0", "temp": root.stats.cpu_temp},
                  {"name": "Core 1", "temp": root.stats.cpu_temp},
                  {"name": "Core 2", "temp": root.stats.cpu_temp},
                  {"name": "Core 3", "temp": root.stats.cpu_temp}
                ]

                Rectangle {
                  id: coreChip
                  implicitHeight: Style.space(22)
                  implicitWidth: (cpuCol.width - Style.space(18)) / 4
                  radius: Style.cornerRadius
                  color: root.mix(Commons.Color.popups.background, root.foreground, chipHover.hovered ? 0.16 : 0.08)
                  border.width: 1
                  border.color: chipHover.hovered ? root.tempColor(modelData.temp) : Util.alpha(root.foreground, 0.12)
                  scale: chipMouse.pressed ? 0.94 : (chipHover.hovered ? 1.04 : 1.0)

                  Behavior on color { ColorAnimation { duration: Style.duration(120) } }
                  Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }
                  Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

                  Row {
                    anchors.centerIn: parent
                    spacing: 3
                    Text {
                      text: modelData.name.replace("Core ", "C") + ":"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                      text: root.formatTemp(modelData.temp)
                      color: root.tempColor(modelData.temp)
                      font.family: root.fontFamily
                      font.weight: Font.DemiBold
                      font.pixelSize: Style.font.caption
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }

                  HoverHandler { id: chipHover }
                  MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.tempInFahrenheit = !root.tempInFahrenheit
                  }
                }
              }
            }

            // DaylightStrip Slider Track with Animated Gliding Thumb Dot
            Item {
              width: parent.width
              height: Style.space(12)

              // Track Background
              Rectangle {
                id: cpuTrack
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: Math.max(3, Style.space(3))
                radius: height / 2
                color: Util.alpha(root.foreground, 0.10)

                // Filled portion
                Rectangle {
                  height: parent.height
                  width: Math.max(height, parent.width * (Math.min(100.0, root.stats.cpu_pct) / 100.0))
                  radius: height / 2
                  color: Util.alpha(root.metricColor(root.stats.cpu_pct), 0.40)

                  Behavior on width { NumberAnimation { duration: Style.duration(380); easing.type: Easing.OutCubic } }
                }

                // Gliding Elsewhen-style Circular Thumb
                Rectangle {
                  id: cpuThumb
                  width: Math.max(8, Style.space(9))
                  height: width
                  radius: width / 2
                  color: root.metricColor(root.stats.cpu_pct)
                  border.width: 1.5
                  border.color: cpuHover.hovered ? "#ffffff" : root.metricColor(root.stats.cpu_pct)
                  anchors.verticalCenter: parent.verticalCenter
                  x: Math.round(Math.max(0, Math.min(parent.width - width, (parent.width - width) * (Math.min(100.0, root.stats.cpu_pct) / 100.0))))

                  Behavior on x { NumberAnimation { duration: Style.duration(380); easing.type: Easing.OutCubic } }
                  Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }
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
              root.close()
            }
          }
        }

        // 2. GPU ROW
        Rectangle {
          id: gpuRow
          width: parent.width
          implicitHeight: gpuCol.implicitHeight + Style.space(22)
          radius: Style.cornerRadius
          color: root.mix(Commons.Color.popups.background, root.foreground, gpuHover.hovered ? 0.12 : 0.065)
          scale: gpuMouse.pressed ? 0.985 : (gpuHover.hovered ? 1.008 : 1.0)

          Behavior on color { ColorAnimation { duration: Style.duration(140) } }
          Behavior on scale { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }

          Column {
            id: gpuCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(11)
            spacing: Style.space(8)

            RowLayout {
              width: parent.width

              Column {
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                spacing: Style.space(2)

                Row {
                  spacing: Style.space(6)
                  Text {
                    text: "󰢮"
                    color: root.metricColor(root.stats.gpu_pct)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Text {
                    text: root.stats.gpu_model || "Graphics"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.weight: Font.DemiBold
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Text {
                  text: root.stats.gpu_mhz + " MHz · Max " + root.stats.gpu_max_mhz + " MHz"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Item { Layout.fillWidth: true }

              Text {
                text: root.stats.gpu_pct.toFixed(1) + "%"
                color: root.metricColor(root.stats.gpu_pct)
                font.family: root.fontFamily
                font.weight: Font.DemiBold
                font.pixelSize: Style.font.title
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
              }
            }

            // DaylightStrip Slider Track
            Item {
              width: parent.width
              height: Style.space(12)

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: Math.max(3, Style.space(3))
                radius: height / 2
                color: Util.alpha(root.foreground, 0.10)

                Rectangle {
                  height: parent.height
                  width: Math.max(height, parent.width * (Math.min(100.0, root.stats.gpu_pct) / 100.0))
                  radius: height / 2
                  color: Util.alpha(root.metricColor(root.stats.gpu_pct), 0.40)

                  Behavior on width { NumberAnimation { duration: Style.duration(380); easing.type: Easing.OutCubic } }
                }

                Rectangle {
                  width: Math.max(8, Style.space(9))
                  height: width
                  radius: width / 2
                  color: root.metricColor(root.stats.gpu_pct)
                  border.width: 1.5
                  border.color: gpuHover.hovered ? "#ffffff" : root.metricColor(root.stats.gpu_pct)
                  anchors.verticalCenter: parent.verticalCenter
                  x: Math.round(Math.max(0, Math.min(parent.width - width, (parent.width - width) * (Math.min(100.0, root.stats.gpu_pct) / 100.0))))

                  Behavior on x { NumberAnimation { duration: Style.duration(380); easing.type: Easing.OutCubic } }
                  Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }
                }
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
              root.close()
            }
          }
        }

        // 3. COOLING FAN ROW
        Rectangle {
          id: fanRow
          width: parent.width
          implicitHeight: fanCol.implicitHeight + Style.space(22)
          radius: Style.cornerRadius
          color: root.mix(Commons.Color.popups.background, root.foreground, fanHover.hovered ? 0.12 : 0.065)
          scale: fanMouse.pressed ? 0.985 : (fanHover.hovered ? 1.008 : 1.0)

          Behavior on color { ColorAnimation { duration: Style.duration(140) } }
          Behavior on scale { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }

          Column {
            id: fanCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(11)
            spacing: Style.space(8)

            RowLayout {
              width: parent.width

              Column {
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                spacing: Style.space(2)

                Row {
                  spacing: Style.space(6)
                  Text {
                    text: "󰈐"
                    color: root.stats.fan_rpm > 0 ? root.accentColor : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                    rotation: 0
                    transformOrigin: Item.Center

                    // Interactive spinning fan blades when fan is active
                    RotationAnimation on rotation {
                      from: 0
                      to: 360
                      duration: root.stats.fan_rpm > 3500 ? Style.duration(400) : Style.duration(800)
                      loops: Animation.Infinite
                      running: root.stats.fan_rpm > 0 && !Style.reduceMotion
                    }
                  }
                  Text {
                    text: "Cooling Fan"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.weight: Font.DemiBold
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Text {
                  text: root.stats.fan_status
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Item { Layout.fillWidth: true }

              Text {
                text: root.stats.fan_rpm > 0 ? root.stats.fan_rpm + " RPM" : "Off"
                color: root.stats.fan_rpm > 0 ? root.accentColor : root.dim
                font.family: root.fontFamily
                font.weight: Font.DemiBold
                font.pixelSize: Style.font.title
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
              }
            }

            // DaylightStrip Slider Track
            Item {
              width: parent.width
              height: Style.space(12)

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: Math.max(3, Style.space(3))
                radius: height / 2
                color: Util.alpha(root.foreground, 0.10)

                Rectangle {
                  height: parent.height
                  width: Math.max(height, parent.width * (Math.min(100.0, root.stats.fan_pct) / 100.0))
                  radius: height / 2
                  color: Util.alpha(root.accentColor, 0.40)

                  Behavior on width { NumberAnimation { duration: Style.duration(380); easing.type: Easing.OutCubic } }
                }

                Rectangle {
                  width: Math.max(8, Style.space(9))
                  height: width
                  radius: width / 2
                  color: root.stats.fan_rpm > 0 ? root.accentColor : root.dim
                  border.width: 1.5
                  border.color: fanHover.hovered ? "#ffffff" : (root.stats.fan_rpm > 0 ? root.accentColor : root.dim)
                  anchors.verticalCenter: parent.verticalCenter
                  x: Math.round(Math.max(0, Math.min(parent.width - width, (parent.width - width) * (Math.min(100.0, root.stats.fan_pct) / 100.0))))

                  Behavior on x { NumberAnimation { duration: Style.duration(380); easing.type: Easing.OutCubic } }
                  Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }
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

        // 4. MEMORY & LOAD ROW
        Rectangle {
          id: memRow
          width: parent.width
          implicitHeight: memCol.implicitHeight + Style.space(22)
          radius: Style.cornerRadius
          color: root.mix(Commons.Color.popups.background, root.foreground, memHover.hovered ? 0.12 : 0.065)
          scale: memMouse.pressed ? 0.985 : (memHover.hovered ? 1.008 : 1.0)

          Behavior on color { ColorAnimation { duration: Style.duration(140) } }
          Behavior on scale { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }

          Column {
            id: memCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(11)
            spacing: Style.space(8)

            RowLayout {
              width: parent.width

              Column {
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                spacing: Style.space(2)

                Row {
                  spacing: Style.space(6)
                  Text {
                    text: ""
                    color: root.metricColor(root.stats.mem_pct)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Text {
                    text: "Memory & Load"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.weight: Font.DemiBold
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Text {
                  text: root.stats.mem_used + "G / " + root.stats.mem_total + " GB · 1m Load " + root.stats.load_1m.toFixed(2)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Item { Layout.fillWidth: true }

              Text {
                text: root.stats.mem_pct + "%"
                color: root.metricColor(root.stats.mem_pct)
                font.family: root.fontFamily
                font.weight: Font.DemiBold
                font.pixelSize: Style.font.title
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
              }
            }

            // DaylightStrip Slider Track
            Item {
              width: parent.width
              height: Style.space(12)

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: Math.max(3, Style.space(3))
                radius: height / 2
                color: Util.alpha(root.foreground, 0.10)

                Rectangle {
                  height: parent.height
                  width: Math.max(height, parent.width * (Math.min(100.0, root.stats.mem_pct) / 100.0))
                  radius: height / 2
                  color: Util.alpha(root.metricColor(root.stats.mem_pct), 0.40)

                  Behavior on width { NumberAnimation { duration: Style.duration(380); easing.type: Easing.OutCubic } }
                }

                Rectangle {
                  width: Math.max(8, Style.space(9))
                  height: width
                  radius: width / 2
                  color: root.metricColor(root.stats.mem_pct)
                  border.width: 1.5
                  border.color: memHover.hovered ? "#ffffff" : root.metricColor(root.stats.mem_pct)
                  anchors.verticalCenter: parent.verticalCenter
                  x: Math.round(Math.max(0, Math.min(parent.width - width, (parent.width - width) * (Math.min(100.0, root.stats.mem_pct) / 100.0))))

                  Behavior on x { NumberAnimation { duration: Style.duration(380); easing.type: Easing.OutCubic } }
                  Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }
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
              root.close()
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // ---- SECTION 5: INTERACTIVE ACTION BUTTONS ----
        Column {
          width: parent.width
          spacing: Style.space(8)

          // Primary Launch Button (Styled natively with qs.Ui.Button)
          Button {
            width: parent.width
            height: Style.space(34)
            bordered: true
            iconText: "󰄬"
            text: "Launch Btop Terminal Dashboard"
            fontSize: Style.font.bodySmall
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: {
              if (root.bar) root.bar.run("omarchy launch or focus tui btop")
              else Quickshell.execDetached(["omarchy-launch-or-focus-tui", "btop"])
              root.close()
            }
          }

          // Secondary Quick Controls Row
          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            // Switch Bar Metric Mode
            Button {
              Layout.fillWidth: true
              height: Style.space(30)
              bordered: true
              iconText: "󰍹"
              text: {
                var names = ["Overview", "Thermals", "Clocks", "RAM & Load"]
                return "View: " + names[root.displayMode]
              }
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.nextMode()
            }

            // Temp Unit Toggle
            Button {
              Layout.preferredWidth: Style.space(80)
              height: Style.space(30)
              bordered: true
              iconText: "󰔄"
              text: root.tempInFahrenheit ? "°F" : "°C"
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.tempInFahrenheit = !root.tempInFahrenheit
            }

            // Live Telemetry Refresh
            Button {
              Layout.preferredWidth: Style.space(90)
              height: Style.space(30)
              bordered: true
              iconText: "󰑐"
              iconSpinning: statsProc.running
              text: "Refresh"
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.refresh()
            }
          }
        }
      }
    }
  }
}
