# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0.0 — Initial Release

**Shipped:** 2026-07-05
**Phases:** 1 | **Plans:** 1 | **Sessions:** retrospective closeout

### What Was Built

- Normal macOS SwiftUI Dock app with standard menu/window behavior.
- Codex and GLM / ZAI provider dashboards with quota rings, metric cards, refresh controls, settings, and error states.
- Codex local data path using app-server quota reads, session fallback, SQLite rollout paths, token-count parsing, and codexU-aligned cost/wool-progress calculations.
- GLM quota API path using local settings or Anthropic-compatible environment variables.
- App icon, local `.app` bundle script, and parser/unit verification coverage.

### What Worked

- Retrospective GSD mapping gave the already-built app enough structure for review, audit, and milestone history.
- Provider abstraction kept Codex and GLM behavior separate while sharing one dashboard model.
- Local-first data collection preserved the privacy constraint while still allowing provider quota APIs where required.

### What Was Inefficient

- GSD structure was added after implementation, so Phase 1 had to be reconstructed from code, screenshots, review notes, and handoff history.
- The first Codex usage implementation scanned too much local JSONL data before the cache and key-line extraction were added.
- The first milestone tag was created before complete-milestone closeout, requiring a final tag move to the true completion commit.

### Patterns Established

- Keep provider implementations behind `UsageProvider` and emit normalized `ProviderSnapshot` data.
- Store release and handoff truth in `.planning/` so future agents do not depend on chat history.
- Treat private provider credentials as user-owned local configuration, never repo data.

### Key Lessons

1. Start future feature work with `$gsd-new-milestone` before implementation so phase artifacts do not need to be reconstructed.
2. For local usage aggregation, measure source size and scan strategy early; hundreds of MB of JSONL can dominate perceived refresh speed.
3. Tags should point at the final milestone-complete state, not just the feature implementation state.

### Cost Observations

- Model mix: not measured.
- Sessions: retrospective closeout across one long implementation thread.
- Notable: most rework came from UI calibration and Codex data-source parity rather than SwiftUI app-shell work.

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v1.0.0 | retrospective | 1 | Added GSD structure after implementation so future milestones can run normally. |

### Cumulative Quality

| Milestone | Tests | Coverage | Zero-Dep Additions |
|-----------|-------|----------|-------------------|
| v1.0.0 | 14 passing tests | Parser, formatter, progress-marker, and local-time behavior | SwiftPM app with no third-party runtime dependency |

### Top Lessons (Verified Across Milestones)

1. Future work should begin with a milestone and requirements artifact before implementation.
2. Local data-source performance needs early instrumentation when source files are large.
