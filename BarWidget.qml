import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.alexanderpuschkinberlin.keyboard-backlight"

  readonly property bool ambientEnabled: setting("ambientEnabled", false) === true
  readonly property bool manualOverride: setting("manualOverride", false) === true
  readonly property int darkThreshold: Number(setting("ambientDarkThreshold", 35))
  readonly property int brightThreshold: Number(setting("ambientBrightThreshold", 105))
  readonly property int ambientIntervalMinutes: {
    var value = Number(setting("ambientIntervalMinutes", 10))
    return isFinite(value) ? Math.max(1, Math.min(1440, Math.round(value))) : 10
  }
  property bool sessionLocked: true
  property bool lockStateKnown: false
  property bool startupReady: false
  property double lastSampleAt: 0

  function setIntervalMinutes(value) {
    var minutes = Number(value)
    if (!isFinite(minutes)) return
    persistSettings({ ambientIntervalMinutes: Math.max(1, Math.min(1440, Math.round(minutes))) })
  }

  function checkLockState() {
    if (!lockProc.running) lockProc.running = true
  }

  function updateLockState(value) {
    var known = value === "true" || value === "false"
    var wasKnown = lockStateKnown
    var wasLocked = sessionLocked
    lockStateKnown = known
    sessionLocked = !known || value === "true"
    if (sessionLocked) {
      ambientTimer.stop()
      if (!wasLocked || wasKnown !== known) resetAmbient()
      ambientStatus = known ? "Paused while locked" : "Waiting for lock status"
      return
    }
    if (!wasKnown || wasLocked) {
      resetAmbient() // A new session should not inherit the old room's average.
      if (startupReady) sampleAmbient()
    }
  }

  property real ambientAverage: -1
  property real ambientReading: -1
  property string ambientMode: ""
  property string ambientStatus: "Waiting for sample"
  property bool ambientHealthy: false
  property int ambientGeneration: 0
  property int sampleGeneration: -1
  readonly property string ambientHelper: Qt.resolvedUrl("bin/ambient-light").toString().replace(/^file:\/\//, "")

  function sampleAmbient() {
    if (!ambientEnabled || manualOverride || !lockStateKnown || sessionLocked) return
    // A previous bounded capture can still be finishing when unlock arrives.
    if (ambientProc.running) { sampleRetry.restart(); return }
    sampleRetry.stop()
    ambientTimer.restart()
    lastSampleAt = Date.now()
    var args = [root.ambientHelper, "--dark", String(darkThreshold), "--bright", String(brightThreshold)]
    if (ambientAverage >= 0) args = args.concat(["--previous", String(ambientAverage), "--mode", ambientMode])
    sampleGeneration = ambientGeneration
    ambientProc.command = args
    ambientProc.running = true
  }

  function resetAmbient() {
    ambientGeneration++
    ambientAverage = -1
    ambientMode = ""
    ambientHealthy = false
  }

  function setAmbientEnabled(value) {
    resetAmbient()
    persistSettings({ ambientEnabled: value, manualOverride: false })
    lastSchedulePeriod = ""
    Qt.callLater(function() { if (value) root.sampleAmbient(); else root.applySchedule(true) })
  }

  function resumeAutomatic() {
    resetAmbient()
    persistSettings({ manualOverride: false })
    Qt.callLater(function() { if (root.ambientEnabled) root.sampleAmbient(); else root.applySchedule(true) })
  }

  function changeThreshold(which, delta) {
    var update = {}
    if (which === "dark") update.ambientDarkThreshold = Math.max(0, Math.min(brightThreshold - 20, darkThreshold + delta))
    else update.ambientBrightThreshold = Math.max(darkThreshold + 20, Math.min(255, brightThreshold + delta))
    persistSettings(update)
    resetAmbient()
    Qt.callLater(root.sampleAmbient)
  }

  property int level: 0
  property int maximum: 2
  property string deviceName: ""
  property string lastSchedulePeriod: ""
  readonly property string levelIcon: level <= 0 ? "󰹐" : (level >= maximum ? "󰛨" : "󰌶")
  readonly property bool scheduleEnabled: setting("scheduleEnabled", false) === true
  readonly property int nightStartHour: Number(setting("nightStartHour", 20))
  readonly property int dayStartHour: Number(setting("dayStartHour", 7))
  readonly property string helper: Qt.resolvedUrl("bin/keyboard-backlight").toString().replace(/^file:\/\//, "")
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function setMode(mode, automatic) {
    if (!automatic) {
      persistSettings({ manualOverride: true })
      resetAmbient()
    }
    if (actionProc.running) return
    actionProc.command = [root.helper, "set", mode]
    actionProc.running = true
  }

  function cycle() {
    if (level <= 0) setMode("low")
    else if (level >= maximum) setMode("off")
    else setMode("high")
  }

  function schedulePeriod() {
    var hour = new Date().getHours()
    var night = nightStartHour
    var day = dayStartHour
    if (night === day) return "night"
    if (night > day) return (hour >= night || hour < day) ? "night" : "day"
    return (hour >= night && hour < day) ? "night" : "day"
  }

  function applySchedule(force) {
    if (manualOverride || (ambientEnabled && ambientHealthy)) return
    if (!scheduleEnabled) {
      lastSchedulePeriod = ""
      return
    }
    var period = schedulePeriod()
    if (!force && period === lastSchedulePeriod) return
    lastSchedulePeriod = period
    setMode(period === "night" ? "low" : "off", true)
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setScheduleEnabled(value) {
    persistSettings({ scheduleEnabled: value, manualOverride: false })
    lastSchedulePeriod = ""
    if (value) Qt.callLater(function() { root.applySchedule(true) })
  }

  function setScheduleHour(key, value) {
    var normalized = ((Number(value) % 24) + 24) % 24
    var update = {}
    update[key] = normalized
    persistSettings(update)
    lastSchedulePeriod = ""
    if (scheduleEnabled) Qt.callLater(function() { root.applySchedule(true) })
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.anchorItem = button
    target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  onManualOverrideChanged: if (manualOverride) { ambientTimer.stop(); sampleRetry.stop() }
  onAmbientEnabledChanged: if (!ambientEnabled) { ambientTimer.stop(); sampleRetry.stop() }
  onAmbientIntervalMinutesChanged: if (startupReady && ambientEnabled && !manualOverride && lockStateKnown && !sessionLocked) ambientTimer.restart()
  onScheduleEnabledChanged: if (!scheduleEnabled) lastSchedulePeriod = ""
  Component.onCompleted: {
    refresh()
    scheduleDelay.start()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  Timer { interval: 5000; running: true; repeat: true; onTriggered: root.refresh() }
  Timer { interval: 30000; running: true; repeat: true; onTriggered: root.applySchedule(false) }
  Timer { id: scheduleDelay; interval: 1000; repeat: false; onTriggered: { root.startupReady = true; root.applySchedule(true); root.checkLockState(); root.sampleAmbient() } }

  Timer { id: ambientTimer; interval: root.ambientIntervalMinutes * 60000; repeat: false; onTriggered: root.sampleAmbient() }
  Timer { id: sampleRetry; interval: 250; repeat: false; onTriggered: root.sampleAmbient() }
  // Lock service is private; use its public read-only IPC, without camera access.
  Timer { interval: 1000; running: root.ambientEnabled; repeat: true; onTriggered: root.checkLockState() }
  Process {
    id: lockProc
    command: ["timeout", "2s", "omarchy-shell", "lock", "isLocked"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateLockState(text.trim()) }
  }

  IpcHandler {
    target: root.moduleName + ".ambient"
    function status(): string { return JSON.stringify({ enabled: root.ambientEnabled, paused: root.manualOverride, healthy: root.ambientHealthy, reading: root.ambientReading, average: root.ambientAverage, mode: root.ambientMode, message: root.ambientStatus, level: root.level, sampling: ambientProc.running, intervalMinutes: root.ambientIntervalMinutes, locked: root.sessionLocked, lockStateKnown: root.lockStateKnown, lastSampleAt: root.lastSampleAt, timerRunning: ambientTimer.running }) }
    function interval(minutes: int): void { root.setIntervalMinutes(minutes) }
    function sample(): void { root.sampleAmbient() }
    function open(): void { root.open() }
    function resume(): void { root.resumeAutomatic() }
    function manual(mode: string): void { if (["off", "low", "high"].indexOf(mode) >= 0) root.setMode(mode) }
  }

  Process {
    id: ambientProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.sampleGeneration !== root.ambientGeneration || !root.ambientEnabled || root.manualOverride || root.sessionLocked || !root.lockStateKnown) return
        try {
          var result = JSON.parse(text)
          if (!result.ok) throw new Error(result.error || "Camera unavailable")
          root.ambientHealthy = true
          root.ambientReading = result.reading
          root.ambientAverage = result.average
          root.ambientMode = result.mode
          root.ambientStatus = "Light: " + Math.round(result.reading) + " / 255 · smoothed: " + Math.round(result.average)
          root.setMode(result.mode, true)
        } catch (error) {
          root.resetAmbient()
          root.ambientStatus = String(error).replace(/^Error: /, "")
          root.applySchedule(true)
        }
      }
    }
  }

  Process {
    id: statusProc
    command: [root.helper, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var values = text.trim().split(/\s+/)
        if (values.length >= 3) {
          root.level = Number(values[0]) || 0
          root.maximum = Number(values[1]) || 2
          root.deviceName = values.slice(2).join(" ")
        }
      }
    }
  }

  Process { id: actionProc; onExited: refreshDelay.start() }
  Timer { id: refreshDelay; interval: 150; repeat: false; onTriggered: root.refresh() }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.levelIcon
    active: root.level > 0
    tooltipText: ""
    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycle()
      else root.toggle()
    }
  }
}
