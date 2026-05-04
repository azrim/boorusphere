## 2.0.17

* **Fix in-app updater "failed to download"**: user report after v2.0.15 — the updater advertised an update but the download 404'd. Root cause: `AppVersionRepo.fetch()` queried `https://github.com/azrim/boorusphere/raw/main/pubspec.yaml` to detect the latest version. But `pubspec.yaml` on `main` advertises the new version as soon as the version-bump commit lands, which is BEFORE the `Build APK` workflow uploads the corresponding APK assets to the matching GitHub Release. During that ~10 min build window, the updater would happily advertise version X and then 404 on the GitHub Release download URL because no `boorusphere-X.Y.Z-*.apk` asset existed yet.
* **Fix**: query the GitHub Releases API (`https://api.github.com/repos/azrim/boorusphere/releases/latest`) instead. A release only exists once `softprops/action-gh-release` has uploaded the APKs at the very end of `Build APK`, so anything `releases/latest` returns is guaranteed to have a downloadable APK. We additionally verify the running architecture's APK is in the release's `assets` list — defends against partial uploads (network hiccup mid-upload, runner timeout, etc.). `pubspec.yaml` is kept as a fallback **only** when the Releases API call errors (network failure, DNS, rate limit) — if the API responds successfully but the response doesn't contain a usable release, we return `AppVersion.zero` rather than fall back to pubspec, since falling back would re-introduce the original race.
* **No effect on the URL the updater downloads**: the asset URL is still derived from `gitUrl/releases/download/v$version/boorusphere-$version-$kAppArch.apk`. We just no longer advertise versions for which that URL doesn't yet exist.

## 2.0.16

* **Fix swipe up/down silently dying after a 2nd pinch at scale = 1**: user report — *"after zooming out using pinch until original size, if I zoom out again at original size, the swipe up and down gesture is doing nothing. when I close and open the post again, it back to normal."* The custom `_SinglePointerVerticalDragRecognizer` (used in both `_PostImageGestureOverlay` and `_PostVideoSwipeOverlay`) maintained a local `_activePointers` set / counter to self-reject on multi-touch. When a 2nd pointer landed, we called `resolve(GestureDisposition.rejected)` and returned **without** calling `super.addAllowedPointer(event)` for the 2nd pointer — meaning Flutter never tracked it in our recognizer, so we **never received its up/cancel events**, but we'd already added the pointer ID to `_activePointers`. The ID leaked. The next single-finger gesture would see `_activePointers` count ≥ 1 stale entry, exceed the multi-touch threshold, and self-reject silently. Closing and reopening the post created a fresh recognizer instance, which is why it "fixed itself".
* **Why a pinch at scale = 1 was the trigger**: at any other scale the parent `ValueListenableBuilder<Matrix4>` toggles `isZoomed` on the scale crossing 1.01 → `RawGestureDetector`'s gesture map drops/re-adds `_SinglePointerVerticalDragRecognizer` → fresh instance with empty `_activePointers`. But pinching at scale = 1 doesn't change scale (capped at min 1.0), so the recognizer instance survives and the leaked ID accumulates.
* **Fix**: explicitly `_activePointers.remove(event.pointer)` on the multi-touch yield path before `return` so the never-tracked pointer doesn't leak. The first pointer (which IS tracked and IS in arena) continues to be cleaned up via `rejectGesture` / `didStopTrackingLastPointer` as usual. Both `post_image.dart` and `post_video.dart` recognizers updated; the video version was additionally migrated from `int` counter to `Set<int>` to match the image version's semantics.

## 2.0.15

* **Page-snap animation now resolves in ~80 ms instead of ~280 ms**: user report — *"the swipe gesture is done, I swipe and release my finger. but the animation isn't done immediately ... but the user will be doing another gesture like swipe up, because in their eyes it's already done ... that make any gesture is considered as swipe left or right gesture."* While the snap is animating, `Scrollable` is in a `BallisticScrollActivity`. As soon as the user touches down (even before they move) the drag recognizer's `_handleDragDown` fires, holds the ballistic, and the `HorizontalDragGestureRecognizer` is immediately a contender for the next motion. Any horizontal jitter at the start of a follow-up gesture wins the arena and the page continues animating from the frozen position. Shortening the snap to ~80 ms (essentially imperceptible) collapses the window for follow-up gesture confusion.
* **How**: `_GentlePageScrollPhysics` now overrides `spring` with a stiff, slightly under-damped `SpringDescription(mass: 0.3, stiffness: 800, ratio: 0.95)` — `ω = √(k/m) ≈ 51.6 rad/s`, settle time `≈ 4/ω ≈ 80 ms`. Combined with a permissive `Tolerance(distance: 3 px, velocity: 5 px/s)` so the simulation declares "done" within human-imperceptible bounds (default tolerance is roughly 0.4 px / 20 px/s — keeps the simulation alive past the point any human could perceive motion). Net: snap is essentially instant.

