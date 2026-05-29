---
name: codegraph
description: Use when a project has a `.codegraph/` index and you need structural code intelligence — who calls a symbol, what breaks if you change it, where a symbol is defined, or how X reaches Y — instead of grep; also when enabling codegraph in a new project, or unsure which queries are MCP tools vs the codegraph CLI. Symptoms — about to grep for call sites, about to edit/rename/remove a symbol, picking up unfamiliar code, or a `codegraph_*` tool call failed with "not found".
---

# CodeGraph

## Overview

codegraph is a tree-sitter AST knowledge graph (SQLite). Sub-millisecond queries return **structural** facts grep can't: call edges, impact sets, symbol definitions, flow paths — including dynamic-dispatch hops (callbacks, facades) grep silently misses.

**Core rule:** for structural questions, query codegraph BEFORE grep. For literal text (string contents, comments, log messages) or once a file is already open, grep/Read is still right.

## Two entry points — neither is a superset

`serve --mcp` exposes only *some* commands as `codegraph_*` MCP tools; the rest are Bash CLI only. (Verified on codegraph 0.9.7 — re-check with `codegraph --help` if a tool call fails.)

| | MCP only | CLI only (`codegraph <cmd>`) | Both |
|---|---|---|---|
| | `trace`, `node`, `explore` | `callers`, `callees`, `impact`, `affected`, `status`, `files` | `search`/`query`, `context` |

- **Navigate / understand** (want code bodies, trace X→Y, survey area) → MCP: `context` / `trace` / `node` / `explore`
- **Analyze / list** (transitive impact, callers, affected tests) → CLI: `impact` / `callers` / `callees` / `affected`
- **Overlapping `context` / `search` → default MCP** (output is LLM-tuned: no ANSI noise, self-budgets context, no shell round-trip). Use CLI only when already piping/grepping in a Bash flow.

## Proactive triggers — query before you act, not only when asked

The structural question is usually implicit in an **action**, not a phrased question:

- **Before edit / rename / remove a symbol** → `codegraph impact <symbol>` (transitive blast radius). The execution tool for the "trace the call chain before changing anything" review discipline; stronger than grep (catches dynamic dispatch).
- **Before changing a method — who calls it?** → `codegraph callers <symbol>`, or MCP `codegraph_node <symbol>` (returns Called by ← call sites + Calls → callees, with file:line). Don't grep to count call sites.
- **Picking up unfamiliar code** → MCP `codegraph_context "<task>"` first, then Read.
- **Verify "how does X reach Y"** → MCP `codegraph_trace <from> <to>` (whole path, each hop's body, dynamic hops bridged).

## Reliability fallback

- A capability isn't an MCP tool (impact/callers/callees)? → use the **Bash CLI**, do NOT fall back to grep.
- A `codegraph_*` tool call fails / returns "not initialized" / the server disconnects? → **report it and retry / `codegraph init`**; don't silently grep — half a grep misses dynamic-dispatch call sites.
- PHP DI / facade callee resolution is a known weak spot — only there, supplement with a grep second-check.

## New-project setup & known gotchas

Read `reference.md` (in this skill dir) for: init steps, the `.mcp.json` snippet / `codegraph install`, the `.claude/settings.json` allowlist, and the gotchas (the tool-managed `CODEGRAPH_START/END` block gets overwritten on re-sync; that block's table over-promises CLI commands as `codegraph_*` MCP tools; `daemon.pid` isn't in the default gitignore).
