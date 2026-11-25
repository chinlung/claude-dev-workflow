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

## Round 3 - Final Whole-Branch Review (fable, 7930ded..a54539f, 2026-11-25)
Review Focus 1–5 hold (5 checked through `watch` on a 101-comment fixture). All suites green before the round.
- [CODE] N - I1 a plain round on a stopped watch kept judging with `active` false, so the guard was off while the SKILL acted; now refused as exit 7 `stopped`
- [DESIGN] Y - I2 nothing could stop a watch although SKILL and guard both said "stop the watch"; added `watch --stop` (writes `active` false, exit 0), the SKILL runs it on 「停止監看」 and on an exit 7 that ends the loop, the deny text names it. design.md must describe the subcommand
- [REQUIREMENT] Y - I3 a required check that never appears kept every round unsettled until `limit`, hiding failures and comments for 24 h; now unsettled only for the first 3 rounds of a head, then a `checks-failed` that ends in `no-progress`. The spec scenario already scopes it to a new head; rewrite it with the bound
- [CODE] N - I4 the round signature counted new comments instead of naming them, so a second comment after the first was triaged stopped the watch as `no-progress`; the signature now carries the sorted keys
- [CODE] N - I5 the guard denied the triage's own GETs for repos named `*-x<letter>*` (unanchored `-x`) or containing `mutation` (substring over the whole command); `-x` now needs a word start, `mutation` counts only with `graphql`
- [CODE] N - M2 `--start` skipped too-soon always, so a second session's `--start` reset an active watch; now skipped only when the previous stretch has stopped, which is what the spec's two-session scenario already says
- [CODE] N - M4 SKILL had no branch for a run id with `attempt` null; it is reported, never rerun
- [CODE] N - M7 docs: script header and USAGE name watch/watch-ack/exit 8, root README pair names pr-watch and `--triage-only`, CHANGELOG mutant count, guard comment's MCP read list; the guard test's pass floor raised from 25 to 75 and its `no-unquote` mutant fixed (its perl did not compile, so it "died" on an empty hook)
- [DESIGN] Y - M7 design.md drifted from the code: no-progress threshold is 2 settled unchanged rounds (design says ≥ 1); `dirty` ignores untracked files (design says any `git status --porcelain` output); `watch-ack` takes positional `<owner/repo> <pr>` (design says `--pr`); the guard section still lists the substring rules and the narrow MCP matcher instead of deny-by-default
- [REQUIREMENT] Y - M1 `watch` never computes review coverage, yet spec and SKILL list `unreviewed` among the report-only states; a `ready` stop says "mergeable" while pr-closeout's merge step can still answer exit 6 `unreviewed`. Phase 6: drop `unreviewed` from the watch's list and say the `ready` stop excludes coverage (the merge path checks it), or wire coverage in — user's call
- [CODE] N - M3 lost update between `watch` and `watch-ack` from another session (no lock); deferred to follow-ups, a comment is triaged twice at worst
- [CODE] N - M5 `--triage-only` takes bare ids, so an id that exists on two endpoints is triaged twice; deferred to follow-ups
- [CODE] N - M6 an I/O error in saveState/loadState exits 1 with a stack trace and may leave a `.tmp.<pid>` file; deferred to follow-ups
- [CODE] N - M8 tests that guarded less than they claimed: covered by this round's new cases (tick after stop, `--start` while watched, `--stop`, required-missing window, second comment) and their five `w-*` mutants plus two guard mutants; a round-2 null rollup stopping `ready` is the documented one-round grace (design [default])

## Round 4 - code-audit-rigor (7930ded..4adac41, 2026-11-25)
Three confirmed (one Medium, two Low), eight dismissed with rationale; report kept locally, not in the repo.
- [DESIGN] Y - BUG-001 a triaged comment reached the scope ledger with no rule on its form: an unconfirmed, comment-derived In-scope line is printed back into the context by the scope-ledger Stop and SessionStart hooks, with "已授權自主執行→繼續做". SKILL now writes it as 「請使用者裁定：…」 in the model's words with the comment key and author, never the comment's text, and turns it into a fix item only after the user confirms. design.md threat model row 1 must name the ledger form as part of the control
- [CODE] N - BUG-002 check names (`hits[].detail`, `checks[].name`, `failedRuns[].name`) are text someone else wrote and the SKILL named only comments and CI logs; the rule names them now
- [CODE] N - BUG-003 the guard denied the triage's own reads for a repo named `replies` or `*graphql*mutation*` (sibling of Round 3 I5); `/replies` counts only at the end of a path and `graphql` as its own word

## Round 5 - Security Review (security-guidance on faff8a8, 2026-11-25)
- [CODE] N - Round 4's BUG-003 fix narrowed two guard rules to "followed by a space or the end" and let through spellings they used to deny (`fetch('…/replies',{method:'POST'})`, `gh api -X GET -f query='mutation…' graphql; …`). Both rules now deny unless a path or a name continues (`/replies/<more>`, `graphql-<name>`); four deny cases and two mutants (`replies-loose`, `gql-loose`). A regression of this change's own edit, not a new spelling to chase
