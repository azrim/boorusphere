## 2.0.2

* **Page-swipe lock while zoomed actually engages now**: 2.0.1 replaced the `ListenableBuilder`-driven physics swap with a custom `_PageViewerScrollPhysics` whose `shouldAcceptUserOffset` consulted `canSwipeListenable` directly, on the assumption Flutter's `Scrollable` re-evaluates that on every pointer-down. It doesn't — `Scrollable` only re-runs `physics.shouldAcceptUserOffset(position)` inside `_updatePosition()` (which fires on `didUpdateWidget`). Because the `PageView` was built once and pinned, `setCanDrag()` was never called again and the `HorizontalDragGestureRecognizer` stayed installed permanently — letting the user page to the next post even while the current image was zoomed. Reverted to the `ListenableBuilder` wrapping the `PageView`: the underlying `PageView` State preserves across rebuild, but the swap from `PageScrollPhysics` to `NeverScrollableScrollPhysics` triggers `didUpdateWidget`, which un-installs the drag recognizer correctly.
* **CI: skip oversize APKs in Telegram delivery**: Telegram bot `sendDocument` is hard-capped at 50 MB. The universal APK introduced in 2.0.1 is ~62 MB (it bundles every ABI) and tripped a 413 on the post-merge Build APK run, which in turn blocked the `Attach APKs to GitHub Release` step from firing on a tag push. The Telegram delivery loop now skips any APK > 49 MB with a clear log line; the universal APK still ships via the workflow artifact + GitHub Release path. Per-ABI splits continue to be delivered to Telegram unchanged.

## 2.0.1

Follow-up gesture fixes against 2.0.0 + universal APK in CI.

* **Double-tap-to-zoom-out fix**: 2.0.0 stripped the entire single-finger gesture overlay (tap + double-tap + swipe) the moment the image zoomed past 1× scale. That was the easiest way to give `InteractiveViewer`'s single-finger pan recognizer the full gesture arena, but it also stripped the double-tap recognizer — leaving the user no way to recover from a zoom except pinching back. Tap and double-tap are now mounted at every zoom level; only swipe-up / swipe-down are suppressed while zoomed.
* **Reactive `PageView` swipe-lock**: the post viewer used to wrap its `PageView` in a `ListenableBuilder` watching `canSwipeListenable` and toggling between `PageScrollPhysics()` and `NeverScrollableScrollPhysics()`. Every zoom/zoom-out rebuilt the entire `PageView`, which in practice left the underlying `Scrollable` in an ambiguous state — manifesting as "after swipe to next post, gestures are dead until the settle finishes". Replaced with a custom `_PageViewerScrollPhysics` that gates `shouldAcceptUserOffset` on the listenable; the `PageView` is now built once and its drag-acceptance is consulted reactively on every pointer-down.
* **Universal APK in CI**: the `apkrelease` grind task now also runs `flutter build apk` (no `--split-per-abi`) so every tagged release attaches a universal APK alongside the per-ABI ones, giving users who don't know their device ABI a fallback download. `bin/renameapks.dart` is generalised to map every known source filename onto the user-facing `boorusphere-X.Y.Z-{abi|universal}.apk` name.

## 2.0.0

Major version bump consolidating the UI tech-debt + render-bottleneck modernization shipped across 1.9.2 – 1.9.6 and the gesture-stack rewrite below.

**Highlights since 1.9.0:**

