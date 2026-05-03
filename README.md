<div align="center">
    <div><img src="assets/icons/exported/legacy-circle.png" alt="boorusphere icon" height="92"></div>
    <div><h1 align="center">Boorusphere</h1></div>
    <div>Simple, content-focused booru viewer for Android</div>
    <br/>
    <div>
        <a href="https://github.com/azrim/boorusphere/stargazers">
            <img alt="Stargazers" src="https://img.shields.io/github/stars/azrim/boorusphere?style=for-the-badge&logo=apachespark&logoColor=ebebf0&color=ff89b5&labelColor=23232F"/>
        </a>
        <a href="https://github.com/azrim/boorusphere/releases/latest">
            <img alt="Latest release" src="https://img.shields.io/github/v/release/azrim/boorusphere?style=for-the-badge&logo=pkgsrc&logoColor=ebebf0&labelColor=23232F&color=95b6ff">
        </a>
        <a href="https://github.com/azrim/boorusphere/actions">
            <img alt="Workflow status" src="https://img.shields.io/github/actions/workflow/status/azrim/boorusphere/ci.yml?style=for-the-badge&logo=githubactions&logoColor=ebebf0&labelColor=23232F&label=CI">
        </a>
        <a href="https://github.com/azrim/boorusphere/blob/main/LICENSE.md">
            <img alt="License" src="https://img.shields.io/github/license/azrim/boorusphere?style=for-the-badge&logo=gitbook&logoColor=ebebf0&color=b0a8f7&labelColor=23232F"/>
        </a>
    </div>
    <br/>
    <div>
        <a href="https://github.com/azrim/boorusphere/releases">
            <img src="assets/button-GHReleases.png" alt="GitHub release" width="160">
        </a>
        <!--
        <a href="https://apt.izzysoft.de/fdroid/index/apk/io.chaldeaprjkt.boorusphere">
            <img src="assets/button-IzzyOnDroid.png" alt="IzzyOnDroid release" width="160">
        </a>
        -->
    </div>
</div>

# Features

### Browse & search
- Multi-server support — Danbooru, Gelbooru, Moebooru, Konachan, Safebooru, Szurubooru, e621, Shimmie, Philomena, and more, all manageable from the in-app drawer.
- Add new servers with a guided **engine selector** (no manual API parsing required) — pick the booru engine, paste the base URL, done.
- Tag-suggestion search with rolling search history. Single-word matches are surfaced before multi-word matches so common tags like `hololive` come up before `hololive_girl_tall` when you type `h`.
- Per-server rating filter (Safe / Questionable / Explicit) directly in the search bar.
- Block tags from search results (server-scoped or global).

### Post viewer
- Pinch-zoom + pan with `InteractiveViewer`. Pinch-zoom automatically disables horizontal page-swipe so panning a zoomed image won't accidentally jump to the next post.
- Double-tap to zoom in/out at the tap point.
- Swipe up to open the post details sheet (tags, source info, dimensions). Multi-select tags from the sheet to copy, block, or search.
- Background blur on explicit content with a one-tap unblur.
- Save favorites and revisit them from the drawer.

### Media
- Plays videos and animated images (.gif, .webm, .mp4) inline.
- Sends correct `Referer` / `User-Agent` headers on video requests so hotlink-protected booru CDNs (e.g. Gelbooru) work.
- Image cache shared between timeline thumbnails, post viewer, and downloader — open-then-download reuses the bytes you already loaded instead of re-fetching.

### Downloads
- One-tap download of images and videos to the device's `Downloads/Boorusphere/` folder (per-server subfolder configurable).
- Re-uses the in-memory cache when available — instant downloads if you've already viewed the post.
- Downloads tab in the drawer with redownload + open-in-system-viewer actions.

### Backup & restore
- Export everything (settings, search history, server list, blocked tags, favorites, downloads metadata) to a single backup file.
- **Telegram backup integration** — schedule automatic backups (daily / weekly / monthly) to a Telegram chat via your own bot, with a "Backup now" button for manual snapshots. Includes a "Test connection" button to verify your bot token / chat ID before scheduling.

### UI
- Material 3 with dynamic color (Android 12+) — pulls from your wallpaper palette.
- Light, dark, and AMOLED-friendly themes.
- High refresh rate support (90 / 120 Hz) via `flutter_displaymode`.
- Edge-to-edge layout with translucent system bars and optional backdrop blur on overlays.
- Customizable gestures (horizontal vs vertical post swipe, swipe-to-close-search, etc).

# Preview

