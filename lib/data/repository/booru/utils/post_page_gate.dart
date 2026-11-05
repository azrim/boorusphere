/// The difference between the post page a probe asked for and whatever else
/// arrived with a 200.
///
/// Boards that gate access answer *every* path they were given — measured on
/// 2026-11-05, `derpibooru.org/1183740` and `/images/1183740` both returned
/// 200 whose body was the site's "Making sure you're not a bot!" page, and
/// `booru.allthefallen.moe` answered an API path the same way. A probe that
/// reads only the status therefore certifies the gate: the scan writes a post
/// link that leads the reader to a page with no image in it, and a host that
/// was never reached still looks like a detected engine.
///
/// The body is the only witness left, so the phrases below are matched against
/// the document title and the two paths the gates load their own assets from.
/// Not against the whole page: a real post page talks about captchas, cookies
/// and JavaScript the way any site does — safebooru's fixture carries the word
/// captcha nineteen times — so a looser rule would refuse the boards that
/// answer instead of the wall standing in front of them.
class PostPageGate {
  const PostPageGate._();

  /// HTML requires a title and every board we probe writes one within the
  /// first few hundred bytes, so an answer that never names itself is not a
  /// post page. Multi-line titles are folded into one line: gelbooru and
  /// konachan both wrap theirs around the tag list.
  static final _titleTag = RegExp(
    r'<title[^>]*>(.*?)</title>',
    caseSensitive: false,
    dotAll: true,
  );

  /// Titles that are the interstitial talking, in the words it chose.
  static const _gateTitles = <String>[
    // Anubis, which fronts the Derpibooru family. Matched without the
    // apostrophe because boards rewrite that sentence with a typographic one.
    'not a bot',
    'oh noes',
    // Cloudflare: the browser check and the block page.
    'just a moment',
    'attention required',
    // Verifying-browser pages that are not Cloudflare's own.
    'checking your browser',
    'checking browser',
    'you are human',
    'enable javascript',
    // A refusal that arrived under a friendly status code.
    'access denied',
    'are you a robot',
  ];

  /// Paths only a gate serves: the interstitial loading its own script, so
  /// these are looked for anywhere in the head, not only in the title.
  static const _gatePaths = <String>[
    'within.website/x/cmd/anubis',
    '/cdn-cgi/challenge-platform',
  ];

  /// What the document calls itself, or null when it never says.
  static String? titleOf(String head) {
    final match = _titleTag.firstMatch(head);
    if (match == null) return null;

    return match.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Whether [head] is an interstitial rather than the page that was asked for.
  static bool isBotGate(String head) {
    final lower = head.toLowerCase();
    if (_gatePaths.any(lower.contains)) return true;

    final title = titleOf(head);
    if (title == null) return false;

    final text = title.toLowerCase();
    return _gateTitles.any(text.contains);
  }

  /// Whether [head] looks like the post page itself: a document that names
  /// itself and is not one of the gates above.
  static bool isPostPage(String head) {
    if (isBotGate(head)) return false;
    return titleOf(head) != null;
  }
}
