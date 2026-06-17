import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
    searchQuery: 'posts.json?tags={tags}&page={page-id}&limit={post-limit}',
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
    searchQuery: 'post.json?tags={tags}&page={page-id}&limit={post-limit}',
    suggestionQuery:
        'tag.json?name=*{tag-part}*&order=count&limit={post-limit}',
    postUrl: 'post/show/{post-id}',
  ),
  BooruEngine(
    name: 'E621',
    searchParserId: 'E621.json',
    suggestionParserId: 'E621.json',
    searchQuery: 'posts.json?tags={tags}&page={page-id}&limit={post-limit}',
    suggestionQuery:
        'tags.json?search[name_matches]=*{tag-part}*&search[order]=count&limit={post-limit}',
    postUrl: 'posts/{post-id}',
  ),
  BooruEngine(
    name: 'Shimmie',
    searchParserId: 'Shimmie.xml',
    suggestionParserId: 'Shimmie.xml',
    searchQuery:
        'api/danbooru/find_posts/index.xml?tags={tags}&limit={post-limit}&page={page-id}',
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
        'api/v1/json/search/images?q={tags}&page={page-id}&per_page={post-limit}',
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
    final selectedEngine = useState<BooruEngine?>(null);
    final profileName = useTextEditingController();
    final siteUrl = useTextEditingController(text: 'https://');
    final useApiAddr = useState(false);
    final apiAddr = useTextEditingController(text: 'https://');
    final server = useState(Server.empty);

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
      if (first == 172 && second != null && second >= 16 && second <= 31) return true;
      if (first == 192 && second == 168) return true;
      return false;
    }

    validateAddress(String? value) {
      if (value?.contains(RegExp(r'https?://.+\..+')) == false) {
        return context.t.servers.addrError;
      }
      final uri = Uri.tryParse(value!);
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

    void updateServer() {
      final engine = selectedEngine.value;
      if (engine == null) return;

      server.value = Server(
        id: profileName.text.trim(),
        homepage: siteUrl.text.trim(),
        apiAddr: useApiAddr.value ? apiAddr.text.trim() : '',
        searchUrl: engine.searchQuery,
        tagSuggestionUrl: engine.suggestionQuery,
        postUrl: engine.postUrl,
        searchParserId: engine.searchParserId,
        suggestionParserId: engine.suggestionParserId,
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.t.servers.add)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Engine selector
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: DropdownButtonFormField<BooruEngine>(
                    decoration: InputDecoration(
                      labelText: context.t.servers.engineType,
                      border: const OutlineInputBorder(),
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
                ),

                // Profile name
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextFormField(
                    controller: profileName,
                    enableIMEPersonalizedLearning: !imeIncognito,
                    decoration: InputDecoration(
                      labelText: context.t.servers.profileName,
                      border: const OutlineInputBorder(),
                    ),
                    validator: validateName,
                    onChanged: (_) => updateServer(),
                  ),
                ),

                const SizedBox(height: 16),

                // Site URL
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextFormField(
                    controller: siteUrl,
                    enableIMEPersonalizedLearning: !imeIncognito,
                    decoration: InputDecoration(
                      labelText: context.t.servers.homepageHint,
                      border: const OutlineInputBorder(),
                    ),
                    validator: validateAddress,
                    onChanged: (_) => updateServer(),
                  ),
                ),

                // Custom API address
                CheckboxListTile(
                  value: useApiAddr.value,
                  title: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(context.t.servers.useCustomApi),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(context.t.servers.useCustomApiDesc),
                  ),
                  onChanged: (isChecked) {
                    if (isChecked != null) {
                      useApiAddr.value = isChecked;
                      updateServer();
                    }
                  },
                ),

                if (useApiAddr.value)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: TextFormField(
                      controller: apiAddr,
                      enableIMEPersonalizedLearning: !imeIncognito,
                      decoration: InputDecoration(
                        labelText: context.t.servers.apiAddrHint,
                        border: const OutlineInputBorder(),
                      ),
                      validator: validateAddress,
                      onChanged: (_) => updateServer(),
                    ),
                  ),

                const Divider(),

                // Add button
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: () {
                      if (formKey.currentState?.validate() != true) {
                        return;
                      }

                      updateServer();
                      final serverPod = ref.read(serverStateProvider.notifier);
                      serverPod.add(server.value);
                      context.router.maybePop();
                    },
                    child: Text(context.t.servers.add),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
