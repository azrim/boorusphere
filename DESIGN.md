---
name: Boorusphere
description: Playful booru image browser with dynamic color theming
colors:
  primary: "#9516E5"
  surface: "#FFFBFE"
  surface-dark: "#1C1B1F"
  on-surface: "#1C1B1F"
  on-surface-dark: "#E6E1E5"
  primary-container: "#F0DBFF"
  primary-container-dark: "#4A0080"
  accent-dracula: "#BD93F9"
  accent-catpuccin: "#C6A0F6"
  accent-nord: "#88C0D0"
  accent-solarized: "#D3618A"
  accent-gruvbox: "#CC9975"
  accent-one-dark: "#61AFEF"
  accent-monokai: "#F92672"
  accent-github: "#0381F0"
typography:
  body:
    fontFamily: "system-ui, -apple-system, sans-serif"
    fontSize: "14sp"
    fontWeight: 400
    lineHeight: 1.5
rounded:
  sm: "4px"
  md: "8px"
  lg: "12px"
  xl: "16px"
  full: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "16px"
  lg: "24px"
  xl: "32px"
---

# Design System: Boorusphere

## 1. Overview

**Creative North Star: "The Curated Vault"**

Boorusphere is a content-first mobile image browser. The design philosophy is radical minimalism in chrome, maximum expression in content. Every screen should feel like opening a window onto a well-organized collection — the UI recedes so images can breathe. Three theme modes (day, night, midnight AMOLED) give users control over their viewing environment, with dynamic Material You color adapting to the device wallpaper or a curated palette of 10 accent colors.

**Key Characteristics:**
- Content-first: images dominate every screen; chrome is minimal and purposeful
- Adaptive: dynamic color theming with 10 curated palette presets
- Three-mode darkness: night (Material dark) and midnight (true AMOLED black) for image viewing
- Gesture-driven: swipe navigation, drag-to-zoom, bottom-sheet details
- Tactile micro-interactions: shimmer loading, staggered grid, parallax transitions

## 2. Colors

The palette is adaptive — Material You generates the full scheme from a single seed color. Ten curated accent palettes are available as alternatives.

