import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "CalcModel.js" as CalcModel

Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string expression: ""
  property string result: ""
  property bool resultVisible: false
  // Maps each dependency bin to "checking", "available" or "missing". Empty
  // until the first probe finishes, so nothing flashes on load.
  property var dependencyStates: ({})
  property int probeIndex: 0
  property bool installingDependencies: false
  property bool copied: false
  property var history: []
  property int historyIndex: -1
  property bool helpVisible: false
  // True while ↑/↓ are walking the history. Browsing keeps the list on screen
  // even though the input box now holds the selected expression, and makes the
  // answer area show that entry's stored result instead of a fresh evaluation.
  property bool browsingHistory: false
  // Set while the code (not the user) is writing to the input box: the
  // TextField's onTextChanged must not treat a browsed fill as manual typing.
  property bool syncingInput: false

  // ── Output and process bounds ─────────────────────────────────────────────
  // A child is never allowed to retain output in the shared shell process
  // without a ceiling. qalc answers are tiny; anything larger is either a
  // pathological expression or a sign the child is not qalc, and is dropped
  // rather than rendered.
  readonly property int outputLimit: 4096
  property string evalBuffer: ""
  property bool evalOverflow: false
  readonly property int probeTimeoutMs: 2000
  readonly property int evalTimeoutMs: 5000
  readonly property int historyTimeoutMs: 3000
  readonly property int killGraceMs: 1500

  // Absolute interpreter locations. The plugin never resolves an executable
  // through PATH, so a shadowed binary earlier in PATH cannot be reached.
  readonly property string shBin: "/usr/bin/sh"
  readonly property string testBin: "/usr/bin/test"

  // Minimal environment for a probe: a fixed PATH, nothing inherited.
  readonly property var probeEnvironment: ({
    "PATH": "/usr/bin:/bin",
    "LC_ALL": "C"
  })

  // qalc keeps its cached exchange rates under the XDG data/config roots, so it
  // needs HOME and the XDG overrides to find them, but nothing else.
  readonly property var qalcEnvironment: ({
    "HOME": Quickshell.env("HOME") || "",
    "PATH": "/usr/bin:/bin",
    "XDG_DATA_HOME": Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") || "") + "/.local/share",
    "XDG_CONFIG_HOME": Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") || "") + "/.config",
    "LC_ALL": "C.UTF-8"
  })

  // wl-copy is a Wayland client: it needs the compositor socket and runtime
  // directory, and nothing else.
  readonly property var clipboardEnvironment: ({
    "WAYLAND_DISPLAY": Quickshell.env("WAYLAND_DISPLAY") || "wayland-1",
    "XDG_RUNTIME_DIR": Quickshell.env("XDG_RUNTIME_DIR") || "",
    "PATH": "/usr/bin:/bin"
  })

  // Shares the [menu] surface tokens — themes that style the menu also style
  // the calculator, matching the emojis and clipboard overlays.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(600), panel.width - Style.gapsOut * 2)
  property int inputHeight: Math.max(Style.space(38), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int rowHeight: Math.max(Style.space(40), Style.font.body + Style.spacing.rowPaddingX * 2)
  // Fixed width reserved for the history shortcut badge so every row's
  // expression starts on the same x, badge or not.
  property int shortcutSlotWidth: Math.max(Style.space(26), Style.font.body + Style.spacing.md * 2)
  property int historyLimit: CalcModel.HISTORY_LIMIT
  property int debounceMs: 150
  // Mirrors CalcModel.EXPRESSION_MAX so the TextField stops accepting input at
  // the same bound the model enforces.
  readonly property int expressionLimit: CalcModel.EXPRESSION_MAX

  readonly property string stateDir: CalcModel.stateDir(Quickshell.env("HOME"), Quickshell.env("XDG_STATE_HOME"))
  readonly property string historyPath: CalcModel.historyFile(stateDir)
  readonly property string legacyHistoryPath: CalcModel.legacyHistoryFile(Quickshell.env("HOME"), Quickshell.env("XDG_STATE_HOME"))
  readonly property int historyBytesMax: CalcModel.HISTORY_BYTES_MAX
  property bool historyMigrated: false
  property bool pendingLegacyRemoval: false
  readonly property bool inputEmpty: expression.trim() === ""
  readonly property bool showHistory: (inputEmpty || browsingHistory) && history.length > 0 && !helpVisible
  readonly property bool showHelp: inputEmpty && helpVisible
  readonly property bool showHint: inputEmpty && history.length === 0 && !helpVisible
  // The entry currently highlighted by ↑/↓, or null when not browsing.
  readonly property var browsedEntry: (browsingHistory && historyIndex >= 0 && historyIndex < history.length)
    ? history[historyIndex] : null
  // While browsing, the answer area mirrors the stored result rather than a
  // fresh evaluation, so what the user sees always matches the highlighted row.
  readonly property string shownResult: browsedEntry ? browsedEntry.result : result
  readonly property bool shownResultVisible: browsingHistory ? browsedEntry !== null : resultVisible
  readonly property int historyVisibleRows: Math.min(history.length, 7)
  readonly property int hintHeight: Math.round(Style.font.body * 1.6)
  readonly property int noticeHeight: Math.round(Style.font.body * 1.6)
  readonly property int historyHeight: historyVisibleRows * rowHeight + Math.max(0, historyVisibleRows - 1) * Style.spacing.xs
  readonly property int helpLineHeight: Math.round(Style.font.body * 1.7)
  readonly property int helpRows: CalcModel.helpRowCount()
  readonly property int helpHeight: helpRows * helpLineHeight
  readonly property var helpSections: CalcModel.helpSections()
  readonly property var missingDeps: CalcModel.missingDependencies(dependencyStates)
  readonly property bool depsMissing: missingDeps.length > 0
  readonly property string dependencyNotice: CalcModel.dependencyNotice(missingDeps)
  // Tallest a lower section may grow before it starts scrolling.
  readonly property int maxSectionHeight: Math.max(
    Style.space(60),
    panel.height - Style.gapsOut * 2 - contentMargin * 2 - inputHeight - contentSpacing - (depsMissing ? noticeHeight + contentSpacing : 0))
  readonly property int panelHeight: Math.max(
    Style.space(80),
    Math.min(
      contentMargin * 2 + inputHeight + contentSpacing
        + (showHistory ? historyHeight : 0)
        + (showHelp ? Math.min(helpHeight, maxSectionHeight) : 0)
        + (showHint ? hintHeight : 0)
        + (depsMissing ? noticeHeight + contentSpacing : 0),
      panel.height - Style.gapsOut * 2))
  readonly property int cardHeight: Math.min(panelHeight, panel.height - Style.gapsOut * 2)

  function open(payloadJson) {
    root.opened = true
    root.expression = ""
    root.result = ""
    root.resultVisible = false
    root.copied = false
    root.historyIndex = -1
    root.browsingHistory = false
    root.helpVisible = false
    // Cheap recheck: only re-probe what was known to be missing, so a tool
    // installed while the overlay was closed is picked up on the next summon.
    if (root.depsMissing) root.checkDependencies()
    // TextField.text is set imperatively: a QML binding would be broken the
    // moment the user types, and then stop resetting on the next open.
    Qt.callLater(function() {
      input.text = ""
      input.forceActiveFocus()
    })
  }

  function close() {
    root.opened = false
  }

  // ── Dependencies ──────────────────────────────────────────────────────────

  // Probe every declared binary, one Process reused sequentially, driven by
  // CalcModel.DEPENDENCIES so the probe list and the notice/install list can
  // never drift apart. The probe is `test -x` on the absolute path with a
  // constructed environment, so it neither resolves through PATH nor inherits
  // one. Exit code is locale-independent, unlike a translated "not found"
  // message, so we never parse output. A dependency reads as "missing" only
  // once its probe says so; until then it stays "checking" and the notice
  // stays hidden.
  function checkDependencies() {
    var next = {}
    for (var i = 0; i < CalcModel.DEPENDENCIES.length; i++) {
      next[CalcModel.DEPENDENCIES[i].bin] = "checking"
    }
    root.dependencyStates = next
    root.probeIndex = 0
    root.runProbe()
  }

  function runProbe() {
    if (root.probeIndex >= CalcModel.DEPENDENCIES.length) return
    var dep = CalcModel.DEPENDENCIES[root.probeIndex]
    probeProc.probeBin = dep.bin
    probeProc.command = [root.testBin, "-x", dep.path]
    probeProc.running = false
    probeProc.running = true
  }

  function setDependencyState(bin, available) {
    var next = {}
    for (var key in root.dependencyStates) next[key] = root.dependencyStates[key]
    next[bin] = available ? "available" : "missing"
    root.dependencyStates = next
  }

  // Install every missing provider package in one floating terminal, via the
  // absolute Omarchy launcher (never a PATH lookup). The launcher detaches
  // (setsid), so its Process exits before pacman finishes; the re-probe here is
  // best-effort, and the reliable pickup is the recheck in open() once the user
  // summons the overlay again.
  function installDependencies() {
    if (root.installingDependencies) return
    var cmd = CalcModel.installCommand(root.missingDeps)
    if (!cmd) return
    if (!root.omarchyPath) return
    root.installingDependencies = true
    installProc.command = [root.omarchyPath + "/bin/omarchy-launch-floating-terminal-with-presentation", cmd]
    installProc.running = true
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "icyleaf.qalculator")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // ── History persistence ───────────────────────────────────────────────────
  //
  // Reads and writes go through `Process`, not `FileView`. FileView follows a
  // symlink planted at the path, blocks the whole shell process on a FIFO, and
  // has no size ceiling; a descriptor-bound child avoids all three. Both
  // helpers work on a path passed as an argument and data passed on stdin, and
  // the script text is a constant — no value from QML is ever spliced into it.

  function loadHistory(raw) {
    root.history = CalcModel.parseHistory(raw)
  }

  function readHistory() {
    historyReadProc.buffer = ""
    historyReadProc.overflow = false
    historyReadProc.command = [
      "/usr/bin/dd", "if=" + root.historyPath,
      "iflag=nofollow,nonblock,count_bytes,fullblock",
      "bs=1", "count=" + (root.historyBytesMax + 1), "status=none"
    ]
    historyReadProc.running = true
  }

  // A reader that fails is "no history yet", never "delete what is there". A
  // missing file (rc != 0) leaves the list empty, and an oversized file is
  // dropped rather than parsed, because a truncated document is not a valid one.
  function historyLoaded(code) {
    root.loadHistory(code === 0 && !historyReadProc.overflow ? historyReadProc.buffer : "[]")
    historyReadProc.buffer = ""
    if (!root.historyMigrated) root.migrateLegacyHistory()
  }

  function saveHistory() {
    historyWriteProc.payload = CalcModel.serializeHistory(root.history)
    historyWriteProc.command = [
      "/usr/bin/sh", "-c",
      // umask first so mktemp creates 0600; refuse a symlinked directory;
      // repair the directory and drop non-regular entries it may contain;
      // write through a fresh same-directory temporary and rename over the
      // destination so a planted symlink is replaced, never followed.
      'umask 077; dir="$1"; dest="$2"; ' +
      'if [ -L "$dir" ] || { [ -e "$dir" ] && [ ! -d "$dir" ]; }; then exit 1; fi; ' +
      'mkdir -p -m 700 -- "$dir" || exit 1; ' +
      'if [ -L "$dir" ] || [ ! -d "$dir" ]; then exit 1; fi; ' +
      'chmod 700 -- "$dir" 2>/dev/null || exit 1; ' +
      'find "$dir" -mindepth 1 -maxdepth 1 ! -type f -exec rm -rf -- {} + 2>/dev/null; ' +
      't=$(mktemp -p "$dir" .history.XXXXXXXXXX) || exit 1; ' +
      'trap \'rm -f -- "$t"\' EXIT HUP INT TERM; ' +
      'cat > "$t" || exit 1; ' +
      'mv -f -T -- "$t" "$dest" || exit 1',
      "qalculator-history-write", root.stateDir, root.historyPath
    ]
    historyWriteProc.running = true
  }

  // One-time carry-over from the old flat file. The legacy file is removed only
  // after the new write reports success, so a failed write cannot lose the only
  // copy: if anything fails the old file is simply left in place.
  function migrateLegacyHistory() {
    root.historyMigrated = true
    legacyReadProc.buffer = ""
    legacyReadProc.overflow = false
    legacyReadProc.command = [
      "/usr/bin/dd", "if=" + root.legacyHistoryPath,
      "iflag=nofollow,nonblock,count_bytes,fullblock",
      "bs=1", "count=" + (root.historyBytesMax + 1), "status=none"
    ]
    legacyReadProc.running = true
  }

  function legacyHistoryLoaded(code) {
    var raw = legacyReadProc.buffer
    legacyReadProc.buffer = ""
    if (code !== 0 || legacyReadProc.overflow) return
    var entries = CalcModel.parseHistory(raw)
    if (entries.length === 0) return
    // A history that already exists at the new location wins; the stale legacy
    // file is not worth carrying over.
    if (root.history.length > 0) return
    root.history = entries
    root.pendingLegacyRemoval = true
    root.saveHistory()
  }

  function removeLegacyHistory() {
    if (!root.pendingLegacyRemoval) return
    root.pendingLegacyRemoval = false
    legacyRemoveProc.command = ["/usr/bin/rm", "-f", "--", root.legacyHistoryPath]
    legacyRemoveProc.running = true
  }

  function recordHistory(expr, value) {
    root.history = CalcModel.addHistoryEntry(root.history, { expression: expr, result: value }, root.historyLimit)
    root.saveHistory()
  }

  // ── Evaluation ────────────────────────────────────────────────────────────

  function scheduleEvaluation() {
    root.copied = false
    if (root.expression.trim() === "") {
      root.result = ""
      root.resultVisible = false
      evalTimer.stop()
      return
    }
    evalTimer.restart()
  }

  function applyOutput(output) {
    if (!CalcModel.isEvaluable(root.expression, output)) {
      root.resultVisible = false
      return
    }
    var value = CalcModel.cleanResult(output)
    if (!CalcModel.withinLength(value, CalcModel.RESULT_MAX)) {
      root.resultVisible = false
      return
    }
    root.result = value
    root.resultVisible = true
  }

  function copyResult(value) {
    if (!value) return
    // No wl-copy means no clipboard. Do not claim success: the notice already
    // tells the user what is missing.
    if (!CalcModel.dependencyAvailable(root.dependencyStates, "wl-copy")) return
    var wlCopy = CalcModel.dependencyPath("wl-copy")
    if (!wlCopy) return
    // argv form, not stdin: wl-copy exits once it has forked the owner, while
    // piping keeps this Process alive for as long as the selection lives. The
    // `--` keeps a result that starts with `-` from being read as an option.
    clipProc.command = [wlCopy, "--type", "text/plain", "--", String(value)]
    clipProc.running = true
    root.copied = true
    copiedReset.restart()
  }

  // Enter: copy and close. Alt+Enter: copy and stay open. While browsing, Enter
  // copies the highlighted entry's stored result; otherwise it commits the
  // current expression. History is written on this commit rather than on every
  // debounce tick, so partial keystrokes (`2`, then `2+`) never make it to disk.
  function accept(keepOpen) {
    var value = ""
    if (root.browsedEntry) {
      value = root.browsedEntry.result
    } else if (root.expression.trim() !== "" && root.resultVisible) {
      value = root.result
      root.recordHistory(root.expression.trim(), value)
    }
    if (!value) return
    root.copyResult(value)
    if (!keepOpen) root.dismiss()
    else {
      root.exitHistoryBrowsing()
      Qt.callLater(function() { input.forceActiveFocus() })
    }
  }

  // Walk the history newest-first. `step` is +1 to move to the next older entry
  // (↓, matching the list focus moving down the rows) and -1 to move back toward
  // the newest (↑). The first ↓ from the neutral state selects row 0 (the newest
  // entry); walking back past row 0 clears the input and returns to typing.
  function moveHistory(step) {
    if (root.history.length === 0 || root.helpVisible) return
    if (!root.browsingHistory && !root.inputEmpty) return
    var from = root.browsingHistory ? root.historyIndex : -1
    var next = CalcModel.nextHistoryIndex(from, step, root.history.length)
    if (next === from) return
    if (next === -1) {
      root.exitHistoryBrowsing()
      return
    }
    root.browsingHistory = true
    root.historyIndex = next
    // Reflect the browsed expression in the input box without triggering the
    // "user typed something" path. The stored result, not a re-evaluation, is
    // what the answer area shows (see shownResult).
    root.syncingInput = true
    input.text = root.history[next].expression
    root.syncingInput = false
    root.expression = root.history[next].expression
    root.resultVisible = false
    evalTimer.stop()
  }

  // Leave the browse mode and hand the overlay back to typing.
  function exitHistoryBrowsing() {
    root.browsingHistory = false
    root.historyIndex = -1
    root.syncingInput = true
    input.text = ""
    root.syncingInput = false
    root.expression = ""
    root.result = ""
    root.resultVisible = false
  }

  // Ctrl+/ swaps the history area between the history list and the help
  // reference. Help only makes sense with an empty input, so opening it leaves
  // the browse mode first.
  function toggleHelp() {
    if (!root.inputEmpty && !root.browsingHistory) return
    if (!root.helpVisible) root.exitHistoryBrowsing()
    root.helpVisible = !root.helpVisible
    root.historyIndex = -1
  }

  // Ctrl+1..Ctrl+9 and Ctrl+0 copy the nth history row (tenth for 0) and close,
  // mirroring Enter on a highlighted row. Rows past ten have no shortcut.
  function acceptHistoryRow(index) {
    if (!root.showHistory || index < 0 || index >= root.history.length) return
    root.copyResult(root.history[index].result)
    root.dismiss()
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Component.onCompleted: {
    root.checkDependencies()
    root.readHistory()
  }

  // Reader: `dd` with O_NOFOLLOW|O_NONBLOCK, capped at historyBytesMax + 1 so an
  // oversized file is detected rather than truncated. Output is byte-counted in
  // the parser, not collected whole.
  Process {
    id: historyReadProc
    command: []
    property string buffer: ""
    property bool overflow: false
    clearEnvironment: true
    environment: ({ "PATH": "/usr/bin:/bin", "LC_ALL": "C" })
    onStarted: historyReadTimeout.restart()
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        if (historyReadProc.overflow) return
        historyReadProc.buffer += chunk
        // .length is UTF-16 units; the authoritative byte cap is dd's count.
        if (historyReadProc.buffer.length > root.historyBytesMax) historyReadProc.overflow = true
      }
    }
    onExited: function(code) {
      historyReadTimeout.stop()
      root.historyLoaded(code)
    }
  }

  // Writer: the whole script is a constant; the directory and destination are
  // positional parameters and the document arrives on stdin, so no value is
  // ever interpolated into shell text.
  Process {
    id: historyWriteProc
    command: []
    property string payload: ""
    stdinEnabled: true
    clearEnvironment: true
    environment: ({ "PATH": "/usr/bin:/bin", "LC_ALL": "C" })
    onStarted: {
      historyWriteTimeout.restart()
      historyWriteProc.write(historyWriteProc.payload)
      historyWriteProc.payload = ""
      // Quickshell does not close a child's stdin on its own; without this the
      // writer waits for EOF forever.
      historyWriteProc.stdinEnabled = false
    }
    onExited: function(code) {
      historyWriteTimeout.stop()
      // Deferred legacy cleanup waits for this confirmation: the old file is
      // only unlinked once the new one is on disk.
      if (code === 0) root.removeLegacyHistory()
    }
  }

  Process {
    id: legacyReadProc
    command: []
    property string buffer: ""
    property bool overflow: false
    clearEnvironment: true
    environment: ({ "PATH": "/usr/bin:/bin", "LC_ALL": "C" })
    onStarted: legacyReadTimeout.restart()
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        if (legacyReadProc.overflow) return
        legacyReadProc.buffer += chunk
        if (legacyReadProc.buffer.length > root.historyBytesMax) legacyReadProc.overflow = true
      }
    }
    onExited: function(code) {
      legacyReadTimeout.stop()
      root.legacyHistoryLoaded(code)
    }
  }

  Process {
    id: legacyRemoveProc
    command: []
    clearEnvironment: true
    environment: ({ "PATH": "/usr/bin:/bin" })
  }

  Process {
    id: probeProc
    property string probeBin: ""
    command: []
    clearEnvironment: true
    environment: root.probeEnvironment
    onStarted: probeTimeout.restart()
    onExited: function(code) {
      probeTimeout.stop()
      root.setDependencyState(probeBin, code === 0)
      root.probeIndex = root.probeIndex + 1
      root.runProbe()
    }
  }

  // A probe that never answers must not leave a child behind for the life of
  // the shell. The test is trivial, so the deadline is short.
  Timer {
    id: probeTimeout
    interval: root.probeTimeoutMs
    repeat: false
    onTriggered: if (probeProc.running) probeProc.signal(9)
  }

  // The history reader and writer are local file operations; a hung one means
  // something is wrong (a stuck FIFO, an unwritable mount) and must be cleared.
  Timer {
    id: historyReadTimeout
    interval: root.historyTimeoutMs
    repeat: false
    onTriggered: {
      if (!historyReadProc.running) return
      historyReadProc.signal(15)
      historyReadProc.buffer = ""
      root.historyLoaded(-1)
    }
  }
  Timer {
    id: historyWriteTimeout
    interval: root.historyTimeoutMs
    repeat: false
    onTriggered: if (historyWriteProc.running) historyWriteProc.signal(15)
  }
  Timer {
    id: legacyReadTimeout
    interval: root.historyTimeoutMs
    repeat: false
    onTriggered: {
      if (!legacyReadProc.running) return
      legacyReadProc.signal(15)
      legacyReadProc.buffer = ""
      root.legacyHistoryLoaded(-1)
    }
  }

  Process {
    id: installProc
    command: []
    // The Omarchy launcher is a user-session tool: it spawns the terminal
    // emulator and needs the inherited session environment (DBus, Wayland,
    // PATH for the rest of Omarchy). The executable is addressed by absolute
    // path and every package name is validated in CalcModel, so neither the
    // command nor its arguments come from untrusted data.
    onExited: function(code) {
      // The floating terminal is detached, so this fires almost immediately and
      // is not proof the install landed. Keep the click from being re-entrant
      // and let open()/recheck confirm later.
      root.installingDependencies = false
      root.checkDependencies()
    }
  }

  Process {
    id: evalProc
    command: []
    clearEnvironment: true
    environment: root.qalcEnvironment
    // SplitParser, not StdioCollector: a collector retains the whole stream
    // before any check runs. Here each chunk is counted as it arrives and the
    // child is signalled on overflow, so a pathological expression cannot grow
    // the shared shell process without bound.
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        if (root.evalOverflow) return
        root.evalBuffer += chunk
        // .length counts UTF-16 units; this is defense in depth on top of the
        // model-level result cap.
        if (root.evalBuffer.length > root.outputLimit) {
          root.evalOverflow = true
          root.evalBuffer = ""
          evalProc.signal(15)
          evalKillTimer.start()
        }
      }
    }
    onExited: function(code, status) {
      evalTimeout.stop()
      evalKillTimer.stop()
      if (!root.evalOverflow && code === 0) root.applyOutput(root.evalBuffer)
      else if (code !== 0) root.resultVisible = false
      root.evalBuffer = ""
      root.evalOverflow = false
    }
  }

  // Escalation if the child ignores TERM; kept alive past the leader's exit so a
  // stuck descendant is still reached.
  Timer {
    id: evalKillTimer
    interval: root.killGraceMs
    repeat: false
    onTriggered: if (evalProc.running) evalProc.signal(9)
  }

  // Absolute deadline for one evaluation. qalc answers in milliseconds; five
  // seconds is already pathological.
  Timer {
    id: evalTimeout
    interval: root.evalTimeoutMs
    repeat: false
    onTriggered: {
      if (!evalProc.running) return
      root.resultVisible = false
      evalProc.signal(15)
      evalKillTimer.start()
    }
  }

  Process {
    id: clipProc
    command: []
    clearEnvironment: true
    environment: root.clipboardEnvironment
  }

  Timer {
    id: evalTimer
    interval: root.debounceMs
    repeat: false
    onTriggered: {
      if (!CalcModel.dependencyAvailable(root.dependencyStates, "qalc")) return
      if (root.expression.trim() === "") return
      var qalc = CalcModel.dependencyPath("qalc")
      if (!qalc) return
      // Replacing the buffer before start discards any late chunk from a
      // superseded run: a stale answer must never overwrite a newer one.
      root.evalBuffer = ""
      root.evalOverflow = false
      evalProc.command = [qalc, "-t", "--", root.expression]
      evalProc.running = true
      evalTimeout.restart()
    }
  }

  Timer {
    id: copiedReset
    interval: 1200
    repeat: false
    onTriggered: root.copied = false
  }

  // Teardown: nothing this plugin started may outlive it. Signals reach the
  // direct child only, which is why every command here is a plain argv with no
  // shell wrapper to orphan anyone.
  Component.onDestruction: {
    if (probeProc.running) probeProc.signal(15)
    if (evalProc.running) evalProc.signal(15)
    if (clipProc.running) clipProc.signal(15)
    if (installProc.running) installProc.signal(15)
    if (historyReadProc.running) historyReadProc.signal(15)
    if (historyWriteProc.running) historyWriteProc.signal(15)
    if (legacyReadProc.running) legacyReadProc.signal(15)
    if (legacyRemoveProc.running) legacyRemoveProc.signal(15)
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "icyleaf-qalculator"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Item {
          width: parent.width
          height: root.inputHeight

          TextField {
            id: input
            anchors.fill: parent
            foreground: root.foreground
            accent: Color.accent
            font.pixelSize: Style.font.title
            placeholderText: "Type an expression…"
            // Bound the ingress at the widget itself; CalcModel re-checks the
            // same cap before anything is stored or rendered.
            maximumLength: root.expressionLimit
            onTextChanged: {
              // A programmatic fill while browsing is not user typing: keep the
              // browse state and do not re-evaluate.
              if (root.syncingInput) return
              // A paste can carry control characters; drop them at the widget so
              // nothing invisible ever reaches the model or the history file.
              var cleaned = CalcModel.sanitizeText(text)
              if (cleaned !== text) {
                input.text = cleaned
                return
              }
              // Editing the box by hand ends history browsing and returns to a
              // live evaluation of whatever is now typed.
              if (root.browsingHistory) {
                root.browsingHistory = false
                root.historyIndex = -1
              }
              if (root.expression !== text) {
                root.expression = text
                root.scheduleEvaluation()
              }
            }

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.dismiss()
                event.accepted = true
              } else if (event.key === Qt.Key_Slash && (event.modifiers & Qt.ControlModifier)) {
                root.toggleHelp()
                event.accepted = true
              } else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_0 || (event.key >= Qt.Key_1 && event.key <= Qt.Key_9))) {
                root.acceptHistoryRow(CalcModel.historyIndexForKey(event.key))
                event.accepted = true
              } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                root.moveHistory(CalcModel.historyStepForKey(event.key))
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.accept(Boolean(event.modifiers & Qt.AltModifier))
                event.accepted = true
              }
            }
          }

          Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.controlPaddingX
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(parent.width * 0.5, implicitWidth)
            visible: root.shownResultVisible
            text: root.copied ? "Copied" : root.shownResult
            // A qalc answer is data, not markup: never let Qt sniff it as rich
            // text, which would turn a crafted expression into an <img> fetch.
            textFormat: Text.PlainText
            color: root.copied ? Color.accent : root.selectedText
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
          }
        }

        Rectangle {
          width: parent.width
          height: root.noticeHeight
          visible: root.depsMissing
          radius: Style.cornerRadius
          color: root.installingDependencies ? root.selectedBackground : "transparent"

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: Style.spacing.sm
            rightPadding: Style.spacing.sm
            text: root.installingDependencies ? "Installing in a floating terminal…" : root.dependencyNotice
            textFormat: Text.PlainText
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }

          MouseArea {
            anchors.fill: parent
            enabled: !root.installingDependencies
            cursorShape: Qt.PointingHandCursor
            onClicked: root.installDependencies()
          }
        }

        Flickable {
          width: parent.width
          height: Math.min(root.helpHeight, root.maxSectionHeight)
          visible: root.showHelp
          contentWidth: width
          contentHeight: root.helpHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            width: parent.width
            spacing: 0

            Repeater {
              model: root.helpSections

              Column {
                required property var modelData
                width: parent.width
                spacing: 0

                Text {
                  width: parent.width
                  height: root.helpLineHeight
                  text: modelData.title
                  textFormat: Text.PlainText
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.weight: Font.DemiBold
                  verticalAlignment: Text.AlignVCenter
                }

                Repeater {
                  model: modelData.rows

                  Item {
                    required property var modelData
                    width: parent.width
                    height: root.helpLineHeight

                    Text {
                      id: syntaxText
                      anchors.left: parent.left
                      anchors.leftMargin: Style.spacing.rowPaddingX
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.syntax
                      textFormat: Text.PlainText
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }

                    Text {
                      anchors.left: syntaxText.right
                      anchors.leftMargin: Style.spacing.lg
                      anchors.right: parent.right
                      anchors.rightMargin: Style.spacing.rowPaddingX
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.note
                      textFormat: Text.PlainText
                      color: root.foreground
                      opacity: 0.55
                      horizontalAlignment: Text.AlignRight
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                    }
                  }
                }
              }
            }
          }
        }

        ListView {
          width: parent.width
          height: root.historyHeight
          visible: root.showHistory
          clip: true
          model: root.history
          spacing: Style.spacing.xs
          currentIndex: root.historyIndex
          boundsBehavior: Flickable.StopAtBounds
          // Keyboard browsing must keep the selected row on screen when the
          // history is longer than the visible area.
          onCurrentIndexChanged: {
            if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
          }

          delegate: Rectangle {
            required property int index
            required property var modelData
            width: ListView.view.width
            height: root.rowHeight
            radius: root.cornerRadius
            color: index === root.historyIndex ? root.selectedBackground : "transparent"

            readonly property bool hasShortcut: index < 10

            Rectangle {
              id: shortcutBadge
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter
              width: root.shortcutSlotWidth
              height: shortcutLabel.implicitHeight + Style.spacing.xxs * 2
              radius: Style.space(3)
              color: root.selectedBackground
              visible: parent.hasShortcut

              Text {
                id: shortcutLabel
                anchors.centerIn: parent
                text: CalcModel.historyShortcutLabel(index)
                textFormat: Text.PlainText
                color: root.foreground
                opacity: 0.65
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.weight: Font.Bold
              }
            }

            Text {
              anchors.left: parent.left
              // Fixed slot for every row, badge or not, so expressions line up.
              anchors.leftMargin: Style.spacing.sm + root.shortcutSlotWidth + Style.spacing.sm
              anchors.right: resultLabel.left
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.expression
              textFormat: Text.PlainText
              color: index === root.historyIndex ? root.selectedText : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Text {
              id: resultLabel
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.rowPaddingX
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(parent.width * 0.5, implicitWidth)
              text: modelData.result
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.85
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignRight
              elide: Text.ElideRight
            }

            MouseArea {
              anchors.fill: parent
              onClicked: root.copyResult(modelData.result)
            }
          }
        }

        Text {
          width: parent.width
          height: root.hintHeight
          visible: root.showHint
          text: root.depsMissing ? "" : "Ctrl+/ for help  ·  try  2+2  ·  10 usd to gbp"
          textFormat: Text.PlainText
          color: root.foreground
          opacity: 0.58
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
        }
      }
    }
  }
}
