# Claude Code Plugins Collection

[English](README.md) | [繁體中文](README.zh-TW.md)

A collection of powerful plugins for Claude Code, featuring automated development workflows and multi-perspective decision-making systems.

## Available Plugins

| Plugin | Description | Command |
|--------|-------------|---------|
| [Dev Workflow](#dev-workflow-plugin) | Complete development workflow from requirements to QA | `/dev-workflow` |
| [Multi-Agent Debate](#multi-agent-debate-plugin) | Multi-perspective analysis with critical review | `/debate` |

## Installation

```bash
# Add the marketplace
/plugin marketplace add chinlung/claude-dev-workflow

# Install all plugins
/plugin install dev-workflow@scl-claude-plugins
/plugin install multi-agent-debate@scl-claude-plugins
```

Or install directly:

```bash
/plugin install chinlung/claude-dev-workflow
```

---

# Dev Workflow Plugin

A comprehensive development workflow system for Claude Code, automating the journey from requirements analysis to quality assurance.

Inspired by the 8-role workflow system from [Kiro IDE](https://kiro.dev), designed by [Pahud Hsieh](https://www.facebook.com/pahud.hsieh). Watch the [tutorial video](https://www.youtube.com/watch?v=RdrRHXbXZF8) to learn more about the original concept.

## Features

- **7 Specialized Agents** working in sequence
- **Structured Documentation** output for every phase
- **handoff.md Mechanism** for seamless context transfer between agents
- **Pause Point** after architecture design for user confirmation
- **Progress Tracking** with TodoWrite
- **Flexible Execution**: Full workflow, single step, or resume from checkpoint
- **Language Agnostic**: Works with any programming language

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

---

# Multi-Agent Debate Plugin

A multi-agent dialectical system that generates optimal solutions through multi-perspective analysis and critical review.

## Features

- **5 Specialized Agents** working collaboratively
- **Smart Perspective Configuration** based on requirement type
- **Quantitative Scoring System** (30-point scale)
- **Consensus-Driven Decision Making** (≥2 agents must agree)
- **Iterative Refinement** through multiple debate rounds
- **User Participation** at key decision points

## Usage

### Basic Usage

```bash
/debate Design a caching strategy for the API layer
```

### With Options

```bash
/debate <requirement> [--max-rounds N] [--perspectives "angle1,angle2,angle3"]
```

**Examples:**
```bash
/debate Should we use microservices or monolith for the new project?
/debate --max-rounds 5 How to optimize database query performance?
/debate --perspectives "security,performance,maintainability" Design the authentication system
```

## Agents

| Agent | Role |
|-------|------|
| Orchestrator | Analyzes requirements, configures perspectives, manages workflow |
| Perspective A | Proposes solutions from assigned angle |
| Perspective B | Proposes solutions from assigned angle |
| Perspective C | Proposes solutions from assigned angle |
| Critic | Reviews all proposals, raises challenges, provides quantitative scoring |

## Workflow

```
┌─────────────────┐
│  Orchestrator   │ → Analyze & Configure Perspectives
└────────┬────────┘
         ▼
┌─────────────────────────────────────┐
│  Perspective A │ B │ C  (Parallel)  │ → Initial Proposals
└────────┬────────────────────────────┘
         ▼
┌─────────────────┐
│     Critic      │ → Review & Challenge
└────────┬────────┘
         ▼
┌─────────────────────────────────────┐
│  Perspective A │ B │ C  (Parallel)  │ → Rebuttals & Revisions
└────────┬────────────────────────────┘
         ▼
┌─────────────────┐
│ Consensus Check │ → ≥2 agree? → Done
└────────┬────────┘   Otherwise ↩️ Back to Critic
         ▼
┌─────────────────┐
│  User Decision  │ → Continue / Adopt / Intervene / Reset
└─────────────────┘
```

## Smart Perspective Configuration

The Orchestrator automatically selects perspectives based on requirement type:

| Requirement Type | Perspective A | Perspective B | Perspective C |
|-----------------|---------------|---------------|---------------|
| Architecture Design | Performance-First | Maintainability-First | Scalability-First |
| Feature Development | Fast Delivery | Quality-First | UX-First |
| Performance Optimization | Algorithm Optimization | Caching Strategy | Architecture Refactoring |
| Bug Fixing | Quick Patch | Root Cause Fix | Defensive Refactoring |
| Technology Selection | Mainstream & Stable | Emerging Tech | Custom Solution |
| Security Issues | Least Privilege | Defense in Depth | Zero Trust |
| User Experience | Simplify Flow | Add Guidance | Customization |
| Cost Control | Minimum Cost | Balanced Approach | Long-term Investment |
| Refactoring | Incremental | Complete Rewrite | Hybrid Strategy |

## Scoring Criteria

The Critic evaluates each proposal on three dimensions (10 points each, 30 total):

| Dimension | Criteria |
|-----------|----------|
| **Feasibility** | Technical achievability, resource availability, timeline reasonability |
| **Benefit** | Problem resolution degree, positive value, ROI |
| **Risk Control** | Risk identification completeness, mitigation reliability, failure impact scope |

**Score Guide:**
- 9-10: Excellent - Complete solution / Mature technology
- 7-8: Good - Mostly solved / Minor preparation needed
- 5-6: Fair - Partially solved / Challenges exist but manageable
- 3-4: Poor - Limited benefit / Significant resources required
- 1-2: Very Poor - Minimal benefit / Questionable feasibility

## Use Cases

- Architecture design decisions
- Feature development planning
- Performance optimization strategies
- Bug fix approaches
- Technology stack selection
- Security solution design
- UX improvement strategies
- Cost optimization plans
- Refactoring task planning

---

## Configuration

Both plugins work out of the box with any project. Each agent adapts to your project's structure and conventions.

For project-specific coding standards, consider creating a `CLAUDE.md` file in your project root with your team's guidelines.

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgments

- Dev Workflow inspired by the 8-role workflow system from [Kiro IDE](https://kiro.dev), designed by [Pahud Hsieh](https://www.facebook.com/pahud.hsieh)
- [Tutorial video](https://www.youtube.com/watch?v=RdrRHXbXZF8) explaining the original workflow concept
- Built for [Claude Code](https://claude.ai/code)
