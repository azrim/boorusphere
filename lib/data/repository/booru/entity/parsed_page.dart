import 'dart:collection';

import 'package:boorusphere/data/repository/booru/entity/post.dart';

/// One parsed server page.
///
/// [posts] are the entries that survived the content guard and can be shown;
/// [rawCount] is how many entries the payload carried in total. The two differ
/// whenever the server returned a post the guard rejects (missing file URL,
/// zero dimensions, duplicate id), and pagination must use [rawCount] to tell
/// "the server had no more entries" apart from "we dropped some".
///
/// Iterating a [ParsedPage] yields [posts], so callers that only care about
/// the content can treat it as a plain collection.
class ParsedPage extends IterableMixin<Post> {
  const ParsedPage({required this.posts, required this.rawCount});

  const ParsedPage.empty() : posts = const [], rawCount = 0;

  final List<Post> posts;
  final int rawCount;

  @override
  Iterator<Post> get iterator => posts.iterator;
}
