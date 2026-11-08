---
name: Boorusphere
description: Playful booru image browser with dynamic color theming
colors:
  primary: "#951EE5"
  surface: "#FFFBFE"
  surface-dark: "#1C1B1F"
  on-surface: "#1C1B1F"
  on-surface-dark: "#E6E1E5"
  primary-container: "#F0DBFF"
  primary-container-dark: "#4A0080"
  accent-dracula: "#BD93F9"
  accent-catpuccin: "#C6A0F6"
  accent-nord: "#88C0D0"
  accent-solarized: "#D23682"
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

Boorusphere is a content-first mobile image browser. The design philosophy is radical minimalism in chrome, maximum expression in content. Every screen should feel like opening a window onto a well-organized collection: the UI recedes so images can breathe. Three theme modes (day, night, midnight AMOLED) give users control over their viewing environment, with dynamic Material You color adapting to the device wallpaper, or one of ten curated editor palettes that recolour every surface.

**Key Characteristics:**
- Content-first: images dominate every screen; chrome is minimal and purposeful
- Adaptive: wallpaper-driven dynamic color, or ten curated editor palettes that recolour every surface
- Three-mode darkness: night (Material dark) and midnight (true AMOLED black) for image viewing
- Gesture-driven: swipe navigation, drag-to-zoom, bottom-sheet details
- Tactile micro-interactions: shimmer loading, staggered grid, parallax transitions
- Section blocks: every chrome list (drawer, settings, server pages) groups its rows into one rounded surface under a small-caps label, so structure comes from a few quiet blocks instead of many cards

## 2. Colors

A scheme is produced one of two ways. The **System** palette takes the wallpaper scheme on Android 12+ and harmonizes it; **Material You** generates a scheme from the brand seed. The ten named palettes (Dracula, Catppuccin, Nord, Solarized, Gruvbox, One Dark, Monokai, GitHub, Tokyo Night, Ayu) are curated: each owns its page, cards, text, hairlines and accents the way a code editor theme does, so picking one recolours the whole app instead of only shifting the accent hue.

### What a curated palette decides

An editor theme ships a surface ramp: a page, the panels that float on it, the tone a selected row takes, and two grades of rule. That ramp is what a curated palette stores; `toScheme` maps it onto Material roles and never mixes a new surface out of two others.

- **Page** (`background`): the surface every screen paints behind its content.
- **Steps** (`containerLow` → `containerHighest`): the theme's own background-light, floating, background-lighter and selection tones, mapped straight onto `surfaceContainerLow` through `surfaceContainerHighest`. A chip is the theme's selection colour, not a wash of its text colour.
- **Lines** (`border`, `line`): the soft hairline (`outlineVariant`) is the theme's border lifted until it reads as a rule on the page it divides, in a field underline, and around a midnight block; the theme's emphasis rule (`outline`) is shown as written. Collapsing them into one is what made every edge read as a drawn line, and a hairline equal to the block's fill drew nothing at all.
- **Text / Muted**: the theme's foreground and comment tones.
- **Primary / Secondary / Tertiary**: the theme's own syntax accents.

A comment tone is written for syntax, not for UI, and a light theme's pink or yellow often lands under 4.5:1. `toScheme` therefore lifts the muted role and each accent towards the page's opposite, one small step at a time, and stops the moment the floor is met. Text, muted text and the labels on container tints are lifted against every tone they can land on, not only the page, because a section, a chip and a selection fill are all surfaces the app writes on. The hue is always the theme's; only lightness moves, and only where it has to.

Four themes ship one polarity only: **Nord** and **Monokai** never had a light variant, and **Solarized** and **Gruvbox** do have one but it is warm paper, which would tint the artwork it sits behind. Their day scheme is generated from their accent, because inventing a light variant is exactly what this system stopped doing, and a viewer's surround has to stay neutral.

**The Neutral Surround Rule.** A light page is the field an image is judged against, so a warm or cool paper tone belongs to the theme's cards and accents, not to the page. A theme whose light page is saturated paper ships as a dark-only palette instead.

**The Ramp Rule.** A surface is never mixed out of two other colours to produce a new tone. If the theme does not define a step, it is not invented; the role that would need it falls back to the nearest tone the theme does define.

### Generated palettes

