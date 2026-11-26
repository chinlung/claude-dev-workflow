# Review Notes — pr-watch-guard-segments

<!-- Phase 5 log. One line per review comment, appended under a `## Round N - [Review Type] (YYYY-MM-DD)` heading:
     - [REQUIREMENT|DESIGN|CODE|CONSTITUTION] Y/N - description
     Y/N answers ONE question: "must an OpenSpec artifact be updated in Phase 6?" — it does NOT mean "handled / fixed".
       [CODE] is therefore always N, even when the fix is already committed.
       [CONSTITUTION] Y = a NEW cross-feature rule to add to the project constitution; do not log "existing rules were followed".
     Tag by the artifact the fix lands in (spec → REQUIREMENT, design.md → DESIGN, code only → CODE), not by the nature of the problem.
     Never edit proposal.md / specs/ / design.md / tasks.md during review — record here, reconcile in Phase 6.
     Add `final` to the last Round heading only after the user says review has converged — the archive gate checks it. -->

## Round 1 - Security Review: commit-level security-guidance r1 (2026-11-26)
- [CODE] N - MEDIUM: a quoted or escaped "-X GET" inside a value (-f 'body= -X GET', body=\ -X\ GET, nested quotes) cleared a field write; main had the same hole (it stripped quotes before looking for GET). Fixed in 2fd03c1: a GET counts only as an unquoted, unescaped argument of its own gh api.

## Round 2 - Security Review: Stop-level security-guidance r2 (2026-11-26)
- [CODE] N - MEDIUM, introduced by the per-segment write range: fields reaching gh api through $( ), backticks or xargs fell into another segment and were allowed (main denied them). Fixed in 1498b8d; superseded by the Round 3 ruling, which reads write signals on the whole line again.

## Round 3 - Security Review: commit-level security-guidance r3, user ruling (2026-11-26)
- [CODE] N - MEDIUM: a ) could close a backtick frame in the awk scanner, misplacing segment boundaries. Third parser-differential round of the same class (r1 quoted GET, r2 substitutions, r3 frames). Root cause: narrowing where write signals are read needs a parser that never sees a boundary earlier than bash does. Moot after the ruling below.
- [REQUIREMENT] Y - User ruling (option 1, GET-only narrowing): write signals (methods, fields, --input) are read on the whole line as on main; only the GET is narrowed, to each gh api's own unquoted, unescaped arguments before the first separator, quote or backslash. The spec scenario 「別段的旗標不算 gh api 的旗標」(gh api … | cut -f1 allowed) is dropped: another command's flag still counts, and that false deny joins the deferred content-class follow-up. The requirement text must say GET-per-gh-api, not per-segment judgement of methods and fields.
- [REQUIREMENT] Y - proposal.md What Changes / Decisions describe per-segment write ranges and quote-aware splitting; rewrite to the GET-only behaviour and record the ruling and the three review rounds as the reason.
- [DESIGN] Y - design.md describes the awk scanner, two ranges and a "a misread only widens what is read for writes" guarantee that r2 and r3 disproved. Rewrite: tr-based marking (separators, quotes, backslashes → $Q), GET range = up to the first $Q, write signals whole line; approaches considered (bash regex scanner 15.7 s; awk per-segment scanner, abandoned after three review rounds; GET-only, chosen; command-position parsing, deferred); measurement: 317-command corpus, 0 deny→allow, 3 allow→deny (script text).

## Round 4 - Code Review: review-branch r1 + codex r1 (2026-11-26)
- [CODE] N - review-branch S0 (PASS 92, LOW, introduced): a backslash-newline continuation ended the GET range, so a multi-line read with -X GET on a continued line was denied (main allowed it). Fixed: backslash-newline is dropped before marking, as bash drops it; test + mutant no-continue.
- [CODE] N - codex P2 (introduced): a gh api spelled across quotes or a backslash ("g"h api, gh "a"pi, g\h api) was found by $norm but not by the per-gh-api loop, so its field write was allowed (main denied it). Fixed fail-closed: the loop must find as many gh api as $norm, else deny; tests + mutant count-check.
- [CODE] N - review-branch S1 (PASS 80, LOW, introduced): a quoted endpoint before the method (gh api "repos/…" -X GET -f per_page=100) is denied, the cost of cutting the GET range at the first quote. Kept (reintroducing partial parsing is what Round 3 ruled out); documented in the hook comment and CHANGELOG, pinned by a deny test.
- [DESIGN] Y - design.md Trade-offs must list the known false denies of the chosen design: another command's flag on the same line (cut -f1, rm -f, grep -F, bash -x), a quoted endpoint before the method, and the slower worst case measured under load (corpus max ≈1.5 s vs main ≈0.9 s on the same run).
