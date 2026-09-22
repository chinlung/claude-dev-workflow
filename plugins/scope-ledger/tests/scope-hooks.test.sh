#!/bin/bash
# scope-ledger hook fixture tests
# 用法：bash plugins/scope-ledger/tests/scope-hooks.test.sh
# 消費者：提交前手跑 + CI（.github/workflows/validate.yml）+ 本地 PostToolUse hook
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS="$SCRIPT_DIR/../hooks"
PASS=0; FAIL=0

# 帶模板：無模板的 mktemp -d 在 macOS 會落到 /var/folders/…，sandbox 只准寫 $TMPDIR
TMPBASE="${TMPDIR:-/tmp}"
WORK=$(mktemp -d "${TMPBASE%/}/scope-hooks-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# ---- helpers ----
check() {        # check <name> <actual> <expected substring (grep BRE)>
  if printf '%s' "$2" | grep -q -- "$3"; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — got: $2"; fi
}
check_empty() {  # check_empty <name> <actual>
  if [ -z "$2" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — expected empty, got: $2"; fi
}
check_eq() {     # check_eq <name> <actual> <expected exact>
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — expected [$3], got [$2]"; fi
}
check_flag() {   # check_flag <name> <path> <exists|absent>
  if [ "$3" = exists ] && [ -f "$2" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  elif [ "$3" = absent ] && [ ! -f "$2" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — flag state wrong: $2"; fi
}
# run_hook <script> <json> <tmpdir> <project_dir>
run_hook() { printf '%s' "$2" | TMPDIR="$3" CLAUDE_PROJECT_DIR="$4" bash "$HOOKS/$1" 2>/dev/null || true; }

# make_repo <dir> [branch]：git worktree fixture
make_repo() {
  mkdir -p "$1/src" "$1/.claude"
  git -C "$1" init -q 2>/dev/null
  git -C "$1" config core.fsmonitor false 2>/dev/null
  # 需要一個 commit：unborn branch 上 `rev-parse --abbrev-ref HEAD` 會失敗，gate 會 fail-open 放行
  git -C "$1" -c user.email=t@t.t -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m init 2>/dev/null
  git -C "$1" checkout -q -b "${2:-feature/x}" 2>/dev/null
}
# write_ledger <dir> <branch> <rounds> <in-scope lines…>
write_ledger() {
  local d="$1" b="$2" r="$3"; shift 3
  {
    printf -- '---\ngoal: 修好通知漏發\nbranch: %s\nopened: 2026-09-23\nreview_rounds: %s\n---\n## In scope\n' "$b" "$r"
    for l in "$@"; do printf '%s\n' "$l"; done
    printf '## Deferred\n## Log\n'
  } > "$d/.claude/scope-ledger.local.md"
}

# ===== _ledger.sh helpers =====
. "$HOOKS/_ledger.sh"
p=$WORK/h1; make_repo "$p"
write_ledger "$p" feature/x 2 '- [ ] A ← 來源: user' '- [x] B ← 來源: user' '- [ ] C ← 來源: review-branch@r1'
L="$p/.claude/scope-ledger.local.md"
check_eq "H1 ledger_path" "$(ledger_path "$p/")" "$p/.claude/scope-ledger.local.md"
check_eq "H2 ledger_field branch" "$(ledger_field "$L" branch)" "feature/x"
check_eq "H3 ledger_field goal" "$(ledger_field "$L" goal)" "修好通知漏發"
check_eq "H4 ledger_rounds" "$(ledger_rounds "$L")" "2"
check_eq "H5 ledger_unchecked 只列 In scope 的未勾項" "$(ledger_unchecked "$L")" "$(printf -- '- [ ] A ← 來源: user\n- [ ] C ← 來源: review-branch@r1')"
check_eq "H6 bump → 3" "$(ledger_bump_rounds "$L")" "3"
check_eq "H6b 檔案內已更新" "$(ledger_rounds "$L")" "3"
# rounds key missing → inserted before closing ---
printf -- '---\ngoal: g\nbranch: b\n---\n## In scope\n- [ ] x\n' > "$L"
check_eq "H7 缺 review_rounds → 視為 0" "$(ledger_rounds "$L")" "0"
check_eq "H7b bump 補上鍵 → 1" "$(ledger_bump_rounds "$L")" "1"
check_eq "H7c 補在 frontmatter 內" "$(ledger_field "$L" review_rounds)" "1"
# non-numeric rounds → 0
printf -- '---\nreview_rounds: abc\n---\n## In scope\n' > "$L"
check_eq "H8 非數字 rounds → 0" "$(ledger_rounds "$L")" "0"
# Deferred section's unticked-looking lines are not In scope
printf -- '---\n---\n## In scope\n- [x] done\n## Deferred\n- [ ] not mine\n' > "$L"
check_empty "H9 Deferred 段的 [ ] 不算未完成" "$(ledger_unchecked "$L")"
# missing file → empty, no crash
check_empty "H10 檔案不存在 → 空" "$(ledger_unchecked "$WORK/nope.md")"
check_eq "H10b 檔案不存在 rounds → 0" "$(ledger_rounds "$WORK/nope.md")" "0"

# ===== scope-gate.sh =====
gate_json() { printf '{"session_id":"%s","cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" "$2" "$3"; }

# G1 非 git 目錄 → allow
p=$WORK/g1; mkdir -p "$p/src"; t=$WORK/gt1; mkdir -p "$t"
check_empty "G1 非 git 目錄 → allow" "$(run_hook scope-gate.sh "$(gate_json s1 "$p" "$p/src/a.php")" "$t" "$p")"
check_flag  "G1 不留 flag" "$t/claude-scope-gate-s1" absent

# G2 git + 程式碼檔 + 無帳本 → deny 一次 + flag
p=$WORK/g2; make_repo "$p"; t=$WORK/gt2; mkdir -p "$t"
rc=0; out=$(printf '%s' "$(gate_json s2 "$p" "$p/src/a.php")" | TMPDIR="$t" CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/scope-gate.sh" 2>/dev/null) || rc=$?
check "G2 無帳本首次編輯 → deny" "$out" '"permissionDecision":"deny"'
check "G2 exit 0" "$rc" '^0$'
check "G2 訊息指向 init" "$out" 'scope init'
check_flag "G2 留 flag" "$t/claude-scope-gate-s2" exists
# G3a 批次窗內手足編輯 → 續 deny；G3b 窗外重試 → allow
check "G3a 批次窗內 → 續 deny" "$(run_hook scope-gate.sh "$(gate_json s2 "$p" "$p/src/b.ts")" "$t" "$p")" '"permissionDecision":"deny"'
touch -t 202001010000 "$t/claude-scope-gate-s2"
check_empty "G3b 窗外重試 → allow" "$(run_hook scope-gate.sh "$(gate_json s2 "$p" "$p/src/b.ts")" "$t" "$p")"

# G4 帳本存在且 branch 相符 → allow、不留 flag（兩種副檔名）
p=$WORK/g4; make_repo "$p" feature/x; t=$WORK/gt4; mkdir -p "$t"
write_ledger "$p" feature/x 0 '- [ ] A'
check_empty "G4 帳本相符 .php → allow" "$(run_hook scope-gate.sh "$(gate_json s4 "$p" "$p/src/a.php")" "$t" "$p")"
check_empty "G4 帳本相符 .go → allow" "$(run_hook scope-gate.sh "$(gate_json s4 "$p" "$p/src/a.go")" "$t" "$p")"
check_flag  "G4 不留 flag" "$t/claude-scope-gate-s4" absent

# G5 帳本 branch 不符 → deny，訊息含兩個分支名
p=$WORK/g5; make_repo "$p" feature/y; t=$WORK/gt5; mkdir -p "$t"
write_ledger "$p" feature/x 0 '- [ ] A'
out=$(run_hook scope-gate.sh "$(gate_json s5 "$p" "$p/src/a.php")" "$t" "$p")
check "G5 branch 不符 → deny" "$out" '"permissionDecision":"deny"'
check "G5 訊息含帳本分支" "$out" 'feature/x'
check "G5 訊息含當前分支" "$out" 'feature/y'
# G5b 帳本 branch 欄空白 → fail-open allow
write_ledger "$p" "" 0 '- [ ] A'
mkdir -p "$WORK/gt5b"
check_empty "G5b 帳本 branch 空白 → allow" "$(run_hook scope-gate.sh "$(gate_json s5b "$p" "$p/src/a.php")" "$WORK/gt5b" "$p")"

# G6 非程式碼檔（md / json）→ allow，即使無帳本
p=$WORK/g6; make_repo "$p"; t=$WORK/gt6; mkdir -p "$t"
check_empty "G6 .md → allow" "$(run_hook scope-gate.sh "$(gate_json s6 "$p" "$p/README.md")" "$t" "$p")"
check_empty "G6 .json → allow" "$(run_hook scope-gate.sh "$(gate_json s6 "$p" "$p/package.json")" "$t" "$p")"
check_flag  "G6 不留 flag" "$t/claude-scope-gate-s6" absent
# G6c workflow yaml 算程式碼 → deny
check "G6c .github/workflows/*.yml → deny" "$(run_hook scope-gate.sh "$(gate_json s6c "$p" "$p/.github/workflows/ci.yml")" "$t" "$p")" '"permissionDecision":"deny"'

# G7 豁免路徑：.claude/（帳本本身）與 openspec/ → allow
p=$WORK/g7; make_repo "$p"; t=$WORK/gt7; mkdir -p "$t"
check_empty "G7 .claude/ 內 → allow" "$(run_hook scope-gate.sh "$(gate_json s7 "$p" "$p/.claude/scope-ledger.local.md")" "$t" "$p")"
check_empty "G7 openspec/ 內 .sh → allow" "$(run_hook scope-gate.sh "$(gate_json s7 "$p" "$p/openspec/changes/x/run.sh")" "$t" "$p")"
# G8 專案外路徑 → allow
check_empty "G8 專案外 → allow" "$(run_hook scope-gate.sh "$(gate_json s8 "$p" "$WORK/elsewhere/x.php")" "$t" "$p")"
# G9 無 file_path → allow
check_empty "G9 無 file_path → allow" "$(printf '{"session_id":"s9","cwd":"%s","tool_name":"Edit","tool_input":{}}' "$p" | TMPDIR="$t" CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/scope-gate.sh" 2>/dev/null || true)"
# G10 session_id 消毒
p=$WORK/g10; make_repo "$p"; t=$WORK/gt10; mkdir -p "$t"
check "G10 消毒後仍 deny" "$(run_hook scope-gate.sh "$(gate_json 's10/../evil' "$p" "$p/src/a.php")" "$t" "$p")" '"permissionDecision":"deny"'
check_flag "G10 flag 落在消毒後路徑" "$t/claude-scope-gate-s10_.._evil" exists

# ===== scope-review-triage.sh =====
skill_json() { printf '{"session_id":"%s","cwd":"%s","tool_name":"Skill","tool_input":{"skill":"%s"}}' "$1" "$2" "$3"; }
agent_json() { printf '{"session_id":"%s","cwd":"%s","tool_name":"Agent","tool_input":{"subagent_type":"%s","description":"%s"}}' "$1" "$2" "$3" "$4"; }

p=$WORK/r1; make_repo "$p"; t=$WORK/rt1; mkdir -p "$t"
write_ledger "$p" feature/x 0 '- [ ] A'
L="$p/.claude/scope-ledger.local.md"
# R1 非 review skill → 靜默、rounds 不動（兩例）
check_empty "R1 brainstorming → 靜默" "$(run_hook scope-review-triage.sh "$(skill_json s1 "$p" superpowers:brainstorming)" "$t" "$p")"
check_empty "R1 commit → 靜默" "$(run_hook scope-review-triage.sh "$(skill_json s1 "$p" commit-commands:commit)" "$t" "$p")"
check_eq "R1 rounds 仍 0" "$(ledger_rounds "$L")" "0"
# R2 review skill + 帳本 → 注入 triage 政策，rounds 1；再一次 → 2
out=$(run_hook scope-review-triage.sh "$(skill_json s2 "$p" code-audit-rigor:review-branch)" "$t" "$p")
check "R2 注入 additionalContext" "$out" '"additionalContext"'
check "R2 政策：input 不是工單" "$out" '不是工單'
check "R2 標第 1 輪" "$out" '第 1 輪'
check_eq "R2 rounds 寫回 1" "$(ledger_rounds "$L")" "1"
out=$(run_hook scope-review-triage.sh "$(skill_json s2 "$p" security-review)" "$t" "$p")
check "R2b 第 2 輪" "$out" '第 2 輪'
check_empty "R2b 未達門檻無告警" "$(printf '%s' "$out" | grep -o '收斂告警' || true)"
# R3 第 3 輪 → 收斂告警（兩例：3 與 4）
out=$(run_hook scope-review-triage.sh "$(skill_json s3 "$p" codex-review-bg)" "$t" "$p")
check "R3 第 3 輪出現收斂告警" "$out" '收斂告警'
out=$(run_hook scope-review-triage.sh "$(skill_json s3 "$p" claude-security)" "$t" "$p")
check "R3b 第 4 輪仍告警" "$out" '收斂告警'
check_eq "R3b rounds 4" "$(ledger_rounds "$L")" "4"
# R4 Agent 型 review（subagent_type 命中）→ 注入並計輪；非 review agent → 靜默
p=$WORK/r4; make_repo "$p"; t=$WORK/rt4; mkdir -p "$t"; write_ledger "$p" feature/x 0 '- [ ] A'
check "R4 pr-review-toolkit:code-reviewer → 注入" "$(run_hook scope-review-triage.sh "$(agent_json s4 "$p" pr-review-toolkit:code-reviewer "look at diff")" "$t" "$p")" '"additionalContext"'
check "R4b high-precision-dev:critic → 注入" "$(run_hook scope-review-triage.sh "$(agent_json s4 "$p" high-precision-dev:critic "x")" "$t" "$p")" '"additionalContext"'
check_eq "R4 rounds 2" "$(ledger_rounds "$p/.claude/scope-ledger.local.md")" "2"
check_empty "R4c Explore agent → 靜默" "$(run_hook scope-review-triage.sh "$(agent_json s4 "$p" Explore "find files")" "$t" "$p")"
# R4d subagent_type 空、description 提 review → 注入（fallback）
check "R4d 無 subagent_type、description 含 review → 注入" "$(run_hook scope-review-triage.sh "$(agent_json s4 "$p" "" "review the auth module")" "$t" "$p")" '"additionalContext"'
# R5 review skill 但無帳本 → 仍注入政策並點名 init；不崩潰
p=$WORK/r5; make_repo "$p"; t=$WORK/rt5; mkdir -p "$t"
out=$(run_hook scope-review-triage.sh "$(skill_json s5 "$p" review-branch)" "$t" "$p")
check "R5 無帳本 → 注入" "$out" '"additionalContext"'
check "R5 無帳本 → 指向 init" "$out" 'scope init'
# R6 其他工具 → 靜默（兩例）
check_empty "R6 Bash → 靜默" "$(printf '{"session_id":"s6","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git review"}}' "$p" | TMPDIR="$t" CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/scope-review-triage.sh" 2>/dev/null || true)"
check_empty "R6 Edit → 靜默" "$(printf '{"session_id":"s6","cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"review.php"}}' "$p" | TMPDIR="$t" CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/scope-review-triage.sh" 2>/dev/null || true)"

# ===== scope-stop-check.sh =====
stop_json() { printf '{"session_id":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":%s}' "$1" "$2" "$3"; }

# S1 stop_hook_active=true → 靜默（即使有未完成項）
p=$WORK/s1; make_repo "$p"; t=$WORK/st1; mkdir -p "$t"; write_ledger "$p" feature/x 0 '- [ ] A' '- [ ] B'
check_empty "S1 stop_hook_active → 靜默" "$(run_hook scope-stop-check.sh "$(stop_json s1 "$p" true)" "$t" "$p")"
# S2 無帳本 → 靜默
p=$WORK/s2; make_repo "$p"; t=$WORK/st2; mkdir -p "$t"
check_empty "S2 無帳本 → 靜默" "$(run_hook scope-stop-check.sh "$(stop_json s2 "$p" false)" "$t" "$p")"
# S3 全勾 → 靜默（兩例：1 項全勾、3 項全勾）
p=$WORK/s3; make_repo "$p"; t=$WORK/st3; mkdir -p "$t"; write_ledger "$p" feature/x 0 '- [x] A'
check_empty "S3 全勾 → 靜默" "$(run_hook scope-stop-check.sh "$(stop_json s3 "$p" false)" "$t" "$p")"
write_ledger "$p" feature/x 0 '- [x] A' '- [x] B' '- [x] C'
check_empty "S3b 三項全勾 → 靜默" "$(run_hook scope-stop-check.sh "$(stop_json s3 "$p" false)" "$t" "$p")"
# S4 兩項未勾 → block、列出項目與數量；同狀態再停 → 靜默；狀態變（勾掉一項）→ 再 block 一次
p=$WORK/s4; make_repo "$p"; t=$WORK/st4; mkdir -p "$t"; write_ledger "$p" feature/x 0 '- [ ] 修三條路徑' '- [x] 補測試' '- [ ] 姊妹缺口'
rc=0; out=$(printf '%s' "$(stop_json s4 "$p" false)" | TMPDIR="$t" CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/scope-stop-check.sh" 2>/dev/null) || rc=$?
check "S4 未勾 → block" "$out" '"decision":"block"'
check "S4 exit 0" "$rc" '^0$'
check "S4 數量 2" "$out" '2 項'
check "S4 列出項目 1" "$out" '修三條路徑'
check "S4 列出項目 2" "$out" '姊妹缺口'
check_flag "S4 記錄狀態" "$t/claude-scope-stop-s4" exists
check_empty "S4b 同狀態再停 → 靜默" "$(run_hook scope-stop-check.sh "$(stop_json s4 "$p" false)" "$t" "$p")"
write_ledger "$p" feature/x 0 '- [x] 修三條路徑' '- [x] 補測試' '- [ ] 姊妹缺口'
out=$(run_hook scope-stop-check.sh "$(stop_json s4 "$p" false)" "$t" "$p")
check "S4c 狀態變 → 再 block" "$out" '"decision":"block"'
check "S4c 數量 1" "$out" '1 項'
check_empty "S4d 又同狀態 → 靜默" "$(run_hook scope-stop-check.sh "$(stop_json s4 "$p" false)" "$t" "$p")"
# S5 不同 session 各自記狀態
check "S5 另一 session 同帳本 → block" "$(run_hook scope-stop-check.sh "$(stop_json s5 "$p" false)" "$t" "$p")" '"decision":"block"'
# S6 畸形帳本（無 In scope 段）→ 靜默
p=$WORK/s6; make_repo "$p"; t=$WORK/st6; mkdir -p "$t"; printf 'goal only\n' > "$p/.claude/scope-ledger.local.md"
check_empty "S6 畸形帳本 → 靜默" "$(run_hook scope-stop-check.sh "$(stop_json s6 "$p" false)" "$t" "$p")"

# ===== scope-session-start.sh =====
start_json() { printf '{"session_id":"%s","cwd":"%s","hook_event_name":"SessionStart","source":"%s"}' "$1" "$2" "$3"; }
# T1 無帳本 → 靜默（兩種 source）
p=$WORK/t1; make_repo "$p"; t=$WORK/tt1; mkdir -p "$t"
check_empty "T1 無帳本 startup → 靜默" "$(run_hook scope-session-start.sh "$(start_json s1 "$p" startup)" "$t" "$p")"
check_empty "T1 無帳本 compact → 靜默" "$(run_hook scope-session-start.sh "$(start_json s1 "$p" compact)" "$t" "$p")"
# T2 有帳本 → 印 goal、未完成數、輪數
p=$WORK/t2; make_repo "$p"; t=$WORK/tt2; mkdir -p "$t"; write_ledger "$p" feature/x 2 '- [ ] A' '- [x] B' '- [ ] C'
out=$(run_hook scope-session-start.sh "$(start_json s2 "$p" compact)" "$t" "$p")
check "T2 含 goal" "$out" '修好通知漏發'
check "T2 未完成 2 項" "$out" '未完成 2 項'
check "T2 review 2 輪" "$out" '2 輪'
check "T2 含清單行" "$out" '- \[ \] C'
# T2b 全勾 → 仍印（未完成 0 項）
write_ledger "$p" feature/x 0 '- [x] A'
check "T2b 全勾仍印、0 項" "$(run_hook scope-session-start.sh "$(start_json s2 "$p" resume)" "$t" "$p")" '未完成 0 項'
# T3 hooks.json 合法且四個事件都掛
if [ -f "$HOOKS/hooks.json" ]; then
  check "T3 hooks.json PreToolUse" "$(jq -r '.hooks.PreToolUse[0].matcher' "$HOOKS/hooks.json")" 'Edit|Write|MultiEdit|NotebookEdit'
  check "T3 hooks.json PostToolUse" "$(jq -r '.hooks.PostToolUse[0].matcher' "$HOOKS/hooks.json")" 'Skill|Agent'
  check "T3 hooks.json Stop" "$(jq -r '.hooks.Stop[0].hooks[0].command' "$HOOKS/hooks.json")" 'scope-stop-check.sh'
  check "T3 hooks.json SessionStart" "$(jq -r '.hooks.SessionStart[0].matcher' "$HOOKS/hooks.json")" 'startup|resume|compact|clear'
  # T4 每個被 hooks.json 指到的腳本都存在
  for s in $(jq -r '.. | .command? // empty' "$HOOKS/hooks.json" | sed -E 's#.*/hooks/([^"]+)".*#\1#'); do
    check_flag "T4 $s 存在" "$HOOKS/$s" exists
  done
else
  FAIL=$((FAIL+1)); echo "FAIL: T3 hooks.json 不存在"
fi

# ---- summary ----
echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
