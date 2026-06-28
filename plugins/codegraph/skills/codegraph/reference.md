# CodeGraph — setup & gotchas reference

Loaded on demand from the `codegraph` skill. Version baseline: **codegraph 0.9.7** (`codegraph --version`; newer tool surfaces may differ — trust `codegraph --help` + the live MCP tool list over this doc).

## Enable in a new project

**This plugin bundles the MCP server** (`plugins/codegraph/.mcp.json` → `codegraph serve --mcp`). So once the plugin is installed, the MCP server is available in every project — a new project needs only:

1. **Index**: `codegraph init -i` (creates `.codegraph/`). If it already exists, `codegraph status` checks health.

That's it — no per-project `codegraph install` and no per-project `.mcp.json`. The bundled server serves whichever project's `.codegraph/` is in the working directory.

> **Trade-off of bundling**: the MCP server launches in *every* project the plugin is active in, including un-indexed ones — there it returns "not initialized" until you run `codegraph init -i` (graceful, but it's a spawned process). After creating a fresh `.codegraph/`, restart the session if the MCP tools don't pick it up.

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
    ]
  }
}
```

Project-`.mcp.json` variant: same list but swap the five MCP entries' prefix `mcp__plugin_codegraph_codegraph__` → `mcp__codegraph__`.

> Widening an allowlist is Self-Modification — the agent will be blocked by the safety gate. The **user** must apply it (`/permissions`, a `!` shell command, or manual edit).

## Known gotchas

- **`CODEGRAPH_START/END` block is tool-managed.** `codegraph install` writes a guidance block into the project `.claude/CLAUDE.md`; re-syncing **overwrites everything between the markers**. Put any custom codegraph prose **outside** `CODEGRAPH_END` (same failure mode as Laravel Boost regenerating CLAUDE.md).
- **That block's table over-promises.** It lists `callers`/`callees`/`impact`/`status`/`files` as `codegraph_*` MCP tools, but 0.9.7 doesn't export them — calling those as MCP tools yields InputValidationError / ToolSearch finds nothing. They're CLI-only.
- **The allowlist `install` writes is also wrong.** It may allow non-existent MCP tools and miss the real `trace`/`explore` — reconcile against the snippet above after enabling.
- **Index lag.** If a codegraph response opens with `⚠️ … edited since the last index sync`, Read the listed files directly; files not in that banner are authoritative. `codegraph status` lists pending files too.