## 2.0.14

* **Pinch-to-zoom now wins gesture arena over horizontal page swipe**: previously, when starting a pinch on a post image, finger 1's slight horizontal motion at gesture start could let `PageView`'s built-in `HorizontalDragGestureRecognizer` claim the arena before `InteractiveViewer`'s `ScaleGestureRecognizer` accumulated the second finger — so the page would side-swipe instead of zooming. The fix wraps `PostImage`'s render tree in a `Listener` that observes pointer events at the engine level. The moment a second pointer lands, we synchronously force `onZoomChanged(true)` → `controller.canSwipeListenable` flips → the wrapping `ListenableBuilder` rebuilds `PageView` with `NeverScrollableScrollPhysics` → `Scrollable._updatePosition()` runs on `didUpdateWidget` and recreates the position, cancelling any in-flight horizontal drag. The arena is then free for `ScaleGestureRecognizer` to win pinch-zoom uncontested. Also handles the way out: when the last finger lifts, we re-evaluate scale and re-enable swipe only if the user did not actually end up zoomed (e.g., a two-finger tap that never resolved into a pinch).
* **No effect on single-finger gestures**: tap, double-tap, single-pointer vertical-drag-for-swipe and the existing horizontal page swipe all behave identically — the pointer-count guard only kicks in on multi-touch.

## 2.0.13

* **Tone down horizontal page swipe sensitivity**: previous post-viewer used the framework default `PageScrollPhysics`, which committed a page change at any drag past 50 % of page width AND on any fling above ~20–50 px/s. In practice that meant a casual / accidental horizontal swipe (e.g., near the edge of the screen) would page-flip mid-browse. Custom `_GentlePageScrollPhysics` now requires either: a drag past **60 %** of page width, OR a deliberate fling above **400 px/s**. Below either threshold the page snaps back to where it came from. Existing pinch-to-zoom multi-touch yield is unaffected (the physics swap on `canSwipeListenable` still drops to `NeverScrollableScrollPhysics` while zoomed).

## 2.0.12

* **Restore working swipe-up / swipe-down gestures on post viewer**: 2.0.5 moved all vertical-drag handling out of `PostImage` / `PostVideo` and up to a new route-level `_PostViewerPullToDismissShell`. The intent was to add an elastic pull-to-dismiss visual on top of the existing fast-fling-up / fast-fling-down behavior. In practice the route-level `VerticalDragGestureRecognizer` could not reliably win the gesture arena over `InteractiveViewer`'s built-in scale recognizer at scale = 1 (the scale recognizer claims pure-vertical drags greedily even when no scaling is happening), so the entire swipe-up / swipe-down family silently went dead. 2.0.8's threshold tuning didn't help because the recognizer was never firing in the first place.
* **Fix**: revert to the proven per-surface gesture wiring used in v2.0.4. Vertical drag is now owned by `_PostImageGestureOverlay` (inside `PostImage`'s Stack) and `_PostVideoSwipeOverlay` (inside `PostVideo`'s Stack). Both are layered above `InteractiveViewer` / the video surface using `Positioned.fill` + `HitTestBehavior.translucent` and self-reject on multi-touch so pinch-to-zoom is uncontested. `EnhancedPostViewer` wires `onSwipeUp = expandSheet` and `onSwipeDown = Navigator.maybePop()` directly to those overlays.
* **Velocity threshold lowered to 250 px/s** (from 500) so a casual flick lands the gesture, matching the 2.0.8 intent. The elastic pull-to-dismiss visual from 2.0.5 is gone — gesture correctness took priority over the visual flair.
* **Architecture**: `_PostViewerPullToDismissShell` and `_PullToDismissDragRecognizer` are removed entirely. `flutter/foundation.dart` and `flutter/gestures.dart` imports also dropped (no longer used in the post viewer file).

## 2.0.11

* **Fix the "blinking pill" while a post image is loading**: 2.0.9 removed a `Shimmer` overlay from the in-app updater's download progress bar, which was a fine cleanup but did not match what users were actually seeing. The real culprit was the **post-image loading pill** in `_PostImageStatus` — its `AnimatedSwitcher` child carried a `ValueKey('loading-$loadPercent')` that incremented on every percent tick (`1% → 2% → 3% → …`). Each percent change triggered a fresh 200 ms cross-fade-in/out cycle on the pill, which combined with 5–10 progress events per second during a download produced the visible flicker. The switcher now keys only on load-state TYPE (`loading` / `completed` / `failed`), not on percent — the percent text and progress value update in place inside a stable `_PostImageLoadingPill` widget so the row no longer cross-fades during normal download.
* **No behavior change to completed / failed transitions**: those still cross-fade smoothly because their state-type key still changes.

