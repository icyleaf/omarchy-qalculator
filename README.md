# Omarchy Qalculator

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![QML](https://img.shields.io/badge/QML-Qt6-41cd52.svg)](https://www.qt.io/)
[![Omarchy](https://img.shields.io/badge/Omarchy-Plugin-8b5cf6.svg)](https://github.com/omarchy)
[![Language: 中文](https://img.shields.io/badge/Language-简体中文-green.svg)](README.zh-CN.md)

> A Raycast-style quick calculator overlay for **Omarchy Shell** on Hyprland — press the hotkey, type an expression, watch the answer appear live, press <kbd>Enter</kbd> to copy it and get out of the way.

`omarchy-qalculator` (`icyleaf.qalculator`) wraps the battle-tested [`qalc`](https://qalculate.github.io/) engine in a single, focused overlay: arithmetic, powers, functions, unit conversion and currency, all evaluated offline against qalc's cached rates. No window to manage, no daemon of its own, no separate app to launch — just a keyboard-first surface that opens on the focused monitor and disappears the moment you are done.

![preview](preview.png)

---

## Why Qalculator?

Most desktop calculators are either a full app you have to find and close, or a terminal invocation that lives in your shell history. Qalculator is neither.

| Dimension               | omarchy-qalculator                              | GNOME Calculator      | Raw `qalc` in a terminal         |
| :---------------------- | :---------------------------------------------- | :-------------------- | :------------------------------- |
| **Invocation**          | Global hotkey, in-place overlay                 | App launcher + window | Open terminal, type, read, close |
| **Feedback**            | Live answer as you type (150 ms debounce)       | Click / keypad driven | Submit, then read                |
| **History**             | Persistent, deduplicated, one key to re-copy    | Session history panel | Shell scrollback                 |
| **Engine**              | Native `qalc` — units, currencies, functions    | Custom GPL engine     | Native `qalc`                    |
| **Footprint**           | One QML overlay, no resident process of its own | Full GTK app          | Full `qalc` binary on every call |
| **Copy behaviour**      | <kbd>Enter</kbd> copies and closes              | Manual select & copy  | Manual select & copy             |
| **Dependency handling** | Probed at startup, one-click install if missing | Bundled               | `qalc` must be on `PATH`         |

### Design goals

- **One keystroke to an answer.** The overlay opens focused, evaluates as you type, and copies on <kbd>Enter</kbd>. Nothing else competes for your attention.
- **Truthful output.** qalc's interactive mode echoes partial input (`1 +` answers `1`). Qalculator's evaluation gate suppresses those echoes, so you never copy a half-finished expression by mistake.
- **No silent failure.** External tools (`qalc`, `wl-copy`) are probed at startup; the card names what is missing and offers a one-click install instead of failing quietly.

---

## Features

- **Live evaluation** — the answer appears as you type (150 ms debounce). The evaluation gate rejects trailing operators and output-equals-input echoes.
- **Full qalc reach** — arithmetic, powers, functions, constants, unit conversion and currency (`2+2`, `sqrt(625)`, `29 inches to cm`, `10 usd to gbp`). Offline; qalc uses its cached exchange rates.
- **Copy on Enter** — <kbd>Enter</kbd> copies the answer and closes. <kbd>Alt</kbd>+<kbd>Enter</kbd> copies and keeps the overlay open for the next calculation.
- **Persistent history** — the last 50 successful expressions, newest first. Re-computing an expression moves it to the top instead of duplicating it.
- **Built-in help** — <kbd>Ctrl</kbd>+<kbd>/</kbd> swaps the history area for a syntax reference (math, percent, conversions, currency, keys), and swaps back.
- **Focused-monitor overlay** — a fullscreen `PanelWindow` on the focused output, matching the emojis and clipboard overlays.
- **Missing dependencies?** — each external tool is probed once at load; a missing one shows a clickable notice that installs it.

---

## Keyboard Shortcuts

| Shortcut                                                                     | Description                                   |
| :--------------------------------------------------------------------------- | :-------------------------------------------- |
| <kbd>SUPER</kbd> + <kbd>=</kbd>                                              | Toggle the overlay                            |
| <kbd>Enter</kbd>                                                             | Copy the answer and close                     |
| <kbd>Alt</kbd> + <kbd>Enter</kbd>                                            | Copy the answer and stay open                 |
| <kbd>↑</kbd> / <kbd>↓</kbd>                                                  | Browse history (empty input)                  |
| <kbd>Ctrl</kbd> + <kbd>1</kbd>…<kbd>9</kbd> / <kbd>Ctrl</kbd> + <kbd>0</kbd> | Copy history row 1–10 and close (empty input) |
| <kbd>Ctrl</kbd> + <kbd>/</kbd>                                               | Toggle the syntax help (empty input)          |
| <kbd>Esc</kbd>                                                               | Close                                         |

Conversions use qalc's `to` keyword (`10 usd to gbp`, `29 inches to cm`). qalc reads `in` as the inch unit, so `10 usd in gbp` is **not** a conversion — the help lists `to` examples only.

---

## Prerequisites

Ensure the following tools are available on your system:

- **Calculator engine**: `qalc` (Arch: the `libqalculate` package) on `PATH`. Currency conversion uses qalc's cached rates; no network call is made by this plugin.
- **Wayland clipboard tooling**: `wl-copy` (part of `wl-clipboard`) for the copy action.

Both are checked once at load. If either is missing, the overlay shows a notice naming the binary and its package; clicking it runs `omarchy pkg add libqalculate wl-clipboard` in a floating terminal and re-probes once that terminal closes. Everything else keeps working: a missing `qalc` disables live evaluation, a missing `wl-copy` disables copy (no false "Copied" confirmation).

---

## Installation & Setup

1. **Install Plugin via Omarchy CLI**:

```bash
omarchy plugin add https://github.com/icyleaf/omarchy-qalculator.git --enable
```

2. **Bind Global Hotkey** (in `~/.config/hypr/bindings.lua`):

`SUPER + =` is delivered as `code:21` (the `=` key without Shift), and Omarchy's default bind for that key is the tiling action "Shrink window left". Unbind it first, then bind the overlay:

```lua
-- ~/.config/hypr/bindings.lua
hl.unbind("SUPER + code:21")

o.bind("SUPER + code:21", "Qalculator", "omarchy-shell shell toggle icyleaf.qalculator '{}'")
```

The Shift/Alt/Ctrl resize variants of that key can be left intact.

---

## Update & Uninstall

- **Update Plugin**:

```bash
omarchy plugin update icyleaf.qalculator
```

- **Uninstall Plugin**:

```bash
omarchy plugin remove icyleaf.qalculator
```

---

## Architecture

| File            | Role                                                                                                                |
| :-------------- | :------------------------------------------------------------------------------------------------------------------ |
| `manifest.json` | `kinds: ["overlay"]`, `activation: "on-demand"`, `keepLoaded: true`.                                                |
| `Overlay.qml`   | The overlay: input, live answer, history list, qalc process, clipboard process, dependency probe.                   |
| `CalcModel.js`  | The pure-JS seam: history parsing/dedup/capping, result cleaning, the evaluation gate, and the help reference data. |
| `tests/`        | QML test suite covering `CalcModel.js`.                                                                             |

History is stored at `~/.local/state/omarchy/qalculator-history.json`, written atomically on commit only — partial keystrokes never reach disk.

### Tests

```bash
cd tests
qmltestrunner -input tst_calcmodel.qml
```

---

## Contributing

Contributions are welcome. Keep the pure logic in `CalcModel.js` where it is covered by tests, and keep the QML layer thin:

1. **Branch off `main`**, using a `<type>/<short-description>` name (e.g. `feat/`, `fix/`, `chore/`, `refactor/`).
2. **Verify locally** — run the test suite above before committing.
3. **Conventional Commits** — write clear commit messages (e.g. `feat(overlay): ...`, `fix(history): ...`).
4. **Submit a PR** against `main`.

---

## Credits

`omarchy-qalculator` stands on the shoulders of the open-source community:

- **[Qalculate! (`libqalculate`)](https://github.com/Qalculate/libqalculate)**: The calculation engine — units, currencies, functions and constants, all done by `qalc`.

---

## License

This project is open-sourced under the [MIT License](LICENSE).
