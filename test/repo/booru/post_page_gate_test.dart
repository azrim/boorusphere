import 'dart:convert';
import 'dart:math';

import 'package:boorusphere/data/repository/booru/utils/post_page_gate.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../utils/fake_data.dart';

/// How much of a page the scanner actually reads before judging it.
const _headLimit = 8 * 1024;

String _head(String fixture) {
  final body = utf8.decode(
    getFixture(fixture).readAsBytesSync(),
    allowMalformed: true,
  );
  return body.substring(0, min(body.length, _headLimit));
}

void main() {
  group('post page gate', () {
    test('every post page the scanner is asked about is accepted', () {
      // A rule that refuses real boards is worse than the wall it catches: the
      // address simply stays empty, and every post link goes to the homepage.
      // These are the pages the engines serve today.
      const fixtures = [
        'booruonrails/post.html',
        'danbooru/post.html',
        'e621/post.html',
        'gelbooru/post.html',
        'konachan/post.html',
        'rule34.paheal/post.html',
        'safebooru/post.html',
        'szurubooru/post.html',
      ];

      for (final fixture in fixtures) {
        expect(
          PostPageGate.isPostPage(_head(fixture)),
          isTrue,
          reason: '$fixture is a real post page',
        );
      }
    });

    test('the titles boards wrap around a tag list are still read', () {
      // Gelbooru and Moebooru put the whole tag list inside the title element,
      // across lines, so a single-line reading finds an empty title.
      final folded = PostPageGate.titleOf(_head('gelbooru/post.html'));

      expect(folded, contains('final fantasy'));
      expect(folded, isNot(contains('\n')));
    });

    test('an interstitial answering with 200 is refused', () {
      const gates = {
        'anubis': '''
<!DOCTYPE html>
<html>
  <head><title>Making sure you're not a bot!</title></head>
  <body><h1>Hold on</h1></body>
</html>
''',
        'anubis, wording customised by the board': '''
<!DOCTYPE html>
<html>
  <head><title>Derpibooru — Oh noes!</title></head>
</html>
''',
        'anubis, script only': '''
<!DOCTYPE html>
<html>
  <head>
    <script src="/.within.website/x/cmd/anubis/static/js/app.min.js"></script>
  </head>
</html>
''',
        'cloudflare challenge': '''
<!DOCTYPE html>
<html><head><title>Just a moment...</title></head></html>
''',
        'cloudflare block': '''
<!DOCTYPE html>
<html><head><title>Attention Required! | Cloudflare</title></head></html>
''',
        'a verifying page that is not cloudflare': '''
<!DOCTYPE html>
<html><head><title>Checking browser…</title></head></html>
''',
        'a refusal under a friendly status code': '''
<!DOCTYPE html>
<html><head><title>Access Denied</title></head></html>
''',
        'the allthefallen page, as fetched 2026-11-05': '''
<!DOCTYPE html>
<html lang="en">
  <head>
    <title>booru.allthefallen.moe | Verification</title>
    <style>.challenge-container { max-width: 200px }</style>
  </head>
  <body>
    <h1>booru.allthefallen.moe</h1>
    <div class="challenge-container" data-nonce="c1f2"></div>
  </body>
</html>
''',
        'the ponybooru page, as fetched 2026-11-05': '''
<!DOCTYPE html>
<html>
  <head>
    <title>ponybooru.org | Anti-DDoS Flood Protection and Firewall</title>
  </head>
  <body><h1>Checking your browser</h1></body>
</html>
''',
        'a check that only announces itself in the heading': '''
<!DOCTYPE html>
<html>
  <head><title>funbox-gate</title></head>
  <body><h1>Verifying you are human</h1></body>
</html>
''',
      };

      gates.forEach((name, body) {
        expect(
          PostPageGate.isPostPage(body),
          isFalse,
          reason: 'the $name page is not a post',
        );
      });
    });

    test('markup about captchas is not a gate', () {
      // Boards put captcha and JavaScript boilerplate in ordinary pages —
      // safebooru's mentions captcha nineteen times — and a Philomena heading
      // is the tag list, so the phrases are read in the headline and never in
      // the body underneath it.
      const page = '''
<!DOCTYPE html>
<html>
  <head><title>#512847 - rating:general, 1boy | Board</title></head>
  <body>
    <h1><a href="/posts?tag_id=3">1boy</a> <a href="/posts?tag_id=9">hat</a></h1>
    <noscript>You need to enable JavaScript to run this app.</noscript>
    <a href="/account/reset_captcha">Captcha required</a>
    <p>Are you a human? Verify you are human by e-mail.</p>
    <div class="challenge-container">Nonce: c1f2</div>
  </body>
</html>
''';

      expect(PostPageGate.isPostPage(page), isTrue);
    });

    test('an answer that is not a document is refused', () {
      const notPages = [
        '',
        '{"posts":[{"id":100}]}',
        '<?xml version="1.0"?><posts><post id="100"/></posts>',
        '<!DOCTYPE html><html><head></head><body>Not found</body></html>',
      ];

      for (final body in notPages) {
        expect(
          PostPageGate.isPostPage(body),
          isFalse,
          reason: '${body.isEmpty ? '<empty body>' : body} names no page',
        );
      }
    });
  });
}
