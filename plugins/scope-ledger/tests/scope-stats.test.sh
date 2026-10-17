#!/bin/bash
# scope-ledger: scope-stats.cjs tests
# 用法：bash plugins/scope-ledger/tests/scope-stats.test.sh
# 消費者：提交前手跑 + CI（.github/workflows/validate.yml）+ 本地 PostToolUse hook
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATS="$SCRIPT_DIR/../scripts/scope-stats.cjs"
PASS=0; FAIL=0

TMPBASE="${TMPDIR:-/tmp}"
WORK=$(mktemp -d "${TMPBASE%/}/scope-stats-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

check() {        # check <name> <actual> <expected substring (grep BRE)>
  if printf '%s' "$2" | grep -q -- "$3"; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — got: $2"; fi
}
check_eq() {     # check_eq <name> <actual> <expected exact>
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — expected [$3], got [$2]"; fi
}
jget() {
  node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const v = process.argv[2].split(".").reduce((a, k) => (a == null ? a : a[k]), j);
    console.log(v === undefined ? "undefined" : (typeof v === "object" ? JSON.stringify(v) : String(v)));
  ' "$1" "$2"
}

# ---- two projects: one with the 1.1.0 Log form, one with the 1.0.x form; a project-name with a hyphen ----
P1="$WORK/web/my-repo"; P2="$WORK/other"
mkdir -p "$P1/.claude" "$P2/.claude"
cat > "$P1/.claude/scope-ledger.local.md" <<'EOF'
---
goal: 修好通知漏發
mode: converge
opened: 2026-10-18
opened_on: feature/x
review_rounds: 3
---
## In scope
- [x] 修 handler ← 來源: user
- [ ] 補 retry 測試 ← 來源: code-audit-rigor:review-branch@r1
- [ ] 請使用者裁定：要不要改 API ← 來源: codex@r1
- [ ] 回 Copilot 的 nit ← 來源: pr-review-toolkit:review-pr@r1
## Deferred
- 舊 import 的 N+1 ← 來源: review-branch@r2 ｜ 嚴重度: LOW ｜ 理由: pre-existing ｜ 去處: follow-ups
## Log
- 2026-10-18 10:00 review-branch r1: 6 findings → 3 fixed / 1 deferred / 1 wrong / 1 intentional / 0 moot
- 2026-10-18 10:05 codex r1: 2 findings → 0 fixed / 0 deferred / 2 wrong / 0 intentional / 0 moot
- 2026-10-18 11:00 review-branch r2: 2 findings → 1 fixed / 1 deferred / 0 wrong / 0 intentional / 0 moot
- 2026-10-18 11:10 claude-security:scan r2: 3 findings → 1 fixed / 2 deferred / 0 wrong / 0 intentional / 0 moot
- 2026-10-18 PR #42 opened on feature/x
- 2026-10-18 11:30 code-review r3: 1 findings → something unreadable here
EOF
cat > "$P1/.claude/scope-followups.local.md" <<'EOF'
# scope-ledger follow-ups
- [ ] 2026-10-01 LOW old one ← from: earlier goal ｜ 來源: review-branch@r2 ｜ 去處: follow-ups
- [x] 2026-10-01 LOW done one ← from: earlier goal ｜ 來源: codex@r1 ｜ 去處: follow-ups
- [ ] 2026-10-02 MEDIUM english names ← from: earlier goal | source: security-review@r1 | where: issue #3
EOF
cat > "$P2/.claude/scope-ledger.local.md" <<'EOF'
---
goal: harvest things
mode: harvest
opened: 2026-09-23
opened_on: main
review_rounds: 1
---
## In scope
- [ ] fix A ← 來源: security-review@r1
## Deferred
## Log
- 2026-09-23 10:00 security-review r1: 5 findings → 2 adopted / 3 deferred / 0 noise
EOF

echo "== explicit --project, JSON"
node "$STATS" --project "$P1" --project "$P2" --json > "$WORK/out.json"
check_eq "ledgers scanned" "$(jget "$WORK/out.json" ledgers.length)" 2
check_eq "review-branch rounds summed across lines" "$(jget "$WORK/out.json" tools.review-branch.rounds)" 2
check_eq "review-branch findings" "$(jget "$WORK/out.json" tools.review-branch.findings)" 8
check_eq "review-branch fixed" "$(jget "$WORK/out.json" tools.review-branch.fixed)" 4
check_eq "review-branch deferred" "$(jget "$WORK/out.json" tools.review-branch.deferred)" 2
check_eq "review-branch wrong" "$(jget "$WORK/out.json" tools.review-branch.wrong)" 1
check_eq "review-branch intentional" "$(jget "$WORK/out.json" tools.review-branch.intentional)" 1
check_eq "review-branch precision (6/8)" "$(jget "$WORK/out.json" tools.review-branch.precision)" 75
check_eq "codex precision 0 when every finding was wrong" "$(jget "$WORK/out.json" tools.codex.precision)" 0
check_eq "legacy form: adopted → fixed" "$(jget "$WORK/out.json" tools.security-review.fixed)" 2
check_eq "legacy form: deferred kept" "$(jget "$WORK/out.json" tools.security-review.deferred)" 3
check_eq "legacy form: noise → wrong" "$(jget "$WORK/out.json" tools.security-review.wrong)" 0
check_eq "open In scope items per source (hook-qualified source code-audit-rigor:review-branch counts as review-branch)" "$(jget "$WORK/out.json" tools.review-branch.open)" 1
check_eq "no fragment row for the qualified name" "$(jget "$WORK/out.json" tools.code-audit-rigor:review-branch)" undefined
check_eq "a different plugin's same-named tool is NOT merged (pr-review-toolkit:review-pr stays qualified)" "$(jget "$WORK/out.json" tools.pr-review-toolkit:review-pr.open)" 1
check_eq "claude-security:scan merges into claude-security" "$(jget "$WORK/out.json" tools.claude-security.findings)" 3
check_eq "Deferred items per source" "$(jget "$WORK/out.json" tools.review-branch.deferredOpen)" 1
check_eq "follow-ups open per source (ticked line not counted)" "$(jget "$WORK/out.json" tools.review-branch.followupsOpen)" 1
check_eq "follow-ups: English field names accepted" "$(jget "$WORK/out.json" tools.security-review.followupsOpen)" 1
check_eq "unparseable Log line reported by number" "$(jget "$WORK/out.json" ledgers.0.unparsedLog)" '[21]'
check_eq "PR line is not a review round" "$(jget "$WORK/out.json" tools.code-review)" undefined

echo "== table output"
OUT=$(node "$STATS" --project "$P1" --project "$P2")
check "table: header" "$OUT" 'precision%'
check "table: review-branch row" "$OUT" '^review-branch *2 *8 *4 *2 *1 *1 *0 *75'
check "table: unparsed note" "$OUT" 'lines 21'

echo "== --all decodes project dir names against the file system"
ROOT="$WORK/projects"
mkdir -p "$ROOT"
# the encoding replaces every / with -; my-repo keeps its hyphen only because the directory exists
mkdir -p "$ROOT/$(printf '%s' "$P1" | tr '/' '-')" "$ROOT/$(printf '%s' "$P2" | tr '/' '-')" "$ROOT/-no-such-path-here"
node "$STATS" --all --projects-root "$ROOT" --project "$WORK/unrelated" --json > "$WORK/all.json"
check_eq "--all found both projects (unrelated has no ledger)" "$(jget "$WORK/all.json" ledgers.length)" 2
check "--all: hyphenated project decoded" "$(jget "$WORK/all.json" ledgers)" 'web/my-repo'

echo "== no ledgers"
OUT=$(node "$STATS" --project "$WORK/unrelated")
check "empty: says so" "$OUT" 'no review rounds recorded yet'

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
