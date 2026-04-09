# Claude Code Plugins Collection

[English](README.md) | [繁體中文](README.zh-TW.md)

A collection of powerful plugins for Claude Code, featuring automated development workflows and multi-perspective decision-making systems.

## Available Plugins

| Plugin | Description | Command |
|--------|-------------|---------|
| [Dev Workflow](#dev-workflow-plugin) | Complete development workflow from requirements to QA | `/dev-workflow` |
| [Multi-Agent Debate](#multi-agent-debate-plugin) | Multi-perspective analysis with critical review | `/debate` |
| [High-Precision Dev](#high-precision-dev-plugin) | Safety-critical code with p^4 error rate compression | `/init`, `/start` |
| [OpenSpec + Superpowers Workflow](#openspec--superpowers-workflow-plugin) | Six-phase feature development enforcing OpenSpec/Superpowers role separation | auto-triggered skill |

## Installation

```bash
# Add the marketplace
/plugin marketplace add chinlung/claude-dev-workflow

# Install all plugins
/plugin install dev-workflow@scl-claude-plugins
/plugin install multi-agent-debate@scl-claude-plugins
/plugin install high-precision-dev@scl-claude-plugins
/plugin install openspec-superpowers-workflow@scl-claude-plugins
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

---

# High-Precision Dev Plugin

A multi-agent development mode that compresses single-agent error rate from p to p^4 through epistemic division of labor. Designed for safety-critical code: cryptography, financial calculations, data validation, and security-critical logic.

## Intensity Spectrum

This plugin is the highest level of a three-level intensity spectrum:

```
Single Agent (~1x)  →  /debate (~4-5x)  →  /start (~12-18x)
General CRUD           Decisions            Safety-critical code
```

**Chain them**: Use `/debate` to decide What/Why, then `/start` to implement How.

## Usage

### Step 1: Initialize

```bash
/init parse_amount
```

This creates `SPEC.md` and `CONSENSUS.md` templates. Fill in SPEC.md completely (especially the boundary conditions table).

### Step 2: Start

```bash
/start ./SPEC.md
```

This runs the full 4-phase workflow:

1. **Spec Review** — All agents review SPEC.md for ambiguity
2. **Dual Implementation** — Two implementers work independently in isolated worktrees
3. **Adversarial Review** — Critic finds bugs + Adversary attacks with 3 rounds
4. **Integration** — Verifier merges the best parts with full SPEC.md coverage

## Agents

| Agent | Role | Output |
|-------|------|--------|
| Implementer A | Independent defensive implementation | `IMPL_A_REPORT.md` |
| Implementer B | Independent defensive implementation | `IMPL_B_REPORT.md` |
| Critic | Find bugs using severity 1-5 scale | `CRITIQUE.md` |
| Adversary | 3-round red team attack (boundary, semantic, assumption) | `ATTACKS.md` |
| Verifier | Compare, merge, verify against SPEC.md | `VERIFICATION.md` |

## Workflow

```
┌─────────────────────────────────────┐
│  All Agents (except Verifier)       │ → Spec Review
└────────────────┬────────────────────┘
                 ▼
┌─────────────────────────────────────┐
│  Implementer A │ B  (Parallel)      │ → Independent Implementation
│  (Worktree Isolation)               │
└────────────────┬────────────────────┘
                 ▼
┌─────────────────────────────────────┐
│  Critic │ Adversary  (Parallel)     │ → Adversarial Review
└────────────────┬────────────────────┘
    severity ≥ 3 │ ↩️ Fix cycle (max 3)
                 ▼
┌─────────────────────────────────────┐
│           Verifier                  │ → Final Integration
└─────────────────────────────────────┘
```

## When to Use

| Use This | Use `/debate` Instead | Use Single Agent |
|----------|-----------------------|------------------|
| Core algorithms | Architecture decisions | General CRUD |
| Cryptography | Technology selection | UI adjustments |
| Financial calculations | Design trade-offs | Config changes |
| Data validation | Refactoring strategy | Quick prototypes |
| Security-critical logic | Spec validation | |

---

# OpenSpec + Superpowers Workflow Plugin

A six-phase feature development workflow that enforces strict role separation between **OpenSpec** (spec lifecycle, the WHAT) and **Superpowers** (dev discipline, the HOW). Prevents the two toolkits from stepping on each other and eliminates the most common anti-patterns: modifying specs during code review, patching specs incrementally instead of clean rewriting, and leaking cross-cutting constitution rules into individual feature specs.

This plugin ships a single auto-triggered skill (no slash command) — it activates when you mention feature proposals, brainstorming, task planning, PR review, reconciliation, or archiving work inside an OpenSpec-initialized project.

## Prerequisites

- **[OpenSpec CLI](https://github.com/Fission-AI/OpenSpec)** — `npm i -g @fission-ai/openspec`; run `openspec init .` once per project
- **[Superpowers](https://github.com/anthropic-experimental/claude-code-plugins/tree/main/superpowers)** plugin — provides `brainstorming`, `writing-plans`, `subagent-driven-development`, `test-driven-development` skills

## Six-Phase Workflow

| Phase | Leader | Action | Output |
|-------|--------|--------|--------|
| 1. Spec Definition | OpenSpec | `openspec new change` + fill `proposal.md` / `specs/` | User-reviewed proposal + specs |
| 2. Design Refinement | Superpowers `brainstorming` | Socratic refinement | **OVERWRITES** `design.md` in place |
| 3. Task Planning | Superpowers `writing-plans` | 2-5 min granularity tasks | **OVERWRITES** `tasks.md` in place |
| 4. Implementation | Superpowers `subagent-driven-development` + TDD | RED → GREEN → REFACTOR | Working code |
| 5. Review & Feedback | Human-driven | Tag feedback `[REQUIREMENT\|DESIGN\|CODE\|CONSTITUTION]` + Y/N | `review-notes.md`; **specs are never touched** |
| 6. Reconcile & Archive | OpenSpec | Clean rewrite (not patch) + `openspec archive` | Merged into `openspec/specs/<capability>/spec.md` |

## Six Non-Negotiable Rules

1. **Never modify spec files during Phase 5 code review.** All feedback → `review-notes.md` with tag + Y/N.
2. **Never create separate Superpowers design/plan files.** Outputs OVERWRITE OpenSpec's `design.md` / `tasks.md` in place.
3. **Phase 6 reconciliation = clean rewrite.** Goal: specs read as if you knew everything from the start, not a changelog.
4. **`tasks.md` is frozen during reconciliation** — it is execution history, not current spec.
5. **`[CONSTITUTION]` items never go into the feature's spec** — they update `openspec/config.yaml` `context:` / `rules:`.
6. **TDD in Phase 4 is mandatory.** Tests before implementation, always.

## Skill Structure (Progressive Disclosure)

```
skills/openspec-superpowers-workflow/
├── SKILL.md      # 58 lines — trigger map + phase table + 6 rules (always loaded)
└── phases.md     # 290+ lines — full playbook, tag semantics, gotchas (loaded on demand)
```

When the skill activates, Claude first reads `SKILL.md`, identifies which phase applies, then reads the relevant section of `phases.md`. Context budget stays controlled even with a detailed playbook.

## Problems It Solves

Without this skill:
- ❌ `brainstorming` writes to `docs/superpowers/specs/<date>-<topic>.md`, drifting from OpenSpec's `design.md`
- ❌ PR review comments are applied to specs directly, breaking reproducibility
- ❌ Phase 6 reconciliation becomes patch accumulation — nobody can read the spec six months later
- ❌ Cross-cutting rules like "all PHP files must `declare(strict_types=1)`" get written into every feature spec

With this skill:
- ✅ Claude recognises which Phase you are in and applies the correct discipline automatically
- ✅ All working files stay inside `openspec/changes/<name>/` — no scattered sidecars
- ✅ `review-notes.md` is the single feedback channel; reconciliation has a clean list of Y items
- ✅ Constitution rules go to `openspec/config.yaml`, visible to every future `openspec instructions` call

## Not For

- Small bug fixes with no spec impact (do it with TDD directly, skip the six phases)
- Pure prototyping where formal Phase 1 specs would slow exploration
- Projects that do not use OpenSpec (the skill detects absence of `openspec/` and stays dormant)

---

## Configuration

All plugins work out of the box with any project. Each agent adapts to your project's structure and conventions.

For project-specific coding standards, consider creating a `CLAUDE.md` file in your project root with your team's guidelines.

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgments

- Dev Workflow inspired by the 8-role workflow system from [Kiro IDE](https://kiro.dev), designed by [Pahud Hsieh](https://www.facebook.com/pahud.hsieh)
- [Tutorial video](https://www.youtube.com/watch?v=RdrRHXbXZF8) explaining the original workflow concept
- Built for [Claude Code](https://claude.ai/code)