* **Render correctness pass** (Phase B + C, 1.9.1 → 1.9.2): timeline rebuild storm fixed (post-list selectors no longer silently miss updates thanks to `List.unmodifiable` emissions); per-frame `ImageFilter` allocations hoisted out of the hot path; useless `RepaintBoundary` removed; `Hero.flightShuttleBuilder` closure hoisted to top-level so we don't allocate per visible thumbnail per build; pinch-zoom now disables `PageView` swipe.
* **State graph cleanup** (Phase D): `PostViewerController` consolidated to a single `ValueNotifier<PostViewerState>` + selectors (11 notifiers → 1 + 3); `searchBarControllerProvider` migrated to a real `Provider.family`; `homeDrawerControllerProvider` got a real default factory; `app_theme.dart` rewritten to drop a singleton notifier that mutated its own field without notifying Riverpod.
* **Image-stack migration** (Phase E): `extended_image` dropped entirely. Timeline + favicons + downloads + post-placeholder migrated to `cached_network_image`; explicit-content blur uses the framework's `ImageFiltered` instead of `extended_image`'s painter hooks. Post viewer rebuilt on `InteractiveViewer` + `TransformationController` for pinch zoom + pan, with double-tap zoom rebuilt via `Matrix4Tween`.
* **M3 drawer** (Phase F.1): `Scaffold.drawer` adopted; manual slide animation, `vector_math` dependency, and the bespoke `HomeDrawerController` wrapper are gone (-202 LOC).
* **Gelbooru video playback** (1.9.3): pass the post-headers factory to `VideoPlayerController.networkUrl` via `httpHeaders` so hotlink-protected video CDNs accept the request, mirroring the Kropatz fork.
* **README** (1.9.4): full rewrite covering current 1.9.x feature surface and the GitHub Actions APK build + Telegram delivery pipeline.
* **Release plumbing** (1.9.5): `Build APK` workflow granted `contents: write` so `v*` tags can attach APKs to the GitHub Release.
* **Pinch-to-zoom gesture fix** (this release): the post viewer wrapped the entire `PageView` in a `GestureDetector` with vertical-drag callbacks for swipe-up-for-details / swipe-down-to-dismiss; its `VerticalDragGestureRecognizer` aggressively claimed gestures with any vertical component, beating `InteractiveViewer`'s `ScaleGestureRecognizer` to the gesture arena and silently dropping pinch input. The gesture surface is rewritten so each post page owns its own gesture stack, swipe-up/swipe-down ride on a custom `_SinglePointerVerticalDragRecognizer` that synchronously rejects itself the moment a second pointer joins, and the per-page overlay is taken out of the gesture path entirely while the image is zoomed.

## 1.9.5

* CI: grant `contents: write` to the `Build APK` workflow so tagged releases can attach APKs to the GitHub Release. Without this permission `softprops/action-gh-release` fails with HTTP 403 on `v*` tag pushes.

## 1.9.4

* Documentation: full README rewrite covering current 1.9.x features (engine-based server adder, post details sheet, Telegram backup integration, etc) and a new section documenting the GitHub Actions APK build + Telegram delivery pipeline.

## 1.9.3

* Fix Gelbooru and similar boorus failing to play normal videos (.mp4 / .webm). The video player now sends the same headers (Referer, User-Agent) that image requests already use, so servers that hotlink-protect their video CDN no longer reject the playback request.

## 1.9.2

* Pinch-zoom on a post now disables horizontal page-swipe so panning a zoomed image won't accidentally swipe to the next post
* Search suggestions now show single-word matches before multi-word ones (typing "h" now shows `hololive` before `hololive_girl_tall`)
* Drawer rebuilt on top of Material's standard drawer (smoother animation, native gesture handling)
* Post viewer rebuilt on `cached_network_image` + `InteractiveViewer` (drops the unmaintained `extended_image` dependency)
* Timeline thumbnails migrated to `cached_network_image` for better cache behavior
* App theme rewrite removes a silent provider-contract violation that could leave the theme stale across rebuilds
* Internal performance: removed per-frame rebuild storm during drawer animation, removed per-thumbnail closure allocations, removed redundant `RepaintBoundary`s
* CI: `Build APK` workflow builds split-per-abi APKs and posts them to a configured Telegram chat on every push to `main`

## 1.9.1

* Add server switch from search bar icon
* Keep search bar UI stable when scrolling
* Fix tag append action not working correctly
* Make only server list scrollable in drawer

## 1.9.0

* Add new server add page with booru engine selector
* Replace scanner with engine selector in server editor
* Fix Gelbooru tag suggestions using autocomplete2 endpoint
* Fix server migrations running after backup restore
* Improve post viewer and details sheet performance
* Add blur and transparency effects to UI elements

## 1.8.2

* Fix post viewer showing wrong content when swiping
* Fix video player not playing on non-first posts
* Fix download button showing wrong state after downloading
* Fix grid size icon not reappearing after scrolling to top
* Fix cache downloads not showing on downloads page
* Improve post viewer and timeline performance
* Show all backup settings even when disabled
* Update dependencies

## 1.8.1

* Fix download failing when cached quality differs from download quality
* Fix download button showing wrong state on different posts

## 1.8.0

* Add Telegram backup integration
  - Automatically backup your data to Telegram on a schedule (daily, weekly, or monthly)
  - Manual "Backup now" button to send backup instantly
  - Test connection to verify your bot token and chat ID