<p align="justify">
    <img width="24%" src="fastlane/metadata/android/en-US/images/phoneScreenshots/1.png" />
    <img width="24%" src="fastlane/metadata/android/en-US/images/phoneScreenshots/2.png" />
    <img width="24%" src="fastlane/metadata/android/en-US/images/phoneScreenshots/3.png" />
    <img width="24%" src="fastlane/metadata/android/en-US/images/phoneScreenshots/4.png" />
</p>

# Installing

The simplest path is to grab the latest **GitHub Release** APK from the badge above. Pick the APK matching your phone's CPU architecture:

| File suffix | When to pick it |
| --- | --- |
| `arm64-v8a` | Almost every phone made after 2017. **Default choice.** |
| `armeabi-v7a` | Older 32-bit Android phones (pre-2017). |
| `x86_64` | Android emulators / Chromebooks running x86_64 Android. |
| `universal` | Bigger file, runs on all of the above. Use only if unsure. |

The app is **not** on Google Play. F-Droid via IzzyOnDroid is currently disabled but the link remains in the source for when it's re-enabled.

# Building from Source

You'll need the [Flutter SDK](https://flutter.dev/) and a working Android toolchain (Android Studio or just the command-line `sdkmanager`). The project is pinned to `flutter ">=3.35.5"` and `dart ">=3.0.3 <4.0.0"` (see `pubspec.yaml`).

```bash
git clone https://github.com/azrim/boorusphere.git
cd boorusphere

# Install dependencies
flutter pub get

# Generate code (Riverpod providers, Hive adapters, route table, JSON parsers, ...)
dart run build_runner build --delete-conflicting-outputs

# Generate translations
dart run slang

# Run on a connected device or emulator
flutter run
```

After editing entities, providers, routes, or any `*.freezed.dart` / `*.g.dart` consumer, re-run `build_runner`. After editing translation JSON, re-run `slang`. Both ship a watch mode (`build_runner watch`, `slang watch`) that's worth using during active development.

The repo also ships [grinder](https://pub.dev/packages/grinder) tasks under `tool/grind.dart` for common chores. Useful ones:

```bash
grind chkfmt          # dart format --set-exit-if-changed (CI runs this)
grind test            # flutter test --coverage
grind apkrelease      # build split-per-abi release APKs (used by CI)
grind pigeons         # regenerate pigeon platform-channel bindings
```

# APK builds via GitHub Actions

This repo ships a `Build APK` workflow (`.github/workflows/build-apk.yml`) that:

1. Runs on every push to `main`, on every `v*` git tag, and on manual `workflow_dispatch`.
2. Builds split-per-abi release APKs via `grind apkrelease`.
3. Uploads them as a workflow artifact (downloadable from the Actions run page for ~90 days).
4. **Optionally** posts each APK to a Telegram chat via the Bot API.
5. On `v*` tags, also attaches the APKs to the auto-created GitHub Release.

To enable Telegram delivery, add these repository secrets at `Settings → Secrets and variables → Actions`:

| Secret | Value |
| --- | --- |
| `TELEGRAM_BOT_TOKEN` | The bot token from `@BotFather`. |
| `TELEGRAM_CHAT_ID` | The numeric chat ID for the target chat (use `@userinfobot` to look it up). |

If the secrets are missing, the Telegram step becomes a no-op and the APKs still land as workflow artifacts. To get the bot to deliver to a private channel, add the bot to the channel as an admin and use the channel's `-100…` ID.

# Translation

### Translating untranslated strings

```bash
# 1. Generate the missing-translations report
dart run slang analyze --outdir=i18n

# 2. Edit i18n/_missing_translations.json with translations for your locale.

# 3. Apply the translations and re-run analysis
dart run slang apply --outdir=i18n
dart run slang analyze --outdir=i18n
```

It's perfectly fine to leave strings untranslated in `i18n/_missing_translations.json` rather than committing partial English fallbacks into the per-locale JSON.

### Adding a new language

Copy `i18n/strings_en.i18n.json` to `i18n/strings_<language-code>.i18n.json` and either open a PR with the new locale or build it locally:

```bash
dart run slang
dart run slang analyze --outdir=i18n
flutter run
```

# Contributing & changelog

User-facing changes per release are tracked in [`CHANGELOG.md`](CHANGELOG.md). The recent modernization passes (Phase B–G in the v1.9.x line) reduced boilerplate, dropped the unmaintained `extended_image` dependency in favor of `cached_network_image` + `InteractiveViewer`, modernized the drawer to `Scaffold.drawer`, and trimmed a class of silent state-management bugs.

If you're submitting a PR:
- Run `grind chkfmt` and `grind test` locally — CI runs the same and rejects unformatted code.
- Bump `version:` in `pubspec.yaml` (`X.Y.Z+buildCode`) and add a `## X.Y.Z` entry at the top of `CHANGELOG.md`.
- For new languages, follow the **Translation** section above.
