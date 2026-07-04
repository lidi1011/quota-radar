# Project Milestones: Quota Radar

Entries are added when a milestone is formally closed with GSD.

## v1.0.0 Initial Release (Shipped: 2026-07-05)

**Delivered:** A normal macOS SwiftUI Dock app for monitoring Codex and GLM / ZAI coding-plan quotas.

**Phases completed:** Phase 1 (1 plan total)

**Key accomplishments:**

- Built a standard macOS app shell with Dock icon, menu bar, traffic-light controls, and resizable window.
- Implemented Codex and GLM provider dashboards with quota rings, usage cards, refresh controls, loading states, and error states.
- Added settings for refresh interval, provider colors, card visibility, and GLM/ZAI credentials.
- Matched Codex quota/cost behavior to codexU-informed app-server, SQLite, token-count, and pricing logic.
- Added local `.app` build/run script, app icon, and parser/unit verification coverage.

**Stats:**

- 62 files in the initial release commit.
- 2,639 Swift lines across app sources and tests.
- 1 phase, 1 plan, 24/24 v1 requirements covered.
- Verification: `swift test`, `swift build`, `./script/build_and_run.sh --verify`.
- Audit: `.planning/milestones/v1.0.0-MILESTONE-AUDIT.md`.
- Archives: `.planning/milestones/v1.0.0-ROADMAP.md`, `.planning/milestones/v1.0.0-REQUIREMENTS.md`.
- Deferred items: GLM real-token App validation and GitHub/App Store packaging.

**Git range:** initial release commit -> milestone completion commit

## Next

- v1.1 Release Prep - GitHub release packaging, App Store packaging/signing, and follow-up provider refinements.
