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

  // ── History browsing (↓/↑) ───────────────────────────────────────────────

  function test_historyStepForKeyMapsDownToOlder() {
    // ↓ moves down the list, i.e. toward older entries; ↑ walks back.
    compare(CalcModel.historyStepForKey(Qt.Key_Down), 1)
    compare(CalcModel.historyStepForKey(Qt.Key_Up), -1)
  }

  function test_historyStepForKeyIgnoresOtherKeys() {
    compare(CalcModel.historyStepForKey(Qt.Key_Return), 0)
    compare(CalcModel.historyStepForKey(Qt.Key_Escape), 0)
    compare(CalcModel.historyStepForKey(Qt.Key_Slash), 0)
  }

  function test_nextHistoryIndexFirstDownSelectsNewest() {
    // From the neutral -1, one ↓ lands on row 0 (the newest entry).
    compare(CalcModel.nextHistoryIndex(-1, 1, 5), 0)
  }

  function test_nextHistoryIndexDownWalksTowardOlder() {
    compare(CalcModel.nextHistoryIndex(0, 1, 5), 1)
    compare(CalcModel.nextHistoryIndex(3, 1, 5), 4)
  }

  function test_nextHistoryIndexStopsAtOldest() {
    compare(CalcModel.nextHistoryIndex(4, 1, 5), 4)
  }

  function test_nextHistoryIndexUpReturnsToNewestThenLeaves() {
    compare(CalcModel.nextHistoryIndex(2, -1, 5), 1)
    compare(CalcModel.nextHistoryIndex(0, -1, 5), -1)
    // Already neutral: ↑ stays neutral.
    compare(CalcModel.nextHistoryIndex(-1, -1, 5), -1)
  }

  function test_nextHistoryIndexEmptyHistoryIsNeutral() {
    compare(CalcModel.nextHistoryIndex(-1, 1, 0), -1)
    compare(CalcModel.nextHistoryIndex(0, -1, 0), -1)
  }

  function test_nextHistoryIndexClampsOutOfRangeCurrent() {
    // A stale index outside the list is treated as neutral, so ↓ starts at the
    // newest row rather than at a bogus position.
    compare(CalcModel.nextHistoryIndex(99, 1, 3), 0)
    compare(CalcModel.nextHistoryIndex(-5, 1, 3), 0)
    compare(CalcModel.nextHistoryIndex(99, -1, 3), -1)
  }

  function test_nextHistoryIndexFullDownThenFullUp() {
    var count = 3
    var i = -1
    i = CalcModel.nextHistoryIndex(i, 1, count); compare(i, 0)
    i = CalcModel.nextHistoryIndex(i, 1, count); compare(i, 1)
    i = CalcModel.nextHistoryIndex(i, 1, count); compare(i, 2)
    i = CalcModel.nextHistoryIndex(i, 1, count); compare(i, 2) // clamp
    i = CalcModel.nextHistoryIndex(i, -1, count); compare(i, 1)
    i = CalcModel.nextHistoryIndex(i, -1, count); compare(i, 0)
    i = CalcModel.nextHistoryIndex(i, -1, count); compare(i, -1) // leave
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

  // ── Text hygiene ─────────────────────────────────────────────────────────

  function test_sanitizeStripsControlChars() {
    compare(CalcModel.sanitizeText("4\u0000"), "4")
    compare(CalcModel.sanitizeText("a\u001bb"), "ab")
    compare(CalcModel.sanitizeText("x\u202Ey"), "xy")
  }

  function test_sanitizeKeepsVisibleUnicode() {
    // qalc legitimately answers with these; they must survive the filter.
    compare(CalcModel.sanitizeText("73.66 cm"), "73.66 cm")
    compare(CalcModel.sanitizeText("−2"), "−2")
    compare(CalcModel.sanitizeText("√2"), "√2")
    compare(CalcModel.sanitizeText("≈1.414"), "≈1.414")
  }

  function test_cleanResultStripsControlChars() {
    compare(CalcModel.cleanResult("4\u0007"), "4")
    compare(CalcModel.cleanResult("\u202E4"), "4")
  }

  function test_parseHistoryRejectsOversizedFields() {
    var filler = ""
    for (var i = 0; i < CalcModel.EXPRESSION_MAX + 1; i++) filler += "x"
    var raw = JSON.stringify([{ expression: filler, result: "1" }])
    compare(CalcModel.parseHistory(raw).length, 0)
  }

  function test_parseHistoryStripsControlCharsFromEntries() {
    var raw = JSON.stringify([{ expression: "2+2\u0000", result: "4\u202E" }])
    var entries = CalcModel.parseHistory(raw)
    compare(entries.length, 1)
    compare(entries[0].expression, "2+2")
    compare(entries[0].result, "4")
  }

  function test_parseHistoryStopsAtLimit() {
    var many = []
    for (var i = 0; i < CalcModel.HISTORY_LIMIT * 3; i++) many.push({ expression: "e" + i, result: "1" })
    compare(CalcModel.parseHistory(JSON.stringify(many)).length, CalcModel.HISTORY_LIMIT)
  }

  function test_missingPackagesRejectsNonPackageNames() {
    var missing = [{ bin: "qalc", pkg: "libqalculate; rm -rf /" }]
    compare(CalcModel.missingPackages(missing).length, 0)
  }

  function test_dependencyPathIsAbsoluteAndKnown() {
    compare(CalcModel.dependencyPath("qalc"), "/usr/bin/qalc")
    compare(CalcModel.dependencyPath("wl-copy"), "/usr/bin/wl-copy")
    compare(CalcModel.dependencyPath("nope"), "")
  }

  // ── State paths ──────────────────────────────────────────────────────────

  function test_stateDirUsesXdgWhenSet() {
    compare(CalcModel.stateDir("/home/u", "/xdg/state"), "/xdg/state/omarchy/qalculator")
  }

  function test_stateDirFallsBackToXdgSpecDefault() {
    // No /tmp fallback: an unset XDG_STATE_HOME means $HOME/.local/state.
    compare(CalcModel.stateDir("/home/u", ""), "/home/u/.local/state/omarchy/qalculator")
    compare(CalcModel.stateDir("/home/u", undefined), "/home/u/.local/state/omarchy/qalculator")
  }

  function test_historyFileSitsInsideStateDir() {
    compare(CalcModel.historyFile("/s/omarchy/qalculator"), "/s/omarchy/qalculator/history.json")
  }

  function test_legacyHistoryFileIsTheOldFlatPath() {
    compare(CalcModel.legacyHistoryFile("/home/u", ""), "/home/u/.local/state/omarchy/qalculator-history.json")
    compare(CalcModel.legacyHistoryFile("/home/u", "/xdg"), "/xdg/omarchy/qalculator-history.json")
  }

  function test_newPathNeverCollidesWithLegacyPath() {
    var dir = CalcModel.stateDir("/home/u", "")
    verify(CalcModel.historyFile(dir) !== CalcModel.legacyHistoryFile("/home/u", ""))
  }

  function test_historyBytesMaxIsAPositiveInt() {
    verify(CalcModel.HISTORY_BYTES_MAX > 0)
    verify(CalcModel.HISTORY_BYTES_MAX === Math.floor(CalcModel.HISTORY_BYTES_MAX))
  }

  // ── Overlay layout ───────────────────────────────────────────────────────
  //
  // A fixture with generous room, so the cap is not the binding constraint
  // unless a test deliberately shrinks it.
  function layoutFixture(overrides) {
    var base = {
      panelHeight: 1000,
      gapsOut: 10,
      contentTopInset: 8,
      contentBottomInset: 8,
      inputHeight: 40,
      contentSpacing: 10,
      noticeBlock: 0,
      desiredLowerHeight: 200
    }
    if (overrides) for (var key in overrides) base[key] = overrides[key]
    return base
  }

  function test_layoutCentresTheInputOnThePanel() {
    // The input's centre must land on the panel's centre whenever the panel is
    // tall enough to centre it without running off the top.
    var fixtures = [layoutFixture(), layoutFixture({ panelHeight: 1200 }), layoutFixture({ inputHeight: 60 })]
    for (var i = 0; i < fixtures.length; i++) {
      var result = CalcModel.overlayLayout(fixtures[i])
      var inputCentre = result.cardTop + fixtures[i].contentTopInset + fixtures[i].inputHeight / 2
      fuzzyCompare(inputCentre, fixtures[i].panelHeight / 2, 0.0001)
    }
  }

  function test_layoutCapReachesTheBottomGap() {
    // The lower area's maximum is exactly the room left before the card's outer
    // bottom would reach the bottom gap.
    var result = CalcModel.overlayLayout(layoutFixture())
    var fixture = layoutFixture()
    var fixedBlock = fixture.contentTopInset + fixture.inputHeight + fixture.contentSpacing
      + fixture.noticeBlock + fixture.contentBottomInset
    fuzzyCompare(result.cardTop + fixedBlock + result.lowerMaxHeight, fixture.panelHeight - fixture.gapsOut, 0.0001)
  }

  function test_layoutKeepsDesiredLowerWhenItFits() {
    var result = CalcModel.overlayLayout(layoutFixture({ desiredLowerHeight: 200 }))
    fuzzyCompare(result.lowerHeight, 200, 0.0001)
  }

  function test_layoutCapsLowerWhenDesiredIsTaller() {
    var result = CalcModel.overlayLayout(layoutFixture({ desiredLowerHeight: 10000 }))
    fuzzyCompare(result.lowerHeight, result.lowerMaxHeight, 0.0001)
  }

  function test_layoutCardHoldsTheLowerAreaAtItsBottom() {
    // The card's bottom edge sits one content inset below the lower area, so
    // the lower area is exactly `lowerHeight` tall at the bottom of the card.
    var result = CalcModel.overlayLayout(layoutFixture())
    var fixture = layoutFixture()
    var lowerTop = result.cardTop + fixture.contentTopInset + fixture.inputHeight
      + fixture.contentSpacing + fixture.noticeBlock
    fuzzyCompare(lowerTop + result.lowerHeight + fixture.contentBottomInset, result.cardTop + result.cardHeight, 0.0001)
  }

  function test_layoutCardNeverLeavesThePanel() {
    var inputs = [
      layoutFixture(),
      layoutFixture({ desiredLowerHeight: 10000 }),
      layoutFixture({ panelHeight: 300 }),
      layoutFixture({ panelHeight: 130 }),
      layoutFixture({ panelHeight: 60 }),
      layoutFixture({ noticeBlock: 30, desiredLowerHeight: 500 })
    ]
    for (var i = 0; i < inputs.length; i++) {
      var result = CalcModel.overlayLayout(inputs[i])
      verify(result.cardTop >= inputs[i].gapsOut - 0.0001)
      verify(result.cardTop + result.cardHeight <= inputs[i].panelHeight - inputs[i].gapsOut + 0.0001)
    }
  }

  function test_layoutNoticeBlockReducesTheLowerRoom() {
    var without = CalcModel.overlayLayout(layoutFixture({ noticeBlock: 0 }))
    var withNotice = CalcModel.overlayLayout(layoutFixture({ noticeBlock: 30 }))
    fuzzyCompare(withNotice.lowerMaxHeight, without.lowerMaxHeight - 30, 0.0001)
  }

  function test_layoutEmptyLowerReservesOnlyTheFixedBlock() {
    var result = CalcModel.overlayLayout(layoutFixture({ desiredLowerHeight: 0 }))
    fuzzyCompare(result.lowerHeight, 0, 0.0001)
    fuzzyCompare(result.cardHeight, 66, 0.0001)
  }

  function test_layoutClampsCardTopToTheTopGap() {
    // A panel shorter than the input cannot centre it without running off the
    // top; the card anchors at the top gap instead.
    var result = CalcModel.overlayLayout(layoutFixture({ panelHeight: 60 }))
    fuzzyCompare(result.cardTop, 10, 0.0001)
  }

  function test_layoutShortPanelHasNoNegativeLowerRoom() {
    var result = CalcModel.overlayLayout(layoutFixture({ panelHeight: 60 }))
    verify(result.lowerMaxHeight >= 0)
    verify(result.lowerHeight >= 0)
  }

  function test_layoutTallerPanelGivesMoreLowerRoom() {
    var smaller = CalcModel.overlayLayout(layoutFixture({ panelHeight: 800 }))
    var taller = CalcModel.overlayLayout(layoutFixture({ panelHeight: 1200 }))
    verify(taller.lowerMaxHeight > smaller.lowerMaxHeight)
  }

  function test_layoutIgnoresMissingInput() {
    var result = CalcModel.overlayLayout(null)
    verify(result !== null)
    verify(result.cardTop >= 0)
    verify(result.lowerMaxHeight >= 0)
    verify(result.lowerHeight >= 0)
    verify(result.cardHeight >= 0)
  }
}
