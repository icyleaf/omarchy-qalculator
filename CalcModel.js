.pragma library

// Pure-JS seam for the calculator overlay: history persistence and the
// "is this worth showing?" gate that keeps qalc's interactive echo (typing
// `1 +` answers `1`) out of the UI. No QML, no process calls, so it is
// testable with plain fixtures.

var HISTORY_LIMIT = 50

// Caps for anything that came from outside this file: user keystrokes, a qalc
// result, or the history document on disk. The overlay renders every one of
// them, so the limit lives here, before the value reaches a Text or is written
// back. Entries longer than these are rejected rather than truncated, so a
// history document can never be reshaped into a plausible-looking lie.
var EXPRESSION_MAX = 512
var RESULT_MAX = 512

// Hard ceiling on the history document itself, read and written. 50 entries of
// 512+512 characters is well under this; the cap exists so a planted oversized
// file is rejected instead of materialised, and so the reader can detect
// overflow (it reads cap + 1 bytes).
var HISTORY_BYTES_MAX = 65536

// Ceiling on the shell.json read. The file also holds the bar layout and every
// plugin's settings, so it is larger than our own history but must still be
// bounded: an oversized file is rejected rather than materialised.
var SETTINGS_BYTES_MAX = 262144

// Rows of the lower area (history or help) shown before it scrolls. Bounded
// here so the history preview and the help reference request the same height:
// if help asked for its full length instead, swapping the two with Ctrl+/
// would resize the card.
var LOWER_PREVIEW_ROWS = 7

// Pixel height of `LOWER_PREVIEW_ROWS` stacked rows of `rowHeight` with `gap`
// between them (no gap after the last). Both sections size to this ceiling.
function previewHeight(rowHeight, gap) {
  var rows = LOWER_PREVIEW_ROWS
  var step = numberOr(rowHeight, 0)
  return rows * step + Math.max(0, rows - 1) * numberOr(gap, 0)
}

// ── State paths ─────────────────────────────────────────────────────────────

// The plugin owns one directory under the Omarchy state root. Omarchy's own
// state directory is shared and world-traversable, so the plugin's files live
// in a child it can hold at 0700 and whose contents it can safely repair.
// XDG_STATE_HOME is honoured; when unset the spec default is $HOME/.local/state.
// There is deliberately no /tmp fallback: an unwritable state directory must
// fail closed, not relocate the history to a predictable shared path.
function stateDir(home, xdgStateHome) {
  var base = xdgStateHome && String(xdgStateHome).length > 0
    ? String(xdgStateHome)
    : String(home || "") + "/.local/state"
  return base + "/omarchy/qalculator"
}

function historyFile(stateDirPath) {
  return String(stateDirPath) + "/history.json"
}

// Previous single-file location, kept only so the first run on the new layout
// can carry an existing history over. Nothing writes here after migration.
function legacyHistoryFile(home, xdgStateHome) {
  var base = xdgStateHome && String(xdgStateHome).length > 0
    ? String(xdgStateHome)
    : String(home || "") + "/.local/state"
  return base + "/omarchy/qalculator-history.json"
}

// Invisible characters that would desynchronise rendering or sneak a bidi
// reorder into a result: C0 (minus tab), C1, line/paragraph separators and the
// Unicode bidi controls. Everything a qalc answer legitimately contains (√ − ≈
// µ ° etc.) is a visible character and is kept.
var CONTROL_CHARS = /[\u0000-\u0008\u000A-\u001F\u007F-\u009F\u2028\u2029\u202A-\u202E\u2066-\u2069]/g

// ── Text hygiene ────────────────────────────────────────────────────────────

function sanitizeText(value) {
  var text = value === undefined || value === null ? "" : String(value)
  return text.replace(CONTROL_CHARS, "")
}

// Display-and-store form: no control characters, no leading/trailing blanks.
// The caller decides the length policy (reject or truncate) from here.
function cleanText(value) {
  return sanitizeText(value).trim()
}

