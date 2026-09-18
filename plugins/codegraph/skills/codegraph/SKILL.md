---
name: codegraph
description: Use when a project has a `.codegraph/` index and you need structural code intelligence — who calls a symbol, what breaks if you change it, where a symbol is defined, or how X reaches Y — instead of grep; also when enabling codegraph in a new project, or unsure which queries are MCP tools vs the codegraph CLI. Symptoms — about to grep for call sites, about to edit/rename/remove a symbol, picking up unfamiliar code, or a `codegraph_*` tool call failed with "not found".
---

# CodeGraph

## Overview

codegraph is a tree-sitter AST knowledge graph (SQLite). Sub-millisecond queries return **structural** facts grep can't: call edges, impact sets, symbol definitions, flow paths — including dynamic-dispatch hops (callbacks, facades) grep silently misses.

**Core rule:** for structural questions, query codegraph BEFORE grep. For literal text (string contents, comments, log messages) or once a file is already open, grep/Read is still right.

## Two entry points — one MCP tool, everything else on the CLI

(Verified on codegraph 1.6.0 — `codegraph --help`, plus `DEFAULT_MCP_TOOLS` in the platform bundle's `lib/dist/mcp/tools.js` (the npm package's top-level `dist/` is types-only). Re-check both if a call fails.)

By default `serve --mcp` lists **exactly one** tool: `codegraph_explore`. Upstream pared the menu down on purpose — one strong tool steers better than several narrow ones. Every other capability is a Bash CLI command.

| | Entry point |
|---|---|
| `explore` | **MCP** `codegraph_explore` **and** CLI `codegraph explore` — same handler, same output |
| `node`, `query`, `callers`, `callees`, `impact`, `files`, `status` | **CLI**. MCP handlers still exist but are unlisted; `CODEGRAPH_MCP_TOOLS=explore,node,…` on the server re-lists them (the value takes MCP short names — `query` is `search` there; unknown names are dropped silently) |
| `context`, `affected` | **CLI only** |
| ~~`trace`~~, ~~`codegraph_context`~~ | **Gone.** Path tracing ("how does X reach Y") is now part of `explore`'s call-path output |

- **Navigate / understand** (want code bodies, how X reaches Y, survey an area) → MCP `codegraph_explore "<question>"`. Name a file or symbol in the query to get its line-numbered source.
- **Analyze / list** (transitive impact, callers, affected tests) → CLI: `impact` / `callers` / `callees` / `affected`.
- **One symbol's body + caller/callee trail** → CLI `codegraph node <symbol>`.
- Prefer the MCP tool for `explore` (LLM-tuned output, self-budgets context, no shell round-trip); use `codegraph explore` when already in a Bash flow or when the MCP server is down.
- The server works per project: if it started somewhere with no `.codegraph/`, pass `projectPath` to `codegraph_explore`. CLI commands take `-p <path>`.

## Proactive triggers — query before you act, not only when asked

The structural question is usually implicit in an **action**, not a phrased question:

- **Before edit / rename / remove a symbol** → `codegraph impact <symbol>` (transitive blast radius). The execution tool for the "trace the call chain before changing anything" review discipline; stronger than grep (catches dynamic dispatch).
- **Before changing a method — who calls it?** → `codegraph callers <symbol>`, or `codegraph node <symbol>` (source + Called by ← / Calls → with file:line). Don't grep to count call sites.
- **Picking up unfamiliar code** → MCP `codegraph_explore "<task>"` first, then Read.
- **Verify "how does X reach Y"** → MCP `codegraph_explore "how does X reach Y"` (call paths between the symbols, each hop's body, dynamic hops bridged).
- **Which tests does this change touch?** → `codegraph affected [files...]`.

## Reliability fallback

- A `codegraph_*` MCP tool "not found" (`codegraph_node`, `codegraph_trace`, `codegraph_context`, …)? → it is **unlisted or removed in 1.6.0, not broken**. Use the CLI equivalent from the table above. Do NOT retry, and do NOT fall back to grep.
- `codegraph_explore` itself fails or the server disconnects? → run the same query as `codegraph explore "<query>"`; report the MCP failure.
- "No index" / "not initialized" for a project? → **report it and let the user decide.** Indexing is the user's call — do not run `codegraph init` / `index` / `sync` yourself. Until then use Read/Grep for that project, and say the structural answer is grep-grade.
- Checking whether a subcommand exists: **read the help text, not the exit code** — `codegraph <unknown> --help` prints the top-level help with rc=0.
- PHP DI / facade callee resolution is a known weak spot — only there, supplement with a grep second-check.

## New-project setup & known gotchas

Read `reference.md` (in this skill dir) for: init steps, the `.mcp.json` snippet / `codegraph install`, the `.claude/settings.json` allowlist, re-listing MCP tools with `CODEGRAPH_MCP_TOOLS`, and the gotchas (the tool-managed `CODEGRAPH_START/END` block gets overwritten on re-sync; `daemon.pid` isn't in the default gitignore).
