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
        { syntax: "Up / Down", note: "browse history" },
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