function withinLength(text, maxLength) {
  return String(text).length <= maxLength
}

// ── Help ────────────────────────────────────────────────────────────────────

// Every example below was checked against the installed qalc. Keep them in
// `to` form: qalc treats `in` as the inch unit, so `5 ft in m` silently answers
// `0.0387096 m³` instead of converting, and the overlay should not teach it.
function helpSections() {
  return [
    {
      title: "Math",
      rows: [
        { syntax: "2+2 · 60 + 74 · (3+5)*2", note: "arithmetic" },
        { syntax: "2^10 · 3**3", note: "powers" },
        { syntax: "sqrt(625) · 5!", note: "functions, factorial" },
        { syntax: "sin(pi/2) · log10(100) · ln(e)", note: "trig / log" },
        { syntax: "abs(-3) · round(3.7)", note: "rounding" },
        { syntax: "0x1F · 0b1010", note: "hex / binary input" },
        { syntax: "1/3 · pi", note: "constants and fractions" }
      ]
    },
    {
      title: "Percent",
      rows: [
        { syntax: "20% * 50", note: "percent of a value" },
        { syntax: "100 + 15%", note: "increase by a percent" },
        { syntax: "19m + 47%", note: "percent of a quantity" }
      ]
    },
    {
      title: "Conversions",
      rows: [
        { syntax: "29 inches to cm", note: "length" },
        { syntax: "5 kg to lb", note: "mass" },
        { syntax: "20 celsius to fahrenheit", note: "temperature" },
        { syntax: "100 km/h to mph", note: "speed" },
        { syntax: "1 hour to seconds", note: "time" },
        { syntax: "100 MB to GB", note: "data" },
        { syntax: "1 mile to km", note: "use `to`, not `in`" }
      ]
    },
    {
      title: "Currency",
      rows: [
        { syntax: "10 usd to gbp · 45 jpy to inr", note: "fiat" },
        { syntax: "1 btc to usd", note: "crypto" },
        { syntax: "1 EUR to JPY", note: "cached ECB / market rates" }
      ]
    },
    {
      title: "Keys",
      rows: [
        { syntax: "Enter", note: "copy answer and close" },
        { syntax: "Alt+Enter", note: "copy answer, stay open" },
        { syntax: "Down / Up", note: "walk history into the input" },
        { syntax: "Ctrl+1…9 · Ctrl+0", note: "copy history 1-10, close" },
        { syntax: "Ctrl+/", note: "toggle this help" },
        { syntax: "Esc", note: "close" }
      ]
    }
  ]
}

// Flat count of visible rows, used to size the help card.
function helpRowCount() {
  var sections = helpSections()
  var count = 0
  for (var i = 0; i < sections.length; i++) count += sections[i].rows.length + 1
  return count
}

// ── History ─────────────────────────────────────────────────────────────────

// Row index for Ctrl+1..Ctrl+9 and Ctrl+0 (the tenth). Returns -1 when the row
// is out of range, so history longer than ten entries simply ignores the rest.
function historyIndexForKey(key) {
  if (key >= Qt.Key_1 && key <= Qt.Key_9) return key - Qt.Key_1
  if (key === Qt.Key_0) return 9
  return -1
}

// Badge shown at the start of a history row: the Control symbol followed by the
// digit that copies it. Rows past the tenth have no shortcut, so no label.
// U+2303 (⌃) is the compact Control glyph and is covered by the mono fonts.
function historyShortcutLabel(index) {
  if (index < 0 || index > 9) return ""
  return "⌃" + String(index === 9 ? 0 : index + 1)
}

// Step for a history-browse key: ↓ walks toward older entries (the list focus
// moves down the rows), ↑ walks back toward the newest. Any other key is 0.
function historyStepForKey(key) {
  if (key === Qt.Key_Down) return 1
  if (key === Qt.Key_Up) return -1
  return 0
}