### Primary
- **Dynamic Accent** (#9516E5 default / adapts to wallpaper): Primary action color, FABs, active indicators, progress bars. Generated from seed via `ColorScheme.fromSeed()`.

### Surface
- **Day Surface** (#FFFBFE): Light mode background. Slightly tinted via `shade(3)`.
- **Night Surface** (#1C1B1F): Dark mode background. Tinted via `shade(30)`.
- **Midnight Surface** (#000000): True AMOLED black. Pure black for OLED power savings.

### Container
- **Primary Container** (#F0DBFF light / #4A0080 dark): Snackbar backgrounds, chip fills, badges. Generated from seed.

### Neutral
- **On-Surface** (#1C1B1F / #E6E1E5 dark): Primary text color. Follows Material 3 tonal mapping.
- **Outline Variant** (30% opacity): Subtle borders and dividers. Harmonized with the active color scheme.

### Named Rules

**The Adaptive Rule.** No color is ever hard-coded. All colors flow through `ColorScheme.fromSeed()` or the dynamic color system. The accent palette presets swap the seed color; the scheme harmonizes the rest.

**The Midnight Rule.** Midnight mode uses pure black (#000) surfaces — no tinting, no elevation shadows. Depth is conveyed by surface hierarchy alone.

## 3. Typography

**System Font Stack:** `system-ui, -apple-system, sans-serif`

**Character:** The type system is purely functional — system fonts at Material 3 defaults. No custom font loading, no display typeface. Typography serves clarity, not personality; personality comes from the color and motion system.

### Hierarchy
- **Display / Headline**: Material 3 defaults from `ThemeData`. Used in app bars, dialog titles, section headers.
- **Body** (14sp, regular): Primary reading weight. Post tags, search queries, settings labels.
- **Label** (12sp, medium): Metadata — timestamps, file sizes, post counts, badge numbers.

### Named Rules

**The Invisible Typography Rule.** Typography should never be the loudest element on screen. Images are the hero. Text exists to label, navigate, and inform — never to decorate.

## 4. Elevation

The system uses Material 3 tonal elevation, not shadows. Surfaces gain brightness (light mode) or reduce brightness (dark mode) as elevation increases, creating depth through color temperature rather than drop shadows.

### Shadow Vocabulary
- **Snackbars**: Top-rounded (12px radius), primary container background. No shadow — depth from color contrast.
- **Bottom sheets**: Standard Material 3 bottom sheet behavior. Backdrop blur (sigma 10) behind the details sheet.
- **Grid items**: No shadows on thumbnails. Content is flat; depth comes from the staggered layout itself.

### Named Rules

**The Flat Content Rule.** Image thumbnails never have shadows, borders, or elevation. They are the content. The only elevated surfaces are interactive chrome (FABs, snackbars, bottom sheets).

## 5. Components

### Timeline Grid
- **Layout**: Staggered grid (flutter_staggered_grid_view), 2-column default, user-adjustable
- **Items**: Full-bleed image thumbnails with rounded corners (8px), no borders
- **Overlays**: Compact labels sit directly on the image, kept legible by a neutral top/bottom scrim (a fixed black gradient — the one documented exception to the adaptive-palette rule, since the underlying image content is arbitrary):
  - **Top-left**: score (`★ 1.4k`, hidden at 0) + rating badge. Replaced by the selection checkbox while the post is selected.
  - **Rating badge**: one-letter chip — S / Q / E / SN — colored from the scheme only: safe → primary, questionable → tertiary, sensitive → secondary, explicit → error; skipped for unrated posts
  - **Top-right**: media type as the file extension (`PNG`, `JPG`, `GIF`, `MP4`, …), hidden when unknown
  - **Bottom-left**: the most identifying tag name as a chip (`niten`, no category prefix), falling back to artist → copyright → character → general; hidden when the post has no tags
  - **Bottom-right**: original dimensions (`3840×2160`, hidden when unknown)
- **Quick actions**: not on the card — a long-press opens a context menu (select / deselect, favorite, download, share, open source)
- **Selection**: tap a card to toggle while any selection is active; selection starts from the context menu, never from the long-press itself
- **Loading**: Shimmer placeholders with desaturated surface color
- **States**: A spinner while a page is loading; a notice card for empty or failed results
- **Pagination**: Page navigation (previous/next plus a page indicator) floats in a bottom pill above the grid, clearing the bottom search bar

### Navigation
- **Style**: Navigation drawer, opened by a horizontal swipe (disabled while the search bar is open)
- **Content**: Server switcher, theme toggle, and entries for Downloads, Favorites, Tags Blocker, and Settings — each opens a full-screen route

### Bottom Sheet (Post Details)
- **Shape**: Rounded top corners (12px), draggable snap points (0%, 50%, 90%)
- **Background**: Surface color with BackdropFilter blur
- **Content**: Post metadata, tags (chip-style), source link, action buttons
- **Gesture**: Swipe up to expand, swipe down to dismiss

### Chips (Tags)
- **Style**: Filled, primaryContainer background, onPrimaryContainer text
- **Shape**: Rounded full (999px)
- **States**: Tappable for tag navigation

### FAB / Action Buttons
- **Style**: Material 3 FAB with primaryContainer fill
- **Shape**: Rounded (12px or full depending on variant)
- **Position**: Bottom-right, above the system inset

### Snackbars
- **Shape**: Top-rounded (12px), primaryContainer background
- **Position**: Docked to the bottom, clearing the system inset
- **Duration**: Short (2s) for info, indefinite for actions

### Search
- **Style**: Expanding search bar with tag autocomplete dropdown
- **Autocomplete**: Dropdown below search field, tag suggestions with post counts
- **Rating filter**: Segmented button row (Safe / Questionable / Explicit)

### Download Entry
- **Layout**: Horizontal card with thumbnail, progress bar, status icon, actions
- **Progress**: Linear progress indicator with percentage label
- **States**: Pending, downloading, paused, completed, failed

## 6. Do's and Don'ts

### Do:
- **Do** use `ColorScheme` tokens for all colors — never hard-code hex values
- **Do** keep thumbnails edge-to-edge within their card; the compact on-image overlays (see Timeline Grid) are the only chrome allowed on the image, and their neutral scrim is the only non-scheme color
- **Do** use shimmer loading for thumbnails — it communicates "loading" without blank space
- **Do** let the staggered grid handle visual interest — varied aspect ratios are the texture
- **Do** use the midnight AMOLED mode as the hero viewing mode for image-heavy sessions
- **Do** use curved transitions (easeOutCubic) for sheet expansion and page navigation

### Don't:
- **Don't** add shadows, borders, or elevation to image thumbnails — they are the content, not cards
- **Don't** use generic Material defaults without considering the content-first philosophy — every chrome element must earn its pixels
- **Don't** hard-code colors outside of `ColorScheme` — the adaptive palette is the identity
- **Don't** put anything on an image beyond the defined compact overlays (score, rating, media type, one tag, dimensions) — deeper detail lives in the details sheet
- **Don't** add unnecessary onboarding screens — the interface is self-explanatory; empty states teach by doing
- **Don't** use decorative animations — motion serves feedback (loading, transitions), not delight for its own sake
