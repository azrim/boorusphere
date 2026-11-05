/// The difference between the post page a probe asked for and whatever else
/// arrived with a 200.
///
/// Boards that gate access answer *every* path they were given. Measured on
/// 2026-11-05, under this app's own User-Agent, with a real API payload
/// answering one byte further up the same host:
///
/// * `derpibooru.org/images/<id>` — 200, `<title>Derpibooru - Making sure
///   you're not a bot!</title>`, and an image of Anubis thinking.
/// * `booru.allthefallen.moe/images/1` — 200, `<title>booru.allthefallen.moe |
///   Verification</title>`, a challenge container, no post anywhere.
/// * `ponybooru.org/images/<id>` — 503 with `<title>ponybooru.org | Anti-DDoS
///   Flood Protection and Firewall</title>` over `<h1>Checking your browser`.
///
/// A probe that reads only the status certifies all three: the scan writes a
/// post link that leads the reader to a page with no image in it, and a host
/// that was never reached still looks like a detected engine.
///
/// The rule is the opposite of the one a naive reader reaches for. It matches
/// the phrases in the page's own headline — its title and the first heading —
/// and the paths a gate loads its assets from, never in the body: a real post
/// page talks about captchas, cookies and JavaScript the way any site does
/// (safebooru's fixture carries the word captcha nineteen times), so a rule
/// that read the whole document would refuse the boards that answer instead of
/// the wall standing in front of them.
class PostPageGate {
  const PostPageGate._();

  /// HTML requires a title and every board the scanner is asked about writes
  /// one — and closes it — within the first seven hundred bytes, so an answer
  /// that never names itself is not a post page. The titles are folded onto
  /// one line because gelbooru and konachan wrap theirs around the tag list.
  static final _titleTag = RegExp(
    r'<title[^>]*>(.*?)</title>',
    caseSensitive: false,
    dotAll: true,
  );
  static final _headingTag = RegExp(
    r'<h1[^>]*>(.*?)</h1>',
    caseSensitive: false,
    dotAll: true,
  );
  static final _whitespace = RegExp(r'\s+');

  /// What an interstitial says about itself, in the words it chose. Matched in
  /// the headline only; see the class comment for why the body is off limits.
  static const _gateHeadlines = <String>[
    // Anubis, which fronts the Derpibooru family. Spelled without the
    // apostrophe because boards rewrite that sentence with a typographic one.
    'not a bot',
    'oh noes',
    // Cloudflare: the browser check and the block page.
    'just a moment',
    'attention required',
    // The allthefallen page, which announces itself only as `| Verification`
    // and puts its challenge in a box rather than in a word anyone recognises.
    'verification',
    // Flood-protection pages, which title themselves after the product and
    // carry the browser check as the heading underneath.
    'flood protection',
    'checking your browser',
    'checking browser',
    'you are human',
    'enable javascript',
    // A refusal that arrived under a friendly status code.
    'access denied',
    'are you a robot',
  ];

  /// Paths only a gate serves: the interstitial loading its own script, so
  /// these are looked for anywhere in the head, not only in the headline.
  static const _gatePaths = <String>[
    'within.website/x/cmd/anubis',
    '/cdn-cgi/challenge-platform',
  ];

  static String _fold(String text) => text.replaceAll(_whitespace, ' ').trim();

  static String? _tagged(RegExp tag, String head) {
    final match = tag.firstMatch(head);
    return match == null ? null : _fold(match.group(1)!);
  }

  /// What the document calls itself, or null when it never says.
  static String? titleOf(String head) => _tagged(_titleTag, head);

  /// The page's own announcements: its title, then its first heading. Both are
  /// where a gate introduces itself; neither is where a post page keeps its
  /// tag list.
  static List<String> _headlines(String head) => [
    _tagged(_titleTag, head),
    _tagged(_headingTag, head),
  ].whereType<String>().toList();

  /// Whether [head] is an interstitial rather than the page that was asked for.
  static bool isBotGate(String head) {
    final lower = head.toLowerCase();
    if (_gatePaths.any(lower.contains)) return true;

    return _headlines(
      head,
    ).any((line) => _gateHeadlines.any(line.toLowerCase().contains));
  }

  /// Whether [head] looks like the post page itself: a document that names
  /// itself and is not one of the gates above.
  static bool isPostPage(String head) {
    if (isBotGate(head)) return false;
    return titleOf(head) != null;
  }
}
