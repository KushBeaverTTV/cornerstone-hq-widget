import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Cornerstone HQ in the bar (the Linux stand-in for the Windows tray icon).
// Left click: panel. Right click: open / bring back HQ. Middle click: hide it.
Panel {
  id: root
  moduleName: "cornerstone-hq"
  ipcTarget: "cornerstone-hq"
  manageIpc: false

  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/cornerstone.hq"
  readonly property string iconPath: Qt.resolvedUrl("assets/hq.png")
  readonly property string pattern: "^(brave|chrome)-127\\.0\\.0\\.1__-Default$"

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color muted: Qt.darker(foreground, 1.55)
  readonly property color hairline: Qt.darker(foreground, 2.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color okColor: "#3FB950"
  readonly property color badColor: "#E11414"
  readonly property color warnColor: "#FFD400"

  property int windows: 0
  property var services: []
  readonly property int downCount: {
    var n = 0
    for (var i = 0; i < services.length; i++) if (services[i].state !== "active") n++
    return n
  }

  Process {
    id: stateProc
    command: ["bash", root.pluginDir + "/hq-state.sh"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var d = JSON.parse(String(this.text))
          root.windows = Math.max(0, Math.min(99, parseInt(d.windows) || 0))
          root.services = Array.isArray(d.services) ? d.services.slice(0, 8) : []
        } catch (e) {}
      }
    }
  }
  Timer {
    interval: root.opened ? 1500 : 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!stateProc.running) stateProc.running = true
  }
  Timer { id: refreshSoon; interval: 700; onTriggered: if (!stateProc.running) stateProc.running = true }

  function run(cmd) { if (root.bar) root.bar.run(cmd); refreshSoon.restart() }
  function openHq() { run("cornerstone-hq-open") }
  function hideHq() { run("app-summon --hide '" + root.pattern + "'") }
  function closeHq() { run("app-summon --close '" + root.pattern + "'") }
  function restartAll() { run("systemctl --user restart kbp-server hq-bridge kbp-bot streambot lavalink") }
  function restartOne(unit) {
    if (/^[a-z0-9-]+$/.test(unit)) run("systemctl --user restart " + unit + ".service")
  }

  IpcHandler {
    id: ipc
    target: root.ipcTarget
    function toggle(): string { root.toggle(); return root.opened ? "open" : "closed" }
    function show(): string { root.openHq(); return "summoned" }
    function hide(): string { root.hideHq(); return "hidden" }
    Component.onCompleted: IpcRegistry.register(ipc)
    Component.onDestruction: IpcRegistry.unregister(ipc)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: ""
    onPressed: function(code) {
      if (code === Qt.RightButton) root.openHq()
      else if (code === Qt.MiddleButton) root.hideHq()
      else root.toggle()
    }
    iconComponent: Component {
      Item {
        width: 22
        height: 22
        Image {
          anchors.fill: parent
          source: root.iconPath
          sourceSize.width: 64
          sourceSize.height: 64
          fillMode: Image.PreserveAspectFit
          smooth: true
          mipmap: true
          opacity: root.windows > 0 ? 1.0 : 0.7
        }
        Rectangle {
          visible: root.downCount > 0
          width: 7; height: 7; radius: 3.5
          anchors.right: parent.right
          anchors.top: parent.top
          color: root.badColor
        }
      }
    }
  }

  component ActionRow: Rectangle {
    id: row
    property string label: ""
    property color tint: root.foreground
    property real fill: 0.12
    signal activated()
    width: parent ? parent.width : 0
    height: Style.space(30)
    radius: Style.space(6)
    color: Qt.rgba(tint.r, tint.g, tint.b, rowArea.containsMouse ? fill + 0.08 : fill)
    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      width: parent.width - Style.space(20)
      textFormat: Text.PlainText
      text: row.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
    MouseArea {
      id: rowArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: row.activated()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(560))

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "o" || t === "O") { root.openHq(); root.close() }
        else if (t === "h" || t === "H") root.hideHq()
      }
      clip: true

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(10)

        Row {
          spacing: Style.space(10)
          Image {
            width: 36; height: 36
            source: root.iconPath
            sourceSize.width: 72; sourceSize.height: 72
            fillMode: Image.PreserveAspectFit
            smooth: true
            anchors.verticalCenter: parent.verticalCenter
          }
          Column {
            spacing: Style.space(2)
            anchors.verticalCenter: parent.verticalCenter
            Text {
              textFormat: Text.PlainText
              text: "Cornerstone HQ"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              text: (root.windows > 0 ? "Window open" : "Window closed") + " · "
                    + (root.downCount === 0 ? "all services running" : root.downCount + " service(s) down")
              color: root.downCount === 0 ? root.muted : root.badColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Rectangle { width: parent.width; height: 1; color: root.hairline }

        Column {
          width: parent.width
          spacing: Style.space(8)
          ActionRow {
            label: root.windows > 0 ? "Bring HQ here" : "Open HQ"
            tint: root.warnColor
            fill: 0.22
            onActivated: { root.openHq(); root.close() }
          }
          ActionRow {
            visible: root.windows > 0
            label: "Hide HQ (keeps it running)"
            onActivated: root.hideHq()
          }
          ActionRow {
            visible: root.windows > 0
            label: "Close HQ window"
            onActivated: root.closeHq()
          }
        }

        Rectangle { width: parent.width; height: 1; color: root.hairline }

        Text {
          textFormat: Text.PlainText
          text: "Services (tap one to restart it)"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          Repeater {
            model: root.services
            Rectangle {
              required property var modelData
              width: parent.width
              height: Style.space(26)
              radius: Style.space(6)
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, svcArea.containsMouse ? 0.14 : 0.06)
              Rectangle {
                id: dot
                width: 8; height: 8; radius: 4
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                color: modelData.state === "active" ? root.okColor
                     : modelData.state === "activating" ? root.warnColor : root.badColor
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: dot.right
                anchors.leftMargin: Style.space(8)
                textFormat: Text.PlainText
                text: String(modelData.label).slice(0, 40)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                textFormat: Text.PlainText
                text: svcArea.containsMouse ? "restart" : String(modelData.state).slice(0, 20)
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                id: svcArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.restartOne(String(modelData.unit))
              }
            }
          }
        }

        ActionRow {
          label: "Restart all HQ services"
          onActivated: root.restartAll()
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "Right-click icon = open / bring back · middle-click = hide · o open · h hide"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
