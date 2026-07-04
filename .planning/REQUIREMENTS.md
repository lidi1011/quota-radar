# Requirements: Quota Radar

**Defined:** 2026-07-05
**Core Value:** Show local Codex and GLM coding-plan quota status quickly and accurately without uploading usage data, tokens, threads, or credentials.

## v1 Requirements

Requirements for the initial v1.0.0 release.

### App Shell

- [x] **APP-01**: App runs as a normal macOS Dock app with system menu bar.
- [x] **APP-02**: Main window has standard close, minimize, zoom controls and can be resized.
- [x] **APP-03**: App includes a 1:1 Quota Radar icon in the generated `.app` bundle.

### Provider Dashboard

- [x] **DASH-01**: Main window displays Codex and GLM provider panels.
- [x] **DASH-02**: Each provider panel shows quota rings, reset labels, refresh status, and error state.
- [x] **DASH-03**: Provider cards can be hidden independently without breaking responsive layout.
- [x] **DASH-04**: Codex panel shows today, recent 7 days, total usage, and wool progress cards.
- [x] **DASH-05**: GLM panel shows 5-hour token, 7-day quota, MCP, and multiplier/API cards.

### Codex Data

- [x] **CODEX-01**: Codex quota is read from local Codex app-server `account/rateLimits/read` when available.
- [x] **CODEX-02**: Codex quota falls back to local session `rate_limits` data when app-server is unavailable.
- [x] **CODEX-03**: Codex usage reads local `~/.codex/state_5.sqlite` rollout paths and session JSONL token data.
- [x] **CODEX-04**: Codex token cost uses model-aware pricing and `total_token_usage` delta behavior aligned with codexU.
- [x] **CODEX-05**: Codex refresh avoids repeatedly reading unchanged full JSONL files.

### GLM Data

- [x] **GLM-01**: GLM quota is read directly from the GLM/ZAI quota API.
- [x] **GLM-02**: GLM credentials can come from App settings or `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_BASE_URL`.
- [x] **GLM-03**: Missing or invalid GLM credentials produce a clear provider-level error state.

### Settings

- [x] **SET-01**: Settings include global refresh interval.
- [x] **SET-02**: Settings include separate Codex and GLM ring/card colors.
- [x] **SET-03**: Settings include separate visible-card controls for Codex and GLM.
- [x] **SET-04**: GLM credential fields live under the GLM settings tab.

### Privacy And Verification

- [x] **PRIV-01**: App does not upload local Codex usage, session, thread, or credential data to a non-provider service.
- [x] **VER-01**: Project can run `swift test`.
- [x] **VER-02**: Project can run `swift build`.
- [x] **VER-03**: Project can build and launch the `.app` bundle with `./script/build_and_run.sh --verify`.

## v2 Requirements

Deferred to future releases.

### Distribution

- **DIST-01**: Prepare GitHub release package.
- **DIST-02**: Prepare App Store packaging, signing, sandbox, and privacy review.

### Product Extensions

- **PROV-01**: Add additional provider types without rewriting the main dashboard.
- **MENUBAR-01**: Consider optional menu bar companion mode while preserving normal app behavior.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Desktop floating / no-Dock behavior | Explicitly rejected for v1.0.0; app should behave like a normal macOS app. |
| Server-side usage aggregation | Conflicts with privacy goal and is not needed for v1.0.0. |
| Automatic GLM real-account validation without user token | Requires private credentials from the user. |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| APP-01 | Phase 1 | Complete |
| APP-02 | Phase 1 | Complete |
| APP-03 | Phase 1 | Complete |
| DASH-01 | Phase 1 | Complete |
| DASH-02 | Phase 1 | Complete |
| DASH-03 | Phase 1 | Complete |
| DASH-04 | Phase 1 | Complete |
| DASH-05 | Phase 1 | Complete |
| CODEX-01 | Phase 1 | Complete |
| CODEX-02 | Phase 1 | Complete |
| CODEX-03 | Phase 1 | Complete |
| CODEX-04 | Phase 1 | Complete |
| CODEX-05 | Phase 1 | Complete |
| GLM-01 | Phase 1 | Complete |
| GLM-02 | Phase 1 | Complete |
| GLM-03 | Phase 1 | Complete |
| SET-01 | Phase 1 | Complete |
| SET-02 | Phase 1 | Complete |
| SET-03 | Phase 1 | Complete |
| SET-04 | Phase 1 | Complete |
| PRIV-01 | Phase 1 | Complete |
| VER-01 | Phase 1 | Complete |
| VER-02 | Phase 1 | Complete |
| VER-03 | Phase 1 | Complete |

**Coverage:**
- v1 requirements: 24 total
- Mapped to phases: 24
- Unmapped: 0

---
*Requirements defined: 2026-07-05*
*Last updated: 2026-07-05 after retrospective v1.0.0 GSD initialization*
