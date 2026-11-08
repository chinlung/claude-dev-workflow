#!/bin/bash
# openspec-superpowers-workflow skip-gate v2 hook fixture 測試
# 用法:bash plugins/openspec-superpowers-workflow/tests/skip-gate.test.sh   (GATE=<路徑> 測副本)
# 消費者:提交前手跑 + CI(.github/workflows/validate.yml 列舉 plugins/*/tests/*.test.sh)
# 只有全部通過、且實際跑到的斷言數達下限才 exit 0
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE=${GATE:-"$SCRIPT_DIR/../hooks/skip-gate.sh"}
PASS=0; FAIL=0

# 帶模板：無模板的 mktemp -d 在 macOS 會落到 /var/folders/.../T/，Claude Code sandbox 只准寫 $TMPDIR，致整套假紅
TMPBASE="${TMPDIR:-/tmp}"
WORK=$(mktemp -d "${TMPBASE%/}/skip-gate-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

ALL_NO='契約面：API=否 資料=否 schema=否 migration=否 相容=否 權限=否 並行=否 跨模組=否 ｜ 理由：單一模組的錯字修正'

# ---- helpers ----

# run_gate <input_json> <tmpdir> <project_dir>
run_gate() {
  printf '%s' "$1" | TMPDIR="$2" CLAUDE_PROJECT_DIR="$3" bash "$GATE" 2>/dev/null || true
}

# check <名稱> <實際輸出> <期望子字串(固定字串)>
check() {
  if printf '%s' "$2" | grep -qF -- "$3"; then
    PASS=$((PASS+1)); echo "PASS: $1"
  else
    FAIL=$((FAIL+1)); echo "FAIL: $1 — got: $(printf '%s' "$2" | head -c 300)"
  fi
}

# check_empty <名稱> <實際輸出>(allow = 靜默放行,無輸出)
check_empty() {
  if [ -z "$2" ]; then
    PASS=$((PASS+1)); echo "PASS: $1"
  else
    FAIL=$((FAIL+1)); echo "FAIL: $1 — expected empty, got: $(printf '%s' "$2" | head -c 300)"
  fi
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

# decl <專案> <session>:聲明檔路徑；write_decl <專案> <session> <聲明行>
decl() { printf '%s' "$1/.claude/openspec-skip.$2.local.md"; }
write_decl() { mkdir -p "$1/.claude"; printf '# SKIP 判定\n\n%s\n' "$3" > "$(decl "$1" "$2")"; }

DENY='"permissionDecision":"deny"'

# ---- cases ----

# 1) 非 openspec 專案(無 openspec/ 目錄)→ allow
p=$WORK/p1; mkdir -p "$p/src"; t=$WORK/t1; mkdir -p "$t"
out=$(run_gate "$(input_json s1 "$p" "$p/src/a.php")" "$t" "$p")
check_empty "1 非 openspec 專案 → allow" "$out"

# 2) 無 active change、沒有聲明檔 → deny,訊息給出聲明檔路徑與可複製的格式行
p=$WORK/p2; make_proj "$p"; t=$WORK/t2; mkdir -p "$t"
rc=0
out=$(printf '%s' "$(input_json s2 "$p" "$p/src/a.php")" | TMPDIR="$t" CLAUDE_PROJECT_DIR="$p" bash "$GATE" 2>/dev/null) || rc=$?
check "2 缺聲明檔 → deny" "$out" "$DENY"
check "2 deny 以 exit 0 交付 JSON 決策" "$rc" "0"
check "2 deny 訊息含聲明檔路徑" "$out" "$(decl "$p" s2)"
check "2 deny 訊息含格式行" "$out" "契約面：API=否"

# 2b) 同一批並行編輯:沒有聲明時第二個編輯照樣 deny
out=$(run_gate "$(input_json s2 "$p" "$p/src/b.php")" "$t" "$p")
check "2b 同批第二個編輯 → 續 deny" "$out" "$DENY"

# 2c) CLAUDE_PROJECT_DIR 帶尾斜線 → 仍視為專案內,照樣 deny(尾斜線不得讓閘門整個失效)
out=$(run_gate "$(input_json s2 "$p" "$p/src/a.php")" "$t" "$p/")
check "2c 專案目錄尾斜線 → 仍 deny" "$out" "$DENY"

# 3) 寫了八面全「否」的聲明 → allow
write_decl "$p" s2 "$ALL_NO"
out=$(run_gate "$(input_json s2 "$p" "$p/src/a.php")" "$t" "$p")
check_empty "3 八面全否 → allow" "$out"

# 3b) 半形冒號與多空白(Review Focus 3)→ allow
write_decl "$p" s3b '契約面:  API=否  資料=否 schema=否 migration=否 相容=否 權限=否 並行=否 跨模組=否 | 理由: x'
out=$(run_gate "$(input_json s3b "$p" "$p/src/a.php")" "$t" "$p")
check_empty "3b 半形冒號與多空白 → allow" "$out"

# 4) active change 存在 → allow(workflow 已啟動)
p=$WORK/p4; make_proj "$p" active; t=$WORK/t4; mkdir -p "$t"
out=$(run_gate "$(input_json s4 "$p" "$p/src/a.php")" "$t" "$p")
check_empty "4 active change 存在 → allow" "$out"

# 5) changes/ 只有 archive/ → deny(archive 不算 active)
p=$WORK/p5; make_proj "$p" archive-only; t=$WORK/t5; mkdir -p "$t"
out=$(run_gate "$(input_json s5 "$p" "$p/src/a.php")" "$t" "$p")
check "5 只有 archive → deny" "$out" "$DENY"

# 6)–9) 豁免路徑與不明工具形狀
p=$WORK/p6; make_proj "$p"; t=$WORK/t6; mkdir -p "$t"
out=$(run_gate "$(input_json s6 "$p" "$p/openspec/changes/new-change/proposal.md")" "$t" "$p")
check_empty "6 編輯 openspec/ 內檔案 → allow" "$out"
out=$(run_gate "$(input_json s7 "$p" "$p/.claude/settings.json")" "$t" "$p")
check_empty "7 編輯 .claude/ 內檔案 → allow" "$out"
out=$(run_gate "$(input_json s8 "$p" "$WORK/elsewhere/x.php")" "$t" "$p")
check_empty "8 專案外路徑 → allow" "$out"
out=$(printf '{"session_id":"s9","cwd":"%s","tool_name":"Edit","tool_input":{}}' "$p" | TMPDIR="$t" CLAUDE_PROJECT_DIR="$p" bash "$GATE" 2>/dev/null || true)
check_empty "9 無 file_path → allow" "$out"

# 文件類路徑豁免
out=$(run_gate "$(input_json s12 "$p" "$p/README.md")" "$t" "$p"); check_empty "12 README.md → allow" "$out"
out=$(run_gate "$(input_json s12 "$p" "$p/docs/x.txt")" "$t" "$p"); check_empty "12 docs/ 下 → allow" "$out"
out=$(run_gate "$(input_json s12 "$p" "$p/doc/guide.adoc")" "$t" "$p"); check_empty "12 doc/ 下 → allow" "$out"

# 10) openspec/ 存在但 changes/ 目錄不存在 → deny(視同無 active change)
p=$WORK/p10; make_proj "$p" no-changes; t=$WORK/t10; mkdir -p "$t"
out=$(run_gate "$(input_json s10 "$p" "$p/src/a.php")" "$t" "$p")
check "10 無 changes/ 目錄 → deny" "$out" "$DENY"

# 11) session_id 含路徑穿越字元 → 聲明檔路徑經消毒
p=$WORK/p11; make_proj "$p"; t=$WORK/t11; mkdir -p "$t"
out=$(run_gate "$(input_json 's11/../evil' "$p" "$p/src/a.php")" "$t" "$p")
check "11 session_id 消毒後仍 deny" "$out" "$DENY"
check "11 聲明檔路徑經消毒" "$out" ".claude/openspec-skip.s11_.._evil.local.md"
write_decl "$p" 's11_.._evil' "$ALL_NO"
out=$(run_gate "$(input_json 's11/../evil' "$p" "$p/src/a.php")" "$t" "$p")
check_empty "11 消毒後路徑的聲明 → allow" "$out"

# 13) 聲明格式錯誤 → deny 並點名
p=$WORK/p13; make_proj "$p"; t=$WORK/t13; mkdir -p "$t"
write_decl "$p" s13 '契約面：API=否 資料=否 schema=否 migration=否 相容=否 權限=否 並行=否 ｜ 理由：x'
out=$(run_gate "$(input_json s13 "$p" "$p/src/a.php")" "$t" "$p")
check "13 缺 跨模組 → deny" "$out" "$DENY"
check "13 deny 點名缺的 key" "$out" "格式不符：跨模組"
write_decl "$p" s14 '契約面：API=可能 資料=否 schema=否 migration=否 相容=否 權限=否 並行=否 跨模組=否 ｜ 理由：x'
out=$(run_gate "$(input_json s14 "$p" "$p/src/a.php")" "$t" "$p")
check "14 值不是是／否 → deny" "$out" "$DENY"

# 15) 任何一面「是」→ deny,要求啟動 workflow
write_decl "$p" s15 '契約面：API=否 資料=否 schema=否 migration=否 相容=否 權限=否 並行=是 跨模組=否 ｜ 理由：x'
out=$(run_gate "$(input_json s15 "$p" "$p/src/a.php")" "$t" "$p")
check "15 並行=是 → deny" "$out" "$DENY"
check "15 deny 點名標為是的面" "$out" "標為「是」：並行"
write_decl "$p" s15b '契約面：API=是 資料=否 schema=否 migration=否 相容=否 權限=否 並行=否 跨模組=否 ｜ 理由：x'
out=$(run_gate "$(input_json s15b "$p" "$p/src/a.php")" "$t" "$p")
check "15b API=是 → deny" "$out" "$DENY"

# 16) 歸檔後:聲明必須比歸檔標記新
p=$WORK/p16; make_proj "$p"; t=$WORK/t16; mkdir -p "$t"
# mtime 用 touch -t 回填,不用 sleep 等時鐘(POSIX,BSD／GNU 同義)
touch -t 202001010000 "$t/claude-openspec-archived-s16"
out=$(run_gate "$(input_json s16 "$p" "$p/src/a.php")" "$t" "$p")
check "16 歸檔後沒有聲明 → deny" "$out" "$DENY"
check "16 歸檔後版本的訊息" "$out" "已歸檔"
write_decl "$p" s16 "$ALL_NO"
out=$(run_gate "$(input_json s16 "$p" "$p/src/a.php")" "$t" "$p")
check_empty "16 歸檔後寫的聲明 → allow" "$out"
write_decl "$p" s16b "$ALL_NO"; touch -t 202001010000 "$(decl "$p" s16b)"; touch "$t/claude-openspec-archived-s16b"
out=$(run_gate "$(input_json s16b "$p" "$p/src/a.php")" "$t" "$p")
check "16b 歸檔前寫的聲明 → deny" "$out" "$DENY"
check "16b 歸檔前的聲明 → 歸檔後版本的訊息" "$out" "已歸檔"
out=$(run_gate "$(input_json s16b "$p" "$p/src/b.php")" "$t" "$p")
check "16b 同 session 另一個檔 → 續 deny" "$out" "$DENY"

# ---- summary ----
MIN=34
if [ "$((PASS + FAIL))" -lt "$MIN" ]; then
  echo "FAIL: ran $((PASS + FAIL)) assertions, expected at least $MIN"; FAIL=$((FAIL+1))
fi
echo "skip-gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
