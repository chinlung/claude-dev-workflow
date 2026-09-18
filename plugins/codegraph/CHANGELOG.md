# Changelog

All notable changes to the `codegraph` plugin will be documented in this file.

## [1.1.0] - 2026-09-18

### Changed

- **Re-baselined on codegraph 1.6.0 (was 0.9.7).** Upstream now lists **only `codegraph_explore`** over MCP by default (`DEFAULT_MCP_TOOLS = new Set(['explore'])` in the platform bundle's `lib/dist/mcp/tools.js`); `codegraph_trace` and `codegraph_context` no longer exist, and `explore` / `node` gained CLI commands sharing the MCP handlers. The skill's entry-point table had four wrong cells (`explore`, `node`, `trace` as "MCP only"; `context` as "Both"), and its proactive triggers named three MCP tools (`codegraph_node`, `codegraph_context`, `codegraph_trace`) that a default 1.6.0 server does not offer. Table, navigation guidance and triggers are rewritten around "one MCP tool, everything else on the CLI"; flow tracing now points at `codegraph_explore`; an `affected` trigger is added.
- **Reliability fallback no longer tells the agent to run `codegraph init`.** The old rule answered a failed `codegraph_*` call with "retry / `codegraph init`". On 1.6.0 the usual cause is a tool that is unlisted or removed — retrying cannot help and `init` is an unrequested mutation. New rule: "not found" → use the CLI equivalent; `codegraph_explore` down → `codegraph explore`; missing index → report it and let the user decide (upstream's own MCP instructions say indexing is the user's call).
- `reference.md`: `codegraph init` replaces `init -i` (indexing is the default; `-i` is deprecated but accepted); the un-indexed-project trade-off now describes 1.6.0 behaviour (tool stays listed, `projectPath` targets any indexed project, a new index is picked up live); the allowlist drops the four MCP entries that no longer resolve and adds the read-only CLI commands `explore` / `node` / `query` / `context`; new section on re-listing tools with `CODEGRAPH_MCP_TOOLS`; new gotcha — `codegraph <unknown-subcommand> --help` exits 0, so existence must be read from the output.
- README and both root READMEs carry the same table and triggers.

### Notes

- Found while comparing CodeGraph with another code-graph tool: the skill's own "Verified on 0.9.7" line disagreed with the installed `codegraph --version`. An adversarial verifier asked to refute "two cells are stale" instead widened it to the above by reading `tools.js`.
- **Not re-verified on 1.6.0**: the two `reference.md` gotchas about what `codegraph install` writes into a project (`CODEGRAPH_START/END` table, generated allowlist). Checking them means running `install` against a project; they are kept and labelled "observed on 0.9.7".
- Not exercised: `codegraph explore` / `node` against a real index (help output and the shared-handler call sites in the platform bundle's `lib/dist/bin/codegraph.js` were read; no query was run), and `CODEGRAPH_MCP_TOOLS` re-listing (read from `getStaticTools()`, not run).

## [1.0.1] - 2026-06-29

### Fixed

- **Correct the prerequisite npm package name to `@colbymchenry/codegraph`.** The docs previously told users to `npm i -g codegraph`, but that unscoped name on npm is an unrelated third party's 469-byte placeholder (no `bin`) — following it installs nothing executable, so the bundled `.mcp.json` (`command: codegraph`) never resolves and the MCP server silently fails to start. The real upstream tool is the scoped `@colbymchenry/codegraph` (provides a `codegraph` binary). Updated the four references (`README.md` install command + two npmjs links, `skills/codegraph/reference.md` prerequisite). Also removes a dependency-confusion exposure: a scoped name cannot be confused with the unscoped squat. Found by a `security-audit` run and confirmed against the maintainer's working install.

## [1.0.0] - 2026-05-30

### Added

- Initial release.
- Single skill `codegraph` teaching structural-code-intelligence-before-grep discipline for projects with a `.codegraph/` index.
- **Bundled MCP server** (`.mcp.json` → `codegraph serve --mcp`): install the plugin once and the MCP tools (`context`/`trace`/`node`/`explore`/`search`) are available in every project — a new project then needs only `codegraph init -i`, no per-project `codegraph install` or `.mcp.json`. Plugin-provided tools are prefixed `mcp__plugin_codegraph_codegraph__<tool>`. Requires the `codegraph` CLI on `PATH` globally. Trade-off: the server launches in un-indexed projects too (returns "not initialized" until indexed).
- **Entry-point split documentation**: the non-obvious fact that `serve --mcp` exposes only `trace`/`node`/`explore`/`search`/`context` as MCP tools, while `impact`/`callers`/`callees`/`affected`/`status`/`files` are Bash-CLI only (verified on codegraph 0.9.7). Neither surface is a superset.
- **Proactive triggers** tied to actions (edit/rename/remove → `impact`; change a method → `callers`/`node`; unfamiliar code → `context`; flow → `trace`) rather than only phrased questions.
- **Reliability fallback**: when a capability isn't an MCP tool, use the CLI — never silently degrade to a half-grep that misses dynamic-dispatch call sites.
- Progressive-disclosure `reference.md` covering 4-step new-project setup, the read-only `settings.json` allowlist, and known gotchas (tool-managed `CODEGRAPH_START/END` block overwrites on re-sync, that block's table over-promising CLI commands as MCP tools, `daemon.pid` absent from the default gitignore).
