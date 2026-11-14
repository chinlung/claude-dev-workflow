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

# R6：每個未勾選 task 都要附「skip: 理由」，沒有 → fail；任何縮排深度與寫法的框都算 task
P=$WORK/p10; D=$(make_change "$P" foo); printf -- '- [ ] 1.2 later\n' >> "$D/tasks.md"; check "$D"
status "R6: unchecked task without skip fail" R6 fail
eq "R6: unchecked task without skip exit 1" 1 "$RC"
# 只認文件教的行尾格式「 — skip: 理由」：破折號（—、–、- 或 --）、空白、skip:。行中隨處出現的 skip: 不算，
# 否則任務本文提到 skip（`a skip: flag`、`noskip:`、`--skip:`）就會被當成已交代
for line in '1.2 later skip: 不做，見 follow-ups' '1.2 add a skip: flag to the CLI' '1.2 noskip: handle it' '1.2 document the --skip: option' '1.2 later —skip: glued to the dash'; do
  P=$WORK/p11-$RANDOM; D=$(make_change "$P" foo); printf -- '- [ ] %s\n' "$line" >> "$D/tasks.md"; check "$D"
  status "R6: [$line] is not a skip reason fail" R6 fail
done
for dash in '—' '–' '-' '--'; do
  P=$WORK/p11-$RANDOM; D=$(make_change "$P" foo); printf -- '- [ ] 1.2 later %s skip: 範圍外\n' "$dash" >> "$D/tasks.md"; check "$D"
  status "R6: dash [$dash] before skip pass" R6 pass
done
P=$WORK/p11b; D=$(make_change "$P" foo); printf -- '- [ ] 1.2 later — skip: 範圍外\n' >> "$D/tasks.md"; check "$D"
status "R6: skip suffix with a reason pass" R6 pass
# 空理由的三種寫法都不算理由：行尾、只有空白、只有標點
P=$WORK/p11c; D=$(make_change "$P" foo); printf -- '- [ ] 1.2 later — skip:\n' >> "$D/tasks.md"; check "$D"
status "R6: skip with nothing after the colon fail" R6 fail
P=$WORK/p11d; D=$(make_change "$P" foo); printf -- '- [ ] 1.2 later — skip:   \n' >> "$D/tasks.md"; check "$D"
status "R6: skip with only blanks fail" R6 fail
P=$WORK/p11e; D=$(make_change "$P" foo); printf -- '- [ ] 1.2 later — skip: ...\n' >> "$D/tasks.md"; check "$D"
status "R6: skip with only punctuation fail" R6 fail
# OpenSpec 把任何深度、任何內容的框都算 task
P=$WORK/p11f; D=$(make_change "$P" foo); printf -- '  - [ ] nested later\n' >> "$D/tasks.md"; check "$D"
status "R6: nested unchecked box fail" R6 fail
P=$WORK/p11g; D=$(make_change "$P" foo); printf -- '- [ ] **Step 2: write the test**\n' >> "$D/tasks.md"; check "$D"
status "R6: bold-step unchecked box fail" R6 fail
P=$WORK/p11h; D=$(make_change "$P" foo); printf '# Tasks\n\nNothing planned.\n' > "$D/tasks.md"; check "$D"
status "R6: no boxes at all warn" R6 warn
eq "R6: no boxes at all exit 0" 0 "$RC"
P=$WORK/p11i; D=$(make_change "$P" foo); check "$D"
status "R6: every box checked pass" R6 pass
P=$WORK/p11j; D=$(make_change "$P" foo); printf -- '- [x] 1.2 done, skip: not needed after all\n' >> "$D/tasks.md"; check "$D"
status "R6: checked line mentioning skip pass" R6 pass
# 理由可以用標點、引號、反引號開頭，冒號後任一處有字母或數字就算；全形冒號也接受（codex r2）
for reason in 'skip: （範圍外）' 'skip: "not required"' 'skip: `docs/x.md` tracks it' 'skip：範圍外'; do
  P=$WORK/p11-$RANDOM; D=$(make_change "$P" foo); printf -- '- [ ] 1.2 later — %s\n' "$reason" >> "$D/tasks.md"; check "$D"
  status "R6: reason [$reason] pass" R6 pass
done
P=$WORK/p11u; D=$(make_change "$P" foo); printf -- '- [ ] 1.2 later — skip：...\n' >> "$D/tasks.md"; check "$D"
status "R6: full-width colon with only punctuation fail" R6 fail

