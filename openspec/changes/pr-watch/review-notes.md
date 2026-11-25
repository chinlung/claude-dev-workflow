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

## Round 2 - Sandbox Run (private chinlung/pr-watch-sandbox PR #1, 2026-11-25)
Run: session in the sandbox clone with this branch's plugins (`--plugin-dir`), five watch rounds 15:02–15:26, all `watch` calls inside the sandbox with `allowed_domains api.github.com`. Read back from GitHub and the state file after each step.
Verified: round 1 grace (`inGrace` true, no verdict); round 2 `failedRuns` [{unittest, runId 45532561307, attempt 1}] with `noProgressRounds` 1 (below the stop at 2); round 3 bot comment as `issues/comments:7155473650:2938f259baec77f7`, `/review-pr 1 --triage-only 7155473650` table, `watch-ack` into `seen`; local fix as two commits (092310b carries the `pr-watch:` body line, no session link), nothing pushed until the user said push; `gh pr comment 1` while active denied by pr-watch-guard in PreToolUse, GitHub still shows one comment; after push round 4 new head 092310b in grace with unittest pending; round 5 exit 8 `ready` ("mergeable, every check done"), state `active` false, PushNotification sent with PR number and reason only, loop ended with ScheduleWakeup stop. A first `--start` without allowed_domains returned `queryFailed` true with hit `query-failed`, not a verdict.
- [CODE] N - `watch.dirty` counts untracked files, so the triage output `review-pr-comments.json` (written by `/review-pr --triage-only` in the repo root) and `/review-branch`'s `review-branch-results.json` make the tree dirty and step 4's local fix never runs after a comment was triaged; the sandbox session had to gitignore the file and commit .gitignore first
- [CODE] N - pr-watch-guard denies curl to github.com, which is the user's documented fallback when gh cannot reach the API inside the sandbox; the three comment GETs of the triage step ran outside the sandbox instead. Kept: the guard is a tripwire, and allowing curl reads means telling a read from a write by spelling again (Round 1)
- [CODE] N - round 2 asked the user for `gh run rerun` (attempt 1) and, before it ran, read the failed log and called it a code bug, skipping the one rerun SKILL step 4.1 asks for; outcome right, order not as written
- [CODE] N - asked to reply to the bot comment, the session first asked the user (SKILL held) and its draft said "CI unittest 已通過" for a commit not yet pushed; nothing was posted. SKILL could say a drafted reply states local results as local
- [CODE] N - at the stop the notification and ScheduleWakeup stop went out before the report text; SKILL step 5 says report first. No effect on the outcome
- [DESIGN] Y - a tick does not interrupt a busy turn: the 15:19 wakeup did not run while the session was in the push turn (simplify, review-branch, security-review, push, 15:12–15:21) and the round ran right after the push. Verdicts only read state at the time, so nothing was misjudged; design.md should say ticks can be late, never early or skipped silently
- [CODE] N - a stop predicted in the session's reply ("最後可能停在 needs-user") was read as a stop; the state file (round, active) told them apart. No change: the state file is the record
