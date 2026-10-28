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
    fontFamily: "Geist"
    fontSize: "16sp"
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

Boorusphere is a content-first mobile image browser. The design philosophy is radical minimalism in chrome, maximum expression in content. Every screen should feel like opening a window onto a well-organized collection — the UI recedes so images can breathe. Three theme modes (day, night, midnight AMOLED) give users control over their viewing environment, with dynamic Material You color adapting to the device wallpaper, or one of eight curated editor palettes that recolour every surface.

**Key Characteristics:**
- Content-first: images dominate every screen; chrome is minimal and purposeful
- Adaptive: wallpaper-driven dynamic color, or eight curated editor palettes that recolour every surface
- Three-mode darkness: night (Material dark) and midnight (true AMOLED black) for image viewing
- Gesture-driven: swipe navigation, drag-to-zoom, bottom-sheet details
- Tactile micro-interactions: shimmer loading, staggered grid, parallax transitions
- Section blocks: every chrome list — drawer, settings, server pages — groups its rows into one rounded surface under a small-caps label, so structure comes from a few quiet blocks instead of many cards

## 2. Colors

A scheme is produced one of two ways. The **System** palette takes the wallpaper scheme on Android 12+ and harmonizes it; **Material You** generates a scheme from the brand seed. The ten named palettes — Dracula, Catppuccin, Nord, Solarized, Gruvbox, One Dark, Monokai, GitHub, Tokyo Night, Ayu — are curated: each owns its page, cards, text, hairlines and accents the way a code editor theme does, so picking one recolours the whole app instead of only shifting the accent hue.

### What a curated palette decides

An editor theme ships a surface ramp — a page, the panels that float on it, the tone a selected row takes, and two grades of rule. That ramp is what a curated palette stores; `toScheme` maps it onto Material roles and never mixes a new surface out of two others.

- **Page** (`background`): the surface every screen paints behind its content.
- **Steps** (`containerLow` → `containerHighest`): the theme's own background-light, floating, background-lighter and selection tones, mapped straight onto `surfaceContainerLow` through `surfaceContainerHighest`. A chip is the theme's selection colour, not a wash of its text colour.
- **Lines** (`border`, `line`): the soft hairline (`outlineVariant`) and the theme's emphasis rule (`outline`) stay two different tones. Collapsing them into one is what made every edge read as a drawn line.
- **Text / Muted**: the theme's foreground and comment tones.
- **Primary / Secondary / Tertiary**: the theme's own syntax accents.

A comment tone is written for syntax, not for UI, and a light theme's pink or yellow often lands under 4.5:1. `toScheme` therefore lifts the muted role and each accent towards the page's opposite, one small step at a time, and stops the moment the floor is met. The hue is always the theme's; only lightness moves, and only where it has to.

Four themes ship one polarity only: **Nord** and **Monokai** never had a light variant, and **Solarized** and **Gruvbox** do have one but it is warm paper, which would tint the artwork it sits behind. Their day scheme is generated from their accent, because inventing a light variant is exactly what this system stopped doing, and a viewer's surround has to stay neutral.

**The Neutral Surround Rule.** A light page is the field an image is judged against, so a warm or cool paper tone belongs to the theme's cards and accents, not to the page. A theme whose light page is saturated paper ships as a dark-only palette instead.

**The Ramp Rule.** A surface is never mixed out of two other colours to produce a new tone. If the theme does not define a step, it is not invented — the role that would need it falls back to the nearest tone the theme does define.

### Generated palettes

