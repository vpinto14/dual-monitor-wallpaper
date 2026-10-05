import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  // ---------------------------------------------------------------- config
  // Config lives in the `dualWallpaper` block of ~/.config/omarchy/shell.json:
  //   { "dualWallpaper": { "wallpaperDir": "...", "leftMonitor": "", "rightMonitor": "" } }
  // The wallpaper dir holds one image per monitor: the left monitor's file ends
  // in "_L", the right monitor's file ends in "_R".

  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: home + "/.config/omarchy/shell.json"

  property string wallpaperDir: Model.defaultWallpaperDir()
  property string leftMonitor: ""
  property string rightMonitor: ""
  property var dirFiles: []

  // Absolute, resolved wallpaper paths for each side ("" when no match).
  property string leftWallpaper: ""
  property string rightWallpaper: ""

  // Index of the currently selected wallpaper pair (see Model.pairs).
  // Persisted in config; clamped to the pair list on every recompute.
  property int pairIndex: 0

  readonly property string wallpaperDirAbs: Model.expandHome(root.wallpaperDir, root.home)

  function logEvent(event, details) {
    var suffix = (details === undefined || details === null || details === "") ? "" : ": " + String(details)
    console.log("omarchy dual-wallpaper " + new Date().toISOString() + " " + event + suffix)
  }

  // ---------------------------------------------------------- wallpaper dir

  function rescanDir() {
    if (!root.wallpaperDirAbs) return
    dirScanProcess.running = true
  }

  function applyDirListing(output) {
    var files = []
    var lines = String(output || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var name = lines[i].trim()
      if (name) files.push(name)
    }
    files.sort()
    // Same list, same objects: reassigning the model would tear down the
    // FileView just to build identical ones.
    if (JSON.stringify(files) !== JSON.stringify(root.dirFiles)) root.dirFiles = files
    root.recomputeWallpapers()
  }

  function recomputeWallpapers() {
    var pairList = Model.pairs(root.dirFiles)
    var count = pairList.length
    // Keep the index in range; a fresh dir (no saved index) lands on 0, which
    // is the pair that was applied before pairs existed.
    if (count === 0) root.pairIndex = 0
    else if (root.pairIndex < 0 || root.pairIndex >= count) root.pairIndex = 0
    var p = count > 0 ? Model.wallpaperPaths(root.wallpaperDirAbs, root.dirFiles, root.leftMonitor, root.rightMonitor) : { left: "", right: "" }
    if (count > 0) {
      var sel = pairList[root.pairIndex]
      p.left = sel.left ? root.wallpaperDirAbs + "/" + sel.left : ""
      p.right = sel.right ? root.wallpaperDirAbs + "/" + sel.right : ""
    }
    var changed = (p.left !== root.leftWallpaper) || (p.right !== root.rightWallpaper)
    root.leftWallpaper = p.left
    root.rightWallpaper = p.right
    if (changed) logEvent("wallpapers", "left=" + (p.left || "-") + " right=" + (p.right || "-") + " pair=" + root.pairIndex + "/" + count)
  }

  // ------------------------------------------------------------- side logic

  // Which side is the named screen on? Prefer the explicit config; fall back
  // to geometry (leftmost screen = left, rightmost = right), which is
  // unambiguous for two monitors.
  function sideForScreen(name) {
    if (name && name === root.leftMonitor) return "left"
    if (name && name === root.rightMonitor) return "right"
    var screens = Quickshell.screens || []
    var leftmost = null, rightmost = null
    for (var i = 0; i < screens.length; i++) {
      var s = screens[i]
      if (!s) continue
      if (leftmost === null || s.x < leftmost.x) leftmost = s
      if (rightmost === null || s.x > rightmost.x) rightmost = s
    }
    if (leftmost && leftmost.name === name) return "left"
    if (rightmost && rightmost.name === name) return "right"
    return ""
  }

  function wallpaperForScreen(name) {
    var side = root.sideForScreen(name)
    if (side === "left") return root.leftWallpaper
    if (side === "right") return root.rightWallpaper
    return ""
  }

  // -------------------------------------------------------------- config io

  function applyConfigText(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (parsed && typeof parsed === "object" && parsed.dualWallpaper
          && typeof parsed.dualWallpaper === "object" && !Array.isArray(parsed.dualWallpaper)) {
        var cfg = parsed.dualWallpaper
        root.wallpaperDir = String(cfg.wallpaperDir || Model.defaultWallpaperDir())
        root.leftMonitor = String(cfg.leftMonitor || "")
        root.rightMonitor = String(cfg.rightMonitor || "")
        root.pairIndex = Number(cfg.pairIndex) >= 0 ? Number(cfg.pairIndex) : 0
      }
    } catch (error) {
    }
  }

  function mutateConfig(label, mutate) {
    var cfg = null
    try {
      cfg = JSON.parse(shellConfigFile.text() || "{}")
    } catch (error) {
      cfg = null
    }
    if (!cfg || typeof cfg !== "object" || Array.isArray(cfg)) {
      logEvent("config-write-failed", label + " (unreadable shell.json)")
      return false
    }
    if (!cfg.dualWallpaper || typeof cfg.dualWallpaper !== "object" || Array.isArray(cfg.dualWallpaper)) {
      cfg.dualWallpaper = {}
    }
    mutate(cfg.dualWallpaper)
    cfg.version = 1
    shellConfigFile.setText(JSON.stringify(cfg, null, 2) + "\n")
    // Reflect the write locally; the FileView watcher also fires applyConfigText.
    root.applyConfigText(shellConfigFile.text())
    root.rescanDir()
    logEvent("config", label)
    return true
  }

  function setWallpaperDir(value) {
    var dir = String(value || "").trim()
    if (!dir) return false
    return root.mutateConfig("wallpaperDir=" + dir, function(cfg) { cfg.wallpaperDir = dir })
  }

  function setLeftMonitor(value) {
    var name = String(value || "").trim()
    return root.mutateConfig("leftMonitor=" + name, function(cfg) { cfg.leftMonitor = name })
  }

  function setRightMonitor(value) {
    var name = String(value || "").trim()
    return root.mutateConfig("rightMonitor=" + name, function(cfg) { cfg.rightMonitor = name })
  }

  // ------------------------------------------------------- pair navigation

  // The wallpaper pairs in the current dir, as { stem, left, right } rows.
  function pairList() {
    return Model.pairs(root.dirFiles)
  }

  // Move to pair at `index` (clamped, wrapping). Persisted in config so the
  // choice survives a restart. Returns the new index, or -1 when there are
  // no pairs to show.
  function setPairIndex(index) {
    var count = root.pairList().length
    if (count === 0) return -1
    var i = ((index % count) + count) % count
    if (i === root.pairIndex) return i
    // Persist, then update synchronously: mutateConfig's applyConfigText reads
    // the file back, which is not yet flushed (atomic write), so set the
    // index and recompute ourselves for an immediate, consistent update.
    root.mutateConfig("pairIndex=" + i, function(cfg) { cfg.pairIndex = i })
    root.pairIndex = i
    root.recomputeWallpapers()
    return i
  }

  function nextPair() {
    return root.setPairIndex(root.pairIndex + 1)
  }

  function prevPair() {
    return root.setPairIndex(root.pairIndex - 1)
  }

  function screensList() {
    var screens = []
    var list = Quickshell.screens || []
    for (var i = 0; i < list.length; i++) {
      var s = list[i]
      if (!s) continue
      screens.push({
        name: String(s.name || ""),
        width: Number(s.width) || 0,
        height: Number(s.height) || 0,
        x: Number(s.x) || 0,
        side: root.sideForScreen(String(s.name || ""))
      })
    }
    return screens
  }

  function screensJson() {
    return JSON.stringify(root.screensList())
  }

  function statusJson() {
    return JSON.stringify({
      wallpaperDir: root.wallpaperDir,
      wallpaperDirAbs: root.wallpaperDirAbs,
      leftMonitor: root.leftMonitor,
      rightMonitor: root.rightMonitor,
      leftWallpaper: root.leftWallpaper,
      rightWallpaper: root.rightWallpaper,
      pairIndex: root.pairIndex,
      pairCount: root.pairList().length,
      files: root.dirFiles,
      screens: root.screensList()
    })
  }

  // ------------------------------------------------------------- components

  Process {
    id: dirScanProcess
    running: false
    command: ["find", root.wallpaperDirAbs, "-maxdepth", "1", "-type", "f", "-printf", "%f\n"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyDirListing(text)
    }
  }

  FileView {
    id: wallpaperDirView
    path: root.wallpaperDirAbs
    watchChanges: true
    printErrors: false
    onLoaded: root.rescanDir()
    onFileChanged: root.rescanDir()
  }

  FileView {
    id: shellConfigFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyConfigText(text())
    onFileChanged: reload()
  }

  // One background window per screen, exactly like the stock background, but
  // each screen shows the wallpaper of its own side.
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }

      WlrLayershell.namespace: "omarchy-dual-wallpaper"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      updatesEnabled: true

      Image {
        id: frame
        anchors.fill: parent
        source: root.imageUrl(root.wallpaperForScreen(String(modelData.name || "")))
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
      }
    }
  }

  function imageUrl(path) {
    return path ? Util.fileUrl(path) : ""
  }

  Component.onCompleted: {
    logEvent("service-ready")
    root.applyConfigText(shellConfigFile.text())
    root.rescanDir()
  }

  // omarchy-shell dualwallpaper ...
  IpcHandler {
    target: "dualwallpaper"

    function status(): string {
      return root.statusJson()
    }

    function refresh(): string {
      root.rescanDir()
      return "ok"
    }

    // omarchy-shell dualwallpaper dir [path]
    function dir(path: string): string {
      if (String(path || "") === "") return root.wallpaperDir
      return root.setWallpaperDir(path) ? "ok" : "invalid path"
    }

    // omarchy-shell dualwallpaper left [monitor-name]
    function left(name: string): string {
      if (String(name || "") === "") return root.leftMonitor
      return root.setLeftMonitor(name) ? "ok" : "invalid name"
    }

    // omarchy-shell dualwallpaper right [monitor-name]
    function right(name: string): string {
      if (String(name || "") === "") return root.rightMonitor
      return root.setRightMonitor(name) ? "ok" : "invalid name"
    }

    // omarchy-shell dualwallpaper next | prev
    function next(): string {
      var i = root.nextPair()
      return i < 0 ? "no wallpapers" : "pair " + i
    }

    function prev(): string {
      var i = root.prevPair()
      return i < 0 ? "no wallpapers" : "pair " + i
    }
  }
}
