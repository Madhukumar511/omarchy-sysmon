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

        // Header Title
        RowLayout {
          width: parent.width

          Row {
            spacing: Style.space(8)
            Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter

            Rectangle {
              width: 8
              height: 8
              radius: 4
              color: root.accentColor
              anchors.verticalCenter: parent.verticalCenter

              SequentialAnimation on opacity {
                loops: Animation.Infinite
                NumberAnimation { from: 0.4; to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1.0; to: 0.4; duration: 800; easing.type: Easing.InOutSine }
              }
            }

            Text {
              text: "HARDWARE TELEMETRY"
              color: root.barTextColor
              font.family: root.barFont
              font.bold: true
              font.pixelSize: Style.font.subtitle
            }
          }

          Item { Layout.fillWidth: true }

          // Fan status badge
          BorderSurface {
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            implicitHeight: 20
            implicitWidth: fanBadgeText.implicitWidth + 14
            radius: 10
            color: Util.alpha(root.accentColor, 0.15)
            borderSpec: Border.flat(root.accentColor, 1)

            Text {
              id: fanBadgeText
              anchors.centerIn: parent
              text: root.stats.fan_status
              color: root.accentColor
              font.family: root.barFont
              font.bold: true
              font.pixelSize: Style.font.caption
            }
          }
        }

        PanelSeparator { foreground: root.barTextColor }

        // --- SECTION 1: CPU TELEMETRY ---
        Column {
          width: parent.width
          spacing: Style.space(6)

          RowLayout {
            width: parent.width
            Text {
              text: "  CPU: " + (root.stats.cpu_model || "Processor")
              color: root.barTextColor
              font.family: root.barFont
              font.bold: true
              font.pixelSize: Style.font.body
              Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
              elide: Text.ElideRight
              Layout.maximumWidth: Style.space(220)
            }
            Item { Layout.fillWidth: true }
            Text {
              text: root.stats.cpu_pct.toFixed(1) + "% (" + root.stats.cpu_freq.toFixed(2) + " GHz)"
              color: root.accentColor
              font.family: root.barFont
              font.bold: true
              font.pixelSize: Style.font.body
              Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
          }

          // CPU Utilization Bar
          Rectangle {
            width: parent.width
            height: Style.space(6)
            radius: 3
            color: Util.alpha(root.barTextColor, 0.10)

            Rectangle {
              height: parent.height
              width: Math.max(4, parent.width * (root.stats.cpu_pct / 100.0))
              radius: 3
              color: root.accentColor

              Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            }
          }

          // Cores & Thermals grid
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
                implicitWidth: (cardContent.width - Style.space(24)) / 4
                radius: 6
                color: Util.alpha(Commons.Color.background, 0.40)
                borderSpec: Border.flat(Util.alpha(root.barTextColor, 0.15), 1)

                Row {
                  anchors.centerIn: parent
                  spacing: 4
                  Text {
                    text: modelData.name.replace("Core ", "C") + ":"
                    color: root.barTextColor
                    opacity: 0.6
                    font.family: root.barFont
                    font.pixelSize: Style.font.caption
                    verticalAlignment: Text.AlignVCenter
                  }
                  Text {
                    text: Math.round(modelData.temp) + "°"
                    color: root.tempColor(modelData.temp)
                    font.family: root.barFont
                    font.bold: true
                    font.pixelSize: Style.font.caption
                    verticalAlignment: Text.AlignVCenter
                  }
                }
              }
            }
          }
        }

        // --- SECTION 2: INTEL GPU ---
        Column {
          width: parent.width
          spacing: Style.space(6)

          RowLayout {
            width: parent.width
            Text {
              text: "󰢮  GPU: " + (root.stats.gpu_model || "Graphics")
              color: root.barTextColor
              font.family: root.barFont
              font.bold: true
              font.pixelSize: Style.font.body
              Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
              elide: Text.ElideRight
              Layout.maximumWidth: Style.space(220)
            }
            Item { Layout.fillWidth: true }
            Text {
              text: root.stats.gpu_pct.toFixed(1) + "% (" + root.stats.gpu_mhz + " MHz)"
              color: root.accentColor
              font.family: root.barFont
              font.bold: true
              font.pixelSize: Style.font.body
              Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
          }

          Rectangle {
            width: parent.width
            height: Style.space(6)
            radius: 3
            color: Util.alpha(root.barTextColor, 0.10)

            Rectangle {
              height: parent.height
              width: Math.max(root.stats.gpu_pct > 0 ? 4 : 0, parent.width * (root.stats.gpu_pct / 100.0))
              radius: 3
              color: root.accentColor

              Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            }
          }
        }

        // --- SECTION 3: ACTIVE COOLING FAN ---
        Column {
          width: parent.width
          spacing: Style.space(6)

          RowLayout {
            width: parent.width
            Row {
              spacing: 6
              Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
              Text {
                text: "󰈐"
                color: root.stats.fan_rpm > 5000 ? "#ef4444" : (root.stats.fan_rpm > 0 ? root.accentColor : root.barTextColor)
                opacity: root.stats.fan_rpm > 0 ? 1.0 : 0.6
                font.family: root.barFont
                font.pixelSize: Style.font.title
                verticalAlignment: Text.AlignVCenter
                anchors.verticalCenter: parent.verticalCenter

                RotationAnimation on rotation {
                  running: root.stats.fan_rpm > 0
                  loops: Animation.Infinite
                  from: 0
                  to: 360
                  duration: Math.max(300, 2400 - Math.min(2000, root.stats.fan_rpm * 0.35))
                }
              }
              Text {
                text: "Active Cooling Fan"
                color: root.barTextColor
                font.family: root.barFont
                font.bold: true
                font.pixelSize: Style.font.body
                verticalAlignment: Text.AlignVCenter
                anchors.verticalCenter: parent.verticalCenter
              }
            }
            Item { Layout.fillWidth: true }
            Text {
              text: root.stats.fan_rpm > 0 
                ? root.stats.fan_rpm + " RPM (" + root.stats.fan_pct + "%)"
                : "Fan Off (Passive Cooling)"
              color: root.stats.fan_rpm > 5000 ? "#ef4444" : root.accentColor
              font.family: root.barFont
              font.bold: true
              font.pixelSize: Style.font.body
              Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
          }

          Rectangle {
            width: parent.width
            height: Style.space(6)
            radius: 3
            color: Util.alpha(root.barTextColor, 0.10)

            Rectangle {
              height: parent.height
              width: Math.max(4, parent.width * (root.stats.fan_pct / 100.0))
              radius: 3
              color: root.stats.fan_rpm > 5000 ? "#ef4444" : root.accentColor

              Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            }
          }
        }

        // --- SECTION 4: MEMORY (RAM) & LOAD ---
        Column {
          width: parent.width
          spacing: Style.space(6)

          RowLayout {
            width: parent.width
            Text {
              text: "  Memory: " + root.stats.mem_used + "G / " + root.stats.mem_total + "G"
              color: root.barTextColor
              font.family: root.barFont
              font.bold: true
              font.pixelSize: Style.font.body
              Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
            }
            Item { Layout.fillWidth: true }
            Text {
              text: root.stats.mem_pct + "% · Load " + root.stats.load_1m.toFixed(2)
              color: root.accentColor
              font.family: root.barFont
              font.bold: true
              font.pixelSize: Style.font.body
              Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
          }

          Rectangle {
            width: parent.width
            height: Style.space(6)
            radius: 3
            color: Util.alpha(root.barTextColor, 0.10)

            Rectangle {
              height: parent.height
              width: Math.max(4, parent.width * (root.stats.mem_pct / 100.0))
              radius: 3
              color: root.accentColor

              Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            }
          }
        }

        PanelSeparator { foreground: root.barTextColor }

        // --- SECTION 5: FOOTER ACTION ---
        Button {
          width: parent.width
          text: "Launch Btop Terminal Dashboard"
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