## 2.0.10

* **CI now signs release APKs with a stable release keystore**: prior CI builds fell through to Flutter's default debug-style signing because no `key.properties` was provided. Each CI runner generated a different ad-hoc debug key, so two CI builds couldn't install on top of each other and an existing real-keystore install couldn't be upgraded by a CI build at all (Android refused with *"App not installed as package conflicts with an existing package"*). The `Build APK` workflow now reads four `ANDROID_*` GitHub Secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`), decodes the keystore into `android/app/release.jks`, and writes `android/key.properties` so the existing release `signingConfig` in `android/app/build.gradle` picks it up. Falls back to a CI warning + debug signing if any secret is missing, so old PRs / forks that don't have the secrets won't break.
* **`.gitignore` updated** to exclude `android/key.properties`, `android/app/release.jks`, and any other `*.jks` / `*.keystore` so the keystore can never accidentally be committed.
* **First install caveat**: because v1.x and v2.0.0–v2.0.9 weren't signed with this new keystore, the first v2.0.10+ install will require uninstalling the existing app once. From that install forward every CI build installs on top cleanly.

## 2.0.9

* **In-app updater progress bar no longer "blinks"**: the download progress UI on the About page used to overlay a `Shimmer`-driven sweep on top of the `LinearProgressIndicator` with a 700 ms period. The intent was a "loading" affordance on top of the determinate bar, but combined with the bar's own value-update repaints it read as a flicker / blink. The Shimmer is removed; the bar is now just the plain `LinearProgressIndicator(value: progress.progress.ratio)` clipped to a 16-px pill, which already conveys download progress unambiguously.
* **Percent text is now right-aligned in a fixed 48-px slot** so the digit count flipping `9% → 10% → 99% → 100%` no longer reflows the row width. Reduces the perceived "jitter" of the percentage label as the download proceeds.

## 2.0.8

* **Pull-to-dismiss thresholds retuned for casual gestures**: the route-level `_PostViewerPullToDismissShell` introduced in 2.0.5 was too conservative — it required either pulling 120 logical px down OR a release velocity above 500 px/s for either swipe-up (open details) or swipe-down (dismiss) to fire. In practice that meant a "normal" flick that an Instagram/Reddit-style app would land registered as nothing on Boorusphere, and the only way to dismiss a post via gesture was an aggressive whip. The dismiss-distance threshold drops from **120 → 80 logical px**, and the fling-velocity gate drops from **500 → 250 px/s**. Net effect: a moderate flick now opens details on swipe-up and dismisses on swipe-down, while the elastic snap-back on slower drags still preserves the "you can pull around without committing to dismiss" affordance.
* **No architectural change**: vertical drag is still owned exclusively by the route-level shell (no per-surface recognizers re-introduced), so the pinch-to-zoom multi-touch yield from 2.0.5 still holds. While zoomed past 1× the shell still suspends entirely so `InteractiveViewer`'s pan owns single-finger drag uncontested.

## 2.0.7

* **In-app update flow now shows the changelog inline**: when a newer version is detected and the user lands on the About page, the new version's CHANGELOG.md entry is now rendered directly above the Download button — no more "tap *View changelog* → push another route → tap back" round-trip. The inline changelog is sourced via `ChangelogType.git` (the same path the dedicated changelog page uses for "What's new in the upcoming version") so even pre-Release builds delivered to Telegram can show what they ship.
* **Compact card UI**: changelog rendered inside a `surfaceContainerHighest` card capped at 320 logical px tall, with vertical scroll when the entry is long. Reuses the existing `ChangelogDataView` widget so bullet styling stays consistent with the full-screen `ChangelogPage`.
* **Graceful network failure**: if the GitHub raw fetch fails or the version isn't found in the fetched markdown, the inline section silently collapses (no spinner stuck, no error notice) — the Download / Install button is unaffected so the user can still proceed with the update. Loading state shows a small `CircularProgressIndicator` while the fetch is in-flight.
* **Removed redundant "View changelog" button** from the updater stack since the changelog is now visible inline. Users who want the full multi-version history can still reach it via the existing "Changelog" `ListTile` further down on the About page.

## 2.0.6

