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
  echo "$d"
}

# settings <專案根> <committed|local> <frontmatter 內容>
settings() {
  mkdir -p "$1/.claude"
  local f="$1/.claude/openspec-workflow.md"; [ "$2" = local ] && f="$1/.claude/openspec-workflow.local.md"
  printf '%s' "$3" > "$f"
}

# run <p1|p2> <change 目錄>：結果在 $RC、$WORK/out.txt
run() { node "$GATE" "$1" "$2" > "$WORK/out.txt" 2>&1; RC=$?; }
first() { head -1 "$WORK/out.txt"; }

# ---- 繼續的基準 ----
P=$(new_project); D=$(make_change "$P" foo); run p1 "$D"
eq "proceed-baseline: p1 exit 0" 0 "$RC"
eq "proceed-baseline: p1 first line" proceed "$(first)"
run p2 "$D"
eq "proceed-baseline: p2 exit 0" 0 "$RC"

# ---- supervised ----
P=$(new_project); D=$(make_change "$P" foo); settings "$P" committed $'---\ngates: supervised\n---\n'; run p1 "$D"
eq "supervised: p1 exit 10" 10 "$RC"; eq "supervised: first line" stop "$(first)"; has "supervised: reason" "$WORK/out.txt" "- supervised:"
run p2 "$D"; eq "supervised: p2 exit 10" 10 "$RC"
P=$(new_project); D=$(make_change "$P" foo)
settings "$P" committed $'---\ngates: risk-based\n---\n'; settings "$P" local $'---\ngates: supervised\n---\n'; run p1 "$D"
eq "supervised-local-overrides: exit 10" 10 "$RC"
P=$(new_project); D=$(make_change "$P" foo)
settings "$P" committed $'---\ngates: supervised\n---\n'; settings "$P" local $'---\ngates: risk-based\n---\n'; run p1 "$D"
eq "local-risk-based-overrides: exit 0" 0 "$RC"

# ---- 設定讀不懂 → 偏向問人 ----
P=$(new_project); D=$(make_change "$P" foo); settings "$P" committed $'---\ngates: risk_based\n---\n'; run p1 "$D"
eq "settings-typo: exit 10" 10 "$RC"; has "settings-typo: reason" "$WORK/out.txt" "- settings-unreadable:"
run p2 "$D"; eq "settings-typo: p2 exit 10" 10 "$RC"
P=$(new_project); D=$(make_change "$P" foo); settings "$P" local $'---\ngates: risk-based\n'; run p1 "$D"
eq "settings-garbage: exit 10" 10 "$RC"; has "settings-garbage: reason" "$WORK/out.txt" "- settings-unreadable:"

# ---- no-decisions-section ----
P=$(new_project); D=$(make_change "$P" foo); perl -0pi -e 's/## Decisions\n.*\z//s' "$D/proposal.md"; run p1 "$D"
eq "no-decisions-section (missing): exit 10" 10 "$RC"; has "no-decisions-section (missing): reason" "$WORK/out.txt" "- no-decisions-section:"
P=$(new_project); D=$(make_change "$P" foo); perl -pi -e 's/^## Decisions$/## Decision/' "$D/proposal.md"; run p1 "$D"
eq "no-decisions-section (singular heading): exit 10" 10 "$RC"; has "no-decisions-section (singular): reason" "$WORK/out.txt" "- no-decisions-section:"

