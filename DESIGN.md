---
version: "alpha"
name: Quota Radar
description: Dark, information-dense macOS quota dashboard for Codex and GLM coding plan usage.
colors:
  primary: "#F8FAFC"
  secondary: "#A8B0BE"
  accent: "#2563EB"
  codex: "#1E88FF"
  glm: "#10B981"
  cache: "#8B5CF6"
  output: "#F59E0B"
  planPlus: "#60A5FA"
  planPro100: "#2563EB"
  planPro200: "#8B5CF6"
  background: "#111318"
  surface: "#24272F"
typography:
  h1:
    fontFamily: System Rounded
    fontSize: 2rem
    fontWeight: 700
    lineHeight: 1.1
  body-md:
    fontFamily: System
    fontSize: 1rem
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: System
    fontSize: 0.875rem
    fontWeight: 600
    lineHeight: 1.35
rounded:
  sm: 8px
  md: 12px
spacing:
  sm: 8px
  md: 16px
  lg: 24px
components:
  provider-panel:
    background: "{colors.surface}"
    rounded: "{rounded.md}"
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.primary}"
    rounded: "{rounded.sm}"
    padding: 12px
---

## Overview

Quota Radar uses a compact macOS dashboard style: dark material panels, readable numeric hierarchy, modest radius, and distinct Codex/GLM accent colors. The visual priority is fast quota scanning, not decorative branding.

## Colors

- **Primary:** Main text and high-emphasis UI.
- **Secondary:** Supporting text, borders, metadata, and low-emphasis UI.
- **Accent:** Primary actions, selected states, and key interactive affordances.
- **Codex:** Codex rings and emphasis.
- **GLM:** GLM rings and emphasis.
- **Cache / Output:** Token breakdown segments.
- **Plan Plus / Pro100 / Pro200:** Wool-progress subscription markers. Plus uses light blue, Pro100 uses deep blue, and Pro200 uses purple.

## Typography

Use the typography tokens as the source of truth for visible hierarchy. Large numeric values may use rounded system type, monospaced digits, and scale down inside cards.

## Layout

Use stable spacing tokens and responsive constraints. Provider panels default to vertical stacking in the normal macOS window, with an optional horizontal provider layout for wide review sessions. Provider arrangement controls only the outer Codex/GLM stack. Within each panel, the quota ring and cards independently sit side by side when the panel is wide enough and reflow vertically when it is narrow.

Window sizing must remain inside the active screen's visible frame. Each density keeps one complete provider ring reachable, and content that cannot fit uses horizontal or vertical scrolling rather than clipping. Ring-only horizontal layouts fit their height to the tallest panel. Mixed card/ring states use the cards that are actually rendered, not only the saved visibility preferences. When no Provider is visible, show an explicit empty state with a Settings entry point.

## Elevation & Depth

Use depth sparingly. Prefer material, borders, and subtle surface contrast before heavy shadows.

## Shapes

Keep radii modest and consistent. Use `rounded.sm` for controls and `rounded.md` for provider panels and metric cards.

## Components

Component tokens define reusable visual behavior. Provider visibility, provider card visibility, and provider colors are user-configurable in Settings.

Initial or missing quota windows explicitly mark availability as false and show `--`, never a fabricated 0%. A Codex reset countdown is available only when its source window is available and has a reset timestamp. Confirmed zero quota remains a valid value. During refresh, retained quota values remain visible with an “更新中” header; a panel without available data shows “加载中”. Desktop account verification continues to clear its old display before reading for account isolation.

Codex quota rings have two persisted display modes. `7 天` is the default: the outer ring uses the existing secondary/7-day color and shows remaining quota, while the inner ring uses the former primary/5-hour color and counts down the time remaining before the next reset as `(reset time - current time) / seven days`. The center labels the two percentages as `7 天` and `倒计时`; countdown percentages use one fractional digit while quota percentages keep their existing integer format. Beneath the ring, the real reset row is followed by a separate, primary-color-dotted `倒计时` row formatted as `x天x小时x分`. When the upstream app-server exposes only `primary`, the 7-day presentation maps that sole real window to the outer ring instead of displaying the missing `secondary` placeholder. `5 小时 + 7 天` preserves the original nested dual-quota presentation for compatibility if Codex restores the 5-hour reset window. This choice affects only presentation; both raw rate-limit windows remain in the provider snapshot.