// Next selection when walking the history with ↓ (step = +1, toward older
// entries, matching the list focus moving down the rows) or ↑ (step = -1, back
// toward the newest). `current` is -1 when no row is selected. The walk stops
// at both ends rather than wrapping:
//   - stepping past the oldest row keeps the oldest selected
//   - stepping back past the newest returns -1, which the caller reads as
//     "leave the browse mode"
// `count` is the history length.
function nextHistoryIndex(current, step, count) {
  var length = count > 0 ? count : 0
  if (length === 0) return -1
  var from = current >= 0 && current < length ? current : -1
  var next = from + step
  if (next < -1) next = -1
  if (next > length - 1) next = length - 1
  return next
}

function parseHistory(raw) {
  if (!raw) return []
  var parsed
  try {
    parsed = JSON.parse(raw)
  } catch (e) {
    return []
  }
  if (!Array.isArray(parsed)) return []

  var out = []
  // Stop at the limit: a corrupt or hostile document must not materialise tens
  // of thousands of rows into the list model.
  for (var i = 0; i < parsed.length && out.length < HISTORY_LIMIT; i++) {
    var entry = normalizeEntry(parsed[i])
    if (entry) out.push(entry)
  }
  return out
}

function normalizeEntry(value) {
  if (!value || typeof value !== "object") return null
  var expression = cleanText(value.expression === undefined ? value.expr || "" : value.expression)
  var result = cleanText(value.result === undefined ? "" : value.result)
  if (!expression || !result) return null
  if (!withinLength(expression, EXPRESSION_MAX)) return null
  if (!withinLength(result, RESULT_MAX)) return null
  return { expression: expression, result: result }
}

function serializeHistory(entries) {
  return JSON.stringify(capHistory(entries, HISTORY_LIMIT), null, 2) + "\n"
}

function capHistory(entries, limit) {
  if (!Array.isArray(entries)) return []
  var max = limit > 0 ? limit : HISTORY_LIMIT
  return entries.slice(0, max)
}

// Newest first. Re-computing the same expression moves it to the top instead
// of duplicating it, and the most recent result wins.
function addHistoryEntry(entries, entry, limit) {
  var normalized = normalizeEntry(entry)
  if (!normalized) return capHistory(entries, limit)

  var out = [normalized]
  var existing = Array.isArray(entries) ? entries : []
  for (var i = 0; i < existing.length; i++) {
    var prev = normalizeEntry(existing[i])
    if (!prev) continue
    if (prev.expression === normalized.expression) continue
    out.push(prev)
  }
  return capHistory(out, limit)
}

// ── Overlay layout ──────────────────────────────────────────────────────────

// Where the input box sits vertically. "center" is the default; "top" and
// "bottom" pin it near the respective outer gap, with the lower area (history,
// help or hint) filling the space on the other side.
var INPUT_POSITIONS = ["top", "center", "bottom"]
var DEFAULT_INPUT_POSITION = "center"

function normalizeInputPosition(value) {
  var candidate = String(value === undefined || value === null ? "" : value)
  for (var i = 0; i < INPUT_POSITIONS.length; i++) {
    if (INPUT_POSITIONS[i] === candidate) return candidate
  }
  return DEFAULT_INPUT_POSITION
}

