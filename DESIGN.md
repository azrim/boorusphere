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
- **Overlays**: Compact labels sit directly on the image, kept legible by a neutral top/bottom scrim (a fixed black gradient) plus a drop shadow on the tag. The scrim and the tag-category accents are the two documented exceptions to the adaptive-palette rule, since the underlying image content is arbitrary:
  - **Top-left**: score (`★ 1.4k`, hidden at 0) + rating badge. Replaced by the selection checkbox while the post is selected.
  - **Rating badge**: one-letter chip — S / Q / E / SN — colored from the scheme only: safe → primary, questionable → tertiary, sensitive → secondary, explicit → error; skipped for unrated posts
  - **Top-right**: media type as the file extension (`PNG`, `JPG`, `GIF`, `MP4`, …), hidden when unknown
  - **Bottom-left**: the most identifying tag name (`niten`, no category prefix) in a translucent pill tinted by category — artist orange, copyright purple, character green, general blue. The fill is the category color at low opacity with a hairline matching border, so the image shows through; falls back artist → copyright → character → general; hidden when the post has no tags
  - **Bottom-right**: original dimensions (`3840×2160`, hidden when unknown)
  - **Sizing**: the overlay label type, icons and scrim heights scale with the tile width (full size at 130px, floored at 0.7×) so a denser grid shrinks the overlays instead of clipping the labels away
