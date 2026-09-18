# CodeGraph — setup & gotchas reference

Loaded on demand from the `codegraph` skill. Version baseline: **codegraph 1.6.0** (`codegraph --version`; newer tool surfaces may differ — trust `codegraph --help` + the live MCP tool list over this doc). Items still carrying a 0.9.7 note below were observed then and **not re-verified** on 1.6.0, because re-verifying means running `codegraph install` against a project.

## Enable in a new project

**This plugin bundles the MCP server** (`plugins/codegraph/.mcp.json` → `codegraph serve --mcp`). So once the plugin is installed, the MCP server is available in every project — a new project needs only:

1. **Index**: `codegraph init` (creates `.codegraph/` and builds the index — indexing is the default since 1.x; `-i` is deprecated but still accepted). If it already exists, `codegraph status` checks health. **This is the user's step**: the agent reports a missing index, it does not create one.

That's it — no per-project `codegraph install` and no per-project `.mcp.json`. The bundled server resolves the nearest `.codegraph/` at or above the working directory, or above any `projectPath` passed to the tool — so one session can query several indexed projects.

> **Trade-off of bundling**: the MCP server launches in *every* project the plugin is active in, including un-indexed ones (it's a spawned process). There the tool stays listed and a query against an un-indexed path returns guidance to use Read/Grep instead — nothing fails loudly. A freshly created `.codegraph/` is picked up live; no session restart needed.

**Prerequisite**: the `codegraph` CLI must be on `PATH` globally (`npm i -g @colbymchenry/codegraph`, which installs a `codegraph` binary) — the plugin references the `codegraph` binary, it does not bundle it.

**Not using this plugin?** Then wire MCP per-project instead: add `{ "mcpServers": { "codegraph": { "type": "stdio", "command": "codegraph", "args": ["serve", "--mcp"] } } }` to the project `.mcp.json`, or run `codegraph install`. Do **not** add codegraph to `~/.claude.json` global mcpServers (un-indexed projects no-op/error).

**Also recommended per project:**
- **gitignore**: exclude `.codegraph/` runtime files: `*.db`, `cache/`, `*.log`, and `daemon.pid`.
  > Gotcha: the `.codegraph/.gitignore` that `init` writes does **not** cover `daemon.pid` (a runtime PID file). Add it manually, or committing under `.claude/` will surface it as staged.
- **Allowlist** (to skip permission prompts) — see the next section; the prefix differs depending on whether the MCP server comes from this plugin or a project `.mcp.json`.

## settings.json allowlist (read-only only)

Allowlists only **read-only** tools/commands; deliberately excludes `init`/`sync`/`index`/`uninstall` (they mutate `.codegraph/` or re-install).

> **The MCP tool prefix depends on how the server is wired:**
> - **Via this plugin** (bundled `.mcp.json`): `mcp__plugin_codegraph_codegraph__<tool>` — put this in your **global** `~/.claude/settings.json` once and it covers every project.
> - **Via a project `.mcp.json`**: `mcp__codegraph__<tool>` — per-project `.claude/settings.json`.

Plugin-bundled (global `~/.claude/settings.json`):
```json
{
  "permissions": {
    "allow": [
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
    ]
  }
}
```

Project-`.mcp.json` variant: same list but swap the MCP entry's prefix `mcp__plugin_codegraph_codegraph__` → `mcp__codegraph__`.

`codegraph_explore` is the only MCP tool 1.6.0 lists by default, so it is the only MCP entry worth allowlisting. `codegraph_trace` and `codegraph_context` no longer exist; an allowlist entry for them is dead weight.

## Re-listing the other MCP tools (optional)

`node` / `search` / `callers` / `callees` / `impact` / `files` / `status` still have MCP handlers but are unlisted. To list them, set `CODEGRAPH_MCP_TOOLS` on the **server** process — e.g. in a project `.mcp.json`:

```json
{ "mcpServers": { "codegraph": { "type": "stdio", "command": "codegraph", "args": ["serve", "--mcp"], "env": { "CODEGRAPH_MCP_TOOLS": "explore,node,callers,impact" } } } }
```

The value is an allowlist that **replaces** the default, so keep `explore` in it. This plugin's bundled `.mcp.json` sets no env on purpose: upstream measured fewer mis-picks with a single tool, and the CLI covers the rest. Add matching `mcp__…__codegraph_<tool>` allowlist entries only for tools you re-list.

> Widening an allowlist is Self-Modification — the agent will be blocked by the safety gate. The **user** must apply it (`/permissions`, a `!` shell command, or manual edit).

## Known gotchas

- **`CODEGRAPH_START/END` block is tool-managed.** `codegraph install` writes a guidance block into the project `.claude/CLAUDE.md`; re-syncing **overwrites everything between the markers**. Put any custom codegraph prose **outside** `CODEGRAPH_END` (same failure mode as Laravel Boost regenerating CLAUDE.md).
- **That block's table may over-promise** *(observed on 0.9.7, not re-verified on 1.6.0)*. It listed `callers`/`callees`/`impact`/`status`/`files` as `codegraph_*` MCP tools that the server didn't export. On 1.6.0 the same symptom has a different cause — those handlers exist but are unlisted by default — and the same cure: use the CLI. Whatever the block says, the live MCP tool list wins.
- **The allowlist `install` writes may also be off** *(observed on 0.9.7, not re-verified on 1.6.0)*. Reconcile it against the snippet above after enabling: on 1.6.0 the only MCP entry that matters is `codegraph_explore`.
- **`codegraph <unknown-subcommand> --help` exits 0** and prints the top-level help. To check whether a subcommand exists, read the output — the exit code won't tell you.
- **Index lag.** If a codegraph response opens with `⚠️ … edited since the last index sync`, Read the listed files directly; files not in that banner are authoritative. `codegraph status` lists pending files too.
