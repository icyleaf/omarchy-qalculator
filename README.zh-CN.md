# Omarchy Qalculator

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![QML](https://img.shields.io/badge/QML-Qt6-41cd52.svg)](https://www.qt.io/)
[![Omarchy](https://img.shields.io/badge/Omarchy-Plugin-8b5cf6.svg)](https://github.com/omarchy)
[![Language: English](https://img.shields.io/badge/Language-English-blue.svg)](README.md)

> 专为 Wayland & Hyprland 上的 **Omarchy Shell** 打造的 Raycast 式极速计算器覆盖层——按下快捷键，输入表达式，答案实时浮现，<kbd>Enter</kbd> 复制即走。

`omarchy-qalculator`（`icyleaf.qalculator`）将久经考验的 [`qalc`](https://qalculate.github.io/) 引擎封装进一个专注的覆盖层：四则运算、乘方、函数、单位换算与货币汇率，全部离线完成，汇率取自 qalc 的本地缓存。无窗口管理负担，无自带常驻进程，无需另行启动应用——只需一个键盘优先的界面，在当前显示器上打开，用完后立刻消失。

![preview](preview.png)

---

## 为什么选择 Qalculator？

多数桌面计算器要么是需要寻找并关闭的完整应用，要么是留在 Shell 历史里的终端命令。Qalculator 两者皆非。

| 评估维度     | omarchy-qalculator              | GNOME 计算器      | 终端里的原生 `qalc`         |
| :----------- | :------------------------------ | :---------------- | :-------------------------- |
| **唤起方式** | 全局快捷键，原地覆盖层          | 应用启动器 + 窗口 | 开终端、输入、读取、关闭    |
| **即时反馈** | 边输入边出结果（150ms 防抖）    | 点击 / 小键盘驱动 | 提交后再读取                |
| **历史记录** | 持久化、去重、一键重新复制      | 会话内历史面板    | Shell 滚动缓冲              |
| **计算引擎** | 原生 `qalc`——单位、货币、函数   | 自研 GPL 引擎     | 原生 `qalc`                 |
| **资源占用** | 单个 QML 覆盖层，自身无常驻进程 | 完整 GTK 应用     | 每次调用都启动完整 `qalc`   |
| **复制行为** | <kbd>Enter</kbd> 复制并关闭     | 手动选中并复制    | 手动选中并复制              |
| **依赖处理** | 启动时探测，缺失可一键安装      | 随应用捆绑        | 需自行保证 `qalc` 在 `PATH` |

### 设计目标

- **一键得答案。** 覆盖层打开即聚焦，边输入边计算，<kbd>Enter</kbd> 复制。没有任何多余的东西分散注意力。
- **输出可信。** qalc 的交互模式会回显未完成的输入（`1 +` 会回答 `1`）。Qalculator 的求值门控会过滤这类回显，避免你误复制半截表达式。
- **不静默失败。** 外部工具（`qalc`、`wl-copy`）在启动时探测；缺失时卡片会直接点名，并提供一键安装，而不是悄无声息地失效。

---

## 功能特性

- **实时求值** — 答案随输入即时出现（150ms 防抖）。求值门控会拒绝以运算符结尾的表达式以及「输出等于输入」的回显。
- **完整的 qalc 能力** — 四则运算、乘方、函数、常量、单位换算与货币（`2+2`、`sqrt(625)`、`29 inches to cm`、`10 usd to gbp`）。全程离线，汇率取自 qalc 缓存。
- **回车即复制** — <kbd>Enter</kbd> 复制答案并关闭；<kbd>Alt</kbd>+<kbd>Enter</kbd> 复制后保持打开，继续下一次计算。
- **持久化历史** — 保留最近 50 条成功表达式，新的在前。重复计算同一表达式会把它移到顶部而非产生重复项。
- **内置帮助** — <kbd>Ctrl</kbd>+<kbd>/</kbd> 将历史区域切换为语法速查（数学、百分比、换算、货币、按键），再按一次切回。
- **聚焦显示器覆盖层** — 在当前输出上铺满的 `PanelWindow`，与 emoji、剪贴板覆盖层风格一致。
- **依赖缺失提示** — 每个外部工具在加载时探测一次；缺失时会显示可点击的提示项并完成安装。

---

## 键盘快捷键

| 快捷键                                                                       | 说明                                   |
| :--------------------------------------------------------------------------- | :------------------------------------- |
| <kbd>SUPER</kbd> + <kbd>=</kbd>                                              | 切换覆盖层显隐                         |
| <kbd>Enter</kbd>                                                             | 复制答案并关闭                         |
| <kbd>Alt</kbd> + <kbd>Enter</kbd>                                            | 复制答案并保持打开                     |
| <kbd>↑</kbd> / <kbd>↓</kbd>                                                  | 浏览历史（输入为空时）                 |
| <kbd>Ctrl</kbd> + <kbd>1</kbd>…<kbd>9</kbd> / <kbd>Ctrl</kbd> + <kbd>0</kbd> | 复制历史第 1–10 条并关闭（输入为空时） |
| <kbd>Ctrl</kbd> + <kbd>/</kbd>                                               | 切换语法帮助（输入为空时）             |
| <kbd>Esc</kbd>                                                               | 关闭                                   |

换算请使用 qalc 的 `to` 关键字（`10 usd to gbp`、`29 inches to cm`）。qalc 会把 `in` 识别为英寸单位，因此 `10 usd in gbp` **不是**换算——帮助里只列 `to` 的示例。

---

## 前置依赖

请确保系统中具备以下工具：

- **计算引擎**：`qalc`（Arch：`libqalculate` 包）位于 `PATH`。货币换算使用 qalc 的缓存汇率，本插件不发起任何网络请求。
- **Wayland 剪贴板工具**：`wl-copy`（属于 `wl-clipboard` 包），用于复制操作。

两者在加载时各探测一次。若任一缺失，覆盖层会显示一条提示，点名缺失的二进制及其所属包；点击后会在浮动终端中执行 `omarchy pkg add libqalculate wl-clipboard`，终端关闭后重新探测。其余功能不受影响：缺少 `qalc` 仅禁用实时求值，缺少 `wl-copy` 仅禁用复制（不会出现虚假的“已复制”提示）。

---

## 安装与配置

1. **通过 Omarchy CLI 安装插件**：

```bash
omarchy plugin add https://github.com/icyleaf/omarchy-qalculator.git --enable
```

2. **绑定全局快捷键**（`~/.config/hypr/bindings.lua`）：

`SUPER + =` 实际以 `code:21` 传递（不带 Shift 的 `=` 键），而 Omarchy 对该键的默认绑定是平铺动作 “Shrink window left”。需先解绑，再绑定覆盖层：

```lua
-- ~/.config/hypr/bindings.lua
hl.unbind("SUPER + code:21")

o.bind("SUPER + code:21", "Qalculator", "omarchy-shell shell toggle icyleaf.qalculator '{}'")
```

该键位的 Shift / Alt / Ctrl 缩放变体可保持原样。

---

## 更新与卸载

- **更新插件**：

```bash
omarchy plugin update icyleaf.qalculator
```

- **卸载插件**：

```bash
omarchy plugin remove icyleaf.qalculator
```

---

## 架构说明

| 文件            | 职责                                                                         |
| :-------------- | :--------------------------------------------------------------------------- |
| `manifest.json` | `kinds: ["overlay"]`、`activation: "on-demand"`、`keepLoaded: true`。        |
| `Overlay.qml`   | 覆盖层本体：输入框、实时答案、历史列表、qalc 进程、剪贴板进程、依赖探测。    |
| `CalcModel.js`  | 纯 JS 接缝层：历史解析 / 去重 / 截断、结果清洗、求值门控，以及帮助速查数据。 |
| `tests/`        | 覆盖 `CalcModel.js` 的 QML 测试套件。                                        |

历史记录保存在 `~/.local/state/omarchy/qalculator-history.json`，仅在提交时原子写入——半截的按键输入不会落盘。

### 测试

```bash
cd tests
qmltestrunner -input tst_calcmodel.qml
```

---

## 贡献指南

欢迎任何形式的贡献。请将纯逻辑保留在 `CalcModel.js` 中以便测试覆盖，并让 QML 层保持轻薄：

1. **从 `main` 拉出分支**，使用 `<type>/<short-description>` 命名（如 `feat/`、`fix/`、`chore/`、`refactor/`）。
2. **本地验证** — 提交前先跑通上方的测试套件。
3. **约定式提交** — 使用清晰的提交信息（如 `feat(overlay): ...`、`fix(history): ...`）。
4. **提交 PR** 到 `main` 分支。

---

## 致谢

`omarchy-qalculator` 建立在开源社区的肩膀之上：

- **[Qalculate! (`libqalculate`)](https://github.com/Qalculate/libqalculate)**：计算引擎——单位、货币、函数与常量全部由 `qalc` 完成。

---

## 许可证

本项目基于 [MIT License](LICENSE) 开源。
