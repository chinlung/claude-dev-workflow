#!/bin/bash
# openspec-archive-stats.cjs fixture 測試（歸檔時未勾 task 的統計）
# 用法:bash plugins/openspec-superpowers-workflow/tests/archive-stats.test.sh   (STATS=<路徑> 測副本)
# 消費者:提交前手跑 + CI(.github/workflows/validate.yml 列舉 plugins/*/tests/*.test.sh)
# 只有全部通過、且實際跑到的斷言數達下限才 exit 0——下限在案例清單之外計算，提早結束的清單不會讀成綠
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATS=${STATS:-"$SCRIPT_DIR/../scripts/openspec-archive-stats.cjs"}
command -v node >/dev/null 2>&1 || { echo "archive-stats.test: node is required"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "archive-stats.test: jq is required"; exit 1; }

TMPBASE="${TMPDIR:-/tmp}"
WORK=$(mktemp -d "${TMPBASE%/}/archive-stats-test.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

# eq <名稱> <期望> <實際>
eq() {
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — expected [$2] got [$3]"; fi
}
# stats <參數…>:輸出在 $WORK/out.json,exit code 在 $RC
stats() { node "$STATS" "$@" > "$WORK/out.json" 2> "$WORK/err"; RC=$?; }
# j <jq 運算式>:讀 $WORK/out.json
j() { jq -r "$1" "$WORK/out.json" 2>/dev/null; }
# mk_arch <根> <專案> <歸檔目錄名> [tasks 內容]:不給內容就不建 tasks.md
mk_arch() {
  local d="$1/$2/openspec/changes/archive/$3"
  mkdir -p "$d"
  [ "$#" -ge 4 ] && printf '%b' "$4" > "$d/tasks.md"
  return 0
}

# ---- fixture:三個專案、四個已歸檔 ----
R1="$WORK/r1"
mk_arch "$R1" alpha 2026-09-10-a1 '- [x] 1.1 a\n- [x] 1.2 b\n'
mk_arch "$R1" alpha 2026-10-05-a2 '- [ ] 1.1 a\n- [ ] 1.2 b\n- [ ] 1.3 c\n'
mk_arch "$R1" beta  2026-10-20-b1 '- [x] 1.1 a\n- [ ] 1.2 b — skip: 範圍外\n'
mk_arch "$R1" gamma 2026-11-02-c1

stats --root "$R1"
eq "exit 0 on the fixture tree" 0 "$RC"
eq "totals.archived" 4 "$(j .totals.archived)"
eq "totals.noTasks" 1 "$(j .totals.noTasks)"
eq "totals.withTasks" 3 "$(j .totals.withTasks)"
eq "totals.incomplete" 2 "$(j .totals.incomplete)"
eq "totals.zeroChecked" 1 "$(j .totals.zeroChecked)"
eq "totals.withSkipReason" 1 "$(j .totals.withSkipReason)"
eq "totals.incompleteNoReason" 1 "$(j .totals.incompleteNoReason)"
eq "byMonth buckets by directory-name prefix" "1 2 1" "$(j '[.byMonth["2026-09"].archived, .byMonth["2026-10"].archived, .byMonth["2026-11"].archived] | join(" ")')"
eq "definition is a non-empty string" true "$(j '(.definition | type == "string") and (.definition | length > 0)')"

# 專案名:預設雜湊前六碼,--names 才用原名
expect_hash=$(printf 'alpha' | shasum -a 256 | cut -c1-6)
eq "labels are 6 hex chars by default" true "$(j '[.projects[].label | test("^[0-9a-f]{6}$")] | all')"
eq "label is sha256 prefix of the directory name" "$expect_hash" "$(j '.projects[] | select(.archived == 2) | .label')"
stats --root "$R1" --names
eq "--names shows basenames" "alpha beta gamma" "$(j '[.projects[].label] | sort | join(" ")')"

# --since:邊界日當天保留、前一天排除
stats --root "$R1" --since 2026-10-05
eq "--since keeps the boundary day" 3 "$(j .totals.archived)"
stats --root "$R1" --since 2026-10-06
eq "--since drops the day before the boundary" 2 "$(j .totals.archived)"

# 換行與形狀
R2="$WORK/r2"
mk_arch "$R2" crlf 2026-10-01-x '- [ ] 1.1 a\r\n- [x] 1.2 b\r\n'
stats --root "$R2"
eq "CRLF: withTasks" 1 "$(j .totals.withTasks)"
eq "CRLF: incomplete" 1 "$(j .totals.incomplete)"
R3="$WORK/r3"
mk_arch "$R3" empty 2026-10-01-x ''
stats --root "$R3"
eq "empty tasks.md counts as noTasks" 1 "$(j .totals.noTasks)"
eq "empty tasks.md is not withTasks" 0 "$(j .totals.withTasks)"
R4="$WORK/r4"
mk_arch "$R4" nested 2026-10-01-x '- [x] **Step 1** a\n  - [ ] nested\n    - [x] deeper\n'
stats --root "$R4"
eq "nested and bold-step boxes: withTasks" 1 "$(j .totals.withTasks)"
eq "nested unchecked box makes it incomplete" 1 "$(j .totals.incomplete)"
eq "nested boxes with some checked are not zeroChecked" 0 "$(j .totals.zeroChecked)"

# skip 理由:空理由與有理由要分開(CRLF 結尾也一樣)
R6="$WORK/r6"
mk_arch "$R6" reasons 2026-10-01-empty '- [ ] 1.1 a — skip:\r\n'
mk_arch "$R6" reasons 2026-10-02-spaces '- [ ] 1.1 a — skip:   \n'
mk_arch "$R6" reasons 2026-10-03-given '- [ ] 1.1 a — skip: x\r\n- [x] 1.2 b\n'
mk_arch "$R6" reasons 2026-10-04-punct '- [ ] 1.1 a — skip: ...\n'
mk_arch "$R6" reasons 2026-10-05-paren '- [ ] 1.1 a — skip: （範圍外）\n'
mk_arch "$R6" reasons 2026-10-06-quoted '- [ ] 1.1 a — skip: "not required"\n'
mk_arch "$R6" reasons 2026-10-07-fullwidth '- [ ] 1.1 a — skip：範圍外\n'
mk_arch "$R6" reasons 2026-10-08-nodash '- [ ] 1.1 mention a skip: flag\n'
stats --root "$R6"
eq "skip with an empty, blank or punctuation-only reason, or skip: without the dash before it, counts as no reason" 4 "$(j .totals.incompleteNoReason)"
eq "skip with a reason (plain, parenthesised, quoted, full-width colon) counts as withSkipReason" 4 "$(j .totals.withSkipReason)"
eq "all eight are incomplete" 8 "$(j .totals.incomplete)"

# OpenSpec 1.16 的 task 定義：其他清單符號與非 x 標記都是未完成的 task；連結 bullet 不是 task
R7="$WORK/r7"
mk_arch "$R7" forms 2026-10-01-star '* [ ] a\n* [x] b\n'
mk_arch "$R7" forms 2026-10-02-numbered '1. [ ] a\n2) [X] b\n'
mk_arch "$R7" forms 2026-10-03-tilde '- [~] a\n- [x] b\n'
mk_arch "$R7" forms 2026-10-04-links '- [doc](./doc.md)\n- [WIP](./wip.md)\n- [A](https://example.com)\n- [1][ref]\n'
stats --root "$R7"
eq "other bullets and markers: withTasks" 3 "$(j .totals.withTasks)"
eq "other bullets and markers: incomplete" 3 "$(j .totals.incomplete)"
eq "link bullets alone count as noTasks" 1 "$(j .totals.noTasks)"

# 沒有歸檔目錄 / 不存在的根
mkdir -p "$WORK/r5/plain"
stats --root "$WORK/r5"
eq "root without archive dirs exits 0" 0 "$RC"
eq "root without archive dirs has zero archived" 0 "$(j .totals.archived)"
stats --root "$WORK/does-not-exist"
eq "missing --root path exits 2" 2 "$RC"

# 根可以直接是專案,也可以重複給
stats --root "$R1/alpha"
eq "a root that is itself a project works" 2 "$(j .totals.archived)"
stats --root "$R1" --root "$R2"
eq "multiple --root values add up" 5 "$(j .totals.archived)"

# ---- summary ----
MIN=33
if [ "$((PASS + FAIL))" -lt "$MIN" ]; then
  echo "FAIL: ran $((PASS + FAIL)) assertions, expected at least $MIN"; FAIL=$((FAIL+1))
fi
echo "archive-stats: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
