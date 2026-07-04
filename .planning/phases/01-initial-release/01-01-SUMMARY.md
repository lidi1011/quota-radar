---
phase: 001-initial-release
plan: 01
subsystem: macos-app
tags: [swiftui, macos, codex, glm, quota, release]
provides:
  - Normal macOS SwiftUI Dock app for Quota Radar
  - Codex and GLM provider dashboard panels
  - Settings for refresh interval, provider colors, card visibility, and GLM credentials
  - Codex local quota, token, cost, and wool-progress calculation
  - GLM/ZAI quota API integration
  - App icon and local build/run verification script
affects: [app-shell, provider-data, dashboard-ui, settings, release]
tech-stack:
  added: [SwiftPM, SwiftUI, Foundation, AppKit interop via SwiftUI app lifecycle]
  patterns: [UsageProvider abstraction, ProviderSnapshot model, local-only data collection, provider-specific preferences]
key-files:
  created:
    - Package.swift
    - Sources/QuotaRadar/QuotaRadarApp.swift
    - Sources/QuotaRadar/Services/CodexProvider.swift
    - Sources/QuotaRadar/Services/GLMProvider.swift
    - Sources/QuotaRadar/Stores/UsageStore.swift
    - Sources/QuotaRadar/Stores/AppSettings.swift
    - Sources/QuotaRadar/Views/ContentView.swift
    - Sources/QuotaRadar/Views/ProviderPanelView.swift
    - Sources/QuotaRadar/Views/QuotaRingView.swift
    - Sources/QuotaRadar/Views/UsageCardView.swift
    - Sources/QuotaRadar/Views/SettingsView.swift
    - Sources/QuotaRadar/Resources/AppIcon.icns
    - script/build_and_run.sh
    - Tests/QuotaRadarTests/ParserTests.swift
  modified:
    - README.md
    - DESIGN.md
    - .planning/HANDOFF.md
    - .planning/TODO.md
key-decisions:
  - "Build Quota Radar as a normal Dock app rather than a desktop floating window."
  - "Use UsageProvider and ProviderSnapshot to keep Codex, GLM, and future providers extensible."
  - "Read Codex app-server rate limits first, then fall back to local session rate_limits."
  - "Use state_5.sqlite rollout paths and token_count key-line extraction for Codex usage/cost aggregation."
  - "Read GLM quota directly from GLM/ZAI API using local settings or Anthropic-compatible env vars."
coverage:
  - id: VER-01
    description: swift test passes
    verification: ["swift test"]
    human_judgment: false
  - id: VER-02
    description: swift build passes
    verification: ["swift build"]
    human_judgment: false
  - id: VER-03
    description: app bundle launches
    verification: ["./script/build_and_run.sh --verify"]
    human_judgment: false
  - id: GLM-REAL
    description: GLM real account display validation in installed App
    verification: ["Requires user-provided GLM/ZAI token"]
    human_judgment: true
    rationale: "Agent must not fabricate access to private GLM credentials."
duration: retrospective
completed: 2026-07-05
status: complete
---

# Phase 1: Initial Release Summary

Quota Radar v1.0.0 is implemented as a normal macOS SwiftUI app for Codex and GLM / ZAI coding-plan quota monitoring.

## Performance

- **Duration:** Retrospective entry; original work was completed before full GSD phase setup.
- **Tasks:** 1 retrospective release plan completed.
- **Files modified:** SwiftPM app sources, provider services, SwiftUI views, settings store, tests, scripts, docs, planning files.

## Accomplishments

- Built a standard macOS app shell with Dock visibility, menu bar, standard traffic-light controls, and resizable main window.
- Implemented Codex and GLM provider panels with quota rings, usage cards, refresh controls, loading/error states, and responsive layout.
- Added Settings tabs for global refresh interval, provider-specific colors, card visibility, and GLM credentials.
- Implemented Codex quota data collection using app-server `account/rateLimits/read`, session `rate_limits` fallback, SQLite rollout paths, and token-count parsing.
- Aligned Codex cost/wool-progress calculations with codexU-informed model pricing, visible token totals, and subscription-band progress markers.
- Implemented GLM quota API access directly from provider endpoint, with local settings/env credential resolution and clear credential error states.
- Added App icon resources and `script/build_and_run.sh` to assemble and launch a local `.app` bundle.
- Added parser/unit coverage for Codex rate limit parsing, Codex token parsing, GLM status/platform parsing, formatting, progress markers, and local time behavior.
- Optimized startup/refresh by moving provider snapshots off MainActor, using concurrent provider refresh, and caching unchanged Codex session parse results.

## Task Commits

1. **Task 1: Implement Quota Radar v1.0.0** - not yet committed; repository still needs initial release commit.

## Files Created/Modified

- `Sources/QuotaRadar/Services/CodexProvider.swift` - Codex quota, token, cost, and progress data source.
- `Sources/QuotaRadar/Services/GLMProvider.swift` - GLM/ZAI quota API data source.
- `Sources/QuotaRadar/Stores/UsageStore.swift` - refresh state and concurrent provider refresh orchestration.
- `Sources/QuotaRadar/Views/ProviderPanelView.swift` - provider panel layout and card/ring composition.
- `Sources/QuotaRadar/Views/QuotaRingView.swift` - quota ring visualization and gradient behavior.
- `Sources/QuotaRadar/Views/UsageCardView.swift` - metric cards and plan progress card.
- `Sources/QuotaRadar/Views/SettingsView.swift` - Settings UI and provider tabs.
- `Tests/QuotaRadarTests/ParserTests.swift` - parser and formatter regression tests.
- `script/build_and_run.sh` - local `.app` bundle assembly and launch verification.

## Decisions & Deviations

- Decision: Keep the product as a normal macOS app, not a codexU-like floating desktop window.
- Decision: Keep provider credentials and usage data local; GLM calls go only to the configured provider API.
- Decision: Add retrospective GSD structure after implementation so v1.0.0 can still receive GSD review/audit/milestone closeout.
- Deviation: Phase 1 was implemented before PLAN/SUMMARY artifacts existed; this document records the completed scope for future GSD continuity.

## Validation Evidence

- `swift test` passed at 2026-07-05 02:33 with 12 tests and 0 failures.
- `swift build` passed at 2026-07-05 02:33 with exit 0.
- `./script/build_and_run.sh --verify` passed at 2026-07-05 02:33 with exit 0 and launched QuotaRadar.

## Quality Check

All release-candidate checks pass for the recorded verification commands.

## Next Phase Readiness

The app is ready for standard GSD review and milestone audit. Remaining release-prep items are review findings, initial Git commit/tag, optional GitHub release packaging, and App Store distribution planning.