# OpenSpec 的 task 定義（1.16 與 2.0 相同；final review r1）：清單符號 - * + 1. 1) 都算，框內不是 x/X 的都算未完成，連結 bullet 不算
for form in '* [ ] 1.2 b' '+ [ ] 1.2 b' '1. [ ] 1.2 b' '1) [ ] 1.2 b' '- [~] 1.2 deferred' '- [] 1.2 b'; do
  P=$WORK/p11-$RANDOM; D=$(make_change "$P" foo); printf '%s\n' "$form" >> "$D/tasks.md"; check "$D"
  status "R6: unchecked form [$form] fail" R6 fail
done
P=$WORK/p11q; D=$(make_change "$P" foo); printf -- '* [X] 1.2 b\n1. [x] 1.3 c\n' >> "$D/tasks.md"; check "$D"
status "R6: other bullets ticked with x/X pass" R6 pass
P=$WORK/p11r; D=$(make_change "$P" foo); printf -- '- [doc](./doc.md)\n- [WIP](./wip.md)\n- [A](https://example.com)\n- [1][ref]\n' >> "$D/tasks.md"; check "$D"
status "R6: link bullets (multi- and single-char labels) are not tasks pass" R6 pass
P=$WORK/p11s; D=$(make_change "$P" foo); printf -- '- [ ](./still-a-task.md)\n' >> "$D/tasks.md"; check "$D"
status "R6: a whitespace-only box before a link still counts fail" R6 fail
P=$WORK/p11t; D=$(make_change "$P" foo); printf '# Tasks\n\n- [doc](./doc.md)\n- [1](./one)\n' > "$D/tasks.md"; check "$D"
status "R6: only link bullets is no checkbox task warn" R6 warn

# 標準格式範例：每個 Task 一個框
P=$WORK/p11k; D=$(make_change "$P" foo); cp "$FIXTURES/tasks-format/tasks.md" "$D/tasks.md"; check "$D"
status "R6: format sample unticked fail" R6 fail
perl -pi -e 's/\[ \]/[x]/' "$D/tasks.md"; check "$D"
status "R6: format sample ticked pass" R6 pass

# snapshot 先跑 R6：不過就拒絕、不留狀態檔；補勾之後才成功，而且 R5 不把補勾當成 Phase 6 期間的修改
P=$WORK/p11m; D=$(make_change "$P" foo); printf -- '- [ ] 1.2 later\n' >> "$D/tasks.md"
node "$CHECK" snapshot "$D" > "$WORK/snap.out" 2>&1; eq "snapshot: refused while a task has no skip reason" 1 "$?"
eq "snapshot: refusal leaves no state file" absent "$([ -e "$P/.claude/openspec-reconcile.foo.local.json" ] && echo present || echo absent)"
has "snapshot: refusal names the line" "$WORK/snap.out" "1.2 later"
P=$WORK/p11n; D=$(make_change "$P" foo); printf -- '- [ ] 1.2 later — skip:\n' >> "$D/tasks.md"
node "$CHECK" snapshot "$D" > "$WORK/snap.out" 2>&1; eq "snapshot: refused for an empty reason too" 1 "$?"
eq "snapshot: second refusal leaves no state file" absent "$([ -e "$P/.claude/openspec-reconcile.foo.local.json" ] && echo present || echo absent)"
perl -pi -e 's/^- \[ \] 1\.2 later — skip:\n/- [x] 1.2 later\n/' "$D/tasks.md"
node "$CHECK" snapshot "$D" > "$WORK/snap.out" 2>&1; eq "snapshot: succeeds once the task is ticked" 0 "$?"
check "$D"; status "snapshot then check: R5 pass" R5 pass
perl -pi -e 's/^- \[x\] 1\.2 later\n/- [ ] 1.2 later\n/' "$D/tasks.md"; check "$D"
status "snapshot then un-ticking: R5 fail" R5 fail
status "snapshot then un-ticking: R6 fail" R6 fail

# R7：design 有補丁語言 → warn
P=$WORK/p12; D=$(make_change "$P" foo); printf '原本是同步匯出。\n' >> "$D/design.md"; check "$D"
status "R7: patch language warn" R7 warn
eq "R7: patch language exit 0" 0 "$RC"

