import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/booru/provider.dart';
import 'package:boorusphere/data/repository/booru/utils/booru_scanner.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/theme/app_surfaces.dart';
import 'package:boorusphere/presentation/theme/app_typography.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/app_toast.dart';
import 'package:boorusphere/presentation/widgets/block_checkbox_tile.dart';
import 'package:boorusphere/presentation/widgets/field_decoration.dart';
import 'package:boorusphere/presentation/widgets/section_label.dart';
import 'package:boorusphere/presentation/widgets/section_surface.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// How a new server is configured: let [BooruScanner] detect the engine from
/// the homepage, or pick a [BooruEngine] manually.
enum _AddMode { scan, manual }

/// Represents a booru engine type that users can select
///
/// An engine is a dialect, so the list carries no credentials page: the address
/// that hands out an API key belongs to the site, not to the dialect. The named
/// presets in `assets/servers.json` carry it, and a server added from here does
/// not, rather than pointing at some other site's account page.
class BooruEngine {
  const BooruEngine({
    required this.name,
    required this.searchParserId,
    required this.suggestionParserId,
    required this.searchQuery,
    required this.suggestionQuery,
    required this.postUrl,
  });

  final String name;
  final String searchParserId;
  final String suggestionParserId;
  final String searchQuery;
  final String suggestionQuery;
  final String postUrl;
}

/// Available booru engine types
const booruEngines = <BooruEngine>[
  BooruEngine(
    name: 'Danbooru',
    searchParserId: 'Danbooru.json',
    suggestionParserId: 'Danbooru.json',
    searchQuery: 'posts.json?tags={tags}&page={page-num}&limit={post-limit}',
    suggestionQuery:
        'autocomplete.json?search[query]={tag-part}&search[type]=tag_query'
        '&limit={post-limit}',
    postUrl: 'posts/{post-id}',
  ),

  /// One name, two dialects: the site itself answers `dapi` as a JSON envelope
  /// and has a completion endpoint built for the tag box, while the boards still
  /// running the revision before it answer the same calls as XML — and answer
  /// `autocomplete2` with an HTML page. Picking the wrong row there means a tag
  /// box that never fills on a server whose posts read fine, so the list says
  /// which revision each entry serves.
  BooruEngine(
    name: 'Gelbooru (0.2)',
    searchParserId: 'Gelbooru.json',
    suggestionParserId: 'Gelbooru.autocomplete',
    searchQuery:
        'index.php?page=dapi&s=post&q=index&tags={tags}&pid={page-id}&limit={post-limit}&json=1',
    suggestionQuery:
        'index.php?page=autocomplete2&term={tag-part}&type=tag_query&limit={post-limit}',
    postUrl: 'index.php?page=post&s=view&id={post-id}',
  ),
  BooruEngine(
    name: 'Gelbooru (0.1.x)',
    // The boards of the older revision — the booru.org family, which this app's
    // own Safebooru entry belongs to — answer the same `dapi` calls with the
    // attributes on the entry element rather than inside it, and `Safebooru.xml`
    // is the reader written for that spelling. `json=1` there returns a bare
    // array with no `post` envelope, so the 0.2 reader claims nothing.
    searchParserId: 'Safebooru.xml',
    // They do answer the XML tag endpoint, but it sorts its whole tag table for
    // every keystroke; `autocomplete.php` is on the same host, built for the
    // fragment being typed, and is the shape the generic reader takes.
    suggestionParserId: 'Autocomplete.json',
    searchQuery:
        'index.php?page=dapi&s=post&q=index&tags={tags}&pid={page-id}&limit={post-limit}',
    suggestionQuery: 'autocomplete.php?q={tag-part}',
    postUrl: 'index.php?page=post&s=view&id={post-id}',
  ),
  BooruEngine(
    name: 'Moebooru',
    searchParserId: 'Moebooru.json',
    suggestionParserId: 'Moebooru.json',
    searchQuery: 'post.json?tags={tags}&page={page-num}&limit={post-limit}',
    suggestionQuery:
        'tag.json?name=*{tag-part}*&order=count&limit={post-limit}',
    postUrl: 'post/show/{post-id}',
  ),
  BooruEngine(
    name: 'E621',
    searchParserId: 'E621.json',
    suggestionParserId: 'E621.json',
    searchQuery: 'posts.json?tags={tags}&page={page-num}&limit={post-limit}',
    suggestionQuery: 'tags/autocomplete.json?search[name_matches]={tag-part}',
    postUrl: 'posts/{post-id}',
  ),
  BooruEngine(
    name: 'Shimmie',
    searchParserId: 'Shimmie.xml',
    suggestionParserId: 'Shimmie.xml',
    searchQuery:
        'api/danbooru/find_posts?tags={tags}&limit={post-limit}&page={page-num}',
    suggestionQuery: 'api/internal/autocomplete?s={tag-part}',
    postUrl: 'post/view/{post-id}',
  ),
  BooruEngine(
    name: 'Szurubooru',
    searchParserId: 'Szurubooru.json',
    suggestionParserId: 'Szurubooru.json',
    searchQuery:
        'api/posts?offset={post-offset}&limit={post-limit}&query={tags}',
    suggestionQuery: 'api/tags?offset=0&limit={post-limit}&query={tag-part}*',
    postUrl: 'post/{post-id}',
  ),

  /// The boards a user types here are Derpibooru and Ponybooru, and the
  /// software they run is called Philomena. `BooruOnRails` is what this app
  /// first called it, from the shape of the URL rather than the name of
  /// anything: the id a saved server carries is still that one, because rows
  /// already in the box point at it, while the label being chosen is what the
  /// reader can check against the site they came to add.
  BooruEngine(
    name: 'Philomena',
    searchParserId: 'BooruOnRails.json',
    suggestionParserId: 'BooruOnRails.json',
    searchQuery:
        'api/v1/json/search/images?q={tags}&page={page-num}&per_page={post-limit}',
    suggestionQuery: 'api/v1/json/search/tags?q=*{tag-part}*',
    postUrl: 'images/{post-id}',
  ),
];

