#!/bin/bash
# gate-check.cjs fixture 測試（P1／P2 停或繼續的判定、設定檔、錯誤路徑）
# 用法:bash plugins/openspec-superpowers-workflow/tests/gate-check.test.sh   (GATE=<路徑> 測副本)
# 消費者:提交前手跑 + CI(.github/workflows/validate.yml 列舉 plugins/*/tests/*.test.sh)
# 每個停下的理由至少兩個觸發輸入；只有全部通過、且實際跑到的斷言數達下限才 exit 0——下限在案例清單之外計算
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE=${GATE:-"$SCRIPT_DIR/../skills/openspec-superpowers-workflow/validators/gate-check.cjs"}
command -v node >/dev/null 2>&1 || { echo "gate-check.test: node is required"; exit 1; }

TMPBASE="${TMPDIR:-/tmp}"
WORK=$(mktemp -d "${TMPBASE%/}/gate-check-test.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

# eq <名稱> <期望> <實際>
eq() {
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — expected [$2] got [$3]"; fi
}
# has <名稱> <檔案> <固定字串>
has() {
  if command grep -qF -- "$3" "$2" 2>/dev/null; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — $2 lacks [$3]"; fi
}

# new_project：建一個新的專案根目錄，印出路徑（在 $(…) 子 shell 裡呼叫，計數器帶不回來，所以用 mktemp）
new_project() { local p; p=$(mktemp -d "$WORK/p.XXXXXX") || exit 1; mkdir -p "$p/openspec/changes"; echo "$p"; }

# make_change <專案根> <名稱>：P1 與 P2 都會「繼續」的 change（ADDED-only、Decisions 只有 [default]），印出 change 目錄
make_change() {
  local d="$1/openspec/changes/$2"
  mkdir -p "$d/specs/api"
  cat > "$d/proposal.md" <<'EOF'
# Proposal

## Why
Invoices need exporting.

## What Changes
- Add an invoice export.

## Impact
- `src/export/invoice.ts`

## Decisions
- [default] export runs synchronously below 1000 rows
EOF
  cat > "$d/specs/api/spec.md" <<'EOF'
## ADDED Requirements

### Requirement: Export
The system SHALL export invoices.

#### Scenario: basic
- **WHEN** an admin exports
- **THEN** a file is produced
EOF
  cat > "$d/design.md" <<'EOF'
# Design

Decision: export runs as a queued job.

## Open Questions
- [default] keep files for 24 hours
EOF
  printf '## 1. Export\n### Task 1: export job\n- [ ] 1.1 export job with its test\n1. Write the failing test\n2. Implement\n### Task 2: download link\n- [ ] 2.1 download link with its test\n1. Write the failing test\n' > "$d/tasks.md"
  echo "$d"
}

# settings <專案根> <committed|local> <frontmatter 內容>
settings() {
  mkdir -p "$1/.claude"
  local f="$1/.claude/openspec-workflow.md"; [ "$2" = local ] && f="$1/.claude/openspec-workflow.local.md"
  printf '%s' "$3" > "$f"
}

# run <p1|p2|p3|p6b> <change 目錄>：結果在 $RC、$WORK/out.txt
run() { node "$GATE" "$1" "$2" > "$WORK/out.txt" 2>&1; RC=$?; }
first() { head -1 "$WORK/out.txt"; }
# fresh：新專案＋會「繼續」的 change，設定 $P、$D（不在子 shell 裡，變數帶得出來）
fresh() { P=$(new_project); D=$(make_change "$P" foo); }
# stops <名稱> <reason-id>：exit 10，且 stdout 有該理由行（兩條斷言）
stops() { eq "$1: exit 10" 10 "$RC"; has "$1: reason" "$WORK/out.txt" "- $2:"; }

# ---- 繼續的基準 ----
fresh; run p1 "$D"
eq "proceed-baseline: p1 exit 0" 0 "$RC"
eq "proceed-baseline: p1 first line" proceed "$(first)"
run p2 "$D"; eq "proceed-baseline: p2 exit 0" 0 "$RC"
run p3 "$D"; eq "proceed-baseline: p3 exit 0" 0 "$RC"
run p6b "$D"; eq "proceed-baseline: p6b exit 0" 0 "$RC"

# ---- supervised：四個確認點都停 ----
fresh; settings "$P" committed $'---\ngates: supervised\n---\n'; run p1 "$D"
stops "supervised p1" supervised; eq "supervised: first line" stop "$(first)"
run p2 "$D"; eq "supervised: p2 exit 10" 10 "$RC"
run p3 "$D"; stops "supervised p3" supervised
run p6b "$D"; stops "supervised p6b" supervised
fresh; settings "$P" committed $'---\ngates: risk-based\n---\n'; settings "$P" local $'---\ngates: supervised\n---\n'; run p1 "$D"
eq "supervised-local-overrides: exit 10" 10 "$RC"
fresh; settings "$P" committed $'---\ngates: supervised\n---\n'; settings "$P" local $'---\ngates: risk-based\n---\n'; run p1 "$D"
eq "local-risk-based-overrides: exit 0" 0 "$RC"

# ---- 設定讀不懂 → 偏向問人 ----
fresh; settings "$P" committed $'---\ngates: risk_based\n---\n'; run p1 "$D"
stops "settings-typo" settings-unreadable
run p2 "$D"; eq "settings-typo: p2 exit 10" 10 "$RC"
run p6b "$D"; stops "settings-typo p6b" settings-unreadable
fresh; settings "$P" local $'---\ngates: risk-based\n'; run p1 "$D"
stops "settings-garbage" settings-unreadable
run p3 "$D"; stops "settings-garbage p3" settings-unreadable

# ---- no-decisions-section ----
fresh; perl -0pi -e 's/## Decisions\n.*\z//s' "$D/proposal.md"; run p1 "$D"
stops "no-decisions-section (missing)" no-decisions-section
fresh; perl -pi -e 's/^## Decisions$/## Decision/' "$D/proposal.md"; run p1 "$D"
stops "no-decisions-section (singular heading)" no-decisions-section

# ---- needs-user ----
fresh; printf -- '- [needs user] pick (a) strict or (b) lenient\n' >> "$D/proposal.md"; run p1 "$D"
stops "needs-user (dash)" needs-user
fresh; printf -- '* [Needs User] who may export\n' >> "$D/proposal.md"; run p1 "$D"
stops "needs-user (star, mixed case)" needs-user
fresh; printf -- '<!--\n- [needs user] example only\n-->\n' >> "$D/proposal.md"; run p1 "$D"
eq "needs-user-in-comment: exit 0" 0 "$RC"
fresh; printf -- '```\n- [needs user] example only\n```\n' >> "$D/proposal.md"; run p1 "$D"
eq "needs-user-in-fence: exit 0" 0 "$RC"
fresh; perl -pi -e 's/^- `src\/export\/invoice.ts`$/- `src\/export\/invoice.ts`\n- [needs user] outside the Decisions section/' "$D/proposal.md"; run p1 "$D"
eq "needs-user outside Decisions: exit 0" 0 "$RC"

# ---- breaking ----
fresh; perl -pi -e 's/^- Add an invoice export\.$/- **BREAKING** drop the CSV export/' "$D/proposal.md"; run p1 "$D"
stops "breaking (marker)" breaking
fresh; perl -pi -e 's/^Invoices need exporting\.$/This is a BREAKING change for API clients./' "$D/proposal.md"; run p1 "$D"
stops "breaking (inline word)" breaking
fresh; printf '<!-- Mark breaking changes with **BREAKING** -->\n' >> "$D/proposal.md"; run p1 "$D"
eq "breaking only in a comment: exit 0" 0 "$RC"

# ---- delta-modified ----
for kind in MODIFIED REMOVED RENAMED; do
  fresh; mkdir -p "$D/specs/billing"
  printf '## %s Requirements\n\n### Requirement: Old\nThe system SHALL do the old thing.\n' "$kind" > "$D/specs/billing/spec.md"; run p1 "$D"
  eq "delta-modified ($kind): exit 10" 10 "$RC"; has "delta-modified ($kind): detail names the heading" "$WORK/out.txt" "$kind"
done
fresh; printf '## MODIFIED Requirements\r\n\r\n### Requirement: Old\r\nThe system SHALL change.\r\n' > "$D/specs/api/spec.md"; run p1 "$D"
stops "crlf" delta-modified
# CRLF 設定檔（Windows checkout）：front matter 仍讀得懂，不會被誤判成 settings-unreadable 而一律停
fresh; settings "$P" committed $'---\r\ngates: risk-based\r\n---\r\n'; run p1 "$D"
eq "crlf settings: risk-based proceeds" 0 "$RC"
fresh; settings "$P" committed $'---\r\nhigh_risk_paths:\r\n  - src/export/**\r\n---\r\n'; run p1 "$D"
eq "crlf settings: high_risk_paths still match" 10 "$RC"

# ---- high-risk-path ----
for form in '- `src/auth/login.ts`' '- ./src/auth/x.ts' '- src/auth/y.ts changes'; do
  fresh; settings "$P" committed $'---\nhigh_risk_paths:\n  - src/auth/**\n---\n'
  F="$form" perl -pi -e 's/^- `src\/export\/invoice.ts`$/$ENV{F}/' "$D/proposal.md"; run p1 "$D"
  stops "impact-path-forms ($form)" high-risk-path
done
fresh; settings "$P" committed $'---\nhigh_risk_paths:\n  - src/auth/**\n---\n'; run p1 "$D"
eq "impact-no-match: exit 0" 0 "$RC"
fresh; settings "$P" committed $'---\nhigh_risk_paths:\n  - src/*.ts\n---\n'
perl -pi -e 's/^- `src\/export\/invoice.ts`$/- `src\/export\/invoice.ts`\n- `src\/main.ts`/' "$D/proposal.md"; run p1 "$D"
eq "single star matches one level: exit 10" 10 "$RC"
fresh; settings "$P" committed $'---\nhigh_risk_paths:\n  - src/*.ts\n---\n'; run p1 "$D"
eq "single star does not cross a slash: exit 0" 0 "$RC"

# ---- 設定的 YAML 寫法：讀得懂就照讀，讀不懂就停，不可靜默變成空清單 ----
fresh; settings "$P" committed $'---\nhigh_risk_paths:\n- src/export/**\n---\n'; run p1 "$D"
stops "yaml list item at column 0" high-risk-path
fresh; settings "$P" committed $'---\nhigh_risk_paths:\n  - src/export/**   # export code\n---\n'; run p1 "$D"
stops "yaml list item with a trailing comment" high-risk-path
fresh; settings "$P" committed $'---\ngates: risk-based   # or supervised\n---\n'; run p1 "$D"
eq "yaml gates with a trailing comment proceeds" 0 "$RC"
fresh; settings "$P" local $'---\nhigh_risk_paths: [src/export/**]\n---\n'; run p1 "$D"
stops "yaml flow list is not read silently" settings-unreadable
fresh; settings "$P" committed $'---\nhigh_risk_paths: src/export/**\n---\n'; run p1 "$D"
stops "yaml inline scalar is not read silently" settings-unreadable
fresh; settings "$P" committed $'---\nhigh_risk_paths:\n\n  - src/export/**\n---\n'; run p1 "$D"
stops "yaml blank line inside the list" high-risk-path
fresh; settings "$P" committed $'---\nhigh_risk_paths:\n  # export code\n  - src/export/**\n---\n'; run p1 "$D"
stops "yaml comment line inside the list" high-risk-path
# 根目錄檔名（沒有 /）也是路徑
fresh; settings "$P" committed $'---\nhigh_risk_paths:\n  - Dockerfile\n---\n'
perl -pi -e 's/^- `src\/export\/invoice.ts`$/- `src\/export\/invoice.ts`\n- `Dockerfile`/' "$D/proposal.md"; run p1 "$D"
stops "root-level file name in Impact" high-risk-path
# 設計文件 §4.6 範例的原文（註解、縮排清單）照常解析
fresh; settings "$P" committed $'---\ngates: risk-based        # 或 supervised\nhigh_risk_paths:         # 選填，glob\n  - app/Http/Middleware/**\n  - src/auth/**\n---\n'; run p1 "$D"
eq "design doc example parses (no match, proceeds)" 0 "$RC"

# ---- 錯誤路徑 ----
fresh; mkdir -p "$WORK/elsewhere/foo"; cp "$D/proposal.md" "$WORK/elsewhere/foo/"; run p1 "$WORK/elsewhere/foo"
eq "bad-change-dir (not under openspec/changes): exit 1" 1 "$RC"; has "bad-change-dir: message" "$WORK/out.txt" "not under openspec/changes"
fresh; rm "$D/proposal.md"; run p1 "$D"
eq "bad-change-dir (no proposal.md): exit 1" 1 "$RC"
run p9 "$D"; eq "unknown gate: exit 1" 1 "$RC"
node "$GATE" > "$WORK/out.txt" 2>&1; eq "no arguments: exit 1" 1 "$?"

# ---- P2 ----
fresh; printf -- '- [needs user] who sees the archive\n' >> "$D/design.md"; run p2 "$D"
stops "p2-needs-user (dash)" design-needs-user
fresh; printf -- '* [NEEDS USER] retention period\n' >> "$D/design.md"; run p2 "$D"
eq "p2-needs-user (star, upper case): exit 10" 10 "$RC"
fresh; run p2 "$D"
eq "p2-defaults-only: exit 0" 0 "$RC"
fresh; printf '# Design\n\nDecision: queued job.\n' > "$D/design.md"; run p2 "$D"
eq "p2-no-open-questions: exit 0" 0 "$RC"
fresh; printf '# Design\n\n- [needs user] not under Open Questions\n' > "$D/design.md"; run p2 "$D"
eq "p2 needs-user outside Open Questions: exit 0" 0 "$RC"
fresh; perl -pi -e 's/^- \[default\] export runs.*$/- [needs user] p1 item/' "$D/proposal.md"; run p2 "$D"
eq "p2 ignores proposal needs-user: exit 0" 0 "$RC"

# ---- P2：讀不到 design.md 不能當成「沒有問題」 ----
fresh; rm "$D/design.md"; run p2 "$D"
stops "p2 design.md missing" design-unreadable
fresh; rm "$D/design.md"; mkdir "$D/design.md"; run p2 "$D"
stops "p2 design.md unreadable (a directory)" design-unreadable

# ---- P3：tasks.md 格式（每個 ### Task 恰好一個勾選框）不合格 → exit 1，修好再跑 ----
fresh; printf -- '- [ ] 1.2 a second box\n' >> "$D/tasks.md"; run p3 "$D"
eq "p3 a Task with two checkboxes: exit 1" 1 "$RC"; has "p3 two checkboxes: message names the Task" "$WORK/out.txt" "Task 2"
fresh; perl -0pi -e 's/- \[ \] 2\.1 download link with its test\n//' "$D/tasks.md"; run p3 "$D"
eq "p3 a Task with no checkbox: exit 1" 1 "$RC"
fresh; printf '# Tasks\n\n- [ ] do everything\n' > "$D/tasks.md"; run p3 "$D"
eq "p3 no ### Task heading: exit 1" 1 "$RC"
fresh; rm "$D/tasks.md"; run p3 "$D"
eq "p3 tasks.md missing: exit 1" 1 "$RC"
fresh; printf -- '<!--\n- [ ] 2.2 example\n-->\n' >> "$D/tasks.md"; run p3 "$D"
eq "p3 a checkbox inside a comment does not count: exit 0" 0 "$RC"

# ---- P3／P6b：只看設定，不看 change 內容 ----
fresh; printf -- '- [needs user] pick one\n' >> "$D/proposal.md"; perl -pi -e 's/^- Add an invoice export\.$/- **BREAKING** drop it/' "$D/proposal.md"; run p3 "$D"
eq "p3 ignores proposal triggers: exit 0" 0 "$RC"
run p6b "$D"; eq "p6b ignores proposal triggers: exit 0" 0 "$RC"

# ---- require 不執行 main ----
out=$(node -e 'const m = require(process.argv[1]); process.stdout.write([typeof m.checkP1, typeof m.checkP2, typeof m.readSettings].join(","))' "$GATE" 2>&1)
eq "require exports the three functions without running main" "function,function,function" "$out"

# ---- summary ----
MIN=100
if [ "$((PASS + FAIL))" -lt "$MIN" ]; then
  echo "FAIL: ran $((PASS + FAIL)) assertions, expected at least $MIN"; FAIL=$((FAIL+1))
fi
echo "gate-check: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