// Vertical geometry for the overlay, kept here so it is plain numbers in and
// plain numbers out rather than a tangle of QML bindings.
//
// With `position: "center"` the input is pinned to the panel's centre and the
// card grows downward, so a growing history list never moves the input. With
// "top" the input sits just under the top gap; with "bottom" the input sits
// just above the bottom gap and the lower area is placed *above* it instead.
// `inputY`, `noticeY` and `lowerY` are each block's offset from the card's top
// edge, so the caller only has to place boxes. In every case the lower area is
// capped by the room left before the card's outer edge would leave the panel,
// and scrolls internally when its content is taller.
function overlayLayout(input) {
  if (!input || typeof input !== "object") input = {}
  var panelHeight = numberOr(input.panelHeight, 0)
  var gapsOut = numberOr(input.gapsOut, 0)
  var contentTopInset = numberOr(input.contentTopInset, 0)
  var contentBottomInset = numberOr(input.contentBottomInset, 0)
  var inputHeight = numberOr(input.inputHeight, 0)
  var contentSpacing = numberOr(input.contentSpacing, 0)
  var noticeBlock = numberOr(input.noticeBlock, 0)
  var desiredLowerHeight = numberOr(input.desiredLowerHeight, 0)
  var position = normalizeInputPosition(input.position)

  // Everything the card holds besides the lower area, including both content
  // insets and the gap the notice reserves.
  var fixedBlock = contentTopInset + inputHeight + contentSpacing + noticeBlock + contentBottomInset
  // Tallest the card may be, leaving one outer gap top and bottom.
  var available = Math.max(0, panelHeight - gapsOut * 2)

  var cardTop = 0
  var lowerMaxHeight = 0

  if (position === "bottom") {
    // The input's bottom edge is pinned to the bottom gap, so the lower area
    // grows upward and its cap is everything the card does not need for the
    // fixed block.
    lowerMaxHeight = Math.max(0, available - fixedBlock)
  } else if (position === "top") {
    cardTop = gapsOut
    lowerMaxHeight = Math.max(0, panelHeight - gapsOut - cardTop - fixedBlock)
  } else {
    // Center: the input's centre sits on the panel's centre, clamped so the
    // card never starts above the outer gap.
    cardTop = Math.max(gapsOut, panelHeight / 2 - contentTopInset - inputHeight / 2)
    lowerMaxHeight = Math.max(0, panelHeight - gapsOut - cardTop - fixedBlock)
  }

  var lowerHeight = Math.min(Math.max(0, desiredLowerHeight), lowerMaxHeight)
  var cardHeight = Math.min(fixedBlock + lowerHeight, available)

  if (position === "bottom") {
    cardTop = Math.max(gapsOut, panelHeight - gapsOut - cardHeight)
  } else if (position === "center") {
    // Keep the input centred when the card still fits under it; otherwise slide
    // the card up until its bottom reaches the bottom gap.
    cardTop = Math.max(gapsOut, Math.min(cardTop, panelHeight - gapsOut - cardHeight))
  }

  var lowerAbove = position === "bottom"
  var inputY = 0
  var noticeY = 0
  var lowerY = 0
  if (lowerAbove) {
    lowerY = contentTopInset
    noticeY = lowerY + lowerHeight + contentSpacing
    inputY = lowerY + lowerHeight + contentSpacing + noticeBlock
  } else {
    inputY = contentTopInset
    noticeY = inputY + inputHeight + contentSpacing
    lowerY = inputY + inputHeight + contentSpacing + noticeBlock
  }

  return {
    cardTop: cardTop,
    lowerMaxHeight: lowerMaxHeight,
    lowerHeight: lowerHeight,
    inputY: inputY,
    noticeY: noticeY,
    lowerY: lowerY,
    cardHeight: Math.max(0, cardHeight)
  }
}

function numberOr(value, fallback) {
  return typeof value === "number" && isFinite(value) ? value : fallback
}

// ── Settings ────────────────────────────────────────────────────────────────

// Read this plugin's inline settings from the shell.json document. Every key is
// optional and unknown keys are ignored, matching the shell's one-entry-inline
// settings model: the plugin entry is found by id in the top-level plugins[].
function parseSettings(raw, pluginId) {
  var out = { inputPosition: DEFAULT_INPUT_POSITION }
  var config = null
  try {
    config = JSON.parse(String(raw === undefined || raw === null ? "" : raw))
  } catch (e) {
    return out
  }
  if (!config || !Array.isArray(config.plugins)) return out
  for (var i = 0; i < config.plugins.length; i++) {
    var entry = config.plugins[i]
    if (!entry || entry.id !== pluginId) continue
    if (entry.inputPosition !== undefined) out.inputPosition = normalizeInputPosition(entry.inputPosition)
    break
  }
  return out
}

// ── Dependencies ────────────────────────────────────────────────────────────

