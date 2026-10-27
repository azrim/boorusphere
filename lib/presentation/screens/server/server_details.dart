import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/booru/parser/booru_parser.dart';
import 'package:boorusphere/data/repository/booru/provider.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/theme/app_typography.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/field_decoration.dart';
import 'package:boorusphere/presentation/widgets/section_label.dart';
import 'package:boorusphere/presentation/widgets/section_surface.dart';
import 'package:boorusphere/presentation/widgets/settings_sheet.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Query templates and API credentials of a saved server.
class ServerDetails extends HookConsumerWidget {
  const ServerDetails({
    super.key,
    required this.server,
    required this.onSubmitted,
  });

  final Server server;
  final Function(Server) onSubmitted;

  bool hasProperServerQuery(String? value) {
    if (value == null) {
      return false;
    }

    return value.contains('{tags}') &&
        value.contains(RegExp(r'\{(page-id|page-num|post-offset)\}')) &&
        value.contains('{post-limit}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imeIncognito = ref.watch(
      uiSettingStateProvider.select((it) => it.imeIncognito),
    );
    final formKey = useMemoized(GlobalKey<FormState>.new);
    final cSearchUrl = useTextEditingController(text: server.searchUrl);
    final cSuggestUrl = useTextEditingController(text: server.tagSuggestionUrl);
    final cPostUrl = useTextEditingController(text: server.postUrl);
    final cSearchParser = useState(server.searchParserId);
    final cSuggestionParser = useState(server.suggestionParserId);
    final cLogin = useTextEditingController(text: server.login);
    final cApiKey = useTextEditingController(text: server.apiKey);

    useEffect(() {
      cSearchUrl.text = server.searchUrl;
      cSuggestUrl.text = server.tagSuggestionUrl;
      cPostUrl.text = server.postUrl;
      cSearchParser.value = server.searchParserId;
      cSuggestionParser.value = server.suggestionParserId;
      cLogin.text = server.login;
      cApiKey.text = server.apiKey;
    }, [server]);

    openPresetPage() {
      context.router.push(
        ServerPresetRoute(
          onReturned: (newData) {
            cSearchUrl.text = newData.searchUrl;
            cSuggestUrl.text = newData.tagSuggestionUrl;
            cPostUrl.text = newData.postUrl;
            cSearchParser.value = newData.searchParserId;
            cSuggestionParser.value = newData.suggestionParserId;
          },
        ),
      );
    }

    onSave() {
      if (formKey.currentState?.validate() != true) {
        return;
      }

      onSubmitted.call(
        server.copyWith(
          searchUrl: cSearchUrl.text,
          tagSuggestionUrl: cSuggestUrl.text,
          postUrl: cPostUrl.text,
          searchParserId: cSearchParser.value,
          suggestionParserId: cSuggestionParser.value,
          login: cLogin.text.trim(),
          apiKey: cApiKey.text.trim(),
        ),
      );
    }

    final parsers = ref.read(booruParsersProvider);

    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacingMd,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeading(
                  context.t.serverQuery.title,
                  action: TextButton(
                    onPressed: openPresetPage,
                    child: Text(context.t.servers.preset),
                  ),
                ),
                SectionSurface(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(DesignTokens.spacingSm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ParserSelector(
                            label: context.t.servers.parserType.search,
                            type: BooruParserType.search,
                            parsers: parsers,
                            value: cSearchParser.value,
                            onChanged: (newValue) {
                              if (newValue != null) {
                                cSearchParser.value = newValue;
                              }
                            },
                          ),
                          const SizedBox(height: DesignTokens.spacingSm),
                          ParserSelector(
                            label: context.t.servers.parserType.suggestion,
                            type: BooruParserType.suggestion,
                            parsers: parsers,
                            value: cSuggestionParser.value,
                            onChanged: (newValue) {
                              if (newValue != null) {
                                cSuggestionParser.value = newValue;
                              }
                            },
                          ),
                          const SizedBox(height: DesignTokens.spacingSm),
                          TextFormField(
                            minLines: 1,
                            maxLines: 3,
                            controller: cSearchUrl,
                            enableIMEPersonalizedLearning: !imeIncognito,
                            decoration: flatFieldDecoration(
                              context,
                              label: context.t.serverQuery.search,
                            ),
                            validator: (value) {
                              if (hasProperServerQuery(value)) {
                                return null;
                              }

                              return context.t.servers.invalidSearchQuery;
                            },
                          ),
                          const SizedBox(height: DesignTokens.spacingSm),
                          TextFormField(
                            minLines: 1,
                            maxLines: 3,
                            controller: cSuggestUrl,
                            enableIMEPersonalizedLearning: !imeIncognito,
                            decoration: flatFieldDecoration(
                              context,
                              label: context.t.serverQuery.suggestion,
                            ),
                          ),
                          const SizedBox(height: DesignTokens.spacingSm),
                          TextFormField(
                            minLines: 1,
                            maxLines: 3,
                            controller: cPostUrl,
                            enableIMEPersonalizedLearning: !imeIncognito,
                            decoration: flatFieldDecoration(
                              context,
                              label: context.t.serverQuery.post,
                            ),
                          ),
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
                              style: context.theme.textTheme.bodySmall
                                  ?.copyWith(
                                    color: context.colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                          const SizedBox(height: DesignTokens.spacingSm),
                          TextFormField(
                            controller: cLogin,
                            enableIMEPersonalizedLearning: !imeIncognito,
                            decoration: flatFieldDecoration(
                              context,
                              label: context.t.servers.credentials.login,
                            ),
                          ),
                          const SizedBox(height: DesignTokens.spacingSm),
                          TextFormField(
                            controller: cApiKey,
                            enableIMEPersonalizedLearning: !imeIncognito,
                            obscureText: true,
                            decoration: flatFieldDecoration(
                              context,
                              label: context.t.servers.credentials.apiKey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            child: FilledButton(onPressed: onSave, child: Text(context.t.save)),
          ),
        ],
      ),
    );
  }
}

class ParserSelector extends HookWidget {
  const ParserSelector({
    super.key,
    required List<BooruParser> parsers,
    required this.value,
    required this.onChanged,
    required this.label,
    required this.type,
  }) : _parsers = parsers; // ignore: prefer_initializing_formals