## Do's and Don'ts

- Do update this file when quota panel layout, provider colors, typography, spacing, or component tokens change.
- Do validate token references before using exported tokens in code.
- Do keep generated screenshots, prototypes, and QA reports in `artifacts/product-design/`.
- Do not store short-term design debate here; use `.planning/product-design/`.
- Do not copy codexU's desktop-floating window behavior; this product is a normal Dock app.

## Claude Code quota rings

Claude Code is a third, independently visible Provider with a ring-only panel. The outer ring shows 5-hour remaining quota; the inner ring shows 7-day remaining quota. Primary color is `#D97757`, secondary color is `#E9B872`, and panel accent is `#D97757`. Both ring colors are configurable. Unknown or expired windows show `--` with an empty track; confirmed 0% remaining has no colored arc. Reset timestamps come from the captured quota window, never from the context window or token estimates.

The panel header distinguishes waiting-for-data and historical snapshots (quota payload unchanged for more than 15 minutes). Settings offers integration/update, “清除会话绑定”, and “停用 CLI 采集” (restores the original status line). Claude has no token or subscription cards in this release. The existing layout policy handles three Providers using scrolling and screen-bound frame clamping; Codex-specific quota modes remain exclusive to Codex.

Claude settings now includes a persisted source selector: CLI (default) or Claude Desktop. Only the selected source populates the same rings. CLI retains its integration controls; Desktop shows login/keychain/network boundaries and a refresh action. Desktop status identifies only the source and account email when available; organization identifiers and fetch timestamps are not shown. Source switches clear the old display immediately; detected desktop login changes invalidate cached and pending results. There is no automatic cross-source fallback.

CLI and Desktop each have an independent persisted reading toggle (on by default for compatibility). Disabling the selected source immediately clears the rings and prevents both manual and scheduled reads. The main Claude panel shows “已暂停读取” and disables its refresh button when reading is off. CLI pause preserves the collector; the separate stop-collection action restores the original status line. All three provider settings pages place color settings first; Claude source selection, reading controls, current status, and actions follow. Long explanations are collapsed under “读取说明” by default. The brief desktop keychain/network notice and the distinction between CLI pause and uninstall remain visible.

## Main window sizing and compact toolbar

The main window uses the native unified compact toolbar (observed 38 pt vs the previous 52 pt on the verification Mac). Auto-fit occurs only for initial content measurement, layout/provider composition changes, or screen/chrome changes. Geometry updates from manual resizing and quota refreshes must not snap the window back. Auto-fit uses measured content height when available, clamps to the visible screen, and keeps scroll indicators available so a vertical three-provider stack remains reachable on shorter displays. Ring sizes and text are not shrunk to force the whole stack onto one screen.

For horizontal ring-only layouts, both the minimum height and auto-fit target use the measured row height including normal outer padding; the old 360 pt floor must not leave an empty strip below compact rings. Height measurements carry their layout identity, so a direction/density/provider transition discards the previous layout's height and performs a final fit when the new measurement arrives. Vertical stacks and card layouts retain their existing minimum-height policy, and subsequent geometry/refresh updates preserve manually enlarged windows.

General settings includes one “圆环显示与顺序” card with a visibility checkbox, provider name, and accessible up/down buttons in each of three rows. Boundary buttons are disabled. The persisted order applies to both layout directions; hidden providers remain in the list with an “已隐藏” label and retain their position. The card states that hiding only affects display and does not stop quota reads. The layout direction control is labeled “排列方向”. Older settings keep the default order; unknown/duplicate IDs are removed and missing providers appended.