@RoutePage()
class ServerAddPage extends HookConsumerWidget {
  const ServerAddPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formKey = useMemoized(GlobalKey<FormState>.new);
    final imeIncognito = ref.watch(
      uiSettingStateProvider.select((it) => it.imeIncognito),
    );
    final mode = useState(_AddMode.scan);
    final selectedEngine = useState<BooruEngine?>(null);
    final profileName = useTextEditingController();
    final siteUrl = useTextEditingController(text: 'https://');
    final useApiAddr = useState(false);
    final apiAddr = useTextEditingController(text: 'https://');
    final login = useTextEditingController();
    final apiKey = useTextEditingController();
    final profileNameFocus = useFocusNode();
    final siteUrlFocus = useFocusNode();
    final apiAddrFocus = useFocusNode();
    final showApiKey = useState(false);
    final isSubmitting = useState(false);
    final server = useState(Server.empty);
    // Result of the last successful scan, or null when a (re)scan is needed.
    final scanResult = useState<Server?>(null);
    final scanFailed = useState(false);
    // Which form the scan in flight is answering, raised by every edit to an
    // input the probe reads. A result whose revision is no longer current is
    // dropped rather than published.
    final scanRevision = useState(0);
    final scanner = useBooruScanner(
      ref.watch(dioProvider),
      ref.watch(booruParsersProvider),
    );

    bool isPrivateIp(String host) {
      if (host == '::1') return true;
      if (host == 'localhost') return true;
      final addr = host.replaceAll(RegExp(r'[\[\]]'), '');
      final parts = addr.split('.');
      if (parts.length != 4) return false;
      final first = int.tryParse(parts[0]);
      final second = parts.length > 1 ? int.tryParse(parts[1]) : null;
      if (first == null) return false;
      if (first == 10) return true;
      if (first == 127) return true;
      if (first == 0) return true;
      if (first == 172 && second != null && second >= 16 && second <= 31) {
        return true;
      }
      if (first == 192 && second == 168) return true;
      return false;
    }