- **Dynamic Accent** (#9516E5 default / adapts to wallpaper): Primary action color, FABs, active indicators, progress bars.
- **Day Surface** (#FFFBFE): Light mode background, tinted via `shade(3)`.
- **Night Surface** (#1C1B1F): Dark mode background, tinted via `shade(30)`.
- **Midnight Surface** (#000000): True AMOLED black. Pure black for OLED power savings.
- **Outline Variant** (45% opacity): the hairline for generated schemes.
- **Primary Container** (#F0DBFF light / #4A0080 dark): Snackbar backgrounds, chip fills, badges.

### Named Rules

**The Adaptive Rule.** No widget hard-codes a color. Widgets read `ColorScheme`; hex values live only in `lib/presentation/theme/color_palettes.dart` and the theme builder.

**The Palette Rule.** A curated palette is never harmonized and its surfaces are never re-shaded — the theme is shown as designed, down to its own page color.

**The Midnight Rule.** Midnight mode is the one theme that stays flat: the page is pure black (#000), a block keeps the page tone and a hairline separates it, and menus, sheets, cards and dialogs are black with no elevation. Curated accents survive. `AppSurfacePolicy.flat` carries this so a widget asks the theme instead of guessing from brightness.

## 3. Typography

**Family:** Geist, bundled as four static weights (400 / 500 / 600 / 700) in `assets/fonts`. No variable axis, no network fetch: the weight a style asks for is the weight that renders. Latin, Latin Extended, Greek and Cyrillic ship with it.

**Display face:** Poppins 600, used by the wordmark alone. The name is a lockup rather than a heading, and a geometric face against Geist's neutral grotesk is what makes it read as a mark instead of as the first line of the drawer. No other text may use it.

**Fallback:** Noto Sans Thai ships at 400/500/600 so a Thai title keeps its weight. CJK is left to the platform, whose fallback is locale aware: a bundled Japanese face would render Chinese in Japanese glyph forms, which is worse than the system's own Noto.

**Character:** The family is quiet and the scale does the talking. Weights stop at bold, nothing is italic, and tracking carries the hierarchy a second typeface would otherwise carry: display sizes tighten, 11 sp labels open up so they stay legible at arm's length.

### Hierarchy

| Role | Size | Weight | Tracking | Used for |
| --- | --- | --- | --- | --- |
| `displayLarge` | 57 | bold | -1.5 | Not used in chrome; reserved for a future hero |
| `headlineSmall` | 24 | semibold | -0.4 | The wordmark, an empty state's title |
| `titleLarge` | 20 | semibold | -0.2 | A page's own name |
| `titleMedium` | 16 | semibold | -0.1 | A sheet header |
| `bodyLarge` | 16 | regular | 0 | Row titles, field values, body copy |
| `bodyMedium` | 14 | regular | +0.1 | Secondary copy |
| `bodySmall` | 12 | regular | +0.2 | The muted line under a row title |
| `labelLarge` | 14 | semibold | 0 | Buttons |
| `labelSmall` | 11 | medium | +0.2 | Badges, tab counts |

**Numbers line up.** Any count, score, dimension or byte size is set with tabular figures (`AppTextRoles.numeric`), so a column of them does not drift with each digit.

### Named Rules

**The Invisible Typography Rule.** Typography should never be the loudest element on screen. Images are the hero. Text exists to label, navigate, and inform — never to decorate.

**The Four Roles Rule.** Chrome text is one of four roles, and they live on the theme as `AppTextRoles` — a section label, a field label, a row title, a row supporting line. A screen that needs a fifth is a screen that is doing too much; it picks the nearest role instead of a `copyWith` on a size of its own.

### Surface Type Scale
Every row inside a grouped surface — drawer, settings, server lists, forms, sheets — uses the same roles:

- **Section label**: 11 sp, bold, 1.4 tracking, uppercase, `onSurfaceVariant`, hairline underline
- **Row title**: 16 sp `bodyLarge`, `onSurface` — the only primary text in a row
- **Row supporting text**: 12 sp `bodySmall`, `onSurfaceVariant`, 1.4 line height
- **Field label**: 11 sp `labelSmall`, `onSurfaceVariant`; the value stays 16 sp
- **Section description / helper**: 12 sp `bodySmall`, `onSurfaceVariant`

**The One Scale Rule.** These roles come from the theme (`AppTextRoles`, `ListTileTheme`, the field decoration), never from a per-widget `copyWith` on a different size, so a title is 16 sp in settings, in a sheet, and in the server form alike. Spacing follows the same rhythm: 12 dp row inset, 8 dp between a title and its supporting line, 8 dp between fields, 24 dp above a section label and 8 dp below it.

## 4. Elevation

Depth is a ladder with four rungs, not a mood. Every surface picks one of them, and the rung says what the surface is doing:

| Level | Token | Value | What sits here |
| --- | --- | --- | --- |
| Page | — | 0 | The field behind everything: `surface` |
| Raised | `elevationRaised` | 1 | A block that groups rows: `SectionSurface`, cards, the app bar once content scrolls under it |
| Floating | `elevationFloating` | 3 | Chrome that floats over the content: the pagination pill, back to top, the selection bar, snackbars, the favorites tab strip |
| Overlay | `elevationOverlay` | 6 | Something that owns the screen until it is dismissed: menus, dropdowns, every bottom sheet |
| Modal | `elevationModal` | 12 | A dialog that stops the screen |

A step up the ladder does two things at once, never one of them:

- **Tone.** The surface moves from `surface` to `surfaceContainerHigh`, the tone two steps off the page. One step was not enough: in the drawer, where a block sits inside a panel, the delta between `surfaceContainerLow` and `surfaceContainer` disappeared. The drawer itself paints the page tone so its blocks have something to lift from.
- **Shadow.** A shadow is drawn with `DesignTokens.shadowColor` — the scheme's own shadow pulled 18% towards the page, so it reads as a darker part of the surface instead of a grey smudge. Dark themes carry a heavier alpha because a light shadow cannot be faked by a tone step alone.

### Shadow Vocabulary
- **Section blocks**: `surfaceContainerHigh`, hairline `outlineVariant`, no shadow. A block groups rows; it does not float. In Midnight the block stays on the page tone and only the hairline separates it.
- **Empty and error notices**: the same block vocabulary — container tone (the page tone in midnight), a hairline, no shadow; the icon stays muted.
- **Buttons**: flat. The fill carries the affordance, never a shadow.
- **Snackbars**: top-rounded (12px radius), `primaryContainer` fill, floating elevation.
- **Bottom sheets**: every sheet uses the [Sheet Shell](#sheet-shell) — `surfaceContainer` with a hairline top edge and 16px top radius, at overlay elevation. Backdrop blur (sigma 16) sits behind the details sheet only.
- **Popup menus and dropdowns**: `surfaceContainer` fill, hairline `outlineVariant` outline, 16px radius, overlay elevation. A menu is a card that floats; it is not a shadow with no edge.
- **Dialogs**: `surfaceContainer`, 16px radius, modal elevation. A confirm that destroys something takes the error colour as a text button, never a filled primary one: the destructive verb is not the most attractive control in the dialog, and every screen asks with the same dialog so the answer reads the same from the drawer, a page, or a sheet.
- **Grid items**: no shadow, no border, no elevation. Content is flat; depth comes from the staggered layout itself.
- **Bottom search bar**: a glass surface rather than an elevated one — `surface` at 72% over a 20 px backdrop blur, with a hairline `outlineVariant` on the top edge and no shadow. It is the one place blur is structural: the bar floats over moving art and has to stay legible without hiding it.

### Named Rules

**The Four Rungs Rule.** A surface takes one of the four levels above. A shadow, a tone step and a hairline are not interchangeable: a block gets tone and a hairline, a floating control gets a shadow, and nothing gets two rungs at once.

**The Flat Content Rule.** Image thumbnails never have shadows, borders, or elevation. They are the content. Everything with depth is chrome.

## 5. Components

### Section Block
The one primitive shared by the drawer, the settings pages, and the server pages.

- **Surface**: `SectionSurface` — rounded (`radiusXl`) block painting `surfaceContainerHigh` with a hairline `outlineVariant` border and 4 dp inner padding. In midnight it keeps the page tone, so the block stays pure black and the hairline alone separates it
- **Label**: `SectionLabel` — small caps, hairline underline hugging the text; `SectionHeading` adds the 24 dp space above, the 8 dp below, and an optional trailing action
- **Rows**: `TileGroup` wraps `ListTile`s in the shared `ListTileTheme` (12 dp inset, rounded ink); custom rows (`DrawerTile`) match the same inset
- **Why**: the container carries the only border, so a section reads as one block instead of a stack of separate cards

### Empty States
- **Shape**: the [Section Block](#section-block) vocabulary — `surfaceContainerHigh` (the page tone in midnight), a hairline, no shadow, and a muted icon. A notice is a block, not a floating card
- **Type**: the title is the only primary line (`rowTitle`), the body explains the state in `rowSupporting`, and there is never a third line
- **Action**: a state that has a way forward offers it as one filled button under the body. A state that only says no is a dead end, and the reader has to guess which screen would fix it
- **Layout**: centred, one block wide, and scrollable, so a large font scale or a short window never cuts the action off
- **Where**: timeline errors and empty results, Favorites, Downloads, the changelog, licenses, and the first run

### First Run
- **The page is the list**: a new install opens on the server presets, built from the same block, rows and plus the drawer uses with one server in it. The first decision is a pick, not a page explaining what a server is
- **Header**: the wordmark, then the question the list answers as the page title, with one supporting line under it
- **Rows**: favicon, name and homepage per preset, closed by the add row that scans an address, so a booru outside the list is still one tap away
- **Limit**: five presets, then the section action opens the full list
- **Why**: onboarding in the app's own vocabulary teaches the drawer before the drawer is ever opened, and it costs no extra screen

### Timeline Grid
- **Layout**: Staggered grid (flutter_staggered_grid_view), 2-column default, user-adjustable
- **Items**: Full-bleed image thumbnails with rounded corners (8px), no borders
- **Overlays**: Compact labels sit directly on the image, kept legible by a neutral top/bottom scrim (a fixed black gradient) plus a drop shadow on the tag. The scrim and the tag-category accents are the two documented exceptions to the adaptive-palette rule, since the underlying image content is arbitrary:
  - **Top-left**: score (`★ 1.4k`, hidden at 0) + rating badge. Replaced by the selection checkbox while the post is selected.
  - **Rating badge**: one-letter chip — S / Q / E / SN — colored from the scheme only: safe → primary, questionable → tertiary, sensitive → secondary, explicit → error; skipped for unrated posts
  - **Top-right**: media type as the file extension (`PNG`, `JPG`, `GIF`, `MP4`, …), hidden when unknown
  - **Bottom-left**: the most identifying tag name (`niten`, no category prefix) in a translucent pill tinted by category — artist orange, copyright purple, character green, general blue. The fill is the category color at low opacity with a hairline matching border, so the image shows through; falls back artist → copyright → character → general; hidden when the post has no tags
  - **Bottom-right**: original dimensions (`3840×2160`, hidden when unknown)
  - **Sizing**: the overlay label type, icons and scrim heights scale with the tile width (full size at 130px, floored at 0.7×) so a denser grid shrinks the overlays instead of clipping the labels away. They ignore the system font scale: the tile is the unit, so a 2× font setting must not push the labels past the image
- **Quick actions**: not on the card — a long-press opens the [Context Menu](#context-menu-post-actions)
- **Selection**: tap a card to toggle while any selection is active; selection starts from the context menu, never from the long-press itself
- **Accessibility**: each card is one screen-reader node — the overlays are folded into a single label (tag, rating, score, file type, dimensions), the tap and long-press actions ride on that node, and the selected state is announced rather than drawn as an unlabelled check. A post with none of those falls back to its id so the node is never nameless
- **Loading**: Shimmer placeholders with desaturated surface color
- **States**: A spinner while a page is loading; an [empty state](#empty-states) for empty or failed results
- **Pagination**: Page navigation (previous/next plus a page indicator) floats in a bottom pill above the grid, clearing the bottom search bar. While the list is moving the pill drops to 30% opacity, so it reads as a hint instead of asking for a decision mid-scroll
- **Back to top**: a circular button appears at the trailing edge of the same band once the grid is 600 dp down, and leaves again at the top. It is the only control that changes with scroll position
- **Long-press hint**: a one-shot pill above the bar teaches the gesture behind every post action. It disappears on dismiss or on entering selection mode and is never shown again

### Context Menu (Post Actions)
- **Trigger**: long-press a timeline card (medium haptic) — never a plain tap
- **Placement**: the card opens beside the point the finger went down, the way a desktop menu opens at the cursor, not centred on the screen. It prefers the lower right of that point and flips above or to the left when the preferred corner would push it past the margin. A screen-reader long-press carries no point, so that path centres it
- **Size**: 232 dp at most, 44 dp rows, 14 sp semibold labels and 24 dp icon chips. A context menu is a list of verbs, not a panel: it stays narrow enough to sit beside the finger and short enough that the grid behind it is still the thing being looked at
- **Presentation**: a floating glass card — translucent scheme surface over a backdrop filter, 16 px radius, hairline outline, tinted shadow
- **Backdrop**: the whole screen is blurred, thinly (sigma 11) under a 16% veil, so the menu reads as a layer above the app while the grid stays recognisable. Both are painted at full strength from the first frame — the route fades the page, and animating the blur as well multiplied two fades into one late blur. Tap anywhere or press back to dismiss
- **Rows**: each a tinted icon chip (`secondaryContainer` / `onSecondaryContainer`) plus a label; grouped by intent (select / favorite · download / share / open source) with hairline dividers; disabled rows dim to 38%
- **Motion**: the card fades in and travels the last 8 dp on the standard curve — a menu that appears where the finger already is has no room for a long entrance. Rows fade and slide in with a short stagger; the reverse plays on dismiss
- **Colors**: scheme-only — icon chips and labels come from `ColorScheme`, with no per-action accent colors
### Navigation (Home Drawer)
- **Style**: Navigation drawer, opened by the leading server chip in the search bar or by a swipe anywhere on the grid (a narrow edge zone loses the gesture race to the system back gesture on gesture-nav phones, so the drag zone is the full width while the search bar is closed); rounded right edge, width capped to the viewport
- **Search bar**: the leading chip opens the drawer (and cancels the search while it is open); the trailing button only cycles grid density, so a control never changes meaning mid-scroll. An active non-default rating shows as a tinted chip with a filter icon beside the field, so a filtered feed is a visible state. The bar is a glass surface — `surface` at 72% over a 20 px backdrop blur — because the grid scrolls beneath it; the Interface → Blur setting switches it back to an opaque surface, which is also the cheaper path on slow devices
- **Header**: the wordmark, closed by a `primary` exclamation mark — the name is a shout, not a full stop; the theme switcher (light / dark / system) sits on the trailing edge inside a hairline-bordered square
- **Sections**: each section is one grouped surface — a rounded `surfaceContainerHigh` block with a hairline `outlineVariant` border — and the rows inside stay flat and transparent, so the container carries the only border. In midnight the block keeps the page tone so it never lifts off the black drawer. A small-caps label with a hairline underline hugging the text, plus the item count, opens each section; the servers section closes with a "Manage" action
- **Servers**: one compact row per server — favicon chip with a hairline border and the server name. The active server fills `secondaryContainer` with a `primary` hairline, and is exposed to TalkBack as `selected`. Removing a server asks for confirmation first; the add-server row closes the group with a `primary` plus
- **Library**: Downloads, Favorites, and Tags Blocker, each with a live count badge (hidden at 0)
- **Preferences**: Settings, Gestures & tags (a reference sheet for the gestures and the rating letters), and Reset to default
- **Footer**: Exit (tinted with the error color), the update status when a newer version exists (spinner while downloading), and a version readout preceded by a `primary` status dot that opens About
- **Colors**: section labels are muted uppercase `onSurfaceVariant`; row icons stay neutral `onSurfaceVariant`, and only the count badges, the active-server highlight, the add-server plus, and the footer status dot carry semantic scheme colors
- **Type**: drawer rows run one step denser than content rows — a 14 sp `bodyMedium` label — so more destinations fit without touching the brand header, which keeps its `headlineSmall` wordmark

### Sheet Shell
One container for every bottom sheet in the app — post details, settings pickers, text entry, gesture reference, What's New.

- **Shape**: 16 dp top corners, `surfaceContainer` fill, hairline `outlineVariant` along the top edge, overlay elevation. A 40×4 handle sits 8 dp from the top
- **Header**: the sheet's own name at `titleMedium` semibold with a 48 dp close target on the trailing edge. The name is the thing the sheet is about — the post's identifying tag, the setting being changed — never a generic "Details"
- **Height**: capped at 78% of the screen (90% for a long changelog) and grown by its content, so a three-option picker does not open half empty. Only the panel scrolls
- **Panels**: one job at a time. Rows stack with a single hairline between them and none after the last, so a panel ends on the sheet's own edge
- **Footer**: a hairline, then the sheet's one action, full width
- **Insets**: the keyboard and the system navigation bar are both cleared by the shell, so a field never sits under the IME
- **Dismiss**: the close control, a downward drag, or the backdrop — all three

### Sheet Tabs
- **Use**: only when a sheet holds more than one kind of answer — the post details split into Details / Tags / Links
- **Layout**: directly under the header at 48 dp, inside thumb reach; labels at `labelLarge`, the active one `onSurface` w600 over a 2 dp `primary` underline, and the strip closes with the panel hairline
- **Swipe**: the panels follow the finger, and the gesture belongs to the whole sheet rather than to the rows — with a short panel most of the sheet is empty space, and a swipe that only works on the rows is a swipe nobody finds. It commits at half a page or a 250 dp/s flick, leans against a rubber band at either end, and the underline follows, so the strip is a shortcut rather than the only way in
- **Count**: a tab may carry a muted count, so the size of what is behind it is known before the tap
- **Motion**: underline and label weight animate at 150 ms; the panel slides and the sheet below it resizes on the same 300 ms, so the edge and the content land together instead of the edge arriving first

### Sheet Rows
- **Fact row**: small-caps label on the leading edge, value on the trailing edge in `bodyMedium` with tabular figures, so scores and dimensions line up down the panel
- **Option row**: 16 sp title, an optional 12 sp supporting line, an optional leading swatch, and a `primary` check on the trailing edge; the current option takes a `surfaceContainerHighest` tint
- **Link row**: small-caps label, an optional readout, the address in `primary` at the supporting size, and a copy control
- **Targets**: every row is at least 48 dp tall

### Bottom Sheet (Post Details)
- **Shape**: rounded top corners, opening at 75% of the viewer. That is also the tallest it gets, so it snaps only between open and closed — one downward drag dismisses it instead of walking through intermediate stops
- **Surface**: with the Blur setting on it is a glass sheet — `surface` at 72% over a sigma-16 backdrop blur, so the artwork still reads through it while the rows keep their contrast. With Blur off the sheet paints an opaque `surface`, the cheaper path on slow devices
- **No header**: the sheet opens straight onto the tab strip — the handle, then the panels. The artwork behind it already says which post is open, so a title line and a close button were a second, redundant answer to the same question
- **Panels**: Details (rating, score, dimensions, format), Tags (grouped by category, each with its count; tap to select), Links (post page, source, sample and original file, each with copy)
- **Selection**: tag taps accumulate across panels and survive a panel switch; the action bar then offers copy, block, append, search and clear
- **Gesture**: swipe up or the info button opens it; one swipe down or Back dismisses it, which is why the sheet carries no dismiss control of its own

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
- **Layout**: floating card on `surfaceContainerHigh` at floating elevation, full width minus `spacingMd`, docked above the system inset — a count readout on the left, then download (menu: files or ZIP), favorite, and clear
- **Count**: a readout, not a button label; announced as "N selected"
- **Download**: opens a menu choosing between individual files and a ZIP archive, so no hidden mode is carried between actions
- **Controls**: icon buttons with tooltips, 48 dp targets

### Settings
Every settings screen (Settings, Gesture Settings, Data Backup) uses one row system: rows are grouped into rounded section surfaces, the same block language as the drawer.

- **Containers**: a settings row opens a sheet or a page according to what it holds. Picking one value (language, color palette, download quality, backup frequency) or editing one short value (Telegram chat id, bot token) opens a bottom sheet, so the page stays behind it and the list sits within thumb reach. Opening an area with several independent controls (Backup and restore, Gestures) pushes a page. An `AlertDialog` is reserved for confirming something that discards state and for progress that blocks the screen; it never carries a list of options

- **Section label**: small caps, `onSurfaceVariant`, `labelSmall` bold with 1.4 letter spacing and a hairline underline that hugs the text, exposed to screen readers as a heading. The label owns its own line; it never merges into the row below it
- **Section surface**: rows of one section sit inside a rounded `surfaceContainerHigh` block with a hairline `outlineVariant` border; in midnight it keeps the page tone, so it stays pure black. The page keeps 16 dp side padding and each block owns the only border
- **Rows**: flat rows inside the block, 12 dp inset, no dividers, no shadows; title plus optional subtitle, 8 dp between them; switches, dropdowns and sliders sit on the trailing edge and carry their own state
- **Trailing affordance**: a `chevron_right` marks every row that opens a page, sheet, or dialog. Rows that act immediately (clear cache) and rows with an inline control (switch, dropdown, slider) carry none
- **Sliders**: label on the left, current value on the right, slider across the full row width underneath, optional helper line below. Never a fixed-width slider in the trailing slot — it squeezes the label into a column
- **Selection**: lists of options in a sheet (language, color palette, download quality, backup frequency) mark the active one with `selected` and a trailing check, so the state is visible and announced
- **Sub-pages**: share the section and row widgets with the main page; a settings sub-page that invents its own card layout is a regression

### Server Pages
Server management reuses the same block language as the drawer and settings: a small-caps section label over a rounded `surface` block.

- **Manage**: the saved servers are one block — favicon, name, and homepage per row, with edit / remove in the row menu — closed by an add row whose plus carries `primary`. The app bar names the page, so the block carries no second heading. Reset to default lives in the app bar menu
- **Removal**: removing a server asks first, from the drawer and from this page alike. The same verb answers the same way wherever it is offered
- **Add and Edit are one page**: the add-server row, the drawer action, and the search-bar shortcut all open the same flow, which detects the engine by scanning or lets the user pick one manually
- **Fields**: flat inputs with no fill and a hairline `outlineVariant` underline, with the label in small caps; a form reads as rows inside its block instead of slabs drawn on top of it. The label always sits above the field at the 11 sp label role, in every state, so it never takes the slot the value belongs to; an example belongs in the hint (`e.g. https://…`), never in the label
- **Edit sections**: server (engine, homepage, alias, optional custom API address), server query (parser pickers plus the search / suggestion / post templates, with "From Preset" as the section action), and credentials
- **Credentials**: optional user id and API key, attached to the search, suggestion, and post URLs, and sent along with the scan probe — some boorus answer nothing without them
- **Save**: one filled button pinned under the form

### Download Entry
- **Filter**: a filter that is on is a chip above the list, naming itself and turning itself off; a shortened list never looks like a full one, and its empty state says no match instead of no files
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
- **Do** group related chrome rows into a section block with a small-caps label instead of scattering them as standalone cards
- **Do** pick one of the four elevation rungs for anything that sits above the page, and take the tone step and the shadow together

### Don't:
- **Don't** add shadows, borders, or elevation to image thumbnails — they are the content, not cards
- **Don't** use generic Material defaults without considering the content-first philosophy — every chrome element must earn its pixels
- **Don't** hard-code colors outside of `ColorScheme` — the adaptive palette is the identity (the on-image overlay scrim and tag-category accents are the only documented exceptions)
- **Don't** put anything on an image beyond the defined compact overlays (score, rating, media type, one tag, dimensions) — deeper detail lives in the details sheet
- **Don't** add unnecessary onboarding screens — the interface is self-explanatory; empty states teach by doing
- **Don't** use decorative animations — motion serves feedback (loading, transitions), not delight for its own sake
- **Don't** nest a filled, elevated, or bordered card inside a section block — the block owns the only surface and border, and rows stay flat inside it
- **Don't** invent a second label or row style per screen — the section label, row title, and supporting text come from the shared scale
- **Don't** give a block a shadow or a shadowed surface a second tone step — one rung per surface
