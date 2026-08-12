#!/bin/bash
# openspec-superpowers-workflow skip-gate hook fixture 測試
# 用法:bash plugins/openspec-superpowers-workflow/tests/skip-gate.test.sh
# 消費者:提交前手跑 + CI(.github/workflows/validate.yml)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/../hooks/skip-gate.sh"
PASS=0; FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ---- helpers ----

# run_gate <input_json> <tmpdir> <project_dir>
run_gate() {
  printf '%s' "$1" | TMPDIR="$2" CLAUDE_PROJECT_DIR="$3" bash "$GATE" 2>/dev/null || true
}

# check <名稱> <實際輸出> <期望子字串>
check() {
  if echo "$2" | grep -q "$3"; then
    PASS=$((PASS+1)); echo "PASS: $1"
  else
    FAIL=$((FAIL+1)); echo "FAIL: $1 — got: $2"
  fi
}

# check_empty <名稱> <實際輸出>(allow = 靜默放行,無輸出)
check_empty() {
  if [ -z "$2" ]; then
    PASS=$((PASS+1)); echo "PASS: $1"
  else
    FAIL=$((FAIL+1)); echo "FAIL: $1 — expected empty, got: $2"
  fi
}

# check_flag <名稱> <flag 路徑> <expect:exists|absent>
check_flag() {
  if [ "$3" = "exists" ] && [ -f "$2" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  elif [ "$3" = "absent" ] && [ ! -f "$2" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — flag state wrong: $2"; fi
}

# input_json <session_id> <cwd> <file_path>
input_json() {
  printf '{"session_id":"%s","cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" "$2" "$3"
}

# make_proj <dir> [active|archive-only|no-changes]:建 openspec 專案 fixture
make_proj() {
  mkdir -p "$1/openspec/specs" "$1/src"
  case "${2:-}" in
    active)       mkdir -p "$1/openspec/changes/add-foo" ;;
    archive-only) mkdir -p "$1/openspec/changes/archive/old-change" ;;
    no-changes)   : ;;
    *)            mkdir -p "$1/openspec/changes" ;;
  esac
}

# ---- cases ----

# 1) 非 openspec 專案(無 openspec/ 目錄)→ allow
p=$WORK/p1; mkdir -p "$p/src"; t=$WORK/t1; mkdir -p "$t"
out=$(run_gate "$(input_json s1 "$p" "$p/src/a.php")" "$t" "$p")
check_empty "1 非 openspec 專案 → allow" "$out"
check_flag  "1 非 openspec 專案 → 不留 flag" "$t/claude-openspec-skip-gate-s1" absent

# 2) openspec 專案 + changes/ 空 + 編輯專案內程式檔 → deny + 留 flag
p=$WORK/p2; make_proj "$p"; t=$WORK/t2; mkdir -p "$t"
rc=0
out=$(printf '%s' "$(input_json s2 "$p" "$p/src/a.php")" | TMPDIR="$t" CLAUDE_PROJECT_DIR="$p" bash "$GATE" 2>/dev/null) || rc=$?
check "2 無 active change 首次編輯 → deny" "$out" '"permissionDecision":"deny"'
check "2 deny 以 exit 0 交付 JSON 決策" "$rc" '^0$'
check "2 deny 訊息含契約面清單" "$out" '契約面'
check_flag "2 deny 後留 flag" "$t/claude-openspec-skip-gate-s2" exists

# 3a) flag 剛建立(同一並行批次的手足編輯,批次窗內)→ 續 deny
#     (cross-vendor review 抓到的繞過:首批多檔編輯只攔得住一個)
out=$(run_gate "$(input_json s2 "$p" "$p/src/b.php")" "$t" "$p")
check "3a 批次窗內手足編輯 → 續 deny" "$out" '"permissionDecision":"deny"'

# 3b) flag 已過批次窗(真正的重試)→ allow
touch -t 202001010000 "$t/claude-openspec-skip-gate-s2"
out=$(run_gate "$(input_json s2 "$p" "$p/src/b.php")" "$t" "$p")
check_empty "3b 批次窗外重試 → allow" "$out"

