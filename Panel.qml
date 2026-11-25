import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Cornerstone HQ in the bar (the Linux stand-in for the Windows tray icon).
// Built once per monitor; state polling and IPC live in Service.qml.
// Left click: panel. Right click: open / bring back HQ. Middle click: hide it.
Panel {
  id: root
  moduleName: "cornerstone-hq"
  ipcTarget: "cornerstone-hq"
  manageIpc: false

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("cornerstone.hq") : null
  readonly property string iconPath: Qt.resolvedUrl("assets/hq.png")

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color muted: Qt.darker(foreground, 1.55)
  readonly property color hairline: Qt.darker(foreground, 2.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Theme palette accents with safe fallbacks.
  property var palette: ({})
  readonly property color okColor: palette.color2 || "#3FB950"
  readonly property color warnColor: palette.color3 || Color.accent
  readonly property color badColor: Color.urgent

  FileView {
    id: paletteFile
    path: Color.currentThemePath + "/colors.toml"
    printErrors: false
    onLoaded: {
      var found = {}
      var re = /^\s*([A-Za-z0-9_]+)\s*=\s*"(#[0-9A-Fa-f]{6,8})"/gm
      var m
      while ((m = re.exec(String(text()))) !== null) found[m[1]] = m[2]
      root.palette = found
    }
  }
  Connections {
    target: Color
    function onBackgroundChanged() { paletteFile.reload() }
    function onAccentChanged() { paletteFile.reload() }
  }

  readonly property int windows: service ? service.windows : 0
  readonly property var services: service ? service.services : []
  readonly property int downCount: service ? service.downCount : 0
  readonly property int upCount: service ? service.upCount : 0
  readonly property int totalCount: service ? service.totalCount : 0

  readonly property string barTooltip: {
    var winLabel = windows > 0 ? "Open" : "Closed"
    if (totalCount === 0) return "Cornerstone HQ · " + winLabel
    return downCount === 0
      ? "Cornerstone HQ · " + upCount + "/" + totalCount + " services up"
      : "Cornerstone HQ · " + downCount + " service" + (downCount === 1 ? "" : "s") + " down"
  }

  // Flat list of keyboard-navigable stops: window actions, each service, restart all.
  readonly property var stops: {
    var list = [{ kind: "open" }]
    if (windows > 0) { list.push({ kind: "hide" }); list.push({ kind: "close" }) }
    for (var i = 0; i < services.length; i++)
      list.push({ kind: "svc", unit: String(services[i].unit || "") })
    list.push({ kind: "restartAll" })
    return list
  }

  property int cursor: -1
  property bool watching: false

  onOpenedChanged: {
    cursor = -1
    if (service) {
      if (opened && !watching) { watching = true; service.watchers++; service.refresh() }
      else if (!opened && watching) { watching = false; service.watchers = Math.max(0, service.watchers - 1) }
    }
  }
  Component.onDestruction: {
    if (watching && service) service.watchers = Math.max(0, service.watchers - 1)
  }

  function isFocused(kind, unit) {
    if (cursor < 0 || cursor >= stops.length) return false
    var s = stops[cursor]
    return s.kind === kind && (kind !== "svc" || s.unit === unit)
  }

  function focusOf(kind, unit) {
    for (var i = 0; i < stops.length; i++)
      if (stops[i].kind === kind && (kind !== "svc" || stops[i].unit === unit)) { cursor = i; return }
  }

  function activateStop(s) {
    if (!s || !service) return
    if (s.kind === "open") { service.openHq(); root.close() }
    else if (s.kind === "hide") service.hideHq()
    else if (s.kind === "close") service.closeHq()
    else if (s.kind === "svc") service.restartOne(s.unit)
    else if (s.kind === "restartAll") service.restartAll()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.opened ? "" : root.barTooltip
    onPressed: function(code) {
      if (code === Qt.RightButton && root.service) root.service.openHq()
      else if (code === Qt.MiddleButton && root.service) root.service.hideHq()
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
    property bool focused: false
    signal hovered()
    signal activated()
    width: parent ? parent.width : 0
    height: Style.space(30)
    radius: Style.space(6)
    color: Qt.rgba(tint.r, tint.g, tint.b, rowArea.containsMouse || focused ? fill + 0.08 : fill)
    border.width: focused ? 1 : 0
    border.color: Color.accent
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
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
      onEntered: row.hovered()
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
      onMoveRequested: function(dx, dy) {
        if (dy === 0 || root.stops.length === 0) return
        var n = root.stops.length
        root.cursor = root.cursor < 0 ? (dy > 0 ? 0 : n - 1) : (root.cursor + dy + n) % n
      }
      onActivateRequested: {
        if (root.cursor >= 0 && root.cursor < root.stops.length)
          root.activateStop(root.stops[root.cursor])
      }
      onTextKey: function(t) {
        if (!root.service) return
        if (t === "o" || t === "O") { root.service.openHq(); root.close() }
        else if (t === "h" || t === "H") root.service.hideHq()
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
            mipmap: true
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
            focused: root.isFocused("open", "")
            onHovered: root.focusOf("open", "")
            onActivated: { if (root.service) root.service.openHq(); root.close() }
          }
          ActionRow {
            visible: root.windows > 0
            label: "Hide HQ (keeps it running)"
            focused: root.isFocused("hide", "")
            onHovered: root.focusOf("hide", "")
            onActivated: if (root.service) root.service.hideHq()
          }
          ActionRow {
            visible: root.windows > 0
            label: "Close HQ window"
            focused: root.isFocused("close", "")
            onHovered: root.focusOf("close", "")
            onActivated: if (root.service) root.service.closeHq()
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
              readonly property string unitName: String(modelData.unit || "")
              readonly property bool focused: root.isFocused("svc", unitName)
              width: parent.width
              height: Style.space(26)
              radius: Style.space(6)
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b,
                             svcArea.containsMouse || focused ? 0.14 : 0.06)
              border.width: focused ? 1 : 0
              border.color: Color.accent
              Behavior on color { ColorAnimation { duration: Style.duration(120) } }
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
                text: svcArea.containsMouse || focused ? "restart" : String(modelData.state).slice(0, 20)
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                id: svcArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.focusOf("svc", unitName)
                onClicked: if (root.service) root.service.restartOne(unitName)
              }
            }
          }
        }

        ActionRow {
          label: "Restart all HQ services"
          focused: root.isFocused("restartAll", "")
          onHovered: root.focusOf("restartAll", "")
          onActivated: if (root.service) root.service.restartAll()
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "Right-click = open · middle-click = hide · j/k + Enter navigate · o open · h hide"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
