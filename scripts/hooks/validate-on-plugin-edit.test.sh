#!/bin/bash
# validate-on-plugin-edit.cjs fixture 測試
# 用法:bash scripts/hooks/validate-on-plugin-edit.test.sh
# 消費者:提交前手跑 + CI(.github/workflows/validate.yml)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/validate-on-plugin-edit.cjs"
PASS=0; FAIL=0

# 帶模板：無模板的 mktemp -d 在 macOS 會落到 /var/folders/.../T/，Claude Code sandbox 只准寫 $TMPDIR，致整套假紅
TMPBASE="${TMPDIR:-/tmp}"
WORK=$(mktemp -d "${TMPBASE%/}/plugin-edit-hook-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

check() { # <名稱> <實際> <期望子字串>
  # here-string, not `echo | grep -q`: under pipefail, grep -q quitting at the first match while echo is still writing a long
  # string kills echo with SIGPIPE and turns a match into a failure
  if grep -q "$3" <<<"$2"; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — got: $2"; fi
}

# make_root <dir> [with-failing-suite]:建 scratch 專案根
# stub runner 與 stub suites 都把執行記錄 append 到 <dir>/ran.log
make_root() {
  local r="$1"
  mkdir -p "$r/scripts" "$r/plugins/x/hooks" "$r/plugins/x/tests"
  printf '#!/usr/bin/env node\nrequire("fs").appendFileSync(process.env.RAN_LOG,"runner\\n");\n' > "$r/scripts/validate-fixtures.cjs"
  printf '#!/bin/bash\necho ok >> "$RAN_LOG"\nexit 0\n' > "$r/plugins/x/tests/ok.test.sh"
  if [ "${2:-}" = "with-failing-suite" ]; then
    printf '#!/bin/bash\necho fail-suite ran >&2\nexit 1\n' > "$r/plugins/x/tests/zz-fail.test.sh"
  fi
  : > "$r/plugins/x/hooks/h.sh"
}

# run_hook <root> <file_path> → 全域 rc/out/err
run_hook() {
  rc=0
  out=$(printf '{"tool_input":{"file_path":"%s"}}' "$2" \
    | CLAUDE_PROJECT_DIR="$1" RAN_LOG="$1/ran.log" node "$HOOK" 2>"$1/stderr.txt") || rc=$?
  err=$(cat "$1/stderr.txt" 2>/dev/null || true)
}

# 1) 編輯 plugins/*/hooks/*.sh → 觸發:node runner 與 bash suite 都要跑,exit 0
r=$WORK/r1; make_root "$r"
run_hook "$r" "$r/plugins/x/hooks/h.sh"
check "1 hooks/*.sh 觸發後 exit 0" "$rc" '^0$'
check "1 node runner 有跑" "$(cat "$r/ran.log" 2>/dev/null)" 'runner'
check "1 bash suite 有跑" "$(cat "$r/ran.log" 2>/dev/null)" 'ok'

# 2) 編輯 plugins/*/tests/*.test.sh → 觸發(原 /tests/ 涵蓋),bash suite 要跑
r=$WORK/r2; make_root "$r"
run_hook "$r" "$r/plugins/x/tests/ok.test.sh"
check "2 tests/ 編輯觸發 bash suite" "$(cat "$r/ran.log" 2>/dev/null)" 'ok'

# 3) 任一 bash suite 失敗 → exit 2 且 stderr 含失敗輸出
r=$WORK/r3; make_root "$r" with-failing-suite
run_hook "$r" "$r/plugins/x/hooks/h.sh"
check "3 suite 失敗 → exit 2" "$rc" '^2$'
check "3 stderr 帶回失敗輸出" "$err" 'fail-suite ran'

# 4) 無關檔案 → no-op:exit 0 且什麼都沒跑
r=$WORK/r4; make_root "$r"
run_hook "$r" "$r/README.md"
check "4 無關檔案 exit 0" "$rc" '^0$'
if [ -f "$r/ran.log" ]; then
  FAIL=$((FAIL+1)); echo "FAIL: 4 無關檔案不應觸發任何執行 — ran.log: $(cat "$r/ran.log")"
else
  PASS=$((PASS+1)); echo "PASS: 4 無關檔案零執行"
fi

# 5) 不可解析的 stdin → exit 0(fail-open)
r=$WORK/r5; make_root "$r"
rc=0; printf 'not-json' | CLAUDE_PROJECT_DIR="$r" RAN_LOG="$r/ran.log" node "$HOOK" >/dev/null 2>&1 || rc=$?
check "5 壞輸入 fail-open exit 0" "$rc" '^0$'

# 6) repo 結構閘門(command/skill 同名碰撞、版本記帳、plugin CHANGELOG 記帳、denyWrite 閉包)守護的檔案 → 觸發 node runner
#    .claude/settings.json:denyWrite 閘門讀它;改 denyWrite 或 hook 指令正是該閘門最該跑的時刻
i=0
for rel in plugins/x/commands/c.md plugins/x/skills/s/SKILL.md plugins/x/.claude-plugin/plugin.json \
           plugins/x/CHANGELOG.md .claude-plugin/marketplace.json CHANGELOG.md CHANGELOG.zh-TW.md .claude/settings.json \
           plugins/x/agents/a.md plugins/x/agents/sub/a.md; do
  i=$((i+1)); r=$WORK/r6-$i; make_root "$r"
  run_hook "$r" "$r/$rel"
  check "6 $rel 觸發 node runner" "$(cat "$r/ran.log" 2>/dev/null)" 'runner'
done

# 6b) skill 目錄第一層的程式／資料檔(vendored security-audit 的 validator、上游測試、schema 即此形狀)→ 觸發 node runner
i=0
for rel in plugins/x/skills/s/validate-x.cjs plugins/x/skills/s/validate-x.test.cjs plugins/x/skills/s/report-schema.json; do
  i=$((i+1)); r=$WORK/r6b-$i; make_root "$r"
  run_hook "$r" "$r/$rel"
  check "6b $rel 觸發 node runner" "$(cat "$r/ran.log" 2>/dev/null)" 'runner'
done

# 7) 閘門不讀的檔案 → no-op:skill 目錄下其他 md,以及形似但不在 plugins/<name>/ 底下的
#    commands/skills/manifest/CHANGELOG(專案 .claude/、docs/、plugin 內的 marketplace.json)
i=0
for rel in plugins/x/skills/s/notes.md docs/CHANGELOG.md \
           .claude/commands/x.md docs/skills/foo/SKILL.md plugins/x/.claude-plugin/marketplace.json \
           .claude/agents/a.md plugins/x/agents/notes.txt; do
  i=$((i+1)); r=$WORK/r7-$i; make_root "$r"
  run_hook "$r" "$r/$rel"
  if [ -f "$r/ran.log" ]; then
    FAIL=$((FAIL+1)); echo "FAIL: 7 $rel 不應觸發 — ran.log: $(cat "$r/ran.log")"
  else
    PASS=$((PASS+1)); echo "PASS: 7 $rel 零執行"
  fi
done

# 8) 專案根之外、但路徑同樣含 plugins/<name>/commands/ 的檔案(marketplace 快取 clone 即此形狀)→ no-op
#    守住「子字串式錨定」的退化:比對必須是 root-relative
r=$WORK/r8; make_root "$r"
run_hook "$r" "$WORK/outside/plugins/x/commands/c.md"
if [ -f "$r/ran.log" ]; then
  FAIL=$((FAIL+1)); echo "FAIL: 8 專案根之外的 plugins/x/commands 不應觸發 — ran.log: $(cat "$r/ran.log")"
else
  PASS=$((PASS+1)); echo "PASS: 8 專案根之外零執行"
fi
r=$WORK/r8b; make_root "$r"
run_hook "$r" "$WORK/outside/plugins/x/skills/s/validate-x.cjs"
if [ -f "$r/ran.log" ]; then
  FAIL=$((FAIL+1)); echo "FAIL: 8b 專案根之外的 skill 程式檔不應觸發 — ran.log: $(cat "$r/ran.log")"
else
  PASS=$((PASS+1)); echo "PASS: 8b 專案根之外的 skill 程式檔零執行"
fi

# 9) suite 拿到 NO_MUTANTS=1(只留一般斷言、略過 mutant 重跑,CI 仍跑完整版),node runner 照呼叫端環境;
#    全部 suite 依序跑要 658 s,遠超 settings.json 給 hook 的 120 s,後段 suite 的失敗就回不到 Claude
r=$WORK/r9; make_root "$r"
printf '#!/usr/bin/env node\nrequire("fs").appendFileSync(process.env.RAN_LOG,"runner-env="+process.env.NO_MUTANTS+"\\n");\n' > "$r/scripts/validate-fixtures.cjs"
printf '#!/bin/bash\necho "suite-env=${NO_MUTANTS-unset}" >> "$RAN_LOG"\n' > "$r/plugins/x/tests/env.test.sh"
NO_MUTANTS=from-caller run_hook "$r" "$r/plugins/x/hooks/h.sh"
check "9 suite 的 NO_MUTANTS 是 1(蓋過呼叫端)" "$(cat "$r/ran.log" 2>/dev/null)" 'suite-env=1'
check "9 node runner 不被改環境(照呼叫端)" "$(cat "$r/ran.log" 2>/dev/null)" 'runner-env=from-caller'

# 10) suite 並行:兩支互等對方的 started 檔,依序跑的話第一支等滿 5 s 而失敗 → exit 2
r=$WORK/r10; make_root "$r"
for pair in "a b" "b a"; do set -- $pair
  printf '#!/bin/bash\nD=$(dirname "$RAN_LOG")\ntouch "$D/%s.started"\nfor i in $(seq 1 100); do [ -f "$D/%s.started" ] && exit 0; sleep 0.05; done\necho "%s never saw %s" >&2\nexit 1\n' "$1" "$2" "$1" "$2" > "$r/plugins/x/tests/rendezvous-$1.test.sh"
done
run_hook "$r" "$r/plugins/x/hooks/h.sh"
check "10 兩支 suite 同時在跑 → exit 0" "$rc" '^0$'

# 11) 並行下失敗輸出仍依 suite 名稱排序(不是完成先後),且每段標出是哪支 suite
r=$WORK/r11; make_root "$r"
printf '#!/bin/bash\nsleep 0.5\necho aa-output >&2\nexit 1\n' > "$r/plugins/x/tests/aa-fail.test.sh"
printf '#!/bin/bash\necho zz-output >&2\nexit 1\n' > "$r/plugins/x/tests/zz-fail.test.sh"
run_hook "$r" "$r/plugins/x/hooks/h.sh"
check "11 兩支失敗 → exit 2" "$rc" '^2$'
a=$(echo "$err" | grep -n 'aa-output' | head -1 | cut -d: -f1); z=$(echo "$err" | grep -n 'zz-output' | head -1 | cut -d: -f1)
if [ -n "$a" ] && [ -n "$z" ] && [ "$a" -lt "$z" ]; then PASS=$((PASS+1)); echo "PASS: 11 失敗輸出依 suite 名稱排序"
else FAIL=$((FAIL+1)); echo "FAIL: 11 失敗輸出順序 — aa 行 [$a] zz 行 [$z]"; fi
check "11 標出失敗的 suite" "$err" 'aa-fail.test.sh'

# 12) suite 留在 hook 的 process group(不 detached),跟原本 spawnSync 一樣:harness 砍掉 hook 時才會連帶砍掉它們。
#     另開 group 的話,hook 被砍時 suite 全成孤兒、繼續在背景跑(codex r3)
r=$WORK/r12; make_root "$r"
printf '#!/bin/bash\nps -o pgid= -p $$ | tr -d " " > "$(dirname "$RAN_LOG")/suite.pgid"\n' > "$r/plugins/x/tests/pgid.test.sh"
run_hook "$r" "$r/plugins/x/hooks/h.sh"
self_pgid=$(ps -o pgid= -p $$ | tr -d ' ')
check "12 suite 與 hook 同一個 process group" "$(cat "$r/suite.pgid" 2>/dev/null)" "^${self_pgid}\$"

# 13) 失敗的 suite 輸出很大 → 截斷後才回報(舊的 spawnSync 有 1 MB 上限;不截就整份灌進 Claude 的 context),頭尾都保留
r=$WORK/r13; make_root "$r"
printf '#!/bin/bash\necho HEAD-MARK >&2\nhead -c 200000 /dev/zero | tr "\\0" "x" >&2\necho >&2\necho TAIL-MARK >&2\nexit 1\n' > "$r/plugins/x/tests/big.test.sh"
run_hook "$r" "$r/plugins/x/hooks/h.sh"
check "13 大量輸出仍 exit 2" "$rc" '^2$'
check "13 保留開頭" "$err" 'HEAD-MARK'
check "13 保留結尾" "$err" 'TAIL-MARK'
check "13 註明截斷" "$err" 'truncated'
if [ "${#err}" -lt 60000 ]; then PASS=$((PASS+1)); echo "PASS: 13 回報長度有上限(${#err})"
else FAIL=$((FAIL+1)); echo "FAIL: 13 回報長度沒有上限(${#err})"; fi

# 14) 輸出停不下來的 job → 累計超過上限就停掉它、記為失敗(exit 2),跟舊 spawnSync 的 maxBuffer 一樣;
#     不停的話 hook 會一直等它,直到 harness 的 120 s 把 hook 連同其他失敗一起靜默砍掉。外包 30 s alarm,修好前不至於卡死測試
i=0
for flood in 'yes' 'yes >&2'; do
  i=$((i+1)); r=$WORK/r14-$i; make_root "$r"
  printf '#!/bin/bash\n%s\n' "$flood" > "$r/plugins/x/tests/flood.test.sh"
  rc=0; start=$SECONDS
  out=$(printf '{"tool_input":{"file_path":"%s"}}' "$r/plugins/x/hooks/h.sh" \
    | CLAUDE_PROJECT_DIR="$r" RAN_LOG="$r/ran.log" perl -e 'alarm 30; exec @ARGV' node "$HOOK" 2>"$r/stderr.txt") || rc=$?
  err=$(cat "$r/stderr.txt" 2>/dev/null || true); elapsed=$((SECONDS - start))
  check "14 [$flood] 停掉並記為失敗 → exit 2" "$rc" '^2$'
  check "14 [$flood] 點名並說明為何停掉" "$err" 'flood.test.sh.*stopped'
  if [ "$elapsed" -lt 25 ]; then PASS=$((PASS+1)); echo "PASS: 14 [$flood] 很快就停(${elapsed}s)"
  else FAIL=$((FAIL+1)); echo "FAIL: 14 [$flood] 沒有停(${elapsed}s)"; fi
done

# ---- summary ----
echo "----"
echo "validate-on-plugin-edit.test.sh: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
