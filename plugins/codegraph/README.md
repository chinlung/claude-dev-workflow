# codegraph

> Structural code intelligence for Claude Code — query a tree-sitter knowledge graph (callers, impact, trace, context) before grep when editing or reviewing code.

## Quick start

```bash
# 0. Prerequisite — the codegraph CLI on PATH (one-time, global)
npm i -g codegraph

# 1. Install this plugin (one-time)
/plugin marketplace add chinlung/claude-dev-workflow
/plugin install codegraph@scl-claude-plugins

# 2. Index each project you work in
codegraph init -i
```

That's it — the MCP tools (`context` / `trace` / `node` / `explore`) and CLI commands (`impact` / `callers` / …) now work in that project. The plugin bundles the MCP server, so there's no per-project `codegraph install` or `.mcp.json`.

### Optional — skip the permission prompts (one-time)

Add these entries to the `permissions.allow` array of your **global** `~/.claude/settings.json`. **Merge — do not overwrite the file** (it may hold other settings). Easiest: run `/permissions` and add them via the UI. Manual JSON:

```json
"mcp__plugin_codegraph_codegraph__codegraph_search",
"mcp__plugin_codegraph_codegraph__codegraph_context",
"mcp__plugin_codegraph_codegraph__codegraph_node",
"mcp__plugin_codegraph_codegraph__codegraph_trace",
"mcp__plugin_codegraph_codegraph__codegraph_explore",
"Bash(codegraph callers:*)",
"Bash(codegraph callees:*)",
"Bash(codegraph impact:*)",
"Bash(codegraph affected:*)",
"Bash(codegraph status:*)",
"Bash(codegraph files:*)"
```

Power-user one-liner (safe merge; requires `jq` and an existing valid `~/.claude/settings.json`):

```bash
f=~/.claude/settings.json; jq '.permissions.allow = ((.permissions.allow // []) + ["mcp__plugin_codegraph_codegraph__codegraph_search","mcp__plugin_codegraph_codegraph__codegraph_context","mcp__plugin_codegraph_codegraph__codegraph_node","mcp__plugin_codegraph_codegraph__codegraph_trace","mcp__plugin_codegraph_codegraph__codegraph_explore","Bash(codegraph callers:*)","Bash(codegraph callees:*)","Bash(codegraph impact:*)","Bash(codegraph affected:*)","Bash(codegraph status:*)","Bash(codegraph files:*)"] | unique)' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
```

> Only **read-only** tools/commands are allowlisted — `init`/`sync`/`index`/`uninstall` are deliberately omitted so an agent can't rebuild or remove your index unprompted.

## What it does

`codegraph` is a single-skill plugin that teaches Claude to reach for the [codegraph](https://www.npmjs.com/package/codegraph) knowledge graph **before** falling back to grep for **structural** questions:

- Who calls this symbol? What breaks if I change it?
- Where is this defined? What does it call?
- How does X reach Y (the full flow, including dynamic-dispatch hops grep can't follow)?

It does **NOT** replace grep — literal-text searches (string contents, comments, log lines) and reading an already-open file stay on grep/Read. The skill draws the line and, critically, encodes a non-obvious operational fact: **the MCP tool surface and the CLI command surface are different, and neither is a superset.**

## The entry-point split (the thing people get wrong)

`codegraph serve --mcp` exposes only *some* commands as `codegraph_*` MCP tools; the rest are Bash-CLI only.

| | MCP only | CLI only (`codegraph <cmd>`) | Both |
|---|---|---|---|
| | `trace`, `node`, `explore` | `callers`, `callees`, `impact`, `affected`, `status`, `files` | `search`/`query`, `context` |

- **Navigate / understand** (want code bodies, trace X→Y) → MCP `context` / `trace` / `node` / `explore`
- **Analyze / list** (transitive impact, callers, affected tests) → CLI `impact` / `callers` / `callees` / `affected`
- **Overlapping `context` / `search` → default MCP** (LLM-tuned output, no ANSI noise, no shell round-trip)

Calling `codegraph_impact` / `codegraph_callers` as MCP tools fails — they're CLI-only. The skill prevents that mistake and its fallback rule keeps Claude from silently degrading to a half-grep.

## Proactive triggers

The skill fires on **actions**, not just phrased questions:

| Action | Tool |
|---|---|
| Before edit / rename / remove a symbol | `codegraph impact <symbol>` (CLI) |
| Before changing a method — who calls it? | `codegraph callers <symbol>` (CLI) or `codegraph_node` (MCP) |
| Picking up unfamiliar code | `codegraph_context "<task>"` (MCP) |
| Verify "how does X reach Y" | `codegraph_trace <from> <to>` (MCP) |

## Bundled MCP server — install once, then only `init -i` per project

This plugin **bundles the codegraph MCP server** (`.mcp.json` → `codegraph serve --mcp`). Once the plugin is installed, the MCP tools are available in every project — a new project needs only:

```bash
codegraph init -i   # build the .codegraph/ index; that's it
```

No per-project `codegraph install` and no per-project `.mcp.json`.

- **Prerequisite**: the [`codegraph`](https://www.npmjs.com/package/codegraph) CLI on `PATH` globally (`npm i -g codegraph`) — the plugin references the binary, it doesn't bundle it.
- **Tool prefix**: plugin-provided MCP tools are named `mcp__plugin_codegraph_codegraph__<tool>` (vs `mcp__codegraph__<tool>` when wired via a project `.mcp.json`). Put the plugin-prefixed allowlist entries in your **global** `~/.claude/settings.json` once.
- **Trade-off**: the MCP server launches in every project the plugin is active in, including un-indexed ones (there it returns "not initialized" until `codegraph init -i`).

See `skills/codegraph/reference.md` for the allowlist snippet (both prefixes), gitignore notes, and known gotchas (tool-managed `CODEGRAPH_START/END` block overwrites, `daemon.pid` gitignore gap).

## When it triggers

- A project has a `.codegraph/` index and a structural question arises
- About to grep for call sites, or edit/rename/remove a symbol
- A `codegraph_*` MCP tool call failed with "not found" (→ use the CLI)
- Setting up codegraph in a new project

For literal-text search, just use grep — this skill is not for that.

## Relationship to other plugins

- **Complements** every review/dev plugin (`dev-workflow`, `code-audit-rigor`, `pr-review-toolkit`) — it's the execution tool for "trace the call chain before changing anything."
- **Independent** — it's a reference/technique skill, not a workflow; no commands, no agents.

## License

MIT