* **Search history dedup + reorder-on-reuse**: searching the same term twice (e.g. "hololive" → switch posts → "hololive" again) used to silently no-op when the query already existed in history, leaving stale entries pinned wherever they originally landed. `UserSearchHistoryRepo.save()` now deletes any prior occurrences of the trimmed query (across all servers) before `add()`-ing the fresh entry, so the most recent search always rises to the top of the recent-searches list. The existing UI already iterates the Hive `Map<int, SearchHistory>` in descending key order (`historyList[length - 1 - index]`) — combined with Hive's auto-incrementing keys, the new entry wins the top slot automatically. The internal `isExists` helper is removed since it is no longer needed.

## 2.0.5

* **Pull-to-dismiss in the post viewer**: a slow downward drag on a post now elastically translates and shrinks the entire post viewer body (the details sheet stays pinned). On release, if the drag has accumulated past 120 logical px **OR** the release velocity exceeds 500 px/s downward, the route is popped; otherwise the body snaps back to origin via a 250 ms ease-out-cubic animation. Backdrop fades from solid black to ~40 % opacity over the first ~360 px so the dismiss feels distinct from a page-swipe.
* **Vertical-drag ownership consolidated to a single route-level shell**: every fast-fling-up (open details), fast-fling-down (dismiss), and slow-pull-down (elastic dismiss) gesture is now handled by `_PostViewerPullToDismissShell` directly. `PostImage` and `PostVideo` no longer mount per-post `_SinglePointerVerticalDragRecognizer`s — the per-image overlay only owns tap + double-tap, and the per-video overlay only owns tap-to-toggle-controls. This removes the gesture-arena ambiguity that two competing `VerticalDragGestureRecognizer`s would otherwise create. Pinch-to-zoom still wins multi-touch uncontested via the same multi-touch-rejection pattern.
* **Shell suspends while zoomed**: the shell consults `controller.canSwipeListenable` (the same listenable that swaps the `PageView`'s scroll physics on zoom) and unmounts its drag recognizer entirely while a post is zoomed past 1×. `InteractiveViewer`'s pan recognizer therefore wins single-finger drags uncontested while zoomed, with no risk of accidentally triggering pull-to-dismiss while the user is panning around a zoomed image.

## 2.0.4

* **Video posts: gesture parity with images + explicit details button**: `PostVideo` previously had no swipe wiring at all — `enhanced_post_viewer.dart` only passed a no-op `onToolboxVisibilityChange` callback, so single-finger swipe-up (open details) and swipe-down (dismiss) silently dropped on video posts even though they worked on photo / GIF posts. The video player now mounts a velocity-based `_PostVideoSwipeOverlay` (single-pointer, multi-touch-rejecting `VerticalDragGestureRecognizer` mirroring the `PostImage` recognizer) on top of the existing tap-to-toggle-controls `GestureDetector`. Tap and vertical-drag don't conflict in the gesture arena (tap fires on quick release without movement; drag fires on sufficient vertical motion), so toggling the video controls and swiping to dismiss / open details now work side-by-side. Threshold matches images (500 px/s).
* **Details button in `PostToolbox` and the video toolbox**: opening details was previously gated entirely on the swipe-up gesture, which is invisible to new users and was completely missing from the video path. Both toolboxes now render an `info_outline` `IconButton` (i18n `details`) on the leading edge of the action row when the parent passes `onShowDetails`. Wired in `enhanced_post_viewer.dart` to the same `expandSheet` closure that the swipe-up gesture invokes, so the two paths converge on the same `DraggableScrollableController.animateTo(0.5)` call.
* **CI: cache `~/.pub-cache` keyed on `pubspec.lock`** *(rolled in from the in-flight 2.0.3 cycle, no separate Release was cut)*: every `Analyze and test` and `Build APK` run was cold-downloading ~300 packages from pub.dev (~45 s overhead). Added `actions/cache@v4` between the Flutter setup step and `flutter pub get`. The cache key is `${{ runner.os }}-pub-${{ hashFiles('**/pubspec.lock') }}` with a soft `${{ runner.os }}-pub-` restore-key so PRs that touch `pubspec.lock` still get a partial restore. Subsequent `flutter pub get` and `dart pub global activate grinder` runs reuse the cached package archives without re-downloading.

## 2.0.3

* **CI: cache `~/.pub-cache` keyed on `pubspec.lock`**: every `Analyze and test` and `Build APK` run was cold-downloading ~300 packages from pub.dev (~45 s overhead). Added `actions/cache@v4` between the Flutter setup step and `flutter pub get`. The cache key is `${{ runner.os }}-pub-${{ hashFiles('**/pubspec.lock') }}` with a soft `${{ runner.os }}-pub-` restore-key so PRs that touch `pubspec.lock` still get a partial restore. Subsequent `flutter pub get` and `dart pub global activate grinder` runs reuse the cached package archives without re-downloading.

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
