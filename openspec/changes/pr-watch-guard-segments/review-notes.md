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

## Round 5 - Code Review: review-branch r2 + codex r2 (2026-11-26)
- [CODE] N - codex r2 (base main): no findings. It reviewed the tree before the fix below.
- [CODE] N - review-branch r2 (own read of the final hook): a GET inside a shell comment (gh api …/comments -f body=x # -X GET) cleared the field write; main has the same hole. Sibling of Round 1 (a GET must be an argument of its own gh api). Fixed: the GET range ends at a word that starts with #; test + mutant comment-get.

## Round 6 - Security Review: /security-review r2 (2026-11-26)
- [CODE] N - Result of 2564 differential commands (hand-written, probes, fuzz seed 1) through main's and the branch's hook, executed by a recording fake gh: no finding at the report threshold. 12 commands that main denies and the branch allowed were real writes, in two classes: (1) a decoy gh api that exists only in the marked view offsets a gh api split across quotes (the Round 4 codex fix was incomplete: the count check could be paid for by a decoy), (2) a backslash-newline hides a GET from $norm and places it in a non-flag position. Fixed: a field also needs a GET that $norm sees, as on main, so the branch's allow set is a subset of main's; tests for both classes, mutant norm-get.
- [CODE] N - The hook has no new injection surface: the command string reaches only printf '%s', tr, quoted parameter expansions and fixed regexes; six canary-file payloads created nothing.
- [CODE] N - Known false-deny costs recorded in design Trade-offs (see Round 4): quoted endpoint before the method, another command's flag on the line; and a continuation that splits the method flag itself is denied (the whole-line view does not see it).
- [DESIGN] Y - design.md Trade-offs must also say: the per-gh-api check can only narrow what main allowed, because a field first needs a GET visible to the whole-line view; the two views are a conjunction, not alternatives.
- [CODE] N - Deferred to follow-ups (LOW): a 200 KB -f body takes the guard 11.6 s (main 0.6 s) against the 10 s hook timeout; what Claude Code does on a PreToolUse timeout is not checked. /bin/bash 3.2 under a UTF-8 locale aborts in deny() on an unbound variable (same on main).

## Round 7 - Cross-vendor Review: codex r3 (2026-11-26)
- [CODE] N - codex r3 (base main, tree at 8288187 with every fix landed): no findings. It compared the GET decision against main's.
