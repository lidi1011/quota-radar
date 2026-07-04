# Quota Radar

## What This Is

Quota Radar is a normal macOS SwiftUI Dock app for monitoring Codex and GLM / ZAI coding plan quota usage. It shows provider quota rings, token usage cards, plan progress, refresh state, and provider-specific settings in a resizable App window.

## Core Value

Show local Codex and GLM coding-plan quota status quickly and accurately without uploading usage data, tokens, threads, or credentials.

## Requirements

### Validated

- ✓ Normal macOS app shell with Dock icon, menu bar, standard window controls, and resizable window — v1.0.0 / Phase 1
- ✓ Codex quota and usage dashboard reads local `~/.codex` state, app-server rate limits, and session token logs — v1.0.0 / Phase 1
- ✓ GLM / ZAI quota dashboard reads the quota API using local settings or Anthropic-compatible environment variables — v1.0.0 / Phase 1
- ✓ Settings support refresh interval, provider colors, card visibility, and GLM credentials — v1.0.0 / Phase 1
- ✓ App includes Quota Radar icon and build/run verification script — v1.0.0 / Phase 1

### Active

- [ ] Validate GLM quota display in the installed App with a real user-provided GLM / ZAI token.
- [ ] Prepare GitHub and App Store release packaging decisions.

### Out of Scope

- codexU-style desktop floating window behavior — this product is intentionally a normal macOS app.
- Uploading local usage data or credentials — all quota data must remain local unless explicitly sent to provider quota APIs.
- Menu-bar-only utility mode — can be considered later, but v1.0.0 ships as a Dock app.

## Context

- Stack: SwiftPM, SwiftUI, macOS 14+, local `.app` bundle assembled by `script/build_and_run.sh`.
- Providers: Codex and GLM first, with `UsageProvider` abstraction for future providers.
- Codex source references: codexU and CodexBar implementation patterns, especially app-server rate limits and `token_count` log extraction.
- GLM source reference: `glm-plan-usage` quota API approach, implemented directly rather than depending on a local installed command.
- Current repo state was created before full GSD phase tracking existed; Phase 1 is a retrospective mapping of already implemented v1.0.0 work into GSD structure. The active v1.0.0 requirements have been archived under `.planning/milestones/`; future work should start with a fresh milestone.

## Constraints

- **Privacy**: Do not commit, log, or upload private tokens, cookies, account IDs, Codex threads, or provider credentials.
- **Platform**: macOS 14+ SwiftUI app, standard Dock app behavior.
- **Data sources**: Prefer local Codex state and provider quota APIs; no remote aggregation service.
- **UI**: Follow `DESIGN.md`: compact dark dashboard, modest radii, provider-specific accent colors, information-dense layout.
- **Verification**: Before release claims, run `swift test`, `swift build`, and `./script/build_and_run.sh --verify`.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Build as a normal Dock app instead of codexU-style floating window | User explicitly wanted standard macOS app behavior with Dock, menu, window controls, and resizing | ✓ Good |
| Use provider abstraction with Codex and GLM first | Keeps space for future providers without coupling UI to one backend | ✓ Good |
| Read Codex app-server rate limits before session-log fallback | Matches current Codex quota source more closely and avoids stale log-only data | ✓ Good |
| Use `state_5.sqlite` rollout paths and `token_count` key-line extraction for Codex cost cards | Aligns with codexU-style data scope and avoids repeatedly reading hundreds of MB of JSONL | ✓ Good |
| Store GLM credentials in local settings / env only | Keeps credentials local and avoids repo leakage | ✓ Good |
| Retrospectively create GSD Phase 1 for v1.0.0 | Initial implementation happened before full GSD phase setup; future reviews and milestones need structured state | ✓ Good |

## Current State

v1.0.0 Initial Release is implemented, reviewed, verified, audited, archived in `.planning/milestones/`, and ready for release-prep follow-up work.

## Next Milestone Goals

- Prepare GitHub release packaging.
- Prepare App Store signing, sandboxing, notarization, and privacy review.
- Validate GLM quota display with a real user-provided GLM/ZAI token.

---
*Last updated: 2026-07-05 after v1.0.0 milestone closeout*
