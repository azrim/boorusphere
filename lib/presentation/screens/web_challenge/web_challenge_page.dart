import 'dart:async';
import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/theme/app_typography.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/widgets/app_toast.dart';
import 'package:boorusphere/presentation/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Opens a server's own page so a challenge only a browser can answer is
/// answered once, then hands the result to the API client.
///
/// A server behind Cloudflare answers the API with its "Just a moment…" page,
/// which no amount of header work gets past. The clearance cookie and the
/// User-Agent that earned it are stored together, keyed by host, and every
/// later request from the app presents that pair.
///
/// The page closes itself as soon as the clearance appears; [Done] exists for
/// a server that lets the browser through without one.
@RoutePage()
class WebChallengePage extends ConsumerStatefulWidget {
  const WebChallengePage({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<WebChallengePage> createState() => _WebChallengePageState();
}

class _WebChallengePageState extends ConsumerState<WebChallengePage> {
  /// Reads the platform store rather than the page, so an HttpOnly clearance
  /// cookie — the one that matters — is included.
  final _cookies = AndroidWebViewCookieManager(
    const PlatformWebViewCookieManagerCreationParams(),
  );

  WebViewController? _controller;
  Timer? _poll;
  Uri? _site;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    // The page opens after the first frame: the theme, and so the WebView's
    // background, is not available inside initState.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _start() {
    final server = ref.read(serverStateProvider).getById(widget.serverId);
    final target = server.homepage.trim().isNotEmpty
        ? server.homepage
        : server.apiAddress;
    final site = Uri.tryParse(target);
    if (site == null || !site.hasScheme || site.host.isEmpty) return;
    _site = site;

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Theme.of(context).colorScheme.surface)
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => unawaited(_check())),
      )
      ..loadRequest(site);

    // A navigation happens when the challenge hands over, so the timer covers
    // the case where the clearance arrives without one.
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    setState(() => _controller = controller);
  }

  Future<void> _check() async {
    final site = _site;
    if (!mounted || site == null || _capturing) return;
    final cookies = await _cookies.getCookies(site);
    if (!cookies.any((it) => it.name == 'cf_clearance')) return;
    await _capture();
  }

  /// Copies what the browser holds for the site into the shared store and
  /// closes the page with `true`, which is the caller's cue to retry.
  Future<void> _capture({bool manual = false}) async {
    final controller = _controller;
    final site = _site;
    if (!mounted || _capturing || controller == null || site == null) return;

    _capturing = true;
    final t = context.t;
    final server = ref.read(serverStateProvider).getById(widget.serverId);
    // Read before the first gap: a pop while a cookie is being read leaves the
    // element disposed, and a read after that throws.
    final store = ref.read(webClearanceRepoProvider);
    final userAgent = await controller.getUserAgent() ?? '';
    final origins = <Uri>{site, ...await _resourceOrigins(controller)};

    var saved = 0;
    for (final origin in origins) {
      // Reads and analytics hosts load on the page too, but their cookies are
      // useless to the API and never leave this account.
      if (!_sameSite(site, origin)) continue;
      final cookies = await _cookies.getCookies(origin);
      if (cookies.isEmpty) continue;
      await store.save(
        host: origin.host,
        userAgent: userAgent,
        cookies: cookies.map((it) => '${it.name}=${it.value}').join('; '),
      );
      saved++;
    }

    if (!mounted) return;
    _capturing = false;
    if (saved == 0) {
      if (manual) showToast(context, t.webChallenge.nothingSaved);
      return;
    }

    _poll?.cancel();
    showToast(context, t.webChallenge.saved(serverName: server.name));
    context.router.pop(true);
  }

  /// Every origin the page pulled a file from, so the image CDN of the same
  /// site is cleared in the same pass as the API.
  Future<List<Uri>> _resourceOrigins(WebViewController controller) async {
    const script =
        'JSON.stringify([...new Set(performance.getEntriesByType("resource")'
        '.map(function (entry) { try { return new URL(entry.name).origin; }'
        ' catch (_) { return ""; } })'
        '.filter(function (origin) { return origin; }))])';
    try {
      final raw = await controller.runJavaScriptReturningResult(script);
      return _decodeOrigins(raw);
    } catch (_) {
      return const [];
    }
  }

  /// The result arrives as JSON text, occasionally quoted twice by the
  /// platform channel.
  static List<Uri> _decodeOrigins(Object? raw) {
    Object? value = raw;
    for (var i = 0; i < 2 && value is String; i++) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        return const [];
      }
    }
    if (value is! List) return const [];
    return value
        .whereType<String>()
        .map(Uri.tryParse)
        .whereType<Uri>()
        .toList();
  }

  static bool _sameSite(Uri site, Uri other) {
    if (!other.hasScheme || other.host.isEmpty) return false;
    return _registrable(site.host) == _registrable(other.host);
  }

  static String _registrable(String host) {
    final normalized = host.toLowerCase();
    final parts = normalized.split('.');
    if (parts.length <= 2) return normalized;
    return parts.sublist(parts.length - 2).join('.');
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.t.webChallenge.title),
        actions: [
          TextButton(
            onPressed: controller == null ? null : () => _capture(manual: true),
            child: Text(context.t.webChallenge.done),
          ),
        ],
      ),
      body: controller == null
          ? EmptyState(
              icon: const Icon(Icons.link_off),
              title: context.t.error.unknown,
            )
          : Column(
              children: [
                _Hint(text: context.t.webChallenge.hint),
                Expanded(child: WebViewWidget(controller: controller)),
              ],
            ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingMd,
          vertical: DesignTokens.spacingSm,
        ),
        child: Row(
          children: [
            Icon(
              Icons.shield_outlined,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: DesignTokens.spacingSm),
            Expanded(
              child: Text(text, style: AppTextRoles.of(context).rowSupporting),
            ),
          ],
        ),
      ),
    );
  }
}