* Faster downloads using cached content
  - Downloads now use already-loaded images instead of re-downloading
  - Shows notification when download completes from cache
* Fix app updater not downloading updates correctly
* App now restarts after importing backup to apply changes
* Various bug fixes and improvements

## 1.7.0

* New post details experience
  - Swipe up on any post to see details, tags, and source info
  - Details slide up smoothly from the bottom of the screen
  - Select multiple tags at once to copy, block, or search them together
  - Swipe down or drag the handle to close details
* Improved gesture controls
  - New gesture settings page to customize swipe behavior
  - Choose between horizontal or vertical swipe to browse posts
  - Smoother animations throughout the app
* Better app performance
  - Fixed various memory and rendering issues
  - Reduced lag when scrolling through posts
  - Updated to latest Flutter libraries

## 1.6.0

* Add swipe gestures for better navigation
  - Swipe down to close search bar
  - Swipe up on images to open post details
  - Smooth animations that follow your finger
* Faster and smoother search experience
  - Search bar opens instantly without lag
  - Search history shows immediately when typing
  - Better performance with large suggestion lists
* Remove confusing Home button from side menu
* Fix search handle position on phones with notches
* Fix various app warnings and improve stability

## 1.5.4

* integrate server management into home drawer

## 1.5.3

* fix: remove automatic parser persistence to prevent overwriting manual selection
* fix(e621): handle API response format change with stricter validation
* chore: update repository URLs to azrim/boorusphere
* feat: add Windows batch script for release builds

## 1.5.2

* add API credentials (user ID and API key) support for servers
* add Rule34.xxx to default servers
* add GIF and video overlay indicators in timeline
* add exit button to home drawer
* fix: improve GIF detection by checking MIME type
* fix: handle GIF type in post viewer switch statement

## 1.5.1

* Maybe fix download issue

## 1.5.0

* Update Flutter
* Add ability to add an api key before scanning server

## 1.4.10

* Add easy way to append api key to server URLs

## 1.4.9

* Add german translation - Thanks @LorenorZorro3000

## 1.4.8

* Fix download indicator

## 1.4.7

* Add post count to tag suggestions
* Support for autocomplete.php (Safebooru and others)

## 1.4.6

* Stream videos instead of waiting for the full download
* Hide pause overlay on initial video load

## 1.4.5

* Fix backstack exit got blocked by the double back-tap prompt
* Fix update app button did not work properly

## 1.4.4

* Fix unable to exit app with double back-tap

## 1.4.3

* Update th-th, ja-jp, and uwu translation (@rinme)
* Fix download failed on danbooru (@makisukurisu)
* Update Flutter to 3.22.2

## 1.4.2

* Add zh-TW translation (@xperiazu21)
* Add zh-Hans translation (@History-exe)
* Update UK translation (@CakesTwix)

## 1.4.1

* Fix BooruOnRails web post url scanning
* Fix downloading images that has special characters name
* Fix scanning issues on realbooru
* Improve scanning mechanism
* Initial support for Szurubooru
* Japanese and Thai translation update (by @rinme)
* Update flutter to 3.10.5

## 1.4.0

* Add warning popup when using menu > clear all on Downloads screen
* Fix built-in updater did not works (bug since 1.3.8)
* Fix search suggestion and history filtering method
* Fix some jank on homepage caused by unnecessary layout rebuilds
* Optimize search screen UI performance
* Show recent changelog after updating the app
* Update flutter to 3.10.4

## 1.3.9
* Fix video player keeps playing when navigating to the next screen
* Apply high-framerate workaround for crappy OS such as OxygenOS
* Cleanup previous routes when pressing Home on sidebar
* Fix some UI performance issue

## 1.3.8
* Update flutter to 3.10.1
* Add UwUgish (or UwUnglish? oh my lord...) language (by @rinme and @Tienisto)

## 1.3.7
* Fix search suggestion text is not properly decoded/unescaped
* Relax search suggestion fetching update
* Update Turkish translation (by @kyoyacchi)
* Update Ukrainian translation (by @CakesTwix)

## 1.3.6
* DownloadsPage: add option to filter downloads by status
* Several UI updates, fixes, and improvement
* Update Indonesian language

## 1.3.5
* Fix backup archive creation after 1.3.2 (caused by download quality selection)

