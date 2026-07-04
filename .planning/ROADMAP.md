# Roadmap: Quota Radar

## Overview

Quota Radar v1.0.0 delivers a normal macOS SwiftUI app for monitoring Codex and GLM / ZAI coding-plan quotas from local or provider-owned data sources. This roadmap is retrospective for the initial release because implementation started before full GSD phase tracking was added.

## Milestones

- ✅ **v1.0.0 Initial Release** - Phase 1 complete and archived. See `.planning/milestones/v1.0.0-ROADMAP.md`.
- 📋 **v1.1 Release Prep** - Future phases for GitHub/App Store packaging and follow-up features

## Phases

**Phase Numbering:**
- Integer phases: planned or retrospective milestone work.
- Decimal phases: future urgent insertions.

- [x] **Phase 1: Initial Release** - Implement the Quota Radar macOS app and v1.0.0 feature set. (completed 2026-07-05)

## Phase Details

### Phase 1: Initial Release
**Goal**: Build the Quota Radar macOS app with Codex and GLM quota monitoring, settings, provider abstraction, responsive dashboard UI, app icon, and local build/run verification.
**Depends on**: Nothing (first phase)
**Requirements**: APP-01 APP-02 APP-03 DASH-01 DASH-02 DASH-03 DASH-04 DASH-05 CODEX-01 CODEX-02 CODEX-03 CODEX-04 CODEX-05 GLM-01 GLM-02 GLM-03 SET-01 SET-02 SET-03 SET-04 PRIV-01 VER-01 VER-02 VER-03
**Success Criteria** (what must be TRUE):
  1. User can run Quota Radar as a normal macOS app with Dock icon, menu bar, standard window controls, and resizable window.
  2. User can see Codex and GLM provider panels with rings, cards, refresh status, settings-controlled colors, and settings-controlled card visibility.
  3. Codex data is read from local Codex app-server / `~/.codex` sources with codexU-aligned quota, usage, token, and cost calculations.
  4. GLM data is read from the GLM/ZAI quota API using local settings or Anthropic-compatible environment variables.
  5. `swift test`, `swift build`, and `./script/build_and_run.sh --verify` pass for the current release candidate.
**Plans**: 1/1 plans complete

Plans:
- [x] 01-01: Implement Quota Radar v1.0.0 app, provider data sources, UI, settings, icon, and verification scripts.

## Progress

**Execution Order:**
Phase 1 establishes v1.0.0. Future phases continue numbering from Phase 2.

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Initial Release | v1.0.0 | 1/1 | Complete | 2026-07-05 |

## Backlog

- Validate GLM quota display in the installed App with a real user-provided GLM / ZAI token.
- Prepare GitHub release and App Store packaging/signing decisions.
