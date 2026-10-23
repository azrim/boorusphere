import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/screens/server/server_add_page.dart';
import 'package:boorusphere/presentation/screens/server/server_details.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/widgets/filled_field.dart';
import 'package:boorusphere/presentation/widgets/section_label.dart';
import 'package:boorusphere/presentation/widgets/section_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

@RoutePage()
class ServerEditorPage extends StatelessWidget {
  const ServerEditorPage({super.key, required this.server});

  final Server server;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t.servers.edit(name: server.name))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: DesignTokens.spacingLg),
          child: _ServerEditor(server: server),
        ),
      ),
    );
  }
}

class _ServerEditor extends HookConsumerWidget {
  const _ServerEditor({required this.server});

  final Server server;

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
    final imeIncognito = ref.watch(
      uiSettingStateProvider.select((it) => it.imeIncognito),
    );
    final current = useState(server);
    final useApiAddr = useState(server.apiAddr.isNotEmpty);
    final homepage = useTextEditingController(text: server.homepage);
    final alias = useTextEditingController(
      text: server.alias.isEmpty ? server.id : server.alias,
    );
    final apiAddr = useTextEditingController(
      text: server.apiAddr.isEmpty ? 'https://' : server.apiAddr,
    );
    final selectedEngine = useState<BooruEngine?>(_detectEngine(server));

    validateAddress(String? value) {
      if (value?.contains(RegExp(r'https?://.+\..+')) == false) {
        return context.t.servers.addrError;
      }

      return null;
    }

    void updateServerFromEngine(BooruEngine? engine) {
      if (engine == null) return;

      current.value = current.value.copyWith(
        searchUrl: engine.searchQuery,
        tagSuggestionUrl: engine.suggestionQuery,
        postUrl: engine.postUrl,
        searchParserId: engine.searchParserId,
        suggestionParserId: engine.suggestionParserId,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingMd,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeading(context.t.servers.title),
              SectionSurface(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(DesignTokens.spacingSm),
                    child: Form(
                      key: formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<BooruEngine>(
                            initialValue: selectedEngine.value,
                            decoration: filledFieldDecoration(
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
                              updateServerFromEngine(engine);
                            },
                            validator: (value) {
                              if (value == null) {
                                return context.t.servers.engineRequired;
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: DesignTokens.spacingSm),
                          TextFormField(
                            controller: homepage,
                            enableIMEPersonalizedLearning: !imeIncognito,
                            decoration: filledFieldDecoration(
                              context,
                              label: context.t.servers.homepageHint,
                            ),
                            validator: validateAddress,
                          ),
                          const SizedBox(height: DesignTokens.spacingSm),
                          TextFormField(
                            controller: alias,
                            enableIMEPersonalizedLearning: !imeIncognito,
                            decoration: filledFieldDecoration(
                              context,
                              label: context.t.servers.alias,
                            ),
                          ),
                          const SizedBox(height: DesignTokens.spacingXs),
                          CheckboxListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: DesignTokens.spacingCardInset,
                            ),
                            value: useApiAddr.value,
                            title: Text(context.t.servers.useCustomApi),
                            subtitle: Text(context.t.servers.useCustomApiDesc),
                            onChanged: (isChecked) {
                              if (isChecked != null) {
                                useApiAddr.value = isChecked;
                              }
                            },
                          ),
                          if (useApiAddr.value) ...[
                            const SizedBox(height: DesignTokens.spacingXs),
                            TextFormField(
                              controller: apiAddr,
                              enableIMEPersonalizedLearning: !imeIncognito,
                              decoration: filledFieldDecoration(
                                context,
                                label: context.t.servers.apiAddrHint,
                              ),
                              validator: validateAddress,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        ServerDetails(
          server: current.value,
          onSubmitted: (newServer) {
            final serverPod = ref.read(serverStateProvider.notifier);
            serverPod.edit(
              server,
              newServer.copyWith(
                homepage: homepage.text,
                alias: alias.text.trim(),
                apiAddr: useApiAddr.value ? apiAddr.text : '',
              ),
            );

            context.router.maybePop();
          },
        ),
      ],
    );
  }
}
