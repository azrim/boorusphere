import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/booru/provider.dart';
import 'package:boorusphere/data/repository/booru/utils/booru_scanner.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
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
        return context.t.servers.addrError;
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
      final serverPod = ref.read(serverStateProvider.notifier);
      try {
        await serverPod.add(server.value);
      } on ServerAlreadyExistsException {
        if (!context.mounted) return;
        context.scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              context.t.servers.alreadyExists(name: server.value.name),
            ),
          ),
        );
        return;
      } catch (e, stack) {
        mainLog.e('Servers: failed to save ${server.value.key}', e, stack);
        if (!context.mounted) return;
        context.scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(context.t.error.unknown)),
        );
        return;
      }

      if (context.mounted) await context.router.maybePop();
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.t.servers.add)),
      body: SafeArea(
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
                      padding: const EdgeInsets.all(DesignTokens.spacingSm),
                      child: ValueListenableBuilder<bool>(
                        valueListenable: scanner.isScanning,
                        builder: (context, isScanning, _) {
                          final result = scanResult.value;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                context.t.servers.scanHint,
                                style: context.theme.textTheme.bodySmall
                                    ?.copyWith(
                                      color:
                                          context.colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: DesignTokens.spacingSm),
                              FilledButton.tonalIcon(
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
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: DesignTokens.spacingSm,
                                  ),
                                  child: ValueListenableBuilder<List<String>>(
                                    valueListenable: scanner.logs,
                                    builder: (context, logs, _) {
                                      if (logs.isEmpty) {
                                        return const SizedBox.shrink();
                                      }

                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: logs
                                            .map(
                                              (line) => Text(
                                                line,
                                                style: context
                                                    .theme
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      fontFamily: 'monospace',
                                                    ),
                                              ),
                                            )
                                            .toList(),
                                      );
                                    },
                                  ),
                                ),
                              ],
                              if (result != null) ...[
                                const SizedBox(height: DesignTokens.spacingMd),
                                Container(
                                  padding: const EdgeInsets.all(
                                    DesignTokens.spacingMd,
                                  ),
                                  decoration: BoxDecoration(
                                    color: context.colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(
                                      DesignTokens.radiusMd,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline,
                                        color: context
                                            .colorScheme
                                            .onPrimaryContainer,
                                      ),
                                      const SizedBox(
                                        width: DesignTokens.spacingSm,
                                      ),
                                      Expanded(
                                        child: Text(
                                          context.t.servers.scanResult(
                                            search:
                                                result.searchParserId.isEmpty
                                                ? context.t.auto
                                                : result.searchParserId,
                                            suggestion:
                                                result
                                                    .suggestionParserId
                                                    .isEmpty
                                                ? context.t.auto
                                                : result.suggestionParserId,
                                          ),
                                          style: context
                                              .theme
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: context
                                                    .colorScheme
                                                    .onPrimaryContainer,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (scanFailed.value) ...[
                                const SizedBox(height: DesignTokens.spacingMd),
                                Container(
                                  padding: const EdgeInsets.all(
                                    DesignTokens.spacingMd,
                                  ),
                                  decoration: BoxDecoration(
                                    color: context.colorScheme.errorContainer,
                                    borderRadius: BorderRadius.circular(
                                      DesignTokens.radiusMd,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: context
                                            .colorScheme
                                            .onErrorContainer,
                                      ),
                                      const SizedBox(
                                        width: DesignTokens.spacingSm,
                                      ),
                                      Expanded(
                                        child: Text(
                                          context.t.servers.scanFailed,
                                          style: context
                                              .theme
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: context
                                                    .colorScheme
                                                    .onErrorContainer,
                                              ),
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
                            style: context.theme.textTheme.bodySmall?.copyWith(
                              color: context.colorScheme.onSurfaceVariant,
                            ),
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
                          obscureText: true,
                          decoration: flatFieldDecoration(
                            context,
                            label: context.t.servers.credentials.apiKey,
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
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: DesignTokens.spacingMd,
                ),
                child: FilledButton(
                  onPressed: mode.value == _AddMode.manual
                      ? () {
                          if (formKey.currentState?.validate() != true) {
                            return;
                          }

                          updateServer();
                          submit();
                        }
                      : (scanResult.value == null ? null : submit),
                  child: Text(context.t.servers.add),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
