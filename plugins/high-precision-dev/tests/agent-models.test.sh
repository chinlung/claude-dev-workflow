#!/bin/bash
# high-precision-dev: the judgment agents run on opus, and /start dispatches them with model="opus"
# 用法：bash plugins/high-precision-dev/tests/agent-models.test.sh
# 消費者：提交前手跑 + CI（.github/workflows/validate.yml）+ 本地 PostToolUse hook
#
# critic, adversary, disproof-agent and verifier decide whether an implementation has a problem.
# 1.5.0 put critic and disproof-agent on sonnet for cross-family decorrelation; 1.6.0 moves them to
# opus (a review that misses a bug is never discovered, so it does not get the cheaper tier) and
# leaves decorrelation to a different vendor's pass. The implementers are products checked by the
# Phase 4 tests and are not pinned here.
#
# /start names the model on each judgment dispatch (a PreToolUse model-floor hook, where one is
# installed, cannot see a named agent's frontmatter and bounces a dispatch without a model). The
# explicit value overrides the frontmatter, so each dispatch must equal its agent's frontmatter.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$SCRIPT_DIR/.."
START="$PLUGIN/commands/start.md"
JUDGES=(critic adversary disproof-agent verifier)
PASS=0; FAIL=0

check_eq() {     # check_eq <name> <actual> <expected exact>
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — expected [$3], got [$2]"; fi
}
# fm <file> <key> → a flat frontmatter value; a list as items joined by ","; "undefined" when absent
# (same parser as plugins/code-audit-rigor/tests/finding-verifier.test.sh)
fm() {
  node -e '
    const fs = require("fs");
    const [file, key] = process.argv.slice(1);
    if (!fs.existsSync(file)) { console.log("undefined"); process.exit(0); }
    const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);
    if (lines[0] !== "---") { console.log("undefined"); process.exit(0); }
    const end = lines.indexOf("---", 1);
    const block = end < 0 ? [] : lines.slice(1, end);
    for (let i = 0; i < block.length; i++) {
      const m = /^([A-Za-z][\w-]*):\s*(.*)$/.exec(block[i]);
      if (!m || m[1] !== key) continue;
      if (m[2] !== "") { console.log(m[2].trim()); process.exit(0); }
      const items = [];
      for (let j = i + 1; j < block.length && /^\s+-\s+/.test(block[j]); j++) items.push(block[j].replace(/^\s+-\s+/, "").trim());
      console.log(items.join(","));
      process.exit(0);
    }
    console.log("undefined");
  ' "$1" "$2"
}
# dispatches <agent> → one line per Task( … ) block in start.md naming that agent: "model=<value|none>"
dispatches() {
  node -e '
    const t = require("fs").readFileSync(process.argv[1], "utf8");
    const want = `subagent_type="high-precision-dev:${process.argv[2]}"`;
    const out = [];
    for (const chunk of t.split("Task(").slice(1)) {
      const end = chunk.search(/\n\)/);
      const block = end < 0 ? chunk : chunk.slice(0, end);
      if (!block.includes(want)) continue;
      const m = /\bmodel="([^"]*)"/.exec(block);
      out.push(`model=${m ? m[1] : "none"}`);
    }
    console.log(out.join("\n"));
  ' "$START" "$1"
}

for a in "${JUDGES[@]}"; do
  m=$(fm "$PLUGIN/agents/$a.md" model)
  check_eq "agents/$a.md runs on opus" "$m" opus
  d=$(dispatches "$a")
  check_eq "/start dispatches $a at least once" "$([ -n "$d" ] && echo yes || echo no)" yes
  check_eq "...and every dispatch of $a names its frontmatter model ($m)" "$(printf '%s\n' "$d" | grep -v -c -x -F "model=$m" || true)" 0
done

# Coverage floor as a literal (4 agents × 3 checks), not derived from JUDGES: a floor computed from the
# same array the loop walks passes when the array is emptied (0 checks == 0 × 3).
check_eq "all four judgment agents were checked" "$(( PASS + FAIL ))" 12

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
