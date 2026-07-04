---
status: fixed
phase: "01"
phase_name: "initial-release"
source_review: ".planning/phases/01-initial-release/01-REVIEW.md"
fixed_at: "2026-07-05 03:12 CST"
fixed:
  critical: 0
  warning: 4
  info: 1
  total: 5
verification:
  - "swift test"
  - "swift build"
  - "./script/build_and_run.sh --verify"
---

# Phase 1 Review Fix

All findings from `01-REVIEW.md` have been addressed.

## Fixed Findings

1. **GLM 手动刷新不绕过缓存**
   - Changed `UsageProvider` to accept `snapshot(force:)`.
   - `UsageStore.refreshAll(force:)` and `refresh(_:force:)` now pass `force` through.
   - `GLMProvider` bypasses the 5-minute cache when `force == true`.
   - Added `testGLMForceRefreshBypassesCachedStats`.

2. **Codex 子进程没有超时**
   - Added timeout support to `CommandRunner`.
   - `CommandRunner` now reads stdout/stderr off-thread to avoid pipe backpressure and terminates timed-out child processes.
   - Codex app-server, SQLite, and grep calls now use bounded timeouts.
   - Added `testCommandRunnerTerminatesTimedOutProcess`.

3. **“累计”卡片不是严格全量累计**
   - Removed the `prefix(800)` cap from `CodexTokenLogReader.candidateSources()`.
   - `累计` now aggregates all discovered SQLite rollout/session JSONL sources.

4. **自动刷新间隔修改后不会立即生效**
   - Added a root `.onChange` observer for `settings.refreshIntervalMinutes`.
   - Changing the setting now rebuilds the active timer immediately.

5. **1.0.0 发布元数据未统一**
   - Updated Codex app-server client info version to `1.0.0`.
   - Added `CFBundleShortVersionString=1.0.0` and `CFBundleVersion=1` to generated app bundle plist.

## Verification

- `swift test` passed: 14 tests, 0 failures.
- `swift build` passed.
- `./script/build_and_run.sh --verify` passed.
- Generated `dist/QuotaRadar.app/Contents/Info.plist` contains `CFBundleShortVersionString` `1.0.0` and `CFBundleVersion` `1`.
