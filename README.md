# Claude Dev Workflow Plugin

[English](README.md) | [繁體中文](README.zh-TW.md)

A comprehensive development workflow system for Claude Code, automating the journey from requirements analysis to quality assurance.

Inspired by the 8-role workflow system from [Kiro IDE](https://kiro.dev), designed by [Pahud Hsieh](https://www.facebook.com/pahud.hsieh). Watch the [tutorial video](https://www.youtube.com/watch?v=RdrRHXbXZF8) to learn more about the original concept. This plugin adapts the workflow for Claude Code's architecture.

## Features

- **7 Specialized Agents** working in sequence
- **Structured Documentation** output for every phase
- **handoff.md Mechanism** for seamless context transfer between agents
- **Pause Point** after architecture design for user confirmation
- **Progress Tracking** with TodoWrite
- **Flexible Execution**: Full workflow, single step, or resume from checkpoint
- **Language Agnostic**: Works with any programming language

## Installation

```bash
# Add the marketplace
/plugin marketplace add chinlung/claude-dev-workflow

# Install the plugin
/plugin install dev-workflow@scl-claude-plugins
```

Or install directly:

```bash
/plugin install chinlung/claude-dev-workflow
```

## Usage

### Full Workflow

```bash
/dev-workflow Implement user authentication feature
```

This executes all 7 phases in sequence:
1. **Requirements Analysis** → `01-requirements-analysis.md`
2. **Code Exploration** → `02-code-analysis.md`
3. **Architecture Design** → `03-architecture-design.md` (pauses for confirmation)
4. **Implementation** → `04-implementation-report.md`
5. **Testing** → `05-test-report.md`
6. **Quality Assurance** → `06-quality-report.md`
7. **Documentation** → `07-documentation-report.md`

### Single Step Execution

```bash
/dev-workflow --step analyze Analyze shopping cart requirements
/dev-workflow --step explore Explore authentication code
/dev-workflow --step design Design payment integration
/dev-workflow --step implement Implement the feature
/dev-workflow --step test Write tests for the feature
/dev-workflow --step qa Run quality checks
/dev-workflow --step docs Update documentation and generate PR
```

### Resume from Checkpoint

```bash
/dev-workflow --resume docs/task-20241211-1430-auth-feature/
```

## Agents

| Agent | Role | Output |
|-------|------|--------|
| Issue Analyst | Requirements analysis, user stories, success criteria | `01-requirements-analysis.md` |
| Code Archaeologist | Codebase exploration, pattern identification, reusable components | `02-code-analysis.md` |
| Solution Architect | Architecture design, solution comparison, implementation plan | `03-architecture-design.md` |
| Implementation Specialist | Code implementation following best practices | `04-implementation-report.md` |
| Test Engineer | Test planning, writing, and execution | `05-test-report.md` |
| Quality Assurance | Lint, type check, build verification, code review | `06-quality-report.md` |
| Documentation Specialist | README, CHANGELOG, API docs, PR description | `07-documentation-report.md` |

## Output Structure

All reports are saved in a task directory:

```
docs/task-{YYYYMMDD-HHMM}-{brief-name}/
├── 01-requirements-analysis.md
├── 02-code-analysis.md
├── 03-architecture-design.md
├── 04-implementation-report.md
├── 05-test-report.md
├── 06-quality-report.md
├── 07-documentation-report.md
├── handoff.md
└── summary.md
```

## Workflow Diagram

```
┌─────────────────┐
│  Issue Analyst  │ → Requirements & User Stories
└────────┬────────┘
         ▼
┌─────────────────┐
│Code Archaeologist│ → Codebase Analysis
└────────┬────────┘
         ▼
┌─────────────────┐
│Solution Architect│ → Architecture Design
└────────┬────────┘
         ▼
    ⏸️ PAUSE (User Confirmation)
         ▼
┌─────────────────┐
│Implementation   │ → Working Code
│   Specialist    │
└────────┬────────┘
         ▼
┌─────────────────┐
│  Test Engineer  │ → Test Suite
└────────┬────────┘
         ▼
┌─────────────────┐
│Quality Assurance│ → Quality Report
└────────┬────────┘
         ▼
┌─────────────────┐
│ Documentation   │ → Docs & PR Description
│   Specialist    │
└─────────────────┘
```

## Configuration

The plugin works out of the box with any project. Each agent will adapt to your project's structure and conventions.

For project-specific coding standards, consider creating a `CLAUDE.md` file in your project root with your team's guidelines.

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgments

- Inspired by the 8-role workflow system from [Kiro IDE](https://kiro.dev), designed by [Pahud Hsieh](https://www.facebook.com/pahud.hsieh)
- [Tutorial video](https://www.youtube.com/watch?v=RdrRHXbXZF8) explaining the original workflow concept
- Built for [Claude Code](https://claude.ai/code)