# ---- needs-user ----
P=$(new_project); D=$(make_change "$P" foo); printf -- '- [needs user] pick (a) strict or (b) lenient\n' >> "$D/proposal.md"; run p1 "$D"
eq "needs-user (dash): exit 10" 10 "$RC"; has "needs-user (dash): reason" "$WORK/out.txt" "- needs-user:"
P=$(new_project); D=$(make_change "$P" foo); printf -- '* [Needs User] who may export\n' >> "$D/proposal.md"; run p1 "$D"
eq "needs-user (star, mixed case): exit 10" 10 "$RC"; has "needs-user (star): reason" "$WORK/out.txt" "- needs-user:"
P=$(new_project); D=$(make_change "$P" foo); printf -- '<!--\n- [needs user] example only\n-->\n' >> "$D/proposal.md"; run p1 "$D"
eq "needs-user-in-comment: exit 0" 0 "$RC"
P=$(new_project); D=$(make_change "$P" foo); printf -- '```\n- [needs user] example only\n```\n' >> "$D/proposal.md"; run p1 "$D"
eq "needs-user-in-fence: exit 0" 0 "$RC"
P=$(new_project); D=$(make_change "$P" foo); perl -pi -e 's/^- `src\/export\/invoice.ts`$/- `src\/export\/invoice.ts`\n- [needs user] outside the Decisions section/' "$D/proposal.md"; run p1 "$D"
eq "needs-user outside Decisions: exit 0" 0 "$RC"

# ---- breaking ----
P=$(new_project); D=$(make_change "$P" foo); perl -pi -e 's/^- Add an invoice export\.$/- **BREAKING** drop the CSV export/' "$D/proposal.md"; run p1 "$D"
eq "breaking (marker): exit 10" 10 "$RC"; has "breaking (marker): reason" "$WORK/out.txt" "- breaking:"
P=$(new_project); D=$(make_change "$P" foo); perl -pi -e 's/^Invoices need exporting\.$/This is a BREAKING change for API clients./' "$D/proposal.md"; run p1 "$D"
eq "breaking (inline word): exit 10" 10 "$RC"; has "breaking (inline): reason" "$WORK/out.txt" "- breaking:"
P=$(new_project); D=$(make_change "$P" foo); printf '<!-- Mark breaking changes with **BREAKING** -->\n' >> "$D/proposal.md"; run p1 "$D"
eq "breaking only in a comment: exit 0" 0 "$RC"

# ---- delta-modified ----
for kind in MODIFIED REMOVED RENAMED; do
  P=$(new_project); D=$(make_change "$P" foo); mkdir -p "$D/specs/billing"
  printf '## %s Requirements\n\n### Requirement: Old\nThe system SHALL do the old thing.\n' "$kind" > "$D/specs/billing/spec.md"; run p1 "$D"
  eq "delta-modified ($kind): exit 10" 10 "$RC"; has "delta-modified ($kind): detail names the heading" "$WORK/out.txt" "$kind"
done
P=$(new_project); D=$(make_change "$P" foo); printf '## MODIFIED Requirements\r\n\r\n### Requirement: Old\r\nThe system SHALL change.\r\n' > "$D/specs/api/spec.md"; run p1 "$D"
eq "crlf: exit 10" 10 "$RC"; has "crlf: reason" "$WORK/out.txt" "- delta-modified:"
# CRLF 設定檔（Windows checkout）：front matter 仍讀得懂，不會被誤判成 settings-unreadable 而一律停
P=$(new_project); D=$(make_change "$P" foo); settings "$P" committed $'---\r\ngates: risk-based\r\n---\r\n'; run p1 "$D"
eq "crlf settings: risk-based proceeds" 0 "$RC"
P=$(new_project); D=$(make_change "$P" foo); settings "$P" committed $'---\r\nhigh_risk_paths:\r\n  - src/export/**\r\n---\r\n'; run p1 "$D"
eq "crlf settings: high_risk_paths still match" 10 "$RC"

# ---- high-risk-path ----
for form in '- `src/auth/login.ts`' '- ./src/auth/x.ts' '- src/auth/y.ts changes'; do
  P=$(new_project); D=$(make_change "$P" foo); settings "$P" committed $'---\nhigh_risk_paths:\n  - src/auth/**\n---\n'
  F="$form" perl -pi -e 's/^- `src\/export\/invoice.ts`$/$ENV{F}/' "$D/proposal.md"; run p1 "$D"
  eq "impact-path-forms ($form): exit 10" 10 "$RC"; has "impact-path-forms ($form): reason" "$WORK/out.txt" "- high-risk-path:"