    validateAddress(String? value) {
      if (value == null || value.trim().isEmpty) {
        return context.t.servers.addrError;
      }
      if (!value.contains(RegExp(r'https?://.+\..+'))) {
        return context.t.servers.addrError;
      }
      final uri = Uri.tryParse(value);
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
        return context.t.servers.addrError;
      }
      if (uri.userInfo.isNotEmpty) {
        return context.t.servers.addrError;
      }
      if (isPrivateIp(uri.host)) {
        return context.t.servers.addrLocal;
      }
      return null;
    }

    validateName(String? value) {
      if (value == null || value.trim().isEmpty) {
        return context.t.servers.nameError;
      }
      return null;
    }

    /// Credentials are part of the request itself: a booru that gates its API
    /// answers nothing until the key is attached. Manual mode rebuilds the whole
    /// server from the live fields on every edit, so the pair rides along with
    /// it; the scan path takes them from its own snapshot instead.
    Server withCredentials(Server value) {
      return value.copyWith(
        login: login.text.trim(),
        apiKey: apiKey.text.trim(),
      );
    }

    void updateServer() {
      final engine = selectedEngine.value;
      if (engine == null) return;

      server.value = withCredentials(
        Server(
          id: profileName.text.trim(),
          homepage: siteUrl.text.trim(),
          apiAddr: useApiAddr.value ? apiAddr.text.trim() : '',
          searchUrl: engine.searchQuery,
          tagSuggestionUrl: engine.suggestionQuery,
          postUrl: engine.postUrl,
          searchParserId: engine.searchParserId,
          suggestionParserId: engine.suggestionParserId,
        ),
      );
    }

    /// A previously detected engine is only valid for the inputs it was
    /// scanned from, so any edit there invalidates the result — and the
    /// revision the scan in flight was published under, which is what drops
    /// its answer when it settles.
    void resetScan() {
      scanRevision.value = scanRevision.value + 1;
      if (scanResult.value != null || scanFailed.value) {
        scanResult.value = null;
        scanFailed.value = false;
      }
    }

    Future<void> onScan() async {
      if (formKey.currentState?.validate() != true) {
        return;
      }

      FocusScope.of(context).unfocus();

      // Every input the probe reads is captured here, once. The fields stay
      // editable while the scan runs, so an answer can settle for a form the
      // reader has already changed — and publishing it would attach the
      // account typed now to the host the scan asked about, then send that key
      // there with the first request.
      final name = profileName.text.trim();
      final url = siteUrl.text.trim();
      final base = Server(
        id: name,
        homepage: url,
        apiAddr: useApiAddr.value ? apiAddr.text.trim() : '',
        login: login.text.trim(),
        apiKey: apiKey.text.trim(),
      );
      final revision = scanRevision.value + 1;
      scanRevision.value = revision;
      scanResult.value = null;
      scanFailed.value = false;

      try {
        final scanned = await scanner.scan(base);
        // The page can be gone by the time a scan settles; its hooks are
        // disposed with it.
        if (!context.mounted) return;
        // Still alive is not the same as still asking: the form moved while the
        // probe was out, so this result describes another server.
        if (scanRevision.value != revision) return;

        if (scanned.searchParserId.isEmpty) {
          scanFailed.value = true;
          return;
        }

        // The scanned server carries the credentials the snapshot gave the
        // probe; they are never re-read from the live fields here.
        final result = scanned.copyWith(id: name, homepage: url);
        server.value = result;
        scanResult.value = result;
      } catch (_) {
        if (!context.mounted) return;
        // A cancellation the reader asked for by editing the form is not a
        // failed scan, and the result it would have written is already dropped.
        if (scanRevision.value != revision) return;
        scanFailed.value = true;
      }
    }

    /// Saves the server and leaves the page.
    ///
    /// A name that resolves to an existing key is refused: saving it would
    /// replace that server's configuration, credentials included.
    Future<void> submit() async {
      if (isSubmitting.value) return;
      isSubmitting.value = true;
      try {
        final serverPod = ref.read(serverStateProvider.notifier);
        final lastActiveId = ref.read(serverSettingStateProvider).lastActiveId;
        final hadActiveServer = ref
            .read(serverStateProvider)
            .any((it) => it.id == lastActiveId);
        try {
          await serverPod.add(server.value);
        } on ServerAlreadyExistsException {
          if (!context.mounted) return;
          showToast(
            context,
            context.t.servers.alreadyExists(name: server.value.name),
          );
          return;
        } catch (e, stack) {
          mainLog.e('Servers: failed to save ${server.value.key}', e, stack);
          if (!context.mounted) return;
          showToast(context, context.t.error.unknown);
          return;
        }

        if (!context.mounted) return;

        // A server saved while the session has none (a boot that could not open
        // the server box) is the only one the timeline behind this page could
        // show. Opening its timeline here saves a manual switch through the
        // drawer, which is the state the page would otherwise stay in.
        if (!hadActiveServer) {
          await context.router.replaceAll([
            HomeRoute(session: SearchSession(serverId: server.value.id)),
          ]);
          return;
        }

        await context.router.maybePop();
      } finally {
        if (context.mounted) isSubmitting.value = false;
      }
    }

    void focusFirstInvalid() {
      final target = validateName(profileName.text) != null
          ? profileNameFocus
          : validateAddress(siteUrl.text) != null
          ? siteUrlFocus
          : apiAddrFocus;
      target.requestFocus();
      final targetContext = target.context;
      if (targetContext != null) {
        unawaited(
          Scrollable.ensureVisible(
            targetContext,
            duration: context.motionDuration(DesignTokens.durationNormal),
            curve: DesignTokens.curveStandard,
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.t.servers.add)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Form(
                key: formKey,
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spacingMd,
                  ),
                  children: [
                    const SizedBox(height: DesignTokens.spacingMd),
                    SectionSurface(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(DesignTokens.spacingSm),
                          child: SegmentedButton<_AddMode>(
                            // The mode switch is a control, so the chosen mode takes
                            // the same primary fill the page's own button takes
                            // instead of the neutral tonal default.
                            style: SegmentedButton.styleFrom(
                              selectedBackgroundColor:
                                  context.colorScheme.primary,
                              selectedForegroundColor:
                                  context.colorScheme.onPrimary,
                              foregroundColor:
                                  context.colorScheme.onSurfaceVariant,
                              side: BorderSide(
                                color: context.colorScheme.outlineVariant,
                              ),
                            ),
                            segments: [
                              ButtonSegment(
                                value: _AddMode.scan,
                                icon: const Icon(Icons.radar),
                                label: Text(context.t.servers.mode.scan),
                              ),
                              ButtonSegment(
                                value: _AddMode.manual,
                                icon: const Icon(Icons.tune),
                                label: Text(context.t.servers.mode.manual),
                              ),
                            ],
                            selected: {mode.value},
                            onSelectionChanged: (selection) {
                              mode.value = selection.first;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: DesignTokens.spacingSm),
                    if (mode.value == _AddMode.scan)
                      SectionSurface(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(
                              DesignTokens.spacingSm,
                            ),
                            child: ValueListenableBuilder<bool>(
                              valueListenable: scanner.isScanning,
                              builder: (context, isScanning, _) {
                                final result = scanResult.value;
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      context.t.servers.scanHint,
                                      style: AppTextRoles.of(
                                        context,
                                      ).rowSupporting,
                                    ),
                                    const SizedBox(
                                      height: DesignTokens.spacingSm,
                                    ),
                                    FilledButton.icon(
                                      onPressed: isScanning ? null : onScan,
                                      icon: const Icon(Icons.search),
                                      label: Text(
                                        isScanning
                                            ? context.t.servers.scanning
                                            : context.t.scan,
                                      ),
                                    ),
                                    if (isScanning) ...[
                                      const Padding(
                                        padding: EdgeInsets.only(
                                          top: DesignTokens.spacingMd,
                                        ),
                                        child: LinearProgressIndicator(),
                                      ),
                                      _ScanLog(scanner: scanner),
                                    ],
                                    if (result != null) ...[
                                      const SizedBox(
                                        height: DesignTokens.spacingMd,
                                      ),
                                      _ScanNotice(
                                        icon: Icons.check_circle_outline,
                                        color: context.colorScheme.primary,
                                        message: context.t.servers.scanResult(
                                          search: result.searchParserId.isEmpty
                                              ? context.t.auto
                                              : result.searchParserId,
                                          suggestion:
                                              result.suggestionParserId.isEmpty
                                              ? context.t.auto
                                              : result.suggestionParserId,
                                        ),
                                      ),
                                    ],
                                    if (scanFailed.value) ...[
                                      const SizedBox(
                                        height: DesignTokens.spacingMd,
                                      ),
                                      _ScanNotice(
                                        icon: Icons.error_outline,
                                        color: context.colorScheme.error,
                                        message: context.t.servers.scanFailed,
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    SectionHeading(context.t.servers.title),
                    SectionSurface(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(DesignTokens.spacingSm),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (mode.value == _AddMode.manual) ...[
                                DropdownButtonFormField<BooruEngine>(
                                  decoration: flatFieldDecoration(
                                    context,
                                    label: context.t.servers.engineType,
                                  ),
                                  items: booruEngines.map((engine) {
                                    return DropdownMenuItem(
                                      value: engine,
                                      child: Text(engine.name),
                                    );
                                  }).toList(),
                                  onChanged: (engine) {
                                    selectedEngine.value = engine;
                                    updateServer();
                                  },
                                  validator: (value) {
                                    if (value == null) {
                                      return context.t.servers.engineRequired;
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: DesignTokens.spacingSm),
                              ],
                              TextFormField(
                                controller: profileName,
                                focusNode: profileNameFocus,
                                enableIMEPersonalizedLearning: !imeIncognito,
                                decoration: flatFieldDecoration(
                                  context,
                                  label: context.t.servers.profileName,
                                  hint: context.t.servers.profileNameHint,
                                ),
                                validator: validateName,
                                onChanged: (_) {
                                  resetScan();
                                  updateServer();
                                },
                              ),
                              const SizedBox(height: DesignTokens.spacingSm),
                              TextFormField(
                                controller: siteUrl,
                                focusNode: siteUrlFocus,
                                keyboardType: TextInputType.url,
                                autocorrect: false,
                                enableIMEPersonalizedLearning: !imeIncognito,
                                decoration: flatFieldDecoration(
                                  context,
                                  label: context.t.servers.homepage,
                                  hint: context.t.servers.homepageHint,
                                ),
                                validator: validateAddress,
                                onChanged: (_) {
                                  resetScan();
                                  updateServer();
                                },
                              ),
                              const SizedBox(height: DesignTokens.spacingSm),
                              // The same opt-in as the editor's, in the one
                              // row shape: its tick now lines up with the field
                              // above it instead of stepping in another 12 dp.
                              BlockCheckboxTile(
                                value: useApiAddr.value,
                                title: context.t.servers.useCustomApi,
                                subtitle: context.t.servers.useCustomApiDesc,
                                onChanged: (isChecked) {
                                  // Which address the scan probed is decided
                                  // here, so the result it wrote belongs to the
                                  // opt-in as it was when the scan ran.
                                  useApiAddr.value = isChecked;
                                  resetScan();
                                  updateServer();
                                },
                              ),
                              if (useApiAddr.value) ...[
                                const SizedBox(height: DesignTokens.spacingSm),
                                TextFormField(
                                  controller: apiAddr,
                                  focusNode: apiAddrFocus,
                                  keyboardType: TextInputType.url,
                                  autocorrect: false,
                                  enableIMEPersonalizedLearning: !imeIncognito,
                                  decoration: flatFieldDecoration(
                                    context,
                                    label: context.t.servers.apiAddr,
                                    hint: context.t.servers.apiAddrHint,
                                  ),
                                  validator: validateAddress,
                                  onChanged: (_) {
                                    // Same as the opt-in above: this address is
                                    // where the engine was looked for, so a new
                                    // one asks for a scan of its own.
                                    resetScan();
                                    updateServer();
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    SectionHeading(context.t.servers.credentials.title),
                    SectionSurface(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(DesignTokens.spacingSm),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: DesignTokens.spacingCardInset,
                                  vertical: DesignTokens.spacingXs,
                                ),
                                child: Text(
                                  context.t.servers.credentials.desc,
                                  style: AppTextRoles.of(context).rowSupporting,
                                ),
                              ),
                              const SizedBox(height: DesignTokens.spacingSm),
                              TextFormField(
                                controller: login,
                                enableIMEPersonalizedLearning: !imeIncognito,
                                decoration: flatFieldDecoration(
                                  context,
                                  label: context.t.servers.credentials.login,
                                ),
                                onChanged: (_) {
                                  resetScan();
                                  updateServer();
                                },
                              ),
                              const SizedBox(height: DesignTokens.spacingSm),
                              TextFormField(
                                controller: apiKey,
                                enableIMEPersonalizedLearning: !imeIncognito,
                                obscureText: !showApiKey.value,
                                decoration:
                                    flatFieldDecoration(
                                      context,
                                      label:
                                          context.t.servers.credentials.apiKey,
                                    ).copyWith(
                                      suffixIcon: IconButton(
                                        tooltip: showApiKey.value
                                            ? context.t.hidePassword
                                            : context.t.showPassword,
                                        icon: Icon(
                                          showApiKey.value
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                        ),
                                        onPressed: () {
                                          showApiKey.value = !showApiKey.value;
                                        },
                                      ),
                                    ),
                                onChanged: (_) {
                                  resetScan();
                                  updateServer();
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: DesignTokens.spacingMd),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(DesignTokens.spacingMd),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isSubmitting.value
                      ? null
                      : mode.value == _AddMode.manual
                      ? () {
                          if (formKey.currentState?.validate() != true) {
                            focusFirstInvalid();
                            return;
                          }

                          updateServer();
                          submit();
                        }
                      : (scanResult.value == null ? null : submit),
                  child: isSubmitting.value
                      ? const SizedBox(
                          width: DesignTokens.iconAction,
                          height: DesignTokens.iconAction,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.t.servers.add),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One outcome line inside the scan block.
///
/// Success and failure are the same row with a different glyph, tone and
/// message, so they share one build and cannot drift apart. A flat row rather
/// than a tinted card on top of the block: the block owns the only surface,
/// and the icon carries the outcome.
class _ScanNotice extends StatelessWidget {
  const _ScanNotice({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingCardInset,
        vertical: DesignTokens.spacingSm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: DesignTokens.iconInline, color: color),
          const SizedBox(width: DesignTokens.spacingSm),
          Expanded(
            child: Text(message, style: AppTextRoles.of(context).rowSupporting),
          ),
        ],
      ),
    );
  }
}

/// The scanner's running log, in a box of its own.
///
/// The box keeps its height while the scan runs and the lines scroll inside
/// it, so the form below stays still instead of jumping with every line.
class _ScanLog extends StatefulWidget {
  const _ScanLog({required this.scanner});

  final BooruScanner scanner;

  @override
  State<_ScanLog> createState() => _ScanLogState();
}

class _ScanLogState extends State<_ScanLog> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.scanner.logs.addListener(_follow);
  }

  @override
  void dispose() {
    widget.scanner.logs.removeListener(_follow);
    _controller.dispose();
    super.dispose();
  }

  /// Keeps the newest line in view. The log is a stream of facts rather than a
  /// transition, so it jumps instead of animating.
  void _follow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.jumpTo(_controller.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    // The well reads as inset through the tone below the block it sits in.
    // Midnight has no below: the page is already black, so there the hairline
    // alone does the separating, as every other flat surface does.
    final flat = AppSurfacePolicy.of(context).flat;

    return Padding(
      padding: const EdgeInsets.only(top: DesignTokens.spacingSm),
      child: Container(
        height: DesignTokens.controlHeightMin * 2,
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingCardInset,
          vertical: DesignTokens.spacingSm,
        ),
        decoration: BoxDecoration(
          color: flat ? scheme.surface : scheme.surfaceContainerLow,
          border: flat ? Border.all(color: scheme.outlineVariant) : null,
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        ),
        child: ValueListenableBuilder<List<String>>(
          valueListenable: widget.scanner.logs,
          builder: (context, logs, _) => Scrollbar(
            controller: _controller,
            child: ListView.builder(
              controller: _controller,
              padding: EdgeInsets.zero,
              itemCount: logs.length,
              itemBuilder: (context, index) => Text(
                logs[index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextRoles.of(context).rowSupporting,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
