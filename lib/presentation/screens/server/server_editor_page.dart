import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/screens/server/server_add_page.dart';
import 'package:boorusphere/presentation/screens/server/server_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

@RoutePage()
class ServerEditorPage extends StatelessWidget {
  const ServerEditorPage({super.key, this.server = Server.empty});

  final Server server;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          server != Server.empty
              ? context.t.servers.edit(name: server.name)
              : context.t.servers.add,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: _ServerEditor(server: server),
        ),
      ),
    );
  }
}

class _ServerEditor extends HookConsumerWidget {
  const _ServerEditor({Server server = Server.empty}) : _server = server;

  final Server _server;

  bool get isEditing => _server != Server.empty;

  BooruEngine? _detectEngine(Server server) {
    for (final engine in booruEngines) {
      if (server.searchParserId == engine.searchParserId &&
          server.suggestionParserId == engine.suggestionParserId) {
        return engine;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formKey = useMemoized(GlobalKey<FormState>.new);
    final imeIncognito =
        ref.watch(uiSettingStateProvider.select((it) => it.imeIncognito));
    final server = useState(_server);
    final useApiAddr = useState(_server.apiAddr.isNotEmpty);
    final homepage = useTextEditingController(
        text: isEditing ? _server.homepage : 'https://');
    final apiAddr = useTextEditingController(
        text: _server.apiAddr.isEmpty ? 'https://' : _server.apiAddr);
    final selectedEngine = useState<BooruEngine?>(_detectEngine(_server));

    validateAddress(String? value) {
      if (value?.contains(RegExp(r'https?://.+\..+')) == false) {
        return context.t.servers.addrError;
      }

      return null;
    }

    void updateServerFromEngine(BooruEngine? engine) {
      if (engine == null) return;

      server.value = server.value.copyWith(
        searchUrl: engine.searchQuery,
        tagSuggestionUrl: engine.suggestionQuery,
        postUrl: engine.postUrl,
        searchParserId: engine.searchParserId,
        suggestionParserId: engine.suggestionParserId,
      );
    }

    return Column(
      children: [
        Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: DropdownButtonFormField<BooruEngine>(
                  initialValue: selectedEngine.value,
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
                    updateServerFromEngine(engine);
                  },
                  validator: (value) {
                    if (value == null) {
                      return context.t.servers.engineRequired;
                    }
                    return null;
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16),
                child: TextFormField(
                  controller: homepage,
                  enableIMEPersonalizedLearning: !imeIncognito,
                  decoration: InputDecoration(
                    border: const UnderlineInputBorder(),
                    labelText: context.t.servers.homepageHint,
                  ),
                  validator: validateAddress,
                ),
              ),
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
                      border: const UnderlineInputBorder(),
                      labelText: context.t.servers.apiAddrHint,
                    ),
                    validator: validateAddress,
                  ),
                ),
            ],
          ),
        ),
        ServerDetails(
          server: server.value,
          isEditing: isEditing,
          onSubmitted: (newServer) {
            final serverPod = ref.read(serverStateProvider.notifier);
            newServer = newServer.copyWith(
              homepage: homepage.text,
              apiAddr: useApiAddr.value ? apiAddr.text : '',
            );

            if (isEditing) {
              serverPod.edit(_server, newServer);
            } else {
              serverPod.add(newServer);
            }

            context.router.maybePop();
          },
        ),
      ],
    );
  }
}