done
P=$(new_project); D=$(make_change "$P" foo); settings "$P" committed $'---\nhigh_risk_paths:\n  - src/auth/**\n---\n'; run p1 "$D"
eq "impact-no-match: exit 0" 0 "$RC"
P=$(new_project); D=$(make_change "$P" foo); settings "$P" committed $'---\nhigh_risk_paths:\n  - src/*.ts\n---\n'
perl -pi -e 's/^- `src\/export\/invoice.ts`$/- `src\/export\/invoice.ts`\n- `src\/main.ts`/' "$D/proposal.md"; run p1 "$D"
eq "single star matches one level: exit 10" 10 "$RC"
P=$(new_project); D=$(make_change "$P" foo); settings "$P" committed $'---\nhigh_risk_paths:\n  - src/*.ts\n---\n'; run p1 "$D"
eq "single star does not cross a slash: exit 0" 0 "$RC"

# ---- 錯誤路徑 ----
mkdir -p "$WORK/elsewhere/foo"; cp "$D/proposal.md" "$WORK/elsewhere/foo/"; run p1 "$WORK/elsewhere/foo"
eq "bad-change-dir (not under openspec/changes): exit 1" 1 "$RC"; has "bad-change-dir: message" "$WORK/out.txt" "not under openspec/changes"
P=$(new_project); D=$(make_change "$P" foo); rm "$D/proposal.md"; run p1 "$D"
eq "bad-change-dir (no proposal.md): exit 1" 1 "$RC"
node "$GATE" p9 "$D" > "$WORK/out.txt" 2>&1; eq "unknown gate: exit 1" 1 "$?"
node "$GATE" > "$WORK/out.txt" 2>&1; eq "no arguments: exit 1" 1 "$?"

# ---- P2 ----
P=$(new_project); D=$(make_change "$P" foo); printf -- '- [needs user] who sees the archive\n' >> "$D/design.md"; run p2 "$D"
eq "p2-needs-user (dash): exit 10" 10 "$RC"; has "p2-needs-user (dash): reason" "$WORK/out.txt" "- design-needs-user:"
P=$(new_project); D=$(make_change "$P" foo); printf -- '* [NEEDS USER] retention period\n' >> "$D/design.md"; run p2 "$D"
eq "p2-needs-user (star, upper case): exit 10" 10 "$RC"
P=$(new_project); D=$(make_change "$P" foo); run p2 "$D"
eq "p2-defaults-only: exit 0" 0 "$RC"
P=$(new_project); D=$(make_change "$P" foo); printf '# Design\n\nDecision: queued job.\n' > "$D/design.md"; run p2 "$D"
eq "p2-no-open-questions: exit 0" 0 "$RC"
P=$(new_project); D=$(make_change "$P" foo); printf '# Design\n\n- [needs user] not under Open Questions\n' > "$D/design.md"; run p2 "$D"
eq "p2 needs-user outside Open Questions: exit 0" 0 "$RC"
P=$(new_project); D=$(make_change "$P" foo); perl -pi -e 's/^- \[default\] export runs.*$/- [needs user] p1 item/' "$D/proposal.md"; run p2 "$D"
eq "p2 ignores proposal needs-user: exit 0" 0 "$RC"

# ---- require 不執行 main ----
out=$(node -e 'const m = require(process.argv[1]); process.stdout.write([typeof m.checkP1, typeof m.checkP2, typeof m.readSettings].join(","))' "$GATE" 2>&1)
eq "require exports the three functions without running main" "function,function,function" "$out"

# ---- summary ----
MIN=62
if [ "$((PASS + FAIL))" -lt "$MIN" ]; then
  echo "FAIL: ran $((PASS + FAIL)) assertions, expected at least $MIN"; FAIL=$((FAIL+1))
fi
echo "gate-check: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
