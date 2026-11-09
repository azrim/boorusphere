import 'dart:async';
import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/theme/app_surfaces.dart';
import 'package:boorusphere/presentation/theme/app_typography.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/widgets/app_toast.dart';
import 'package:boorusphere/presentation/widgets/empty_state.dart';
import 'package:boorusphere/utils/http/cloudflare.dart';
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
  /// cookie, the one that matters, is included.
  final _cookies = AndroidWebViewCookieManager(
    const PlatformWebViewCookieManagerCreationParams(),
  );

  /// `cf_clearance` values already proven unusable by the API client, skipped
  /// by automatic polling until Turnstile issues a fresh token.
  final Set<String> _rejectedTokens = {};

  /// `cf_clearance` values already sitting in the WebView cookie store before
  /// the page loaded, so an expired leftover is rejected quietly without
  /// flashing a verification error while the user solves the new challenge.
  final Set<String> _initialTokens = {};

  WebViewController? _controller;
  Timer? _poll;
  Uri? _site;
  Uri? _apiSite;
  bool _capturing = false;
  bool _probedApiSite = false;

  /// The server's own address could not be read, so there is no page to load.
  /// Kept apart from `_controller == null`, which only means "not loaded yet",
  /// so a first frame never reads as a failure.
  bool _addressUnreadable = false;

  @override
  void initState() {
    super.initState();
    // The page opens after the first frame: the theme, and so the WebView's
    // background, is not available inside initState.
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Uri? _validOrigin(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return uri;
  }

  Iterable<String> _cookieTokens(Iterable<WebViewCookie> cookies) {
    return cookies
        .where((it) => it.name == 'cf_clearance' && it.value.isNotEmpty)
        .map((it) => it.value);
  }

  Future<void> _start() async {
    final server = ref.read(serverStateProvider).getById(widget.serverId);
    final homeSite = _validOrigin(server.homepage);
    final apiSite = _validOrigin(server.apiAddress);
    final site = homeSite ?? apiSite;
    if (site == null) {
      setState(() => _addressUnreadable = true);
      return;
    }

    final surfaceColor = Theme.of(context).colorScheme.surface;
    final store = ref.read(webClearanceRepoProvider);
    for (final host in <String>{site.host, if (apiSite != null) apiSite.host}) {
      _rejectedTokens.addAll(
        extractClearanceTokens(store.forHost(host)?.cookies),
      );
    }

    for (final origin in <Uri>{site, ?apiSite}) {
      try {
        final existing = await _cookies.getCookies(origin);
        _initialTokens.addAll(_cookieTokens(existing));
      } catch (_) {}
    }
    if (!mounted) return;

    _site = site;
    _apiSite = apiSite;

    final controller = WebViewController();
    unawaited(controller.setJavaScriptMode(JavaScriptMode.unrestricted));
    unawaited(controller.setBackgroundColor(surfaceColor));
    unawaited(
      controller.setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => unawaited(_check())),
      ),
    );
    unawaited(controller.loadRequest(site));

    // A navigation happens when the challenge hands over, so the timer covers
    // the case where the clearance arrives without one.
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    setState(() => _controller = controller);
  }

  Future<void> _check() async {
    final site = _site;
    final apiSite = _apiSite;
    if (!mounted || site == null || _capturing) return;

    final tokens = <String>{};
    for (final origin in <Uri>{site, ?apiSite}) {
      try {
        final cookies = await _cookies.getCookies(origin);
        tokens.addAll(_cookieTokens(cookies));
      } catch (_) {}
    }
    if (!mounted || _capturing) return;
    if (!tokens.any((it) => !_rejectedTokens.contains(it))) return;

    await _capture();
  }

  /// Copies what the browser holds for the site into the shared store and
  /// closes the page with `true`, which is the caller's cue to retry.
  Future<void> _capture({bool manual = false}) async {
    final controller = _controller;
    final site = _site;
    if (!mounted || _capturing || controller == null || site == null) return;

    _capturing = true;
    var closed = false;
    final t = context.t;
    final server = ref.read(serverStateProvider).getById(widget.serverId);
    // Read before the first gap: a pop while a cookie is being read leaves the
    // element disposed, and a read after that throws.
    final store = ref.read(webClearanceRepoProvider);
    final apiSite = _apiSite;

    try {
      final userAgent = await controller.getUserAgent() ?? '';
      final origins = candidateClearanceOrigins(
        site: site,
        apiSite: apiSite,
        resourceOrigins: await _resourceOrigins(controller),
      );

      var saved = 0;
      final seenTokens = <String>{};
      for (final origin in origins) {
        final cookies = await _cookies.getCookies(origin);
        if (cookies.isEmpty) continue;
        seenTokens.addAll(_cookieTokens(cookies));
        await store.save(
          host: origin.host,
          userAgent: userAgent,
          cookies: cookies.map((it) => '${it.name}=${it.value}').join('; '),
        );
        saved++;
      }

      if (!mounted) return;
      if (saved == 0) {
        if (manual) showToast(context, t.webChallenge.nothingSaved);
        return;
      }

      _poll?.cancel();
      // Saving the cookie only proves the browser holds it. Prove the API
      // client gets past the check too before closing this page: the agent and
      // cookies have to travel together, and a session that only works inside
      // the WebView would send the reader straight back to this card.
      final cleared = await _clearanceWorks();
      if (!mounted) return;
      if (!cleared) {
        final hadFreshToken = seenTokens.any(
          (it) => !_initialTokens.contains(it),
        );
        _rejectedTokens.addAll(seenTokens);

        // When the homepage cleared without covering a separate API host, load
        // the API origin once so a host-scoped challenge there can be solved.
        if (apiSite != null && apiSite.host != site.host && !_probedApiSite) {
          _probedApiSite = true;
          _site = apiSite;
          await controller.loadRequest(apiSite);
          if (!mounted) return;
        } else if (manual || hadFreshToken) {
          showToast(context, t.webChallenge.verifyFailed);
        }

        // The browser may earn a fresh clearance on the next pass, so keep
        // watching instead of leaving the page waiting for a manual tap.
        _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
        return;
      }

      closed = true;
      showToast(context, t.webChallenge.saved(serverName: server.name));
      context.router.pop(true);
    } finally {
      if (mounted && !closed) {
        _capturing = false;
      }
    }
  }

  /// Sends one real API request through the stored clearance.
  ///
  /// Any answer that is not another challenge means Cloudflare let the client
  /// through; whether the query itself succeeded is the timeline's business.
  Future<bool> _clearanceWorks() async {
    final server = ref.read(serverStateProvider).getById(widget.serverId);
    try {
      await ref
          .read(imageboardRepoProvider(server))
          .getPage(const PageOption(limit: 1), 0);
      return true;
    } catch (err) {
      return !isCloudflareChallenge(err);
    }
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

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final server = ref.watch(
      serverStateProvider.select((it) => it.getById(widget.serverId)),
    );

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
      body: switch ((controller, _addressUnreadable)) {
        // The address is the one thing this page cannot work around, so the
        // state names it and hands the reader the form that fixes it.
        (null, true) => EmptyState(
          icon: const Icon(Icons.link_off),
          title: context.t.webChallenge.badAddress,
          body: context.t.webChallenge.badAddressDesc(name: server.name),
          action: FilledButton(
            onPressed: () =>
                context.router.push(ServerEditorRoute(server: server)),
            child: Text(context.t.webChallenge.fixServer),
          ),
        ),
        // Still inside the post-frame callback that builds the controller.
        (null, false) => const Center(child: RefreshProgressIndicator()),
        (final WebViewController loaded, _) => Column(
          children: [
            _Hint(text: context.t.webChallenge.hint),
            Expanded(child: WebViewWidget(controller: loaded)),
          ],
        ),
      },
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The strip is a block on the page, so in Midnight it keeps the page tone
    // instead of lifting off pure black as a grey slab.
    final flat = AppSurfacePolicy.of(context).flat;

    return Material(
      color: flat ? scheme.surface : scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingMd,
          vertical: DesignTokens.spacingSm,
        ),
        child: Row(
          children: [
            Icon(
              Icons.shield_outlined,
              size: DesignTokens.iconInline,
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