## 1.3.4
* Add buffering indicator to the video player
* Add pull-to-refresh on home screen
* Fix backup archive creation after 1.3.0 (caused by rating selection)
* Fix restoring large backup archive
* Update flutter to 3.7.7

## 1.3.3
* Update Turkish translation (by @kyoyacchi)

## 1.3.2
* Add option to select default quality when downloading
* Add support for booru-on-rails
* Add support for parsing post score
* Fix wrong page number starting point causing some of content to be missing
* Improve image zoom scaling algorithm
* Improve search suggestion
* Improve thumbnails rendering and limit it's height on very long picture (such as manga)
* Improve server url scanner
* Update Japanese and Thai translation (by @rinme)
* Update Ukrainian translation (by @CakesTwix)

## 1.3.1
* Add support for "rating:sensitive" parse and selection
* Fix buggy back-stack on search screen and homepage's sidebar
* Fix rating selection query compatibility issue
* Fix some UI bug on favorites-page's content viewer
* Update Bahasa Indonesia

## 1.3.0
* Add rating selection to search screen
* Add settings to only blur content on timeline
* Fix favorites page bottom bar
* Fix restore data permission on Android 12
* Initial support for backstack navigation
* Remove safe-mode on settings page (replaced with rating selection)

## 1.2.9
* Fix loading danbooru image on unstable connection
* Update Flutter to 3.7.0

## 1.2.8
* Add Russian translation (by @wheremyfiji)
* Add Ukrainian translation (by @CakesTwix)
* Update Flutter engine to 3.3.10

## 1.2.7
* Add Filipino language (by @maisans-maid)
* Add Japanese language (by @rinme)
* Add Turkish language (by @kyoyacchi)
* Fix add-button did not replace typed word on search screen
* Fix Keyboard Incognito settings always keep getting reset
* Fix nomedia creation issues
* Fix video player late fullscreen exit
* Improve tag blocker mechanism
* Initial support for backup and restore app data
* Update Indonesia translations
* Update Thai translations (by @rinme and @altinat)

## 1.2.6
* Add Thai language (by @altinat)
* Improve and fix several issues on video player
* Fix download status and progress not showing properly
* Keep screen awake when opening post viewer

## 1.2.5
* Add support for Incognito Keyboard mode (Settings -> Safe Mode -> Incognito Keyboard)
* Fix scanner is being blocked on some site (such as e621)
* Fix video player crash while loading source

## 1.2.4
* Fix parser error when post(s) contains a tag ended with percent

## 1.2.3
* Add support for Shimmie2-powered boorus
* Fix tags encoding issues
* Fix searching tag that has been blocked resulting in endless loading
* Other small bugfix and improvement on server scanner and parser

## 1.2.2
* Add Indonesian language (Bahasa Indonesia)
* A lot code architectural changes for more maintainable codebase
* Settings: add option to switch language (currently only English and Indonesian)
* Fix crash issues when tyring to update app due to missing permission
* Small UI fixes and improvements

## 1.2.1
* Fix tag suggestion for E621
* Fix settings > server > show original content not saved properly
* Fix metadata parsing issues on konachan and yandere
* Fix broken Gelbooru (XML) parser
* Fix content not properly loaded on Moebooru-based websites


## 1.2.0
* Add support for parsing E621
* Add settings to show original content on post preview
* Update flutter engine to 3.3.7 (actual fix for downloader crashing issues on Android 13)

## 1.1.9
* Fix favorite button color on day mode UI
* Fix video post did not recognized as video on rule34
* Preload previous and next post (only applied to photo post, not video)

## 1.1.8
* Fix flutter engine crashing when downloading files on Android 13

## 1.1.7
* Remove problematic Android 13 notification workaround (for some unknown reason it leads to app crashing on production build)

## 1.1.6
* Add option to disable UI Blur (might helps on low-end devices)
* Add support for Favorite posts
* Add workaround for downloader notification issues on Android 13
* Fix app update version checker
* Fix several UI issues
* Handle API origin redirection when scanning server
* Improve tag suggestion result

## 1.1.5
* Fixup load more button keep trying to load page endlessly

## 1.1.4
* Add support for custom server API address
* Add support for in-app-update
* Fix load-more did not work occasionally especially when post limit is at below 40
* Fix server data editing issues
* Fix several UI inconsistency
* Parse categorized tags for server that supports it (like danbooru)