- **Quick actions**: not on the card — a long-press opens the [Context Menu](#context-menu-post-actions)
- **Selection**: tap a card to toggle while any selection is active; selection starts from the context menu, never from the long-press itself
- **Accessibility**: each card is one screen-reader node — the overlays are folded into a single label (tag, rating, score), the tap and long-press actions ride on that node, and the selected state is announced rather than drawn as an unlabelled check
- **Loading**: Shimmer placeholders with desaturated surface color
- **States**: A spinner while a page is loading; a notice card for empty or failed results
- **Pagination**: Page navigation (previous/next plus a page indicator) floats in a bottom pill above the grid, clearing the bottom search bar

### Context Menu (Post Actions)
- **Trigger**: long-press a timeline card (medium haptic) — never a plain tap
- **Presentation**: a floating glass card centered over the timeline — translucent scheme surface with `BackdropFilter` blur, 24px radius, hairline outline, soft shadow
- **Backdrop**: full-screen `ColorScheme.scrim` scrim with a progressive blur; tap the backdrop or press back to dismiss
- **Rows**: 48px, each a tinted icon chip (`secondaryContainer` / `onSecondaryContainer`) plus a label; grouped by intent (select / favorite · download / share · open source) with hairline dividers; disabled rows dim to 38%
- **Motion**: the card springs in (scale + slide + blur, ~300ms) and rows fade/slide in with a short stagger; the reverse plays on dismiss
- **Colors**: scheme-only — icon chips and labels come from `ColorScheme`, with no per-action accent colors

### Navigation (Home Drawer)
- **Style**: Navigation drawer, opened by the leading server chip in the search bar or by an edge swipe (the swipe is disabled while the search bar is open); rounded right edge, width capped to the viewport
- **Header**: an eyebrow tagline above the wordmark, closed by a `primary` dot; the theme switcher (light / dark / system) sits on the trailing edge inside a hairline-bordered square
- **Sections**: each section is one grouped surface — a rounded `surface` block with a hairline `outlineVariant` border — and the rows inside stay flat and transparent, so the container carries the only border. Painting `surface` keeps the block pure black in midnight instead of lifting it off the black drawer. A small-caps label with a hairline underline hugging the text, plus the item count, opens each section; the servers section closes with a "Manage" action
- **Servers**: one compact row per server — favicon chip with a hairline border and the server name. The active server fills `secondaryContainer` with a `primary` hairline and a `primary` status dot, and is exposed to TalkBack as `selected`. Removing a server asks for confirmation first; the add-server row closes the group with a `primary` plus
- **Library**: Downloads, Favorites, and Tags Blocker, each with a live count badge (hidden at 0)
- **Preferences**: Settings and Reset to default
- **Footer**: Exit (tinted with the error color), the update status when a newer version exists (spinner while downloading), and a version readout preceded by a `primary` status dot that opens About
- **Colors**: section labels are muted uppercase `onSurfaceVariant`; row icons stay neutral `onSurfaceVariant`, and only the count badges, the active-server highlight, the add-server plus, and the footer status dot carry semantic scheme colors

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

### Bottom Bar (Search)

The one piece of chrome every timeline screen carries. It is a surface, not glass: the bar paints `scaffoldBackgroundColor` at full opacity (black in midnight) with a hairline `outlineVariant` top border, and the query field sits on `surfaceContainerHighest` at `radiusLg`.

- **Collapsed**: leading drawer chip (server favicon, with the active rating as a corner badge), the query as centered text, and a trailing control that toggles grid columns — or becomes *back to top* once the timeline is scrolled
- **Expanded** (tap the field): a rating chip row appears above the field, the field goes left-aligned and editable, and a reset control joins the trailing close button; the suggestion panel (`BlurBackdrop`) rises behind it
- **Rating badge**: one-letter pill — S / Q / E / SN — filled with the scheme role (safe → primary, questionable → tertiary, sensitive → secondary, explicit → error) and drawn at a fixed size so it stays a badge under font scaling; the rating is announced through semantics, not the glyph
- **Touch targets**: every control in the bar is at least 48 dp, including the rating chip and the icon buttons
- **Height**: measured at runtime (`HomeSearchBar.height`), never assumed — the pagination pill's offset and the grid's bottom padding both read it so they track font scaling
- **Selection mode**: while posts are selected the bar is removed and the [selection action bar](#selection-action-bar) takes the bottom of the screen

### Selection Action Bar
- **Trigger**: choosing *Select* in the [Context Menu](#context-menu-post-actions)
- **Layout**: floating card on `surfaceContainerHigh`, full width minus `spacingMd`, docked above the system inset — a count readout on the left, then download (menu: files or ZIP), favorite, and clear
- **Count**: a readout, not a button label; announced as "N selected"
- **Download**: opens a menu choosing between individual files and a ZIP archive, so no hidden mode is carried between actions
- **Controls**: icon buttons with tooltips, 48 dp targets

### Settings
Every settings screen (Settings, Gesture Settings, Language, Data Backup) uses one row system: flat `ListTile` rows on the page background, no cards, no shadows, no dividers.

- **Section label**: uppercase, `onSurfaceVariant`, `titleSmall` with 0.8 letter spacing — the same label language as the drawer — and exposed to screen readers as a heading. The label owns its own line; it never merges into the row below it
- **Rows**: title plus optional subtitle, 8 dp between them; switches, dropdowns and sliders sit on the trailing edge and carry their own state
- **Trailing affordance**: a `chevron_right` marks every row that opens a page, sheet, or dialog. Rows that act immediately (clear cache) and rows with an inline control (switch, dropdown, slider) carry none
- **Sliders**: label on the left, current value on the right, slider across the full row width underneath, optional helper line below. Never a fixed-width slider in the trailing slot — it squeezes the label into a column
- **Selection**: lists of options (language, color palette, swipe mode) mark the active one with `selected` and a trailing check, so the state is visible and announced
- **Sub-pages**: share the section and row widgets with the main page; a settings sub-page that invents its own card layout is a regression

### Download Entry
- **Layout**: Horizontal card with thumbnail, progress bar, status icon, actions
- **Progress**: Linear progress indicator with percentage label
- **States**: Pending, downloading, paused, completed, failed

## 6. Do's and Don'ts

### Do:
- **Do** use `ColorScheme` tokens for all colors — never hard-code hex values
- **Do** keep thumbnails edge-to-edge within their card; the compact on-image overlays (see Timeline Grid) are the only chrome allowed on the image, and their neutral scrim plus the tag-category accents are the only non-scheme colors
- **Do** use shimmer loading for thumbnails — it communicates "loading" without blank space
- **Do** let the staggered grid handle visual interest — varied aspect ratios are the texture
- **Do** use the midnight AMOLED mode as the hero viewing mode for image-heavy sessions
- **Do** use curved transitions (easeOutCubic) for sheet expansion and page navigation

### Don't:
- **Don't** add shadows, borders, or elevation to image thumbnails — they are the content, not cards
- **Don't** use generic Material defaults without considering the content-first philosophy — every chrome element must earn its pixels
- **Don't** hard-code colors outside of `ColorScheme` — the adaptive palette is the identity (the on-image overlay scrim and tag-category accents are the only documented exceptions)
- **Don't** put anything on an image beyond the defined compact overlays (score, rating, media type, one tag, dimensions) — deeper detail lives in the details sheet
- **Don't** add unnecessary onboarding screens — the interface is self-explanatory; empty states teach by doing
- **Don't** use decorative animations — motion serves feedback (loading, transitions), not delight for its own sake
