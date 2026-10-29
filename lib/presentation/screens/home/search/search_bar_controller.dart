import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/legacy.dart';

final searchBarControllerProvider = ChangeNotifierProvider.autoDispose
    .family<SearchBarController, SearchSession>(
      (ref, session) => SearchBarController(ref, session: session),
    );

/// Controller for the search bar.
///
/// [notifyListeners] is only called for transitions that change the *shape*
/// of the search UI (open/close/reset/clear). Per-keystroke text changes do
/// **not** notify; consumers that need the live text should listen to
/// [textEditingController] directly via [ValueListenableBuilder] or
/// `useValueListenable`. Notifying on every keystroke would force the entire
/// home shell, search bar, and surrounding consumers to rebuild on each
/// character typed.
class SearchBarController extends ChangeNotifier {
  SearchBarController(this.ref, {required this.session}) {
    textEditingController.addListener(_fetch);
  }

  final Ref ref;
  final SearchSession session;

  late final textEditingController = TextEditingController(text: initial);
  final focusNode = FocusNode(debugLabel: 'search field');

  Timer? _textTimer;
  bool _open = false;

  bool get isOpen => _open;
  String get value => textEditingController.value.text;
  String get initial => session.query;

  set _value(String value) {
    textEditingController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
      composing: TextRange(start: value.length, end: value.length),
    );
  }

  /// Debounce shared by every keystroke: one request per pause, not one per
  /// character.
  static const _debounce = Duration(milliseconds: 300);

  _fetch() {
    if (!isOpen) return;
    _textTimer?.cancel();
    _textTimer = Timer(_debounce, _requestSuggestion);
  }

  void _requestSuggestion() {
    if (!isOpen) return;
    final query = value;
    if (query.trim().isEmpty) return;
    ref.read(suggestionStateProvider.notifier).get(query);
  }

  void submit(BuildContext context, String newValue) {
    _value = initial;
    close();
    context.router.push(HomeRoute(session: session.copyWith(query: newValue)));
  }

  void append(String newValue) {
    final current = value.toWordList();
    final result = {...current.take(current.length), ...newValue.toWordList()};
    _value = '${result.join(' ')} ';
  }

  void replaceLast(String newValue) {
    final current = value.toWordList();
    final result = {
      if (current.isNotEmpty) ...current.take(current.length - 1),
      ...newValue.toWordList(),
    };
    _value = '${result.join(' ')} ';
  }

  void appendTyped(String newValue) {
    value.endsWith(' ') ? append(newValue) : replaceLast(newValue);
  }

  void reset() {
    _value = initial;
    notifyListeners();
  }

  void open() {
    _open = true;
    // Reopening the bar with text already in it brings the list back without
    // waiting for another keystroke.
    _requestSuggestion();
    notifyListeners();

    // `autofocus` only fires when the field first mounts, so an explicit
    // request is what raises the keyboard on every open after that. The field
    // only becomes focusable on the rebuild above, hence the post-frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_open) focusNode.requestFocus();
    });
  }

  void close() {
    _textTimer?.cancel();
    _open = false;
    focusNode.unfocus();
    notifyListeners();
  }

  void clear() {
    if (value.isEmpty) {
      reset();
      close();
    } else {
      textEditingController.clear();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _textTimer?.cancel();
    textEditingController.removeListener(_fetch);
    textEditingController.dispose();
    focusNode.dispose();
    super.dispose();
  }
}
