# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.0] - 2026-03-12

### Added
- **Session Learning Plugin**: 經驗學習系統，漸進式保存對話模式
  - `/save-session` 命令：分析對話並保存有價值的模式為 memory 或 skill
    - 5 Phase 分析流程：掃描 → 層級判斷 → 去重合併 → 執行 → 報告
    - 自動區分全域 vs 專案層級保存位置
    - 更新優先於新建，避免記憶膨脹
    - 每次最多 1-2 項變更，精簡克制
  - Stop hook：在實質工作階段結束時輕量提醒執行 `/save-session`
    - Command 類型（非 prompt），不觸發額外 LLM 呼叫
    - Flag file 機制防止同一 session 重複提醒
    - 自動跳過短工作階段（< 10 行 transcript）
- Updated marketplace version to 1.4.0

## [1.3.0] - 2026-03-06

### Added
- **High-Precision Dev Plugin**: Multi-agent development mode for safety-critical code
  - `/high-precision-dev:init` command to scaffold SPEC.md and CONSENSUS.md
  - `/high-precision-dev:start` command to run the 4-phase verification workflow
  - 5 specialized agents:
    - Implementer A/B: Independent defensive implementation in isolated worktrees
    - Critic: Systematic bug finding with severity 1-5 scale
    - Adversary: 3-round red team attack (boundary, semantic, assumption)
    - Verifier: Final integration with SPEC.md coverage verification
  - Error rate compression from p to p^4 through epistemic division of labor
  - Phase 3 fix cycle limit (max 3 iterations) with adversary re-attack
  - Verifier Step Zero: checks CRITIQUE.md/ATTACKS.md before integration
  - Three-level intensity spectrum documentation (single agent → /debate → /start)
- Updated marketplace version to 1.1.0
- Updated README with High-Precision Dev plugin documentation (EN + zh-TW)

## [1.2.0] - 2025-12-19

### Added
- **Multi-Agent Debate Plugin**: A dialectical system for multi-perspective decision making
  - `/debate` command for initiating debates
  - 5 specialized agents:
    - Orchestrator: Analyzes requirements and configures perspectives
    - Perspective A/B/C: Proposes solutions from different angles
    - Critic: Reviews proposals and provides quantitative scoring
  - Smart perspective configuration based on requirement type
  - Quantitative scoring system (30-point scale)
  - Consensus-driven decision making (≥2 agents must agree)
  - Iterative refinement through multiple debate rounds
  - User participation at key decision points
- Updated README to document both plugins in the collection
- Traditional Chinese documentation for multi-agent-debate

## [1.1.0] - 2025-12-11

### Added
- **Documentation Specialist** agent (step 7): Handles documentation updates, CHANGELOG maintenance, and PR description generation
- **handoff.md mechanism**: Central state management document for seamless context transfer between agents
- Language agnostic design: works with any programming language
- Traditional Chinese documentation (README.zh-TW.md, CHANGELOG.zh-TW.md)

### Changed
- Generalized all agents to be language/framework agnostic
- Improved Implementation Specialist with better code pattern recognition
- Enhanced Quality Assurance with more comprehensive checks
- Updated Solution Architect with broader technology considerations
- Refined Test Engineer for multi-language test frameworks

### Fixed
- Repository field format in package.json (should be string not object)
- Corrected GitHub repository URL

### Documentation
- Added tutorial video link by Pahud Hsieh
- Added contributor credits
- Renumbered development workflow documents for sequence consistency

## [1.0.0] - 2024-12-11

### Added
- Initial release of dev-workflow plugin
- 6 specialized agents:
  - Issue Analyst: Requirements analysis and user stories
  - Code Archaeologist: Codebase exploration and pattern identification
  - Solution Architect: Architecture design and solution comparison
  - Implementation Specialist: Code implementation following best practices
  - Test Engineer: Test planning and execution
  - Quality Assurance: Code quality verification and build validation
- Main command `/dev-workflow` with support for:
  - Full workflow execution
  - Single step execution (`--step`)
  - Resume from checkpoint (`--resume`)
- Progress tracking with TodoWrite
- Pause point after architecture design for user confirmation
- Comprehensive documentation output in `docs/task-{timestamp}/` directory