  final void Function(String? newValue) onChanged;
  final List<BooruParser> _parsers;
  final BooruParserType type;
  final String value;
  final String label;

  List<BooruParser> get parsers {
    return _parsers.where((x) => x.type.contains(type)).toList();
  }

  Future<String?> selectParser(
    BuildContext context,
    String title,
    List<BooruParser> parsers,
    String current,
  ) async {
    final picked = await showChoiceSheet<String>(
      context: context,
      title: title,
      selected: current,
      choices: [
        for (final parser in parsers)
          Choice(
            value: parser.id,
            label: parser.id.fileNameNoExt,
            detail: parser.id.fileExt.toUpperCase(),
          ),
      ],
    );
    return picked?.value;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: DesignTokens.spacingXs,
            bottom: DesignTokens.spacingXs,
          ),
          child: Text(label, style: AppTextRoles.of(context).fieldLabel),
        ),
        // A flat row inside the block, ruled like every other field, instead
        // of a filled card stacked on the surface that already carries one.
        Semantics(
          button: true,
          child: InkWell(
            onTap: () async {
              FocusScope.of(context).unfocus();

              onChanged.call(
                await selectParser(context, label, parsers, value),
              );
            },
            child: Container(
              constraints: const BoxConstraints(
                minHeight: DesignTokens.controlHeightMin,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacingCardInset,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  ParserLabel(id: value),
                  const Spacer(),
                  Icon(Icons.arrow_drop_down, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ParserLabel extends StatelessWidget {
  const ParserLabel({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    if (id.isEmpty) {
      return Text(context.t.auto);
    }

    final scheme = context.colorScheme;
    final isJson = id.fileExt.toLowerCase() == 'json';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            id.fileNameNoExt,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: DesignTokens.spacingXs),
        Container(
          // A chip, not a card: flat inside the block, with the fill and its
          // foreground from the same scheme role so the contrast holds when
          // the accent palette changes.
          decoration: BoxDecoration(
            color: isJson ? scheme.primary : scheme.tertiary,
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacingXs,
              vertical: 1,
            ),
            child: Text(
              id.fileExt.toUpperCase(),
              style: context.theme.textTheme.labelSmall?.copyWith(
                color: isJson ? scheme.onPrimary : scheme.onTertiary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
