#!/bin/bash
# Structural checks on the skill's own documents: the description stays under the limit, every reference
# document SKILL.md points at exists, and DESIGN-RED-FLAGS.md keeps its shape and its attribution.
# 用法:bash plugins/openspec-superpowers-workflow/tests/skill-docs.test.sh   (SKILL_DIR=<路徑> 測副本)
# 消費者:提交前手跑 + CI(.github/workflows/validate.yml 列舉 plugins/*/tests/*.test.sh)
# 這些只守結構(長度、檔案存在、標題數、出處);Phase 2 規則是否被遵守靠 eval,不靠這裡的字串比對
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR=${SKILL_DIR:-"$SCRIPT_DIR/../skills/openspec-superpowers-workflow"}
command -v node >/dev/null 2>&1 || { echo "skill-docs.test: node is required"; exit 1; }
PASS=0; FAIL=0

# eq <名稱> <期望> <實際>
eq() {
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — expected [$2] got [$3]"; fi
}
yn() { if "$@"; then echo yes; else echo no; fi; }

# ---- description:Claude Code 對 skill description 有 1536 字上限 ----
desc_len=$(node -e '
  const t = require("fs").readFileSync(process.argv[1], "utf8");
  const m = t.match(/^description:\s*"((?:[^"\\]|\\.)*)"\s*$/m);
  console.log(m ? JSON.parse("\"" + m[1] + "\"").length : -1);
' "$SKILL_DIR/SKILL.md" 2>/dev/null)
eq "description parsed from the front matter" yes "$(yn test "${desc_len:--1}" -gt 100)"
eq "description within 1536 chars" yes "$(yn test "${desc_len:-9999}" -le 1536 -a "${desc_len:--1}" -gt 0)"

# ---- SKILL.md 提到的參考文件都存在(大寫連字號檔名與 phases.md 是 skill 自己的文件,小寫的是 change 的產物) ----
refs=$(node -e '
  const t = require("fs").readFileSync(process.argv[1], "utf8");
  const body = t.replace(/^---[\s\S]*?\n---\n/, "");
  const names = new Set();
  for (const m of body.matchAll(/`((?:[A-Z][A-Z0-9]*-)+[A-Z0-9]+\.md|phases\.md)`/g)) names.add(m[1]);
  console.log([...names].sort().join("\n"));
' "$SKILL_DIR/SKILL.md" 2>/dev/null)
eq "SKILL.md names at least five reference documents" yes "$(yn test "$(printf '%s\n' "$refs" | command grep -c .)" -ge 5)"
while IFS= read -r name; do
  [ -n "$name" ] || continue
  eq "reference $name exists" yes "$(yn test -f "$SKILL_DIR/$name")"
done <<< "$refs"
eq "DESIGN-RED-FLAGS.md is among the references" yes "$(yn command grep -qx 'DESIGN-RED-FLAGS.md' <<< "$refs")"

# ---- DESIGN-RED-FLAGS.md:八條紅旗、每條徵兆/自問/處置、出處與授權 ----
F="$SKILL_DIR/DESIGN-RED-FLAGS.md"
eq "red flags file exists" yes "$(yn test -f "$F")"
eq "red flags file has exactly eight flag headings" 8 "$(command grep -c '^## ' "$F" 2>/dev/null)"
eq "each flag has a symptom line" 8 "$(command grep -c '^- 徵兆：' "$F" 2>/dev/null)"
eq "each flag has a question line" 8 "$(command grep -c '^- 自問：' "$F" 2>/dev/null)"
eq "each flag has an action line" 8 "$(command grep -c '^- 處置：' "$F" 2>/dev/null)"
eq "attribution names the source" yes "$(yn command grep -q 'cursor/plugins' "$F" 2>/dev/null)"
eq "attribution names the license" yes "$(yn command grep -q 'MIT' "$F" 2>/dev/null)"

# ---- phases.md:提到的 validator 都存在;確認點以 gate-check 的 exit code 轉換,舊的硬停措辭不再出現 ----
PH="$SKILL_DIR/phases.md"
cjs=$(perl -ne 'print "$1\n" while /validators\/([a-z-]+\.cjs)/g' "$PH" 2>/dev/null | sort -u)
eq "phases.md names at least three validators" yes "$(yn test "$(printf '%s\n' "$cjs" | command grep -c .)" -ge 3)"
while IFS= read -r name; do
  [ -n "$name" ] || continue
  eq "validator $name named in phases.md exists" yes "$(yn test -f "$SKILL_DIR/validators/$name")"
done <<< "$cjs"
eq "phases.md runs gate-check p1" yes "$(yn command grep -qF 'gate-check.cjs p1' "$PH")"
eq "phases.md runs gate-check p2" yes "$(yn command grep -qF 'gate-check.cjs p2' "$PH")"
eq "phases.md no longer hard-stops every Phase 1" no "$(yn command grep -qF 'Do NOT proceed to Phase 2 until user explicitly approves' "$PH")"

# ---- summary ----
MIN=24
if [ "$((PASS + FAIL))" -lt "$MIN" ]; then
  echo "FAIL: ran $((PASS + FAIL)) assertions, expected at least $MIN"; FAIL=$((FAIL+1))
fi
echo "skill-docs: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