# 3c) 批次窗內但目標是豁免路徑(同批寫 openspec/ 的 workflow 動作)→ allow
#     (路徑豁免必須先於批次窗判斷,否則誤傷合法 workflow 寫入)
p3c=$WORK/p3c; make_proj "$p3c"; t3c=$WORK/t3c; mkdir -p "$t3c"
out=$(run_gate "$(input_json s3c "$p3c" "$p3c/src/a.php")" "$t3c" "$p3c")
check "3c 前置:首次編輯 deny" "$out" '"permissionDecision":"deny"'
out=$(run_gate "$(input_json s3c "$p3c" "$p3c/openspec/changes/new/proposal.md")" "$t3c" "$p3c")
check_empty "3c 批次窗內豁免路徑 → allow" "$out"

# 4) active change 存在 → allow(workflow 已啟動)
p=$WORK/p4; make_proj "$p" active; t=$WORK/t4; mkdir -p "$t"
out=$(run_gate "$(input_json s4 "$p" "$p/src/a.php")" "$t" "$p")
check_empty "4 active change 存在 → allow" "$out"
check_flag  "4 allow 不消耗 flag" "$t/claude-openspec-skip-gate-s4" absent

# 5) changes/ 只有 archive/ → deny(archive 不算 active)
p=$WORK/p5; make_proj "$p" archive-only; t=$WORK/t5; mkdir -p "$t"
out=$(run_gate "$(input_json s5 "$p" "$p/src/a.php")" "$t" "$p")
check "5 只有 archive → deny" "$out" '"permissionDecision":"deny"'

# 6) 編輯 openspec/ 內檔案(寫 proposal/spec 本身)→ allow
p=$WORK/p6; make_proj "$p"; t=$WORK/t6; mkdir -p "$t"
out=$(run_gate "$(input_json s6 "$p" "$p/openspec/changes/new-change/proposal.md")" "$t" "$p")
check_empty "6 編輯 openspec/ 內檔案 → allow" "$out"

# 7) 編輯 .claude/ 內檔案 → allow
out=$(run_gate "$(input_json s7 "$p" "$p/.claude/settings.json")" "$t" "$p")
check_empty "7 編輯 .claude/ 內檔案 → allow" "$out"

# 8) 編輯專案外路徑(scratchpad 等)→ allow
out=$(run_gate "$(input_json s8 "$p" "$WORK/elsewhere/x.md")" "$t" "$p")
check_empty "8 專案外路徑 → allow" "$out"

# 9) tool_input 無 file_path(不明工具形狀)→ allow(fail-open)
out=$(printf '{"session_id":"s9","cwd":"%s","tool_name":"Edit","tool_input":{}}' "$p" | TMPDIR="$t" CLAUDE_PROJECT_DIR="$p" bash "$GATE" 2>/dev/null || true)
check_empty "9 無 file_path → allow" "$out"

# 10) openspec/ 存在但 changes/ 目錄不存在 → deny(視同無 active change)
p=$WORK/p10; make_proj "$p" no-changes; t=$WORK/t10; mkdir -p "$t"
out=$(run_gate "$(input_json s10 "$p" "$p/src/a.php")" "$t" "$p")
check "10 無 changes/ 目錄 → deny" "$out" '"permissionDecision":"deny"'

# 11) session_id 含路徑穿越字元 → 消毒後 flag 仍落在 TMPDIR 內
p=$WORK/p11; make_proj "$p"; t=$WORK/t11; mkdir -p "$t"
out=$(run_gate "$(input_json 's11/../evil' "$p" "$p/src/a.php")" "$t" "$p")
check "11 session_id 消毒後仍 deny" "$out" '"permissionDecision":"deny"'
check_flag "11 flag 落在消毒後路徑" "$t/claude-openspec-skip-gate-s11_.._evil" exists

# ---- summary ----
echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
