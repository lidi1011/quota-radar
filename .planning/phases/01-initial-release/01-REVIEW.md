---
status: issues_found
phase: "01"
phase_name: "initial-release"
depth: standard
mode: inline-fallback
reviewed_at: "2026-07-05 03:01:20 CST"
files_reviewed: 15
critical: 0
warning: 4
info: 1
total: 5
findings:
  critical: 0
  warning: 4
  info: 1
  total: 5
files_reviewed_list:
  - Package.swift
  - Sources/QuotaRadar/App/QuotaRadarApp.swift
  - Sources/QuotaRadar/Models/ProviderModels.swift
  - Sources/QuotaRadar/Services/CodexProvider.swift
  - Sources/QuotaRadar/Services/CommandRunner.swift
  - Sources/QuotaRadar/Services/GLMProvider.swift
  - Sources/QuotaRadar/Services/UsageProvider.swift
  - Sources/QuotaRadar/Stores/AppSettings.swift
  - Sources/QuotaRadar/Stores/UsageStore.swift
  - Sources/QuotaRadar/Support/Formatters.swift
  - Sources/QuotaRadar/Support/JSONExtractors.swift
  - Sources/QuotaRadar/Views/ContentView.swift
  - Sources/QuotaRadar/Views/ProviderPanelView.swift
  - Sources/QuotaRadar/Views/UsageCardView.swift
  - script/build_and_run.sh
---

# Phase 1 Code Review

GSD code review hook was not registered in this retrospective project config, and current delegation policy does not permit spawning a review sub-agent for this request. This review was completed inline using the same source-file scope from `01-01-SUMMARY.md`.

## Findings

### Warning 1: 手动刷新 GLM 不会绕过缓存

- **Files:** `Sources/QuotaRadar/Stores/UsageStore.swift:29`, `Sources/QuotaRadar/Stores/UsageStore.swift:54`, `Sources/QuotaRadar/Services/GLMProvider.swift:17`
- **Issue:** `refreshAll(force:)` and `refresh(_:force:)` accept `force`, but never pass it into provider collection. `GLMProvider.snapshot()` then always uses `GLMQuotaCache.current(ttlSeconds: 300)` when cache is warm.
- **Impact:** 用户点击“刷新”或菜单刷新后，GLM 面板可能 5 分钟内仍显示旧额度。这和手动刷新预期不一致，也会让真凭据调试时误判 API 没更新。
- **Recommendation:** Extend `UsageProvider.snapshot(force:)` or add a provider-specific refresh context. When `force == true`, bypass or invalidate `GLMQuotaCache` before fetching.

### Warning 2: Codex 子进程没有超时，刷新可能无限等待

- **Files:** `Sources/QuotaRadar/Services/CommandRunner.swift:32`, `Sources/QuotaRadar/Services/CodexProvider.swift:453`, `Sources/QuotaRadar/Services/CodexProvider.swift:346`, `Sources/QuotaRadar/Services/CodexProvider.swift:161`
- **Issue:** `CommandRunner.run` uses `process.waitUntilExit()` without timeout. Codex app-server, sqlite3, and per-file grep calls all follow the same unbounded wait pattern.
- **Impact:** 如果 Codex CLI、sqlite3 或 grep 因文件系统、锁、stdin/stdout 管道或异常环境卡住，启动首刷和点击刷新会一直挂起，UI 只能停在 loading 状态。
- **Recommendation:** Add a timeout-aware process runner, terminate timed-out child processes, and surface a provider error such as “Codex 本机读取超时”。Keep the timeout short for app-server and per-file grep.

### Warning 3: “累计”卡片不是严格全量累计

- **Files:** `Sources/QuotaRadar/Services/CodexProvider.swift:23`, `Sources/QuotaRadar/Services/CodexProvider.swift:183`
- **Issue:** `total` card aggregates from `.distantPast`, but `candidateSources()` caps sources to the newest 800 session files. Long-lived Codex users can have older usage omitted while UI still labels it “累计”。
- **Impact:** 数值口径会随历史 session 数量变化；超过 800 个有效 rollout 后，“累计”和累计金额会低估。
- **Recommendation:** Either remove the cap for the total path, maintain separate capped scan only for recent windows, or relabel the card as a bounded local aggregate and document the cap.

### Warning 4: 修改自动刷新间隔后，已启动定时器不会立即更新

- **Files:** `Sources/QuotaRadar/Stores/UsageStore.swift:19`, `Sources/QuotaRadar/Views/SettingsView.swift:11`
- **Issue:** `startAutoRefresh()` schedules the timer once using the current setting. Settings Stepper only updates `AppSettings.refreshIntervalMinutes`; no observer restarts the timer.
- **Impact:** 用户在设置里改刷新间隔后，需要重启 App 或触发额外逻辑才会生效。设置项看起来保存了，但运行行为没有同步。
- **Recommendation:** Observe settings changes in the app/root view and restart the timer, or move timer ownership into `UsageStore` with a method that accepts interval updates.

### Info 1: 1.0.0 发布元数据还没统一

- **Files:** `Sources/QuotaRadar/Services/CodexProvider.swift:435`, `script/build_and_run.sh:35`
- **Issue:** Codex app-server client info still reports version `0.1.0`, and generated `Info.plist` does not include `CFBundleShortVersionString` / `CFBundleVersion`.
- **Impact:** 不影响本地功能，但会影响后续 GitHub release、App Store、诊断日志和用户可见版本识别。
- **Recommendation:** Before tagging `v1.0.0`, set app-server client version and bundle version fields to `1.0.0`.

## Positive Notes

- Codex quota path matches the intended codexU-style hierarchy: app-server `account/rateLimits/read` first, then local `rate_limits` fallback.
- Codex token/cost path uses SQLite rollout sources, model-aware pricing, and total-token delta handling; this is aligned with the current codexU-informed口径.
- Time formatting and “today” window now use local calendar/time zone, matching the latest user requirement.
- UI source keeps card visibility as display-only state; hidden cards do not prevent background provider collection.

## Review Result

No Critical issues found. Four Warnings should be addressed before treating `v1.0.0` as release-ready, especially the GLM force-refresh behavior and unbounded child process waits.
