#!/usr/bin/env bash
# Pre-submission audit for the QML surface. Mirrors the marketplace review's
# recurring findings so a regression is caught locally instead of in review.
# Run from the plugin root: tests/audit.sh
set -uo pipefail

fail=0

# 1. Every Text-like sink must pin its format. Without textFormat a value that
# came from qalc, the history file or a user keystroke is sniffed as rich text,
# and rich text loads <img src="...">.
if command -v python3 >/dev/null 2>&1; then
  out=$(python3 - <<'EOF'
import re, glob, sys
bad = 0
for f in sorted(glob.glob('**/*.qml', recursive=True)):
    src = open(f, encoding='utf-8').read()
    for m in re.finditer(r'\b(Text|Label|TextEdit|StyledText)\s*\{', src):
        i, depth = m.end(), 1
        while i < len(src) and depth:
            depth += (src[i] == '{') - (src[i] == '}'); i += 1
        if 'textFormat:' not in src[m.end():i]:
            print(f"MISSING textFormat {f}:{src[:m.start()].count(chr(10))+1}")
            bad += 1
sys.exit(1 if bad else 0)
EOF
  ) || fail=1
  [ -n "$out" ] && printf '%s\n' "$out"
else
  # Fallback without python: count sinks against format pins.
  sinks=$(grep -rhoE '\b(Text|Label|TextEdit|StyledText)\s*\{' --include='*.qml' . | wc -l)
  pins=$(grep -rhoE 'textFormat:' --include='*.qml' . | wc -l)
  if [ "$pins" -lt "$sinks" ]; then
    echo "FAIL: $pins textFormat for $sinks Text sinks"
    fail=1
  fi
fi

# 2. No whole-output collectors: they retain a child's full stdout/stderr before
# any length check can run.
if grep -rn --include='*.qml' -E '(^|[^:/])StdioCollector' . | grep -vE ':[0-9]+:\s*//'; then
  echo "FAIL: StdioCollector found; use a byte-counting SplitParser or a bounded helper"
  fail=1
fi

# 3. Every Process that can emit untrusted text must clear the inherited
# environment and resolve its executable by absolute path.
if grep -rn --include='*.qml' -E 'command: \["[a-z]' . | grep -vE ':[0-9]+:\s*//'; then
  echo "FAIL: bare executable name in a command; use an absolute path"
  fail=1
fi

# 4. FileView must never be used as a reader: it follows symlinks and has no cap.
if grep -rn --include='*.qml' -E 'FileView|atomicWrites' . | grep -vE ':[0-9]+:\s*//'; then
  echo "FAIL: FileView usage; reads/writes must be descriptor-bound"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "audit: passed"
fi
exit "$fail"
