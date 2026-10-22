# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

## Users

Booru enthusiasts who browse, search, and collect images from booru image boards (Danbooru, Gelboguru, Moebooru, Szurubooru, e621, Shimmie, Philomena, etc.) on mobile. They are power users who understand tag-based search, rating systems, and booru server APIs. Primary context: casual browsing sessions, saving favorites, batch downloading for offline viewing.

A second audience is now served: newcomers who do not know booru APIs and rely on Scan mode / the engine selector to add a server, then browse by tag like everyone else. Power users keep the fast path; newcomers need onboarding that asks nothing about parsers.

## Product Purpose

A native mobile booru client that makes discovering and collecting booru content a fluid, enjoyable experience. Success means the user never has to open a desktop browser for booru access — every core workflow (search, browse, view, save, download) works seamlessly on mobile.

## Positioning

Zero-configuration breadth: paste a bare host and the app detects which booru engine and parsers answer it (Scan mode), so a server is added without hand-writing API config — and the same app covers the widest set of engines in one place. Engine coverage and on-device self-sufficiency are supporting facts, not the headline claim.

## Operating Context

- Browsing happens in short mobile sessions: open drawer → switch server → tag search with autocomplete → staggered timeline → full-screen viewer → save or download.
- Servers are user-supplied and heterogeneous: each server carries its own parser configuration, rating filter, optional API key / user id, and blocked-tag list.
- Media is collected locally to `Downloads/Boorusphere/` (per-server subfolder optional) and re-opened from the Downloads library entry.
- Backup and restore is part of the workflow: full export of settings, search history, servers, blocked tags, favorites and download metadata, optionally scheduled to the user's own Telegram chat via a bot the user creates.
- Distribution is sideloaded: GitHub Releases APKs (plus optional Telegram delivery); the app is not on Google Play.

## Capabilities and Constraints

- Flutter/Dart Android client, package `io.chaldeaprjkt.boorusphere`, Android-only (no iOS or web target).
- Engine abstraction: each booru is a parser with URL templates plus response sniffing; the repo dispatches to the server's configured parser and falls back to scanning every registered parser. New engines are added by writing a parser and registering it.
- Material 3 with dynamic color (Android 12+), light/dark/AMOLED themes, edge-to-edge translucent system bars, high refresh-rate support.
- Viewer: pinch-zoom and pan, double-tap zoom, horizontal page swipe disabled while zoomed, background blur on explicit content, inline video and animated image playback with correct Referer/User-Agent headers.
- No third-party account or cloud: per-server credentials only, all data on device, Telegram integration uses the user's own bot token and chat id.
- Localization via slang with community-contributed locales.
- No explicit commitment to tablet/foldable layouts; the product record speaks to phones.

## Brand Commitments

- Playful & expressive — the UI should feel alive and fun to use, not clinical. Personality through motion, color accents, and thoughtful micro-interactions. The chrome should delight without competing with the content (the images are always the star).
- Anti-reference: generic Material defaults — stock M3 with no personality, looks like every other Flutter app. The UI must feel intentional and crafted, not default.
- Anti-reference: desktop booru sites crammed onto mobile — dense, link-heavy layouts that ignore touch targets and mobile ergonomics.
- Name: Boorusphere. Existing app icon set in `assets/icons/exported/`.

## Evidence on Hand

- Four real phone screenshots: `fastlane/metadata/android/en-US/images/phoneScreenshots/1.png`–`4.png`.
- App icon set (legacy circle/fill, adaptive foreground, logo) in `assets/icons/exported/`.
- Real server presets in `assets/servers.json`.
- Release notes in `CHANGELOG.md`; product/design intent in `DESIGN.md`.
- Absent, and not to be fabricated: user testimonials, review quotes, download counts, benchmarks, press coverage, pricing.

## Product Principles

1. **Content is king** — the image grid and viewer are the product; chrome should be minimal and purposeful.
2. **Delight in the details** — micro-interactions, smooth transitions, and thoughtful touches that reward attention.
3. **Efficient power-user flows** — search, filter, and bulk actions should be fast and accessible, not buried.
4. **Dark by default** — image browsing apps are best in dark mode; light mode is supported but dark is the hero.
5. **Local and self-owned** — content, credentials, and backups stay on the user's device and the user's own services; no account layer, no server of ours.

## Accessibility & Inclusion

Standard mobile accessibility: proper semantic labels, sufficient contrast ratios in both themes, dark mode support, touch targets meeting platform guidelines. Reduced motion support via platform-level settings.
