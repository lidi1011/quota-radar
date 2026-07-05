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

Use stable spacing tokens and responsive constraints. Provider panels stack vertically in the normal macOS window. Within each panel, the quota ring and cards sit side by side on wide windows and reflow vertically on narrow windows.

## Elevation & Depth

Use depth sparingly. Prefer material, borders, and subtle surface contrast before heavy shadows.

## Shapes

Keep radii modest and consistent. Use `rounded.sm` for controls and `rounded.md` for provider panels and metric cards.

## Components

Component tokens define reusable visual behavior. Provider visibility, provider card visibility, and provider colors are user-configurable in Settings.

## Do's and Don'ts

- Do update this file when quota panel layout, provider colors, typography, spacing, or component tokens change.
- Do validate token references before using exported tokens in code.
- Do keep generated screenshots, prototypes, and QA reports in `artifacts/product-design/`.
- Do not store short-term design debate here; use `.planning/product-design/`.
- Do not copy codexU's desktop-floating window behavior; this product is a normal Dock app.