- **Dynamic Accent** (#951EE5 default / adapts to wallpaper): Primary action color, FABs, active indicators, progress bars.
- **Day Surface** (#FFFBFE): Light mode background, tinted via `shade(3)`.
- **Night Surface** (#1C1B1F): Dark mode background, tinted via `shade(30)`.
- **Midnight Surface** (#000000): True AMOLED black. Pure black for OLED power savings.
- **Outline Variant**: the hairline for generated schemes, lifted from the seed's line until it clears 1.5:1 against the page and the raised blocks it separates.
- **Primary Container** (#F0DBFF light / #4A0080 dark): Chip fills and badges.

### Named Rules

**The Adaptive Rule.** No widget hard-codes a color. Widgets read `ColorScheme`; hex values live only in `lib/presentation/theme/color_palettes.dart` and the theme builder. An accent used as a *label* on a block, a dialog, a sheet or a selected chip reads `AppActionRoles` instead: the theme's primary and error lifted once against the highest surface tone, so the same role clears the page and every block between while fills keep the palette's own accent. Chrome painted *on* the artwork, where what sits behind it changes with every post, reads `AppMediaChrome` instead: a role set the theme builds once from the palette's own neutral pair, so its foreground is the lightest neutral it owns and its stage, scrim, plates, tracks and label shadows are the darkest, each at a named alpha. A widget asks for a role and never for `Colors.white` or `Colors.black`, which is what lets a curated palette or the Midnight rule change how the viewer reads in one place. The scrim is still what makes the glyph legible, not the scheme; the theme only decides which black and which white that scrim is made of.

**The Palette Rule.** A curated palette is never harmonized and its surfaces are never re-shaded; the theme is shown as designed, down to its own page color.

**The Flat-First Rule.** Day and night separate boxes by tone and shadow: blocks, cards, menus, sheets, toasts and chips carry no outline. A hairline is kept for rules (dividers, field underlines) and for state marks, not as a box. An outline around a surface that already had a raised tone was a second edge doing the same job, and on a curated palette it was often the brightest line on screen.

**The Midnight Rule.** Midnight mode is the one theme that stays flat: the page is pure black (#000), a block keeps the page tone and a hairline separates it, and menus, sheets, toasts, cards and dialogs are black with no elevation, so they keep the `outlineVariant` hairline every other theme drops. Curated accents survive. `AppSurfacePolicy.flat` carries this so a widget asks the theme instead of guessing from brightness.

## 3. Typography

**Family:** Geist, bundled as four static weights (400 / 500 / 600 / 700) in `assets/fonts`. No variable axis, no network fetch: the weight a style asks for is the weight that renders. Latin, Latin Extended, Greek and Cyrillic ship with it.

**Display face:** Poppins 600, used by the wordmark alone. The name is a lockup rather than a heading, and a geometric face against Geist's neutral grotesk is what makes it read as a mark instead of as the first line of the drawer. No other text may use it.

**Fallback:** Noto Sans Thai ships at 400/500/600 so a Thai title keeps its weight. CJK is left to the platform, whose fallback is locale aware: a bundled Japanese face would render Chinese in Japanese glyph forms, which is worse than the system's own Noto.

**Character:** The family is quiet and the scale does the talking. Weights stop at bold, nothing is italic, and tracking carries the hierarchy a second typeface would otherwise carry: display sizes tighten, 11 sp labels open up so they stay legible at arm's length.

### Hierarchy

| Role | Size | Weight | Tracking | Used for |
| --- | --- | --- | --- | --- |
| `displayLarge` | 57 | bold | -1.5 | Not used in chrome; reserved for a future hero |
| `headlineSmall` | 24 | semibold | -0.4 | The wordmark, a full-screen gate's title (the app lock) |
| `titleLarge` | 20 | semibold | -0.2 | A page's own name |
| `titleMedium` | 16 | semibold | -0.1 | A sheet header |
| `bodyLarge` | 16 | regular | 0 | Row titles, field values, body copy |
| `bodyMedium` | 14 | regular | +0.1 | Secondary copy |
| `bodySmall` | 12 | regular | +0.2 | The muted line under a row title |
| `labelLarge` | 14 | semibold | 0 | Buttons |
| `labelSmall` | 11 | medium | +0.2 | Badges, tab counts |

**Numbers line up.** Any count, score, dimension or byte size is set with tabular figures (`AppTextRoles.numeric`), so a column of them does not drift with each digit.

### Named Rules

**The Invisible Typography Rule.** Typography should never be the loudest element on screen. Images are the hero. Text exists to label, navigate, and inform, never to decorate.

**The Four Roles Rule.** Chrome text is one of four roles, and they live on the theme as `AppTextRoles`: a section label, a field label, a row title, a row supporting line. A screen that needs a fifth is a screen that is doing too much; it picks the nearest role instead of a `copyWith` on a size of its own.

### Surface Type Scale
Every row inside a grouped surface (drawer, settings, server lists, forms, sheets) uses the same roles:

- **Section label**: 11 sp, bold, 1.4 tracking, uppercase, `onSurfaceVariant`, hairline underline
- **Row title**: 16 sp `bodyLarge`, `onSurface`, the only primary text in a row
- **Row supporting text**: 12 sp `bodySmall`, `onSurfaceVariant`, 1.4 line height
- **Field label**: 11 sp `labelSmall`, `onSurfaceVariant`; the value stays 16 sp
- **Section description / helper**: 12 sp `bodySmall`, `onSurfaceVariant`
- **Notice title**: the row title role (16 sp `bodyLarge`, centred). A notice is a block of reading inside the page, so it takes the row role rather than a headline; `headlineSmall` there would out-shout the content the notice reports on

**The One Scale Rule.** These roles come from the theme (`AppTextRoles`, `ListTileTheme`, the field decoration), never from a per-widget `copyWith` on a different size, so a title is 16 sp in settings, in a sheet, and in the server form alike. Spacing follows the same rhythm: 12 dp row inset, 8 dp between a title and its supporting line, 8 dp between fields, 24 dp above a section label and 8 dp below it.

## 4. Elevation

Depth is a ladder with four rungs, not a mood. Every surface picks one of them, and the rung says what the surface is doing:

| Level | Token | Value | What sits here |
| --- | --- | --- | --- |
| Page | none | 0 | The field behind everything: `surface` |
| Raised | `elevationRaised` | 1 | A block that groups rows: `SectionSurface`, cards, the app bar once content scrolls under it |
| Floating | `elevationFloating` | 3 | Chrome that floats over the content: the pagination pill, back to top, the selection bar, toasts, the favorites tab strip |
| Overlay | `elevationOverlay` | 6 | Something that owns the screen until it is dismissed: menus, dropdowns, every bottom sheet |
| Modal | `elevationModal` | 12 | A dialog that stops the screen |

A step up the ladder does two things at once, never one of them:

- **Tone.** The surface moves from `surface` to `surfaceContainerHigh`, the tone two steps off the page. One step was not enough: in the drawer, where a block sits inside a panel, the delta between `surfaceContainerLow` and `surfaceContainer` disappeared. The drawer itself paints the page tone so its blocks have something to lift from.
- **Shadow.** A shadow is drawn with `DesignTokens.shadowColor` (the scheme's own shadow, pulled 18% towards the page), so it reads as a darker part of the surface instead of a grey smudge. Dark themes carry a heavier alpha because a light shadow cannot be faked by a tone step alone.

### Shadow Vocabulary
- **Section blocks**: `surfaceContainerHigh`, no border, no shadow. A block groups rows; it does not float. In Midnight the block stays on the page tone and a hairline `outlineVariant` separates it, because a tone step has nothing to lift from on black.
- **Empty and error notices**: the same block vocabulary, a container tone (the page tone in midnight, with a hairline), no shadow; the icon stays muted.
- **Buttons**: flat. The fill carries the affordance, never a shadow. One primary variant (the filled primary button) carries the action a page or sheet is asking for; `OutlinedButton` and `TextButton` are the ways out beside it, and a destructive confirm is a text button in the error colour.
- **Toasts**: a card floating over the page, inset from the edges, 16 px radius on every corner, `surfaceContainerHigh` fill and floating elevation. Midnight keeps it black with the hairline and no shadow.
- **Bottom sheets**: every sheet uses the [Sheet Shell](#sheet-shell): `surfaceContainer` with a 16px top radius, at overlay elevation. Midnight adds the `outlineVariant` hairline along the top edge. The post details sheet is opaque too: its rows are read against a known surface, and a glass sheet could not hold the muted label's contrast over artwork.
- **Popup menus and dropdowns**: `surfaceContainer` fill, 16px radius, overlay elevation. A menu is a card that floats on its shadow; in Midnight a hairline `outlineVariant` keeps its edge.
- **Dialogs**: `surfaceContainer`, 16px radius, modal elevation; in Midnight it is black, flat, and a hairline `outlineVariant` keeps its edge. A confirm that destroys something takes the error colour as a text button, never a filled primary one: the destructive verb is not the most attractive control in the dialog, and every screen asks with the same dialog so the answer reads the same from the drawer, a page, or a sheet.
- **Grid items**: no shadow, no border, no elevation. Content is flat; depth comes from the staggered layout itself.
- **Bottom search bar**: a glass surface rather than an elevated one (`surface` at 72% over a 20 px backdrop blur, no shadow and no edge line). It is the one place blur is structural: the bar floats over moving art and has to stay legible without hiding it.

### Named Rules

**The Four Rungs Rule.** A surface takes one of the four levels above. A shadow, a tone step and a hairline are not interchangeable: a block gets tone (plus the midnight hairline), a floating control gets a shadow, and nothing gets two rungs at once.

**The Flat Content Rule.** Image thumbnails never have shadows, borders, or elevation. They are the content. Everything with depth is chrome.

## 5. Components

### Section Block
The one primitive shared by the drawer, the settings pages, and the server pages.

- **Surface**: `SectionSurface`, a rounded (`radiusXl`) block painting `surfaceContainerHigh` with 4 dp inner padding. Day and night draw no border: the tone step is the separation. In midnight it keeps the page tone and gains a hairline `outlineVariant`, so the block stays pure black and the line alone separates it
- **Label**: `SectionLabel`, small caps, hairline underline hugging the text; `SectionHeading` adds the 24 dp space above, the 8 dp below, and an optional trailing action
- **Rows**: `TileGroup` wraps `ListTile`s in the shared `ListTileTheme` (12 dp inset, rounded ink) and lets the theme's 12 dp tile padding stand; a block that overrode it became a shorter version of a row that looks identical outside it. Custom rows (`DrawerTile`) match the same inset, the same 16 dp gap to the label, the `rowTitle` role and the 8 dp above the supporting line — one block never holds two row scales
- **Why**: the container carries the block's tone, and in midnight the only border, so a section reads as one block instead of a stack of separate cards

### Empty States
- **Shape**: the [Section Block](#section-block) vocabulary: `surfaceContainerHigh` (the page tone in midnight, with a hairline), no shadow, and a muted icon. A notice is a block, not a floating card
- **Type**: the title is the only primary line (`rowTitle`), the body explains the state in `rowSupporting`, and there is never a third line
- **Action**: a state that has a way forward offers it as one filled button under the body. A state that only says no is a dead end, and the reader has to guess which screen would fix it. A server behind a browser check replaces the retry with *Verify*, which opens the [browser check](#browser-check); retrying would hit the same wall
- **Layout**: centred, one block wide, and scrollable, so a large font scale or a short window never cuts the action off
- **Local filters**: a page that arrived full but has no visible post is its own state. The notice names what hid it (the local filters or the tags blocker) and offers the one control that undoes it (*Show all posts*, or the Tags Blocker screen), so a blank grid is never a dead end
- **Where**: timeline errors and empty results, a page emptied by local filters or the tags blocker, Favorites, Downloads, the changelog, licenses, and the first run

### Browser Check
The screen a challenged server sends the reader to. Opened from the timeline's error card, never from the drawer.

- **Shape**: a plain `Scaffold`, app bar with the check's title and one text action (*Done*), then the hint strip and the server's own page in a WebView
- **Hint strip**: `surfaceContainerHighest` with a shield icon and one `rowSupporting` line. The strip explains why the app cannot answer the check itself; it never repeats the page
- **Behaviour**: the page closes on its own once the clearance cookie appears, saving the cookie **and** the User-Agent that earned it, per host, so the API and the image CDN present the same pair. *Done* is the manual way out for a server that lets the browser through without a challenge
- **Why**: a challenge is answered by running JavaScript, which this app cannot do, so a retry can only fail the same way. One browser pass replaces a dead end

### First Run
- **The page is the list**: a new install opens on the server presets, built from the same block, rows and plus the drawer uses with one server in it. The first decision is a pick, not a page explaining what a server is
- **Header**: the wordmark, then the question the list answers as the page title, with one supporting line under it
- **Rows**: favicon, name and homepage per preset, closed by the add row that scans an address, so a booru outside the list is still one tap away
- **Limit**: five presets, then the section action opens the full list
- **Why**: onboarding in the app's own vocabulary teaches the drawer before the drawer is ever opened, and it costs no extra screen

### Timeline Grid
- **Layout**: Staggered grid (flutter_staggered_grid_view): a device-dependent default (≈2–3 columns depending on width), user-adjustable from the bar. The column count and the thumbnail decode size both come from the extent the grid is actually laid out in, so the page insets are counted once
- **Items**: Full-bleed image thumbnails with rounded corners (8px), no borders
- **Overlays**: Compact labels sit directly on the image, kept legible by a neutral top/bottom scrim plus a drop shadow on the tag, both read from `AppMediaChrome` (see the Adaptive Rule). The tag-category accents are the one non-scheme color left, since those hues are a booru convention rather than a palette decision:
  - **Top-left**: score (`★ 1.4k`, hidden at 0) + rating badge. Replaced by the selection checkbox while the post is selected.
  - **Rating badge**: one-letter chip, S / Q / E / SN, colored from the scheme only: safe → primary, questionable → tertiary, sensitive → secondary, explicit → error; skipped for unrated posts
  - **Top-right**: media type as the file extension (`PNG`, `JPG`, `GIF`, `MP4`, …), hidden when unknown
  - **Bottom-left**: the most identifying tag name (`niten`, no category prefix) in a translucent pill tinted by category: artist orange, copyright purple, character green, general blue. The fill is the category color at low opacity with a hairline matching border, so the image shows through; falls back artist → copyright → character → general; hidden when the post has no tags
  - **Bottom-right**: original dimensions (`3840×2160`, hidden when unknown)
  - **Sizing**: the overlay label type, icons and scrim heights scale with the tile width (full size at 130px, floored at 0.7×) so a denser grid shrinks the overlays instead of clipping the labels away. They ignore the system font scale: the tile is the unit, so a 2× font setting must not push the labels past the image
- **Quick actions**: not on the card; a long-press opens the [Context Menu](#context-menu-post-actions)
- **Selection**: tap a card to toggle while any selection is active; selection starts from the context menu, never from the long-press itself
- **Accessibility**: each card is one screen-reader node: the overlays are folded into a single label (tag, rating, score, file type, dimensions), with the tap and long-press actions on that node and the selected state announced rather than drawn as an unlabelled check. A post with none of those falls back to its id so the node is never nameless
- **Loading**: Shimmer placeholders with desaturated surface color, drawn at the grid's own inset and column count, so the first page does not change shape when it lands
- **States**: A spinner while a page is loading; an [empty state](#empty-states) for empty or failed results
- **Pagination**: Page navigation (previous/next plus a page indicator) floats in a bottom pill above the grid, clearing the bottom search bar. While the list is moving the pill drops to 30% opacity, so it reads as a hint instead of asking for a decision mid-scroll
- **Back to top**: a circular button appears at the trailing edge of the same band once the grid is 600 dp down, and leaves again at the top. It is the only control that changes with scroll position
- **Long-press hint**: a one-shot pill above the bar teaches the gesture behind every post action. It disappears on dismiss or on entering selection mode and is never shown again

### Context Menu (Post Actions)
- **Trigger**: long-press a timeline card (medium haptic), never a plain tap
- **Placement**: the card opens beside the point the finger went down, the way a desktop menu opens at the cursor, not centred on the screen. It prefers the lower right of that point and flips above or to the left when the preferred corner would push it past the margin. A screen-reader long-press carries no point, so that path centres it
- **Size**: 232 dp at most, 48 dp rows, 14 sp semibold labels and 24 dp icon chips. A context menu is a list of verbs, not a panel: it stays narrow enough to sit beside the finger and short enough that the grid behind it is still the thing being looked at
- **Presentation**: a floating card over a blurred backdrop, `surfaceContainerHigh` fill, 16 px radius, tinted shadow; the `outlineVariant` hairline edge returns only in Midnight
- **Backdrop**: the whole screen is blurred, thinly (sigma 11) under a 16% veil, so the menu reads as a layer above the app while the grid stays recognisable. Both are painted at full strength from the first frame; the route fades the page, and animating the blur as well multiplied two fades into one late blur. Tap anywhere or press back to dismiss
- **Rows**: each a tinted icon chip (`secondaryContainer` / `onSecondaryContainer`) plus a label; grouped by intent (select / favorite · download / share / open source) with hairline dividers; disabled rows dim to 38%
- **Motion**: the card fades in and travels the last 8 dp on the standard curve; a menu that appears where the finger already is has no room for a long entrance. Rows fade and slide in with a short stagger; the reverse plays on dismiss
- **Colors**: scheme-only; icon chips and labels come from `ColorScheme`, with no per-action accent colors
### Navigation (Home Drawer)
- **Style**: Navigation drawer, opened by the leading server chip in the search bar or by a swipe anywhere on the grid (a narrow edge zone loses the gesture race to the system back gesture on gesture-nav phones, so the drag zone is the full width while the search bar is closed); rounded right edge, width capped to the viewport
- **Search bar**: the leading chip opens the drawer (and cancels the search while it is open); the trailing button only cycles grid density, so a control never changes meaning mid-scroll. An active non-default rating shows as a tinted chip with a filter icon beside the field, so a filtered feed is a visible state. The bar is a glass surface (`surface` at 72% over a 20 px backdrop blur) because the grid scrolls beneath it; the Interface → Blur setting switches it back to an opaque surface, which is also the cheaper path on slow devices
- **Header**: the wordmark, closed by a `primary` exclamation mark: the name is a shout, not a full stop; the theme switcher (light / dark / system) sits on the trailing edge inside a rounded square, hairline-bordered only in Midnight
- **Sections**: each section is one grouped surface (a rounded `surfaceContainerHigh` block, borderless in day and night), and the rows inside stay flat and transparent, so the container carries the grouping. In midnight the block keeps the page tone and gains a hairline `outlineVariant`, so it never lifts off the black drawer. A small-caps label with a hairline underline hugging the text, plus the item count, opens each section; the servers section closes with a "Manage" action
- **Servers**: one compact row per server: favicon chip (its hairline returns only in Midnight) and the server name. The active server fills `secondaryContainer` with a `primary` hairline, and is exposed to TalkBack as `selected`. Removing a server asks for confirmation first; the add-server row closes the group with a `primary` plus
- **Library**: Downloads, Favorites, and Tags Blocker, each with a live count badge (hidden at 0)
- **Preferences**: Settings, Gestures & tags (a reference sheet for the gestures and the rating letters), and Reset to default
- **Footer**: Exit (tinted with the error color), the update status when a newer version exists (spinner while downloading), and a version readout that opens About
- **Colors**: section labels are muted uppercase `onSurfaceVariant`; row icons stay neutral `onSurfaceVariant`, and only the count badges, the active-server highlight, the add-server plus, and the footer status dot carry semantic scheme colors
- **Type**: drawer rows run one step denser than content rows (a 14 sp `bodyMedium` label), so more destinations fit without touching the brand header, which keeps its `headlineSmall` wordmark

### Sheet Shell
One container for every bottom sheet in the app: post details, settings pickers, text entry, gesture reference, What's New.

- **Shape**: 16 dp top corners, `surfaceContainer` fill, overlay elevation; Midnight adds the `outlineVariant` hairline along the top edge. A 40×4 handle sits 8 dp from the top
- **Header**: the sheet's own name at `titleMedium` semibold with a 48 dp close target on the trailing edge. The name is the thing the sheet is about (the post's identifying tag, the setting being changed), never a generic "Details"
- **Height**: capped at 78% of the screen (90% for a long changelog) and grown by its content, so a three-option picker does not open half empty. Only the panel scrolls
- **Measure**: the content stops at 640 dp and centres while the surface stays full-bleed, so a tablet gets margins rather than a table stretched across the screen
- **Panels**: one job at a time. Rows stack with a single hairline between them and none after the last, so a panel ends on the sheet's own edge
- **Footer**: a hairline, then the sheet's one action, full width
- **Insets**: the keyboard and the system navigation bar are both cleared by the shell, so a field never sits under the IME
- **Dismiss**: the close control, a downward drag, or the backdrop: all three

### Sheet Tabs
- **Use**: only when a sheet holds more than one kind of answer: the post details split into Details / Tags / Links
- **Layout**: directly under the header at 48 dp, inside thumb reach; labels at `labelLarge`, the active one `onSurface` w600 over a 2 dp `primary` underline, and the strip closes with the panel hairline. The tabs share the strip's width instead of scrolling, so the strip never claims the sheet's horizontal swipe
- **Swipe**: the panels follow the finger, and the gesture belongs to the whole sheet rather than to the rows: with a short panel most of the sheet is empty space, and a swipe that only works on the rows is a swipe nobody finds. It commits at half a page or a 250 dp/s flick, leans against a rubber band at either end, and the underline follows, so the strip is a shortcut rather than the only way in
- **Count**: a tab may carry a muted count in tabular figures, so the size of what is behind it is known before the tap
- **Motion**: underline and label weight animate at 150 ms; only the panel travels on the 300 ms slide. The sheet keeps its height across a tab change: a sheet whose edge grew or shrank with the swipe moved diagonally under the finger and read as a jump, so the reader resizes it with a vertical drag instead

### Sheet Rows
- **Fact row**: small-caps label on the leading edge, value on the trailing edge in `bodyMedium` with tabular figures, so scores and dimensions line up down the panel
- **Option row**: 16 sp title, an optional 12 sp supporting line, an optional leading swatch, and a `primary` check on the trailing edge; the current option takes a `surfaceContainerHighest` tint
- **Link row**: small-caps label, an optional readout, the address in `primary` at the supporting size, and a copy control
- **Targets**: every row is at least 48 dp tall

### Bottom Sheet (Post Details)
- **Shape**: rounded top corners. The sheet opens at the height of the panel it is showing: Details around its fact rows, Links up to 520 dp, Tags up to 75% of the viewer. That height is fixed for as long as the sheet stays open — a tab switch slides the panel without moving the edge — and a vertical drag is the reader's own resize. The sheet snaps between closed, the height it opened at and the full 75%, so a drag down from the opening height dismisses it instead of walking through intermediate stops
- **Surface**: opaque `surfaceContainer` with a 16 dp top radius (in Midnight, the page tone with the hairline). The artwork behind stays outside the sheet; the rows never depend on what is behind them
- **No header**: the sheet opens straight onto the tab strip: the handle, then the panels. The artwork behind it already says which post is open, so a title line and a close button were a second, redundant answer to the same question
- **Panels**: Details (rating, score, dimensions, format), Tags (grouped by category, each with its count; a long group offers the rest behind one `+N` chip; tap to select), Links (post page, source, sample and original file, each with copy)
- **Selection**: tag taps accumulate across panels and survive a panel switch; the action bar then offers copy, block (with an undo), append, search as its one filled action, and deselect
- **Gesture**: swipe up or the info button opens it at the current panel's height; one swipe down or Back dismisses it, which is why the sheet carries no dismiss control of its own

### Chips (Tags)
- **Style**: Filled. An unselected tag sits on `surfaceContainerHighest`, borderless in day and night; selecting it fills `primaryContainer` with `onPrimaryContainer` text, so selection reads as a state change rather than a second accent colour. In Midnight the unselected chip keeps the page tone with a hairline `outlineVariant`
- **Shape**: Rounded full (999px)
- **States**: Tappable for tag navigation

### FAB / Action Buttons
- **Style**: Material 3 FAB with primaryContainer fill
- **Shape**: Rounded (12px or full depending on variant)
- **Position**: Bottom-right, above the system inset

### Toasts
- **Shape**: A floating card inset `spacingMd` from the sides and bottom, 16px on every corner, `surfaceContainerHigh` fill and floating elevation. Midnight keeps it black with the hairline and no shadow
- **Position**: Above the bottom search bar (the bar's measured height is the clearance), and above the system inset on every other screen
- **Action**: Inside the card as a text button in the primary colour with its own 48 dp target; running it also dismisses the toast
- **Dismiss**: Swipe down
- **Duration**: Short (2s) for info; an undo gets a longer window (8s), and a newer message replaces it so a stale undo never hides the next result

### Bottom Bar (Search)

The one piece of chrome every timeline screen carries. It follows the Interface → Blur setting: with blur on it is a glass surface (`surface` at 72% over a 20 px backdrop blur) because the grid scrolls beneath it; with blur off it paints `scaffoldBackgroundColor` at full opacity (black in midnight), the cheaper path on slow devices. Either way the bar draws no edge line and no shadow, and the query field sits on `surfaceContainerHighest` at `radiusLg` (the page tone with its own hairline in Midnight).

- **Collapsed**: leading drawer chip (server favicon), the query as centered text, and a trailing control that only toggles grid columns, so a control never changes meaning mid-scroll; back to top is the grid's own floating button. An active non-default rating joins the field as a one-letter filter chip, so a filtered feed is a state the reader can see rather than decode
- **Expanded** (tap the field): a rating chip row appears above the field, the field goes left-aligned and editable, and a reset control joins the trailing close button; the suggestion panel (`BlurBackdrop`) rises behind it
- **Rating chip**: one letter (S / Q / E / SN) beside a filter icon, tinted with the scheme role (safe → primary, questionable → tertiary, sensitive → secondary, explicit → error) inside the same 48 dp control as every other button, so it stays a badge under font scaling; the rating is announced through semantics, not the glyph
- **Touch targets**: every control in the bar is at least 48 dp, including the rating chip and the icon buttons
- **Height**: measured at runtime (`HomeSearchBar.height`), never assumed; the pagination pill's offset and the grid's bottom padding both read it so they track font scaling
- **Selection mode**: while posts are selected the bar is handed over to the [selection action bar](#selection-action-bar), which takes the bottom of the screen: the bar fades and dips 8 dp out while the action bar arrives the same way, so the swap reads as one control replacing another
- **Failure feedback**: a step or refresh that fails while posts are on screen answers with a toast where the action was taken, because the error card appended after the grid is below the fold

### Search Panel (History & Suggestions)
The full-screen pane the bar opens into. It rises from the bottom edge behind the bar on the standard 300 ms slide, and is one surface, not a menu.

- **Surface**: `BlurBackdrop` when Interface → Blur is on (sigma 20 over the page colour at 85%), an opaque `scaffoldBackgroundColor` when it is off. The rows sit on their own transparent `Material`, because the pane paints above the scaffold's ink surface
- **History**: newest first, one row per stored query showing the server and how many times it was searched. Fifteen rows are shown; the box itself keeps the 200 newest searches and ages the rest out. A swipe removes one row and the standard 8 s undo puts it back with its count; clearing the whole list asks first
- **Suggestions**: appear once the query is at least two characters long and does not end in a space. Ten entries at most; tapping one searches it, the trailing plus appends it to the current query
- **Multi-select**: long-pressing a suggestion starts a selection. The header states the count, then wraps *Clear selection* and *Add selected* under it, so the committing action stays reachable at any font scale
- **Clearance**: the list ends with the bar's measured height (bottom inset included) and the pane adds no inset of its own; one clearance, counted once
- **Dismissal**: a downward drag past 30% of the screen, Back, or submitting the query. Once closed and settled the pane is unmounted, so a blur and twenty-five rows are not laid out under the grid; the list scroll position is kept so reopening returns to it
- **Semantics**: while the pane is open the grid behind it is excluded from the semantics tree; while it is closed it is gone from the tree entirely

### Selection Action Bar
- **Trigger**: choosing *Select* in the [Context Menu](#context-menu-post-actions)
- **Layout**: floating card on `surfaceContainerHigh` at floating elevation, full width minus `spacingMd`, docked above the system inset: a count readout on the left, then download, favorite, and clear
- **Count**: a readout, not a button label; announced as "N selected"
- **Download**: one direct action that saves the selected posts as individual files at the configured quality. There is no archive mode to choose, so nothing is carried between actions; the tooltip names what the button does
- **Controls**: icon buttons with tooltips, 48 dp targets

### Settings
Every settings screen (Settings, Gesture Settings, Data Backup) uses one row system: rows are grouped into rounded section surfaces, the same block language as the drawer.

- **Containers**: a settings row opens a sheet or a page according to what it holds. Picking one value (language, color palette, download quality, backup frequency, post limit, swipe mode) or editing one short value (Telegram chat id, bot token) opens a bottom sheet, so the page stays behind it and the list sits within thumb reach. A form that types something in (the backup passphrase) is a sheet too, with its action in the footer and no Cancel button: the header already carries a close target, and a second way out of the same sheet is a duplicate control. Opening an area with several independent controls (Backup and restore, Gestures) pushes a page. An `AlertDialog` is reserved for confirming something that discards state and for progress that blocks the screen; it never carries a list of options, and never a field someone has to type into while their thumb reaches for a button at the bottom of the window
- **Value rows**: a row whose value comes from a short list states that value in the title slot — `Post limit` shows the number, `Swipe navigation` shows the direction — and the row opens the picker on tap, anywhere in its own surface. A `DropdownButton` in the trailing slot was the other shape of this and it failed twice: the row around it swallowed the tap, and a menu that had to fit ten options needed a height invented in code

- **Section label**: small caps, `onSurfaceVariant`, `labelSmall` bold with 1.4 letter spacing and a hairline underline that hugs the text, exposed to screen readers as a heading. The label owns its own line; it never merges into the row below it
- **Section surface**: rows of one section sit inside a rounded `surfaceContainerHigh` block, borderless in day and night; in midnight it keeps the page tone with a hairline `outlineVariant`, so it stays pure black. The page keeps 16 dp side padding and each block owns the grouping
- **Page rhythm**: one scrolling list serves every settings page: a 16 dp side gutter, no top inset — a section heading brings its own 24 dp — and 24 dp of run-out at the bottom, so the last block clears the edge of the window. A block with no heading of its own (backup and restore, the blocked-tag field) opens with a leading 24 dp gap instead, so it starts where a labelled block starts. A `NoticeCard` in that list carries `margin: EdgeInsets.zero`: the list owns the gaps and a card margin never adds a second one on top of them
- **Rows**: flat rows inside the block, 12 dp inset, no dividers, no shadows; title plus optional subtitle, 8 dp between them; switches and sliders sit on the trailing edge and carry their own state
- **Note inside a block**: a supporting line that is not some row's subtitle — the line naming the switch a greyed group answers to, a block's own description — is one `InBlockNote`: the row's 12 dp inset inside the block's own 4 dp, so it starts where a row title starts, and the row's 8 dp title-to-subtitle gap above and below. Padding such a line by hand per page is what puts one block's text 8 dp off the edge of another's
- **Checkbox row**: an opt-in is one `BlockCheckboxTile` — title, optional supporting line on the same 8 dp gap, and the box on the trailing edge like a switch row carries its switch, so every toggle in the app answers from one column. It adds no inset of its own: the form that pads its fields, or the sheet that pads its body, has already paid for the gutter, and a second inset steps the tick past the field above it. Three pages had written the row out by hand, one of them with the box on the other edge
- **Trailing affordance**: a `chevron_right` marks every row that opens a page, sheet, or dialog. Rows that act immediately (clear cache) and rows with an inline control (switch, slider) carry none — no verb glyph either, since the row's own title is the verb. The one other glyph the slot may hold is `open_in_new`, and only on a row that leaves the app (create a Telegram bot); nothing that stays inside the app borrows it
- **Sliders**: label on the left, current value on the right, slider across the full row width underneath, optional helper line below. Never a fixed-width slider in the trailing slot; it squeezes the label into a column
- **Selection**: lists of options in a sheet (language, color palette, download quality, backup frequency) mark the active one with `selected` and a trailing check, so the state is visible and announced
- **Sub-pages**: share the section and row widgets with the main page; a settings sub-page that invents its own card layout is a regression

### Server Pages
Server management reuses the same block language as the drawer and settings: a small-caps section label over a rounded `surface` block.

- **Manage**: the saved servers are one block: favicon, name, and homepage per row, with edit / remove in the row menu, closed by an add row whose plus carries `primary`. The app bar names the page, so the block carries no second heading. Reset to default lives in the app bar menu
- **Removal**: removing a server asks first, from the drawer and from this page alike. The same verb answers the same way wherever it is offered
- **Add and Edit are one page**: the add-server row, the drawer action, and the search-bar shortcut all open the same flow, which detects the engine by scanning or lets the user pick one manually
- **Fields**: flat inputs with no fill and a hairline `outlineVariant` underline, with the label in small caps; a form reads as rows inside its block instead of slabs drawn on top of it. The label always sits above the field at the 11 sp label role, in every state, so it never takes the slot the value belongs to; an example belongs in the hint (`e.g. https://…`), never in the label
- **Edit sections**: server (engine, homepage, alias, optional custom API address), server query (parser pickers plus the search / suggestion / post templates, with "From Preset" as the section action), and credentials
- **Credentials**: optional user id and API key, attached to the search, suggestion, and post URLs, and sent along with the scan probe, since some boorus answer nothing without them
- **Save**: one filled button pinned under the form

### Download Entry
- **Filter**: a filter that is on is a chip above the list, naming itself and turning itself off; a shortened list never looks like a full one, and its empty state says no match instead of no files
- **Layout**: Horizontal card with thumbnail, progress bar, status icon, actions
- **Progress**: Linear progress indicator with percentage label
- **States**: Pending, downloading, paused, completed, failed

## 6. Do's and Don'ts

### Do:
- **Do** use `ColorScheme` tokens for all colors; never hard-code hex values
- **Do** keep thumbnails edge-to-edge within their card; the compact on-image overlays (see Timeline Grid) are the only chrome allowed on the image, and they read their scrim and label colors from `AppMediaChrome`; the tag-category accents are the only non-scheme colors left
- **Do** use shimmer loading for thumbnails; it communicates "loading" without blank space
- **Do** let the staggered grid handle visual interest; varied aspect ratios are the texture
- **Do** use the midnight AMOLED mode as the hero viewing mode for image-heavy sessions
- **Do** use curved transitions (easeOutCubic) for sheet expansion and page navigation
- **Do** group related chrome rows into a section block with a small-caps label instead of scattering them as standalone cards
- **Do** pick one of the four elevation rungs for anything that sits above the page, and take the tone step and the shadow together

### Don't:
- **Don't** add shadows, borders, or elevation to image thumbnails; they are the content, not cards
- **Don't** use generic Material defaults without considering the content-first philosophy; every chrome element must earn its pixels
- **Don't** hard-code colors outside of `ColorScheme`; the adaptive palette is the identity. Chrome over the artwork reads `AppMediaChrome`, not `Colors.white` or `Colors.black`, and the tag-category accents are the only documented exception left (per the Adaptive Rule)
- **Don't** put anything on an image beyond the defined compact overlays (score, rating, media type, one tag, dimensions); deeper detail lives in the details sheet
- **Don't** add unnecessary onboarding screens; the interface is self-explanatory; empty states teach by doing
- **Don't** use decorative animations; motion serves feedback (loading, transitions), not delight for its own sake
- **Don't** nest a filled, elevated, or bordered card inside a section block; the block owns the only surface, and rows stay flat inside it
- **Don't** invent a second label or row style per screen; the section label, row title, and supporting text come from the shared scale
- **Don't** give a block a shadow or a shadowed surface a second tone step; one rung per surface