## 1.1.3
* Revamp several UI elements
* Fix app cannot be closed after using "search tag" or "add tag to current search"
* Fix search history did not sorted properly
* Fix placeholder image did not get de-blurred after clicking show button
* Fix video player state inconsistency issues
* Improve double-back to close consistency

## 1.1.2
* Add option to clear image cache at settings
* Add option to hide downloaded media from gallery at settings
* Add option to set posts limit per load at settings
* Add changelogs viewer at about page
* Auto-load-more content on post viewer
* Downloads: Add option to redownload media when the file is missing
* Fix content loading issues 3dbooru (make sure to clear cache at settings after updating)
* Fix duplicated content issues while parsing api result
* Fix fullscreen restoration issues on Android 9 and below
* Improve search suggestion handling
* Various UI fixes and improvement

## 1.1.1
* Add download dialog and allow for downloading sample image (if exists)
* Add option to group downloaded files by server on Downloads page
* Add Settings option to blur content that rated as explicit
* Add support for Safebooru tag suggestion
  (you may need to reset server at Server -> "Reset to default" to update it)
* Add support for scanning old Danbooru v1.13.0 API (for example: 3dbooru)
* Add support for various booru post details (rating, sample image, resolution, art source)
* Add support to display sample image (lower version of original image) if exist
* Fix pause button can't be used while loading video
* Improve API parser stability
* Improve server scanning methods
* Several UI fixes and improvement
* Show preview image on Downloads page

## 1.1.0
* Add support for Android 13 themed icon
* Add option to edit existing server data
* Allow any server except last to be removed
* Add download progress indicator on Downloads Page
* Add About Page
* App icon update
* Fix all history did not show up on blank input
* Fix downloaded content did not appears on android gallery
* Fix duplicated tags when using append button on search suggestion
* Fix filename display issues on Downloads Page
* Fix retry button did not retry the current page

## 1.0.9
* New feature: Download content directly from the app!
* New UI: Material Design 3 with wallpaper-based color theme for Android 12
* Add more option to manipulate search tags on the floating action button
* Fix parsing Gelbooru API result
* Fix crashing when a server is removed
* Fix video player cannot be muted early
* Fix various UI-related issues
* Improve API transactions stability

## 1.0.8
* Fix clicking URLs did not open external browser
* Fix some minor issues on suggestion, favicon, and custom server scanning.

## 1.0.7
* New feature: Custom booru server
* UI Layout and theming improvement
* Fix deprecated code and update dependencies

## 1.0.6
* Add double back trigger to close app
* Improve search suggestion handling
* Improve video player implementation
* Update several deprecated code and dependencies
* and many other improvement under the hood

## 1.0.5
* Add copy-to-clipboard button to links on the post info page
* Add clear-all button for the search history
* Fix blocked tag list cannot be scrolled
* Fix safe mode for Danbooru
* Muting video volume is now persistent
* New pitch black theme option for the dark mode
* Now you can search the tag directly when selecting the list of tags on the post info page
* Several minor fix and enhancements for the UIs
* Update several deprecated code and dependencies

## 1.0.4
* Add a feature for blocking a particular tags from search result and history
* Several UI Improvement on Search bar (tag suggestion and history) and sidebar
* Now History entries can be removed by swipe it left
* Search suggestion and history entries on-click behaviour are changed, from adding to the search bar to directly search the particular entry.
* However, + button is added because it's really handy for searching multiple tags like before.
* Sidebar now shows the server's web icon instead of basic globe icon

## 1.0.3
* Properly sort search history from latest entry down to the oldest entry
* Fix similar search query are being saved to history (the already saved one are still exists, we have to manually clear it)
* Improve thumbnail quality especially on 2x and 3x grid
* Migrate Tags UI from flutter_tags to simple TextButton
* Update app dependencies

## 1.0.2
* Auto-scroll to the last opened post when go back to home
* Fix Search bar color did not updated when changing theme
* Implement simple update checker based on pubspec.yaml
* Improve Search suggestion behavior
* Make tags safe from being covered by floating action button
* Migrate video player from video_player package to better_player
* Theme switcher can also be persist and has an option to respect system theme
* Beautify drawer menu
* Show displayed source info on the Post Detail (for video post that has zip source)

## 1.0.1
* New Feature: Tag Search History
* Breaking changes: Migrate the settings storage from SharedPreferences to Hivedb.
  any changes on previous version not be preserved (selected server, grid number, safe mode).
* Improved Post tags UI

## 1.0.0
* Initial release
