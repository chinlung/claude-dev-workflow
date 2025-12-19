# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
