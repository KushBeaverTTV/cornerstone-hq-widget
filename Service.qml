import QtQuick
import Quickshell
import Quickshell.Io

// Single session-wide service for Cornerstone HQ: polls hq-state.sh once for
// all monitors (faster only while a panel is open) and owns the single
// `cornerstone-hq` IPC target.
Item {
  id: service

  property var shell: null
  readonly property string pluginId: "cornerstone.hq"
  readonly property string stateScript: Qt.resolvedUrl("hq-state.sh").toString().replace(/^file:\/\//, "")
  readonly property string pattern: "^(brave|chrome)-127\\.0\\.0\\.1__-Default$"

  property int windows: 0
  property var services: []
  property int watchers: 0

  readonly property int totalCount: services.length
  readonly property int downCount: {
    var n = 0
    for (var i = 0; i < services.length; i++) if (services[i].state !== "active") n++
    return n
  }
  readonly property int upCount: Math.max(0, totalCount - downCount)

  function refresh() {
    if (!stateProc.running) stateProc.running = true
  }

  function run(argv) {
    Quickshell.execDetached(argv)
    refreshSoon.restart()
  }

  function openHq() { run(["cornerstone-hq-open"]) }
  function hideHq() { run(["app-summon", "--hide", pattern]) }
  function closeHq() { run(["app-summon", "--close", pattern]) }
  function restartAll() {
    run(["systemctl", "--user", "restart",
         "kbp-server", "hq-bridge", "kbp-bot", "streambot", "lavalink", "yt-cipher"])
  }
  function restartOne(unit) {
    var u = String(unit || "")
    if (/^[a-z0-9-]+$/.test(u)) run(["systemctl", "--user", "restart", u + ".service"])
  }

  Process {
    id: stateProc
    command: ["bash", service.stateScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(String(this.text || ""))
          service.windows = Math.max(0, Math.min(99, parseInt(d.windows, 10) || 0))
          service.services = Array.isArray(d.services) ? d.services.slice(0, 12) : []
        } catch (e) {}
      }
    }
  }

  Timer {
    interval: service.watchers > 0 ? 1500 : 8000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: service.refresh()
  }

  Timer {
    id: refreshSoon
    interval: 700
    onTriggered: service.refresh()
  }

  IpcHandler {
    target: "cornerstone-hq"

    function toggle(): string { if (service.shell) service.shell.toggle(service.pluginId); return "ok" }
    function show(): string { service.openHq(); return "summoned" }
    function hide(): string { service.hideHq(); return "hidden" }
    function refresh(): string { service.refresh(); return "ok" }
  }
}
