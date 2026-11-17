#!/bin/bash
# The pr skill is adapted from mattpocock/skills (MIT). The licence asks every copy to keep the copyright
# and permission notice, so this checks the notice and the source are still named where they should be.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_DIR="$ROOT/skills/pr"
PASS=0; FAIL=0
eq() {
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — expected [$2] got [$3]"; fi
}
yn() { if "$@"; then echo yes; else echo no; fi; }
has() { yn command grep -qF -- "$2" "$1"; }

C="$SKILL_DIR/CREDITS.md"
eq "CREDITS.md exists" yes "$(yn test -f "$C")"
eq "CREDITS.md names the upstream repository" yes "$(has "$C" 'mattpocock/skills')"
eq "CREDITS.md names the upstream file" yes "$(has "$C" 'skills/engineering/pr/SKILL.md')"
eq "CREDITS.md keeps the copyright line" yes "$(has "$C" 'Copyright (c) 2026 Matt Pocock')"
eq "CREDITS.md keeps the permission notice" yes "$(has "$C" 'Permission is hereby granted, free of charge')"
eq "CREDITS.md keeps the notice's own condition" yes "$(has "$C" 'shall be included in all')"
eq "CREDITS.md still credits the Summary visuals" yes "$(has "$C" 'Dex Horthy')"

for f in "$SKILL_DIR/SKILL.md" "$SKILL_DIR/SKILL.en.md" "$ROOT/README.md" "$ROOT/README.zh-TW.md"; do
  name="${f#"$ROOT"/}"
  eq "$name names the upstream repository" yes "$(has "$f" 'mattpocock/skills')"
  eq "$name names the licence" yes "$(has "$f" 'MIT')"
done

# ---- summary ----
MIN=15
if [ "$((PASS + FAIL))" -lt "$MIN" ]; then
  echo "FAIL: ran $((PASS + FAIL)) assertions, expected at least $MIN"; FAIL=$((FAIL+1))
fi
echo "credits: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
