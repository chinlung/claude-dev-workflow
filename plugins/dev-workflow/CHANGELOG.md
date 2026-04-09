# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.2] - 2026-04-10

### Fixed
- `plugin.json` description said "6 specialized agents" but the plugin has always shipped 7 agents (including `documentation-specialist`). The description was a leftover from the `35c0a9c` refactor commit on 2026-03-12 that reverted the version string to match `CHANGELOG.md` [1.0.1] but also reverted the description text to the 1.0.0-era wording. Description now correctly reads "7 specialized agents" and includes "documentation" in the list.

### Notes
- No behavioural or file changes in this release — the 7 agent files (`issue-analyst.md`, `code-archaeologist.md`, `solution-architect.md`, `implementation-specialist.md`, `test-engineer.md`, `quality-assurance.md`, `documentation-specialist.md`) have been present continuously since the 1.1.0 era and were never removed. Only the `plugin.json` metadata drifted.

## [1.0.1] - 2025-01-14

### Added
- Add "Read Project Development Standards" step (Step 0) to 5 agents:
  - `code-archaeologist.md`: Read standards before exploring codebase
  - `documentation-specialist.md`: Read standards before updating docs
  - `quality-assurance.md`: Read standards before quality checks
  - `solution-architect.md`: Read standards before designing architecture
  - `test-engineer.md`: Read standards before writing tests
- Each agent now queries `**/skills/**/*.skill.md` to understand project-specific conventions and best practices

## [1.0.0] - 2024-12-24

### Added
- Initial release
- 7 specialized agents for complete development workflow
- Support for full workflow and single-step execution
- Task handoff system with `handoff.md`
- Pause confirmation point after architecture design
- Progress tracking with TodoWrite
