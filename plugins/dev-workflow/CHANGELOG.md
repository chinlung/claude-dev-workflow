# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
