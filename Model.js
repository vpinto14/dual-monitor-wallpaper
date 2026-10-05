// Pure logic for the dual_monitor_wallpaper plugin.
//
// The wallpaper folder holds one image per monitor. The file for the LEFT
// monitor ends in "_L", the file for the RIGHT monitor ends in "_R" — so a
// pair is "forest_L.png" / "forest_R.png". This module maps a configured
// monitor name to its wallpaper path, and parses the per-screen list the
// service exposes to the panel.

function defaultWallpaperDir() {
  return "~/.omarchy-config/wallpaper"
}

// Expand a leading "~" against $HOME. A bare "~" becomes the home dir;
// anything without a leading "~" is returned unchanged.
function expandHome(dir, home) {
  var d = String(dir || "").trim()
  if (!d) return d
  if (d === "~") return home
  if (d.indexOf("~/") === 0) return home + d.slice(1)
  return d
}

// The file name of an absolute path, for display in the panel.
function basename(path) {
  var p = String(path || "")
  var idx = p.lastIndexOf("/")
  return idx >= 0 ? p.slice(idx + 1) : p
}

// The name of a wallpaper file without its extension: "forest_L.png" ->
// "forest_L". A name with no dot is returned unchanged.
function stemOf(name) {
  var n = String(name || "")
  var idx = n.lastIndexOf(".")
  if (idx > 0) n = n.slice(0, idx)
  return n
}

// True when `name` is a wallpaper file for the given side: its stem (name
// without extension) must end in the side's suffix and carry a real stem
// before it ("L" alone is not a wallpaper). "forest_L.png" is a left file.
function matchesSide(name, side) {
  var stem = stemOf(name)
  var suffix = side === "left" ? "_L" : "_R"
  if (stem.length <= suffix.length) return false
  if (stem.slice(-suffix.length) !== suffix) return false
  return stem.slice(0, -suffix.length).trim().length > 0
}

// The single wallpaper path for `side` among `files` (a list of file names in
// the wallpaper dir). Returns "" when there is no match. If more than one
// file matches, the lexicographically first one wins — deterministic, and it
// is the one the service applies too.
function wallpaperFor(files, side) {
  var stem = side === "left" ? "_L" : "_R"
  var candidates = []
  for (var i = 0; i < files.length; i++) {
    if (matchesSide(files[i], side)) candidates.push(files[i])
  }
  if (candidates.length === 0) return ""
  candidates.sort()
  return candidates[0]
}

// Given an already-resolved absolute wallpaper dir and the two configured
// monitor names, return the two absolute paths the service should render.
//   { left: <abs path | "">, right: <abs path | ""> }
function wallpaperPaths(base, files, leftMonitor, rightMonitor) {
  var b = String(base || "").trim().replace(/\/+$/, "")
  var l = wallpaperFor(files, "left")
  var r = wallpaperFor(files, "right")
  return {
    left: l ? b + "/" + l : "",
    right: r ? b + "/" + r : ""
  }
}

// Parse the JSON array the service publishes about its screens into a list
// the panel can render. Each item: { name, width, height, x, side } where
// side is "left" | "right" | "" (unassigned).
function parseScreens(raw) {
  var screens = []
  try {
    screens = raw ? JSON.parse(String(raw)) : []
  } catch (e) {
    screens = []
  }
  if (!Array.isArray(screens)) screens = []

  var out = []
  for (var i = 0; i < screens.length; i++) {
    var s = screens[i]
    if (!s || typeof s !== "object") continue
    out.push({
      name: String(s.name || ""),
      width: Number(s.width) || 0,
      height: Number(s.height) || 0,
      x: Number(s.x) || 0,
      side: s.side === "left" || s.side === "right" ? s.side : ""
    })
  }
  return out
}

// The wallpaper "pairs" in `files`, as a sorted list of
//   { stem, left, right }
// where `left`/`right` are file names (not paths) — each the
// lexicographically first file for that stem+side ("" when that side has
// none). A stem is a file name with its "_L"/"_R" suffix and extension
// removed: "forest_L.png" and "forest_R.png" share the stem "forest". The
// list is ordered by stem, so index 0 is the pair the service applied
// before pairs existed (the lexicographically first one).
function pairs(files) {
  var byStem = {}
  var order = []
  for (var i = 0; i < files.length; i++) {
    var name = files[i]
    var side = null
    if (matchesSide(name, "left")) side = "left"
    else if (matchesSide(name, "right")) side = "right"
    if (!side) continue
    var key = stemOf(name).slice(0, -2)
    if (!key) continue
    if (!byStem[key]) { byStem[key] = { stem: key, left: "", right: "" }; order.push(key) }
    if (side === "left" && !byStem[key].left) byStem[key].left = name
    else if (side === "right" && !byStem[key].right) byStem[key].right = name
  }
  order.sort()
  var out = []
  for (var j = 0; j < order.length; j++) out.push(byStem[order[j]])
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    defaultWallpaperDir: defaultWallpaperDir,
    expandHome: expandHome,
    basename: basename,
    stemOf: stemOf,
    matchesSide: matchesSide,
    wallpaperFor: wallpaperFor,
    wallpaperPaths: wallpaperPaths,
    pairs: pairs,
    parseScreens: parseScreens
  }
}
