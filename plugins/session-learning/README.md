# session-learning

> Incremental capture of a session's valuable patterns — a cheap Stop-hook reminder plus a five-phase `/save-session` command that **updates existing records before creating new ones**, routes each pattern to the right level (global vs project), and deliberately caps itself at 1-2 changes per run.

## Quick start

```bash
# 1. Install (one-time)
/plugin marketplace add chinlung/claude-dev-workflow
/plugin install session-learning@scl-claude-plugins
```

That's it. At the end of a substantive session the Stop hook reminds you once; run `/save-session` (or `/session-learning:save-session`) whenever you want to capture what the session taught.

## How it works

```
Stop event
  └─ save-session-reminder.sh (bash, no LLM call — a `command` hook)
       ├─ fail-open: no jq, no transcript, or an unreadable one → stay quiet
       ├─ once-per-session flag file under ${TMPDIR:-/tmp}
       ├─ <10-line transcript floor (nothing substantive happened → stay quiet)
       ├─ already-ran detection — matches the three shapes a real invocation
       │    leaves in the transcript (the expanded command tag, its namespaced
       │    variant, and the Skill-invocation form), each anchored on the JSON
       │    quote that opens the field, so discussing the command — or reading
       │    this file — does not suppress the reminder. This paragraph avoids
       │    writing those shapes verbatim for exactly that reason; the shapes
       │    themselves live in hooks/save-session-reminder.sh
       └─ otherwise: blocks the stop once with a one-line nudge (answering it
            ends the session — the hook never blocks twice)

/save-session
  Phase 1  scan the conversation for candidate patterns
  Phase 2  decide the level for each — global (~/.claude/) vs project
  Phase 3  dedupe and merge — the critical phase, and it runs BEFORE any write:
           read ~/.claude/CLAUDE.md, the project CLAUDE.md and the auto-memory
           MEMORY.md index, then list both commands/ dirs (global and project)
           so a reusable workflow is not duplicated either
  Phase 4  execute the chosen updates
  Phase 5  report what changed
```

## What counts as a candidate

Phase 1 looks for four kinds of pattern, each with a bar it has to clear — the bar is what keeps the index from filling up with one-off noise:

| Kind | Triggers on | Saved only if |
|---|---|---|
| **Feedback** | a correction to how you want things done ("don't…", "use X instead", "from now on…") | it applies to future conversations, not just this one |
| **Skill** | a workflow you actually executed in 3+ steps | it is likely to be reused |
| **Project** | project facts — decisions, deadlines, architecture | it cannot be derived from the code or git history |
| **User** | your role, expertise, preferences | it is not already recorded |

Nothing clears the bar? The run reports "nothing to save" and stops.

## Where a pattern lands

| Kind of pattern | Destination |
|---|---|
| Rule or preference that applies to every project | a section of `~/.claude/CLAUDE.md` |
| Reusable cross-project workflow | `~/.claude/commands/*.md` |
| Something about you personally | auto memory, `user` type |
| Tied to this project's stack, paths or architecture | the project's `CLAUDE.md` |
| Project-specific workflow | `.claude/commands/*.md` |
| Project context — decisions, team, timeline | auto memory, `project` type |
| A correction to how Claude works, specific to this project | auto memory, `feedback` type |

## Design principles

- **Update before create.** The first job of every run is to find an existing record to amend, merging overlapping observations into a single entry; a new file is the fallback, not the goal. Tools that skip this step accumulate instead — after fifty sessions you have fifty near-duplicate files nobody reads.
- **Restraint.** At most 1-2 changes per run (updates and creations combined), and nothing is saved unless it clearly clears the "valuable across future conversations" bar. Skipping beats a low-value record — an index diluted with noise is worse than a shorter one.
- **Get the level right.** A project-specific detail in the global `CLAUDE.md` costs every future session tokens it cannot use.
- **The Stop hook is a shell script, not a prompt.** A `command`-type hook adds zero latency and zero tokens to the session-end path; a prompt-based one would spend an LLM call just to decide whether to mention a command.

## Testing

```bash
bash plugins/session-learning/tests/reminder.test.sh   # 12 assertions, also run in CI
```

One of them feeds this README to the hook: the already-ran guard must not read "you opened the docs" as "you ran the command". That is not hypothetical — it is what 1.0.1 fixed, and writing the invocation shapes verbatim into this file would reintroduce it, which is why the flow above describes them instead of quoting them.

## Relationship to session-reflect

Complementary: `session-reflect` proposes **what to change**, `session-learning` stores **patterns already confirmed**. Both hook the Stop event independently, each with its own once-per-session guard, so both may nudge at the end of the same session.
