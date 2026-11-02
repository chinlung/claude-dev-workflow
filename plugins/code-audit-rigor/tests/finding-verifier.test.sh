#!/bin/bash
# code-audit-rigor: agents/finding-verifier.md and its wiring into /review-branch Phase 2
# 用法：bash plugins/code-audit-rigor/tests/finding-verifier.test.sh
# 消費者：提交前手跑 + CI（.github/workflows/validate.yml）+ 本地 PostToolUse hook
#
# Three things that degrade without a word:
#   - the judgment floor: a verifier decides whether a finding is real, so its model stays at opus
#     (high-precision-dev 1.5.0 once set its critic to sonnet; nothing flagged it); effort, memory and
#     maxTurns stay unset (judgment keeps the session's effort, remembered verdicts anchor the next
#     one, a cut-off verification reads like a verdict);
#   - the verdict vocabulary matches review-branch-results.schema.json: annotate turns FAIL into
#     dismissed and PASS into carried, and a word outside the enum fails the validator;
#   - the verification steps live in one place (the agent body): a second copy in the command would
#     drift from the first.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$SCRIPT_DIR/.."
AGENT="$PLUGIN/agents/finding-verifier.md"
CMD="$PLUGIN/commands/review-branch.md"
SCHEMA="$PLUGIN/schema/review-branch-results.schema.json"
PASS=0; FAIL=0

check_eq() {     # check_eq <name> <actual> <expected exact>
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — expected [$3], got [$2]"; fi
}
has() {          # has <file> <fixed string> → yes|no
  if [ -f "$1" ] && grep -q -F -- "$2" "$1"; then echo yes; else echo no; fi
}
contains() {     # contains <text> <fixed string> → yes|no
  case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac
}
# fm <file> <key> → a flat frontmatter value; a list as items joined by ","; "undefined" when absent
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
# section <file> <start heading> <next heading> → the text between them
section() {
  node -e '
    const t = require("fs").readFileSync(process.argv[1], "utf8");
    const a = t.indexOf(process.argv[2]); const b = t.indexOf(process.argv[3], a + 1);
    process.stdout.write(a < 0 ? "" : t.slice(a, b < 0 ? undefined : b));
  ' "$1" "$2" "$3"
}

# ---- the agent definition ----
check_eq "agents/finding-verifier.md exists" "$([ -f "$AGENT" ] && echo yes || echo no)" yes
check_eq "frontmatter name is finding-verifier" "$(fm "$AGENT" name)" finding-verifier
check_eq "frontmatter model is opus (judgment floor)" "$(fm "$AGENT" model)" opus
check_eq "frontmatter disallows Agent (no nested dispatch)" "$(contains ",$(fm "$AGENT" disallowedTools)," ",Agent,")" yes
check_eq "frontmatter leaves effort to the session" "$(fm "$AGENT" effort)" undefined
check_eq "frontmatter sets no memory (a remembered verdict anchors the next)" "$(fm "$AGENT" memory)" undefined
check_eq "frontmatter sets no maxTurns (a cut-off verification reads like a verdict)" "$(fm "$AGENT" maxTurns)" undefined

# ---- the verdict vocabulary is the schema's ----
ENUM=$(node -e '
  const s = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  let found;
  (function walk(o) { if (found || !o || typeof o !== "object") return;
    if (o.verdict && Array.isArray(o.verdict.enum)) { found = o.verdict.enum; return; }
    for (const v of Object.values(o)) walk(v); })(s);
  console.log(found ? found.join(" | ") : "");
' "$SCHEMA")
check_eq "the schema still declares a verdict enum" "$([ -n "$ENUM" ] && echo yes || echo no)" yes
check_eq "the agent's output line names exactly the schema's verdicts" "$(has "$AGENT" "verdict: $ENUM")" yes
check_eq "the agent offers no verdict outside the schema (BORDERLINE)" "$(has "$AGENT" "BORDERLINE")" no

# ---- Phase 2 dispatches it, with an explicit model, and does not keep a second copy of the steps ----
P2=$(section "$CMD" "## Phase 2" "## Phase 3")
check_eq "review-branch has a Phase 2 section" "$([ -n "$P2" ] && echo yes || echo no)" yes
# Only the fenced dispatch template counts: Phase 2's prose mentions the type and the model too, and
# a check over the whole section stays green when the template itself loses them.
TEMPLATE=$(printf '%s' "$P2" | node -e '
  const t = require("fs").readFileSync(0, "utf8");
  const fences = t.split("```").filter((_, i) => i % 2 === 1);
  process.stdout.write(fences.find((f) => f.includes("subagent_type: \"code-audit-rigor:finding-verifier\"")) || "");
')
check_eq "Phase 2 has a dispatch template for code-audit-rigor:finding-verifier" "$([ -n "$TEMPLATE" ] && echo yes || echo no)" yes
# The explicit model overrides the frontmatter, so the two must say the same thing.
check_eq "the template names the agent's frontmatter model explicitly (a floor hook gates a named type without one)" "$(contains "$TEMPLATE" "model: \"$(fm "$AGENT" model)\",")" yes
STEP='引用錨定驗證（機械步驟，先做）'
check_eq "the verification steps are in the agent" "$(has "$AGENT" "$STEP")" yes
check_eq "...and not repeated in the command" "$(has "$CMD" "$STEP")" no

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