// Every external command the overlay shells out to, paired with the Arch
// package that provides it. `path` is the absolute location the plugin will
// execute, so nothing is ever resolved through PATH; `bin` is the bare name
// used as the state key and in the notice. The package name is only what we
// hand to the installer. Both live in `extra`, so a plain `pacman -S` suffices.
var DEPENDENCIES = [
  { bin: "qalc", path: "/usr/bin/qalc", pkg: "libqalculate", feature: "live evaluation" },
  { bin: "wl-copy", path: "/usr/bin/wl-copy", pkg: "wl-clipboard", feature: "copy" }
]

// `states` maps a dependency's bin to one of "checking", "available" or
// "missing". Only "missing" counts: a probe still in flight must not flash the
// "not found" notice, and an available tool must not either.
function missingDependencies(states) {
  if (!states) return []
  var out = []
  for (var i = 0; i < DEPENDENCIES.length; i++) {
    var dep = DEPENDENCIES[i]
    if (states[dep.bin] === "missing") out.push(dep)
  }
  return out
}

function dependencyAvailable(states, bin) {
  return !!states && states[bin] === "available"
}

// Absolute path of the executable for a dependency bin, or "" when the bin is
// not one we declared. Callers pass this straight into an argv array.
function dependencyPath(bin) {
  for (var i = 0; i < DEPENDENCIES.length; i++) {
    if (DEPENDENCIES[i].bin === bin) return DEPENDENCIES[i].path
  }
  return ""
}

// Unique provider packages, in declaration order, for the missing tools.
// Names that do not look like an Arch package are dropped: the launcher runs
// the string through a shell, so nothing but a bare package token may reach it.
var PACKAGE_PATTERN = /^[a-z0-9][a-z0-9@._+-]{0,63}$/

function missingPackages(missing) {
  var out = []
  if (!Array.isArray(missing)) return out
  for (var i = 0; i < missing.length; i++) {
    var pkg = missing[i] && missing[i].pkg
    if (!pkg || !PACKAGE_PATTERN.test(pkg)) continue
    if (out.indexOf(pkg) === -1) out.push(pkg)
  }
  return out
}

// One-click install: Omarchy's own package helper in a floating presentation
// terminal. Returns "" when nothing is missing, so callers can no-op.
function installCommand(missing) {
  var pkgs = missingPackages(missing)
  if (pkgs.length === 0) return ""
  return "omarchy pkg add " + pkgs.join(" ")
}

function dependencyNotice(missing) {
  if (!missing || missing.length === 0) return ""
  var parts = []
  for (var i = 0; i < missing.length; i++) {
    parts.push(missing[i].bin + " (" + missing[i].pkg + ")")
  }
  return "Missing: " + parts.join(", ") + " — click to install"
}

// ── Evaluation gate ─────────────────────────────────────────────────────────

// True when the qalc output is a real answer for the current input rather than
// a partial echo. `qalc -t "1 +"` prints `1`, and `qalc -t "abc"` treats the
// letters as units, so both the trailing-operator case and the
// output-equals-input case are rejected here.
function isEvaluable(expression, output) {
  var expr = String(expression || "").trim()
  if (!expr) return false
  if (hasIncompleteEnding(expr)) return false

  var result = cleanResult(output)
  if (!result) return false
  if (result.indexOf(">") !== -1) return false
  if (result.toLowerCase().indexOf("unrecognized") !== -1) return false
  if (result === expr) return false
  return true
}

function hasIncompleteEnding(expr) {
  return /[+\-*/^%<>=,(]$/.test(String(expr).trim())
}

// qalc -t prints the bare answer, but guard against a stray leading `= ` or a
// trailing interactive prompt if a future version changes its output, and strip
// invisible characters so a crafted result cannot desync rendering.
function cleanResult(output) {
  var text = sanitizeText(output)
  text = text.replace(/\r/g, "").trim()
  if (text.charAt(0) === "=") text = text.slice(1).trim()
  text = text.replace(/>\s*$/, "").trim()
  return text
}
