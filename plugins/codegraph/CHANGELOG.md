# Changelog

All notable changes to the `codegraph` plugin will be documented in this file.

## [1.0.0] - 2026-05-30

### Added

- Initial release.
- Single skill `codegraph` teaching structural-code-intelligence-before-grep discipline for projects with a `.codegraph/` index.
- **Bundled MCP server** (`.mcp.json` → `codegraph serve --mcp`): install the plugin once and the MCP tools (`context`/`trace`/`node`/`explore`/`search`) are available in every project — a new project then needs only `codegraph init -i`, no per-project `codegraph install` or `.mcp.json`. Plugin-provided tools are prefixed `mcp__plugin_codegraph_codegraph__<tool>`. Requires the `codegraph` CLI on `PATH` globally. Trade-off: the server launches in un-indexed projects too (returns "not initialized" until indexed).
- **Entry-point split documentation**: the non-obvious fact that `serve --mcp` exposes only `trace`/`node`/`explore`/`search`/`context` as MCP tools, while `impact`/`callers`/`callees`/`affected`/`status`/`files` are Bash-CLI only (verified on codegraph 0.9.7). Neither surface is a superset.
- **Proactive triggers** tied to actions (edit/rename/remove → `impact`; change a method → `callers`/`node`; unfamiliar code → `context`; flow → `trace`) rather than only phrased questions.
- **Reliability fallback**: when a capability isn't an MCP tool, use the CLI — never silently degrade to a half-grep that misses dynamic-dispatch call sites.
- Progressive-disclosure `reference.md` covering 4-step new-project setup, the read-only `settings.json` allowlist, and known gotchas (tool-managed `CODEGRAPH_START/END` block overwrites on re-sync, that block's table over-promising CLI commands as MCP tools, `daemon.pid` absent from the default gitignore).