# R8：[CONSTITUTION] Y → manual，detail 列出條目
P=$WORK/p13; D=$(make_change "$P" foo); printf -- '- [CONSTITUTION] Y - every export endpoint is rate limited\n' >> "$D/review-notes.md"; check "$D"
status "R8: constitution entry manual" R8 manual
has "R8: detail names the entry" "$WORK/out.json" "rate limited"

# verify：verdict 必須是現行規則版本寫的（codex r2：舊規則的 pass 不得在規則升級後繼續放行）
P=$WORK/p13b; D=$(make_change "$P" foo); check "$D"; SF="$P/.claude/openspec-reconcile.foo.local.json"
eq "check records the rules version in the verdict" true "$(jq '.verdict.rules | type == "number"' "$SF")"
jq 'del(.verdict.rules)' "$SF" > "$SF.tmp" && mv "$SF.tmp" "$SF"
node "$CHECK" verify "$D" > "$WORK/v.out" 2>&1; eq "verify: verdict without a rules version exit 3" 3 "$?"
eq "verify: verdict without a rules version reason" "stale:rules" "$(head -1 "$WORK/v.out")"
check "$D"; jq '.verdict.rules = 1' "$SF" > "$SF.tmp" && mv "$SF.tmp" "$SF"
node "$CHECK" verify "$D" > "$WORK/v.out" 2>&1; eq "verify: verdict from an older rules version exit 3" 3 "$?"
eq "verify: verdict from an older rules version reason" "stale:rules" "$(head -1 "$WORK/v.out")"
# a pass recorded when any skip: on the line counted (rules 2) is not a pass under the suffix-only rule
check "$D"; jq '.verdict.rules = 2' "$SF" > "$SF.tmp" && mv "$SF.tmp" "$SF"
node "$CHECK" verify "$D" > "$WORK/v.out" 2>&1; eq "verify: verdict from rules 2 exit 3" 3 "$?"

# verify：通過後 0；改 design.md 後 1 + stale:design；沒有狀態檔 1 + no-verdict
P=$WORK/p14; D=$(make_change "$P" foo); check "$D"
node "$CHECK" verify "$D" > "$WORK/v.out" 2>&1; eq "verify: fresh verdict exit 0" 0 "$?"
printf 'More.\n' >> "$D/design.md"
node "$CHECK" verify "$D" > "$WORK/v.out" 2>&1; eq "verify: edited design exit 3" 3 "$?"
eq "verify: edited design reason" "stale:design" "$(head -1 "$WORK/v.out")"
P=$WORK/p15; D=$(make_change "$P" foo)
node "$CHECK" verify "$D" > "$WORK/v.out" 2>&1; eq "verify: no state exit 3" 3 "$?"
eq "verify: no state reason" "no-verdict" "$(head -1 "$WORK/v.out")"

# 狀態檔不跟隨 symlink：寫入換成一般檔，專案外的目標不被覆寫
P=$WORK/p16; D=$(make_change "$P" foo); mkdir -p "$P/.claude" "$WORK/outside"; printf 'keep\n' > "$WORK/outside/victim"
ln -s "$WORK/outside/victim" "$P/.claude/openspec-reconcile.foo.local.json"; check "$D"
eq "state write does not follow a symlink" keep "$(cat "$WORK/outside/victim")"
test -L "$P/.claude/openspec-reconcile.foo.local.json"; eq "the state symlink is replaced by a file" 1 "$?"

# 路徑：上層不是 changes → exit 2
mkdir -p "$WORK/x"; node "$CHECK" check "$WORK/x" > /dev/null 2>&1; eq "path: not under openspec/changes exit 2" 2 "$?"

# 既有 validator：CLI 不變；require 不印 usage、不結束行程
node "$VALIDATOR" "$FIXTURES/valid-change" > /dev/null 2>&1; eq "validator CLI still exit 0" 0 "$?"
out=$(node -e 'const m = require(process.argv[1]); process.stdout.write(typeof m.findSpecFiles)' "$VALIDATOR" 2>&1)
eq "validator require exports findSpecFiles without running main" "function" "$out"

# ---- summary ----
MIN=86
if [ "$((PASS + FAIL))" -lt "$MIN" ]; then
  echo "FAIL: ran $((PASS + FAIL)) assertions, expected at least $MIN"; FAIL=$((FAIL+1))
fi
echo "reconcile-check: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
