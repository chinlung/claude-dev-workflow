#!/bin/bash
# reconcile-check.cjs fixture 測試（snapshot／check／verify 與 R1–R9）
# 用法:bash plugins/openspec-superpowers-workflow/tests/reconcile-check.test.sh   (CHECK=<路徑> 測副本)
# 消費者:提交前手跑 + CI(.github/workflows/validate.yml 列舉 plugins/*/tests/*.test.sh)
# 只有全部通過、且實際跑到的斷言數達下限才 exit 0——下限在案例清單之外計算，提早結束的清單不會讀成綠
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V="$SCRIPT_DIR/../skills/openspec-superpowers-workflow/validators"
CHECK=${CHECK:-"$V/reconcile-check.cjs"}
VALIDATOR="$V/validate-openspec-workflow.cjs"
FIXTURES="$SCRIPT_DIR/fixtures/openspec-workflow"
command -v node >/dev/null 2>&1 || { echo "reconcile-check.test: node is required"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "reconcile-check.test: jq is required"; exit 1; }

TMPBASE="${TMPDIR:-/tmp}"
WORK=$(mktemp -d "${TMPBASE%/}/reconcile-test.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

# eq <名稱> <期望> <實際>
eq() {
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — expected [$2] got [$3]"; fi
}
# status <名稱> <R 編號> <期望 status>（讀 $WORK/out.json）
status() { eq "$1" "$3" "$(jq -r --arg id "$2" '.checks[] | select(.id == $id) | .status' "$WORK/out.json" 2>/dev/null)"; }
# has <名稱> <檔案> <固定字串>
has() {
  if command grep -qF -- "$3" "$2" 2>/dev/null; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — $2 lacks [$3]"; fi
}

# make_change <專案根> <名稱>：建一份完整合法的 change，印出 change 目錄
make_change() {
  local d="$1/openspec/changes/$2"
  mkdir -p "$d/specs/api"
  printf '# Proposal\n\nWhy: invoices need exporting.\n' > "$d/proposal.md"
  printf '# Design\n\nDecision: export runs as a queued job.\n' > "$d/design.md"
  printf '# Tasks\n\n- [x] 1.1 build the export\n' > "$d/tasks.md"
  printf '## ADDED Requirements\n\n### Requirement: Export\nThe system SHALL export invoices as CSV.\n\n#### Scenario: export\n- **WHEN** a user exports\n- **THEN** a CSV is produced\n' > "$d/specs/api/spec.md"
  printf '# Review Notes — %s\n\n## Round 1 - PR Review (2026-11-01, final)\n- [CODE] N - rename a variable\n- [DESIGN] Y - export becomes a queued job\n' "$2" > "$d/review-notes.md"
  printf '%s' "$d"
}
# check <change 目錄>：結果在 $WORK/out.json，exit code 在 $RC
check() { node "$CHECK" check "$1" --json > "$WORK/out.json" 2> "$WORK/err"; RC=$?; }

# ---- cases ----

# 合法 change
P=$WORK/p1; D=$(make_change "$P" foo); check "$D"
eq "valid: check exit 0" 0 "$RC"
eq "valid: result pass" pass "$(jq -r .result "$WORK/out.json" 2>/dev/null)"
eq "valid: verdict written" pass "$(jq -r .verdict.result "$P/.claude/openspec-reconcile.foo.local.json" 2>/dev/null)"
status "valid: R9 always manual" R9 manual
status "valid: R5 warn without snapshot or git" R5 warn

# R1：缺 review-notes
P=$WORK/p2; D=$(make_change "$P" foo); rm "$D/review-notes.md"; check "$D"
eq "R1: missing file exit 1" 1 "$RC"
status "R1: missing file fail" R1 fail

# R2：Requirement 第一段沒有 SHALL／MUST
P=$WORK/p3; D=$(make_change "$P" foo)
printf '### Requirement: Export\nThe system exports invoices.\n' > "$D/specs/api/spec.md"; check "$D"
status "R2: no SHALL fail" R2 fail

# R3：最後一輪有 [CODE] Y → fail
P=$WORK/p4; D=$(make_change "$P" foo); printf -- '- [CODE] Y - fixed already\n' >> "$D/review-notes.md"; check "$D"
status "R3: CODE Y in last round fail" R3 fail

# R3：只有較早輪次違規 → warn，exit 0
P=$WORK/p5; D=$(make_change "$P" foo)
printf '# Review Notes\n\n## Round 1 - PR Review (2026-10-01)\n- [CODE] Y - handled this round\n\n## Round 2 - Security Review (2026-11-01, final)\n- [CODE] N - escape output\n' > "$D/review-notes.md"; check "$D"
status "R3: CODE Y only in earlier round warn" R3 warn
eq "R3: earlier-round violation exit 0" 0 "$RC"

# CRLF：同一份合法 change → exit 0（Review Focus 4）
P=$WORK/p6; D=$(make_change "$P" foo)
for f in "$D"/*.md "$D"/specs/api/spec.md; do perl -pi -e 's/\n/\r\n/' "$f"; done; check "$D"
eq "CRLF: valid change exit 0" 0 "$RC"

# R4：最後一輪沒有 final → fail；沒有任何 Round → warn
P=$WORK/p7; D=$(make_change "$P" foo); perl -pi -e 's/, final//' "$D/review-notes.md"; check "$D"
status "R4: no final fail" R4 fail
P=$WORK/p7b; D=$(make_change "$P" foo)
printf '# Review Notes\n\n## Round 1 - PR Review (2026-10-01, final)\n- [CODE] N - a\n\n## Round 2 - Security Review (2026-11-01)\n- [CODE] N - b\n' > "$D/review-notes.md"; check "$D"
status "R4: final on an earlier round only fail" R4 fail
P=$WORK/p8; D=$(make_change "$P" foo); printf '# Review Notes — foo\n' > "$D/review-notes.md"; check "$D"
status "R4: no rounds warn" R4 warn
eq "R4: no rounds exit 0" 0 "$RC"

# R5：snapshot 之後改 tasks.md → fail；不改 → pass
P=$WORK/p9; D=$(make_change "$P" foo)
node "$CHECK" snapshot "$D" > "$WORK/snap.out" 2>&1
eq "snapshot: prints the state file path" "$P/.claude/openspec-reconcile.foo.local.json" "$(cat "$WORK/snap.out")"
check "$D"; status "R5: unchanged since snapshot pass" R5 pass
printf -- '- [x] 1.2 added during reconcile\n' >> "$D/tasks.md"; check "$D"
status "R5: changed since snapshot fail" R5 fail

# R6：未勾選 task 沒有 skip: → warn；有 skip: → pass
P=$WORK/p10; D=$(make_change "$P" foo); printf -- '- [ ] 1.2 later\n' >> "$D/tasks.md"; check "$D"
status "R6: unchecked task warn" R6 warn
eq "R6: unchecked task exit 0" 0 "$RC"
P=$WORK/p11; D=$(make_change "$P" foo); printf -- '- [ ] 1.2 later skip: 不做，見 follow-ups\n' >> "$D/tasks.md"; check "$D"
status "R6: unchecked task with skip pass" R6 pass

# R7：design 有補丁語言 → warn
P=$WORK/p12; D=$(make_change "$P" foo); printf '原本是同步匯出。\n' >> "$D/design.md"; check "$D"
status "R7: patch language warn" R7 warn
eq "R7: patch language exit 0" 0 "$RC"

# R8：[CONSTITUTION] Y → manual，detail 列出條目
P=$WORK/p13; D=$(make_change "$P" foo); printf -- '- [CONSTITUTION] Y - every export endpoint is rate limited\n' >> "$D/review-notes.md"; check "$D"
status "R8: constitution entry manual" R8 manual
has "R8: detail names the entry" "$WORK/out.json" "rate limited"

# verify：通過後 0；改 design.md 後 1 + stale:design；沒有狀態檔 1 + no-verdict
P=$WORK/p14; D=$(make_change "$P" foo); check "$D"
node "$CHECK" verify "$D" > "$WORK/v.out" 2>&1; eq "verify: fresh verdict exit 0" 0 "$?"
printf 'More.\n' >> "$D/design.md"
node "$CHECK" verify "$D" > "$WORK/v.out" 2>&1; eq "verify: edited design exit 3" 3 "$?"
eq "verify: edited design reason" "stale:design" "$(head -1 "$WORK/v.out")"
P=$WORK/p15; D=$(make_change "$P" foo)
node "$CHECK" verify "$D" > "$WORK/v.out" 2>&1; eq "verify: no state exit 3" 3 "$?"
eq "verify: no state reason" "no-verdict" "$(head -1 "$WORK/v.out")"

# 路徑：上層不是 changes → exit 2
mkdir -p "$WORK/x"; node "$CHECK" check "$WORK/x" > /dev/null 2>&1; eq "path: not under openspec/changes exit 2" 2 "$?"

# 既有 validator：CLI 不變；require 不印 usage、不結束行程
node "$VALIDATOR" "$FIXTURES/valid-change" > /dev/null 2>&1; eq "validator CLI still exit 0" 0 "$?"
out=$(node -e 'const m = require(process.argv[1]); process.stdout.write(typeof m.findSpecFiles)' "$VALIDATOR" 2>&1)
eq "validator require exports findSpecFiles without running main" "function" "$out"

# ---- summary ----
MIN=34
if [ "$((PASS + FAIL))" -lt "$MIN" ]; then
  echo "FAIL: ran $((PASS + FAIL)) assertions, expected at least $MIN"; FAIL=$((FAIL+1))
fi
echo "reconcile-check: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
