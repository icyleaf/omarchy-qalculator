import QtQuick 2.15
import QtTest 1.3
import "../CalcModel.js" as CalcModel

TestCase {
  id: root
  name: "CalcModel"

  // ── parseHistory ─────────────────────────────────────────────────────────
  function test_parseHistoryRejectsBadJson() {
    compare(CalcModel.parseHistory("").length, 0)
    compare(CalcModel.parseHistory("not json").length, 0)
    compare(CalcModel.parseHistory("{}").length, 0)
    compare(CalcModel.parseHistory("null").length, 0)
  }

  function test_parseHistoryKeepsValidEntries() {
    var raw = JSON.stringify([
      { expression: "2+2", result: "4" },
      { expression: "", result: "4" },
      { expression: "1/0", result: "" },
      { expression: "1 usd in eur", result: "€0.87" }
    ])
    var entries = CalcModel.parseHistory(raw)
    compare(entries.length, 2)
    compare(entries[0].expression, "2+2")
    compare(entries[1].expression, "1 usd in eur")
  }

  function test_parseHistoryAcceptsLegacyExprKey() {
    var entries = CalcModel.parseHistory(JSON.stringify([{ expr: "3*3", result: "9" }]))
    compare(entries.length, 1)
    compare(entries[0].expression, "3*3")
  }

  // ── addHistoryEntry ──────────────────────────────────────────────────────
  function test_addHistoryEntryPrependsAndCaps() {
    var entries = []
    for (var i = 0; i < 60; i++) entries = CalcModel.addHistoryEntry(entries, { expression: "e" + i, result: String(i) }, 50)
    compare(entries.length, 50)
    compare(entries[0].expression, "e59")
    compare(entries[49].expression, "e10")
  }

  function test_addHistoryEntryDeduplicatesByExpression() {
    var entries = CalcModel.addHistoryEntry([], { expression: "2+2", result: "4" })
    entries = CalcModel.addHistoryEntry(entries, { expression: "3+3", result: "6" })
    entries = CalcModel.addHistoryEntry(entries, { expression: "2+2", result: "4" })
    compare(entries.length, 2)
    compare(entries[0].expression, "2+2")
    compare(entries[1].expression, "3+3")
  }

  function test_addHistoryEntryRejectsEmpty() {
    var entries = CalcModel.addHistoryEntry([], { expression: "2+2", result: "" })
    compare(entries.length, 0)
    entries = CalcModel.addHistoryEntry([], { expression: "", result: "4" })
    compare(entries.length, 0)
  }

  function test_serializeHistoryRoundTrips() {
    var entries = CalcModel.addHistoryEntry([], { expression: "2+2", result: "4" })
    var parsed = CalcModel.parseHistory(CalcModel.serializeHistory(entries))
    compare(parsed.length, 1)
    compare(parsed[0].expression, "2+2")
    compare(parsed[0].result, "4")
  }

  // ── isEvaluable ──────────────────────────────────────────────────────────
  function test_isEvaluableAcceptsRealAnswers() {
    compare(CalcModel.isEvaluable("2+2", "4"), true)
    compare(CalcModel.isEvaluable("29 inches to cm", "73.66 cm"), true)
    compare(CalcModel.isEvaluable("sqrt(625)", "25"), true)
    compare(CalcModel.isEvaluable("2^10", "1024"), true)
  }

  function test_isEvaluableRejectsPartialEcho() {
    // qalc -t "1 +" prints "1"; showing that would be a lie.
    compare(CalcModel.isEvaluable("1 +", "1"), false)
    compare(CalcModel.isEvaluable("2+", "2"), false)
  }

  function test_isEvaluableRejectsOutputEqualInput() {
    compare(CalcModel.isEvaluable("2+2", "2+2"), false)
  }

  function test_isEvaluableRejectsEmpty() {
    compare(CalcModel.isEvaluable("", "4"), false)
    compare(CalcModel.isEvaluable("   ", "4"), false)
    compare(CalcModel.isEvaluable("2+2", ""), false)
  }

  function test_isEvaluableRejectsPromptAndUnknown() {
    compare(CalcModel.isEvaluable("2+2", "> "), false)
    compare(CalcModel.isEvaluable("2+2", "Unrecognized option."), false)
  }

  function test_cleanResultStripsPromptAndEquals() {
    compare(CalcModel.cleanResult("= 4"), "4")
    compare(CalcModel.cleanResult("4\n> "), "4")
    compare(CalcModel.cleanResult("73.66 cm"), "73.66 cm")
  }

  // ── Help ─────────────────────────────────────────────────────────────────
  function test_helpSectionsAreWellFormed() {
    var sections = CalcModel.helpSections()
    verify(sections.length > 0)
    for (var i = 0; i < sections.length; i++) {
      verify(sections[i].title.length > 0)
      verify(sections[i].rows.length > 0)
      for (var j = 0; j < sections[i].rows.length; j++) {
        verify(sections[i].rows[j].syntax.length > 0)
        verify(sections[i].rows[j].note.length > 0)
      }
    }
  }

  function test_helpRowCountMatchesSections() {
    var sections = CalcModel.helpSections()
    var expected = 0
    for (var i = 0; i < sections.length; i++) expected += sections[i].rows.length + 1
    compare(CalcModel.helpRowCount(), expected)
  }

  function test_helpNeverTeachesTheInKeyword() {
    // `in` is the inch unit in qalc; only `to` converts.
    var sections = CalcModel.helpSections()
    for (var i = 0; i < sections.length; i++) {
      for (var j = 0; j < sections[i].rows.length; j++) {
        var syntax = sections[i].rows[j].syntax.toLowerCase()
        verify(syntax.indexOf(" in ") === -1)
      }
    }
  }

  // ── History shortcuts ────────────────────────────────────────────────────
  function test_historyIndexForDigitKeys() {
    compare(CalcModel.historyIndexForKey(Qt.Key_1), 0)
    compare(CalcModel.historyIndexForKey(Qt.Key_5), 4)
    compare(CalcModel.historyIndexForKey(Qt.Key_9), 8)
  }

  function test_historyIndexForZeroIsTenth() {
    compare(CalcModel.historyIndexForKey(Qt.Key_0), 9)
  }

  function test_historyIndexIgnoresOtherKeys() {
    compare(CalcModel.historyIndexForKey(Qt.Key_Slash), -1)
    compare(CalcModel.historyIndexForKey(Qt.Key_Up), -1)
    compare(CalcModel.historyIndexForKey(Qt.Key_Escape), -1)
  }

  function test_historyShortcutLabelFirstNine() {
    compare(CalcModel.historyShortcutLabel(0), "⌃1")
    compare(CalcModel.historyShortcutLabel(4), "⌃5")
    compare(CalcModel.historyShortcutLabel(8), "⌃9")
  }

  function test_historyShortcutLabelTenthIsZero() {
    compare(CalcModel.historyShortcutLabel(9), "⌃0")
  }

  function test_historyShortcutLabelPastTenthIsEmpty() {
    compare(CalcModel.historyShortcutLabel(10), "")
    compare(CalcModel.historyShortcutLabel(-1), "")
  }

  function test_historyShortcutLabelMatchesKeyMapping() {
    // The badge on row N must name the key that actually copies row N.
    compare(CalcModel.historyIndexForKey(Qt.Key_1), 0)
    compare(CalcModel.historyShortcutLabel(0), "⌃1")
    compare(CalcModel.historyIndexForKey(Qt.Key_0), 9)
    compare(CalcModel.historyShortcutLabel(9), "⌃0")
  }

  // ── Dependencies ─────────────────────────────────────────────────────────

  function test_dependenciesAreWellFormed() {
    var deps = CalcModel.DEPENDENCIES
    verify(deps.length > 0)
    for (var i = 0; i < deps.length; i++) {
      verify(deps[i].bin.length > 0)
      verify(deps[i].pkg.length > 0)
      verify(deps[i].feature.length > 0)
    }
  }

  function test_missingDependenciesOnlyCountsMissing() {
    var states = { "qalc": "available", "wl-copy": "missing" }
    var missing = CalcModel.missingDependencies(states)
    compare(missing.length, 1)
    compare(missing[0].bin, "wl-copy")
  }

  function test_missingDependenciesIgnoresChecking() {
    // A probe still in flight must not flash the notice.
    var states = { "qalc": "checking", "wl-copy": "checking" }
    compare(CalcModel.missingDependencies(states).length, 0)
  }

  function test_missingDependenciesHandlesEmptyAndNull() {
    compare(CalcModel.missingDependencies({}).length, 0)
    compare(CalcModel.missingDependencies(null).length, 0)
  }

  function test_dependencyAvailableIsExact() {
    var states = { "qalc": "available", "wl-copy": "missing" }
    compare(CalcModel.dependencyAvailable(states, "qalc"), true)
    compare(CalcModel.dependencyAvailable(states, "wl-copy"), false)
    compare(CalcModel.dependencyAvailable(states, "nope"), false)
    compare(CalcModel.dependencyAvailable(null, "qalc"), false)
  }

  function test_missingPackagesMapsAndDeduplicates() {
    var missing = [
      { bin: "qalc", pkg: "libqalculate" },
      { bin: "qalc", pkg: "libqalculate" },
      { bin: "wl-copy", pkg: "wl-clipboard" }
    ]
    var pkgs = CalcModel.missingPackages(missing)
    compare(pkgs.length, 2)
    compare(pkgs[0], "libqalculate")
    compare(pkgs[1], "wl-clipboard")
    compare(CalcModel.missingPackages([]).length, 0)
    compare(CalcModel.missingPackages(null).length, 0)
  }

  function test_installCommandListsPackages() {
    var missing = [
      { bin: "qalc", pkg: "libqalculate" },
      { bin: "wl-copy", pkg: "wl-clipboard" }
    ]
    compare(CalcModel.installCommand(missing), "omarchy pkg add libqalculate wl-clipboard")
    compare(CalcModel.installCommand([]), "")
    compare(CalcModel.installCommand(null), "")
  }

  function test_dependencyNoticeNamesBinsAndPackages() {
    var missing = [
      { bin: "qalc", pkg: "libqalculate" },
      { bin: "wl-copy", pkg: "wl-clipboard" }
    ]
    var notice = CalcModel.dependencyNotice(missing)
    verify(notice.indexOf("qalc (libqalculate)") !== -1)
    verify(notice.indexOf("wl-copy (wl-clipboard)") !== -1)
    compare(CalcModel.dependencyNotice([]), "")
    compare(CalcModel.dependencyNotice(null), "")
  }
}
