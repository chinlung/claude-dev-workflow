# Changelog

All notable changes to the `pr` plugin will be documented in this file.

## [1.0.0] - 2026-10-20

### Added

- Initial release: the `pr` skill, a PR-body template with three sections — Summary (the smallest visual that makes the point: pseudocode, call tree, component or file tree, Mermaid, or a diff sketch), Evidence (before / after), and Merge Danger (one-way vs two-way door, blast radius). Ported from a standalone `pr` skill; the `GLOSSARY.md` instruction now applies only when the repository has one, and the Codex-only `agents/openai.yaml` was not carried over. Summary visuals credited to Dex Horthy's `show-me` skill in `skills/pr/CREDITS.md`.
