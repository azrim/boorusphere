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
import 'package:boorusphere/presentation/theme/app_typography.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/field_decoration.dart';
import 'package:boorusphere/presentation/widgets/row_subtitle.dart';
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
        'tags.json?search[name_matches]=*{tag-part}*&search[order]=count&limit={post-limit}',
    postUrl: 'posts/{post-id}',
  ),
  BooruEngine(
    name: 'Gelbooru',
    searchParserId: 'Gelbooru.json',
    suggestionParserId: 'Gelbooru.autocomplete',
    searchQuery:
        'index.php?page=dapi&s=post&q=index&tags={tags}&pid={page-id}&limit={post-limit}&json=1',
    suggestionQuery:
        'index.php?page=autocomplete2&term={tag-part}&type=tag_query&limit={post-limit}',
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
    suggestionQuery:
        'tags.json?search[name_matches]=*{tag-part}*&search[order]=count&limit={post-limit}',
    postUrl: 'posts/{post-id}',
  ),
  BooruEngine(
    name: 'Shimmie',
    searchParserId: 'Shimmie.xml',
    suggestionParserId: 'Shimmie.xml',
    searchQuery:
        'api/danbooru/find_posts/index.xml?tags={tags}&limit={post-limit}&page={page-num}',
    suggestionQuery: 'api/internal/autocomplete?s={tag-part}',
    postUrl: 'post/view/{post-id}',
  ),
  BooruEngine(
    name: 'Szurubooru',
    searchParserId: 'Szurubooru.json',
    suggestionParserId: 'Szurubooru.json',
    searchQuery:
        'api/posts?offset={post-offset}&limit={post-limit}&query={tags}',
    suggestionQuery: 'api/tags?offset=0&limit={tag-limit}&query=*{tag-part}*',
    postUrl: 'post/{post-id}',
  ),
  BooruEngine(
    name: 'BooruOnRails',
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
    /// answers nothing until the key is attached, so they ride along with the
    /// server used for scanning too.
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

    /// A previously detected engine is only valid for the name/homepage it was
    /// scanned from, so any edit there invalidates the result.
    void resetScan() {
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
      final name = profileName.text.trim();
      final url = siteUrl.text.trim();

      scanResult.value = null;
      scanFailed.value = false;

      final base = withCredentials(
        Server(
          id: name,
          homepage: url,
          apiAddr: useApiAddr.value ? apiAddr.text.trim() : '',
        ),
      );

      try {
        final scanned = await scanner.scan(base);
        // The page can be gone by the time a scan settles; its hooks are
        // disposed with it.
        if (!context.mounted) return;

        if (scanned.searchParserId.isEmpty) {
          scanFailed.value = true;
          return;
        }

        final result = withCredentials(
          scanned.copyWith(id: name, homepage: url),
        );
        server.value = result;
        scanResult.value = result;
      } catch (_) {
        if (!context.mounted) return;
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
          context.scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(
                context.t.servers.alreadyExists(name: server.value.name),
              ),
              duration: DesignTokens.durationSnackbar,
            ),
          );
          return;
        } catch (e, stack) {
          mainLog.e('Servers: failed to save ${server.value.key}', e, stack);
          if (!context.mounted) return;
          context.scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(context.t.error.unknown),
              duration: DesignTokens.durationSnackbar,
            ),
          );
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
                                      // A flat row inside the block rather than a
                                      // tinted card on top of it: the block owns
                                      // the only surface, and the icon carries the
                                      // outcome.
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal:
                                              DesignTokens.spacingCardInset,
                                          vertical: DesignTokens.spacingSm,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Icon(
                                              Icons.check_circle_outline,
                                              size: DesignTokens.iconInline,
                                              color:
                                                  context.colorScheme.primary,
                                            ),
                                            const SizedBox(
                                              width: DesignTokens.spacingSm,
                                            ),
                                            Expanded(
                                              child: Text(
                                                context.t.servers.scanResult(
                                                  search:
                                                      result
                                                          .searchParserId
                                                          .isEmpty
                                                      ? context.t.auto
                                                      : result.searchParserId,
                                                  suggestion:
                                                      result
                                                          .suggestionParserId
                                                          .isEmpty
                                                      ? context.t.auto
                                                      : result
                                                            .suggestionParserId,
                                                ),
                                                style: AppTextRoles.of(
                                                  context,
                                                ).rowSupporting,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    if (scanFailed.value) ...[
                                      const SizedBox(
                                        height: DesignTokens.spacingMd,
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal:
                                              DesignTokens.spacingCardInset,
                                          vertical: DesignTokens.spacingSm,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Icon(
                                              Icons.error_outline,
                                              size: DesignTokens.iconInline,
                                              color: context.colorScheme.error,
                                            ),
                                            const SizedBox(
                                              width: DesignTokens.spacingSm,
                                            ),
                                            Expanded(
                                              child: Text(
                                                context.t.servers.scanFailed,
                                                style: AppTextRoles.of(
                                                  context,
                                                ).rowSupporting,
                                              ),
                                            ),
                                          ],
                                        ),
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
                              CheckboxListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: DesignTokens.spacingCardInset,
                                ),
                                value: useApiAddr.value,
                                title: Text(context.t.servers.useCustomApi),
                                subtitle: RowSubtitle(
                                  Text(context.t.servers.useCustomApiDesc),
                                ),
                                onChanged: (isChecked) {
                                  if (isChecked != null) {
                                    useApiAddr.value = isChecked;
                                    updateServer();
                                  }
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
                                  onChanged: (_) => updateServer(),
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
    final style = context.theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      color: scheme.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.only(top: DesignTokens.spacingSm),
      child: Container(
        height: DesignTokens.controlHeightMin * 2,
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingCardInset,
          vertical: DesignTokens.spacingSm,
        ),
        decoration: BoxDecoration(
          // A well rather than a card: darker than the block it sits in, so
          // the text reads as an inset readout.
          color: scheme.surfaceContainerLow,
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
                style: style,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
