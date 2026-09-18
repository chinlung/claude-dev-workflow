# codegraph

> Structural code intelligence for Claude Code — query a tree-sitter knowledge graph (callers, impact, call paths, context) before grep when editing or reviewing code.

## Quick start

```bash
# 0. Prerequisite — the codegraph CLI on PATH (one-time, global)
npm i -g @colbymchenry/codegraph

# 1. Install this plugin (one-time)
/plugin marketplace add chinlung/claude-dev-workflow
/plugin install codegraph@scl-claude-plugins

# 2. Index each project you work in
codegraph init
```

That's it — the MCP tool (`codegraph_explore`) and the CLI commands (`impact` / `callers` / `node` / …) now work in that project. The plugin bundles the MCP server, so there's no per-project `codegraph install` or `.mcp.json`. (Docs verified against codegraph **1.6.0**; `init` indexes by default, the old `-i` flag is deprecated but still accepted.)

### Optional — skip the permission prompts (one-time)

Add these entries to the `permissions.allow` array of your **global** `~/.claude/settings.json`. **Merge — do not overwrite the file** (it may hold other settings). Easiest: run `/permissions` and add them via the UI. Manual JSON:

```json
"mcp__plugin_codegraph_codegraph__codegraph_explore",
"Bash(codegraph explore:*)",
"Bash(codegraph node:*)",
"Bash(codegraph query:*)",
"Bash(codegraph context:*)",
"Bash(codegraph callers:*)",
"Bash(codegraph callees:*)",
"Bash(codegraph impact:*)",
"Bash(codegraph affected:*)",
"Bash(codegraph status:*)",
"Bash(codegraph files:*)"
```

Power-user one-liner (safe merge; requires `jq` and an existing valid `~/.claude/settings.json`):

```bash
f=~/.claude/settings.json; jq '.permissions.allow = ((.permissions.allow // []) + ["mcp__plugin_codegraph_codegraph__codegraph_explore","Bash(codegraph explore:*)","Bash(codegraph node:*)","Bash(codegraph query:*)","Bash(codegraph context:*)","Bash(codegraph callers:*)","Bash(codegraph callees:*)","Bash(codegraph impact:*)","Bash(codegraph affected:*)","Bash(codegraph status:*)","Bash(codegraph files:*)"] | unique)' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
```

> Only **read-only** tools/commands are allowlisted — `init`/`sync`/`index`/`uninstall` are deliberately omitted so an agent can't rebuild or remove your index unprompted.

## What it does

`codegraph` is a single-skill plugin that teaches Claude to reach for the [codegraph](https://www.npmjs.com/package/@colbymchenry/codegraph) knowledge graph **before** falling back to grep for **structural** questions:

- Who calls this symbol? What breaks if I change it?
- Where is this defined? What does it call?
- How does X reach Y (the full flow, including dynamic-dispatch hops grep can't follow)?

It does **NOT** replace grep — literal-text searches (string contents, comments, log lines) and reading an already-open file stay on grep/Read. The skill draws the line and, critically, encodes a non-obvious operational fact: **the MCP server lists exactly one tool; everything else is a CLI command.**

## The entry-point split (the thing people get wrong)

As of codegraph 1.6.0, `codegraph serve --mcp` lists **only `codegraph_explore`** by default — upstream pared the menu down on purpose (one strong tool steers agents better than several narrow ones). Every other capability is a Bash CLI command.

| | Entry point |
|---|---|
| `explore` | **MCP** `codegraph_explore` **and** CLI `codegraph explore` — same handler, same output |
| `node`, `query`, `callers`, `callees`, `impact`, `files`, `status` | **CLI**. MCP handlers still exist but are unlisted; `CODEGRAPH_MCP_TOOLS=explore,node,…` on the server re-lists them (the value takes MCP short names — `query` is `search` there; unknown names are dropped silently) |
| `context`, `affected` | **CLI only** |
| ~~`trace`~~, ~~`codegraph_context`~~ | **Gone.** "How does X reach Y" is now part of `explore`'s call-path output |

- **Navigate / understand** (want code bodies, how X reaches Y, survey an area) → MCP `codegraph_explore`
- **Analyze / list** (transitive impact, callers, affected tests) → CLI `impact` / `callers` / `callees` / `affected`
- **One symbol's body + caller/callee trail** → CLI `codegraph node <symbol>`

Calling `codegraph_node` / `codegraph_trace` / `codegraph_context` / `codegraph_impact` as MCP tools fails with "not found" — they are unlisted or removed, not broken. The skill prevents that mistake, and its fallback rule keeps Claude from retrying, from running `codegraph init` on its own, or from silently degrading to a half-grep.

## Proactive triggers

The skill fires on **actions**, not just phrased questions:

| Action | Tool |
|---|---|
| Before edit / rename / remove a symbol | `codegraph impact <symbol>` (CLI) |
| Before changing a method — who calls it? | `codegraph callers <symbol>` or `codegraph node <symbol>` (CLI) |
| Picking up unfamiliar code | `codegraph_explore "<task>"` (MCP) |
| Verify "how does X reach Y" | `codegraph_explore "how does X reach Y"` (MCP) |
| Which tests does this change touch? | `codegraph affected [files...]` (CLI) |

## Bundled MCP server — install once, then only `init` per project

This plugin **bundles the codegraph MCP server** (`.mcp.json` → `codegraph serve --mcp`). Once the plugin is installed, the MCP tool is available in every project — a new project needs only:

```bash
codegraph init   # build the .codegraph/ index; that's it
```

Indexing is the **user's** step. When a project has no index the skill tells Claude to report that and use Read/Grep meanwhile — not to run `init` itself.

No per-project `codegraph install` and no per-project `.mcp.json`.

- **Prerequisite**: the [`@colbymchenry/codegraph`](https://www.npmjs.com/package/@colbymchenry/codegraph) CLI on `PATH` globally (`npm i -g @colbymchenry/codegraph`; it installs a `codegraph` binary) — the plugin references the binary, it doesn't bundle it.
- **Tool prefix**: the plugin-provided MCP tool is named `mcp__plugin_codegraph_codegraph__codegraph_explore` (vs `mcp__codegraph__codegraph_explore` when wired via a project `.mcp.json`). Put the plugin-prefixed allowlist entry in your **global** `~/.claude/settings.json` once.
- **Trade-off**: the MCP server launches in every project the plugin is active in, including un-indexed ones. The tool stays listed there; a query against an un-indexed path returns guidance to use Read/Grep instead, and a query can target any indexed project via `projectPath`. A freshly created `.codegraph/` is picked up live.

See `skills/codegraph/reference.md` for the allowlist snippet (both prefixes), re-listing the other MCP tools with `CODEGRAPH_MCP_TOOLS`, gitignore notes, and known gotchas (tool-managed `CODEGRAPH_START/END` block overwrites, `daemon.pid` gitignore gap, `<unknown-subcommand> --help` exiting 0).

## When it triggers

- A project has a `.codegraph/` index and a structural question arises
- About to grep for call sites, or edit/rename/remove a symbol
- A `codegraph_*` MCP tool call failed with "not found" (→ it's unlisted or removed; use the CLI)
- Setting up codegraph in a new project

For literal-text search, just use grep — this skill is not for that.

## Relationship to other plugins

- **Complements** every review/dev plugin (`dev-workflow`, `code-audit-rigor`, `pr-review-toolkit`) — it's the execution tool for "trace the call chain before changing anything."
- **Independent** — it's a reference/technique skill, not a workflow; no commands, no agents.

## License

MIT
