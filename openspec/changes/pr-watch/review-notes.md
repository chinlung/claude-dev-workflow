# Review Notes — pr-watch

<!-- Phase 5 log. One line per review comment, appended under a `## Round N - [Review Type] (YYYY-MM-DD)` heading:
     - [REQUIREMENT|DESIGN|CODE|CONSTITUTION] Y/N - description
     Y/N answers ONE question: "must an OpenSpec artifact be updated in Phase 6?" — it does NOT mean "handled / fixed".
       [CODE] is therefore always N, even when the fix is already committed.
       [CONSTITUTION] Y = a NEW cross-feature rule to add to the project constitution; do not log "existing rules were followed".
     Tag by the artifact the fix lands in (spec → REQUIREMENT, design.md → DESIGN, code only → CODE), not by the nature of the problem.
     Never edit proposal.md / specs/ / design.md / tasks.md during review — record here, reconcile in Phase 6.
     Add `final` to the last Round heading only after the user says review has converged — the archive gate checks it. -->

## Round 1 - Security Review (security-guidance, 2026-11-25)
- [CODE] N - pr-watch-guard r1: write spellings outside the list (gh api REST POST, other MCP servers' write tools), state only looked up under CLAUDE_PROJECT_DIR — fixed (495d1af)
- [CODE] N - pr-watch-guard r2: attached/quoted -f, curl write flags, *_read suffix allowlist, matcher narrowed to github-named servers — fixed by deny-by-default (397c93d)
- [CODE] N - pr-watch-guard r3: JSON-escaped whitespace, uppercase host, repeated -X — fixed by decoding with jq and normalising once (lowercase, quotes, whitespace); third round of the same class, so spelling-by-spelling patching stopped
- [DESIGN] Y - design.md threat model says writes are "由 hook 擋下，不靠模型自律"; the guard cannot stop a model set on getting past it (that model can set the state's active to false). Rewrite in Phase 6: the guard is a tripwire against habitual or misdirected writes; the boundaries are /review-pr --triage-only having no write step and every fix waiting for the user's confirmation of the table
