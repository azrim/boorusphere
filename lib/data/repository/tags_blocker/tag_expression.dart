/// One whitespace-separated term inside a blocked-tag expression.
///
/// At most one operator is read from the start of a term: `-` negates it and
/// `~` marks it as part of the OR group. Anything after that operator is the
/// tag name, so a stray second operator cannot silently change the rest of
/// the expression.
class BlockedTagTerm {
  const BlockedTagTerm({
    required this.tag,
    required this.isNegative,
    required this.isOr,
  });

  /// Lowercase tag name.
  final String tag;
  final bool isNegative;
  final bool isOr;

  bool matchesNormalized(Set<String> tags) {
    final present = tags.contains(tag);
    return isNegative ? !present : present;
  }
}

/// A blocked-tag entry: tags separated by spaces are ANDed, `~` puts a term
/// into an OR group, and `-` negates a term.
///
/// The syntax matches what a Danbooru-style filter field accepts:
/// `foo bar` hides posts that carry both, `~foo ~bar` hides posts that carry
/// either, and `foo -bar` hides posts that carry `foo` but not `bar`. Every
/// entry is independent: a post is hidden when any entry matches it.
class BlockedTagExpression {
  const BlockedTagExpression(this.terms);

  /// Parses [raw], dropping tokens that carry no tag (a bare `-` or `~`).
  /// An expression whose tokens all ended up dropped never matches, which is
  /// the safe reading of an empty entry.
  factory BlockedTagExpression.parse(String raw) {
    final terms = <BlockedTagTerm>[];
    for (final token in raw.split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      final isNegative = token.startsWith('-');
      final isOr = token.startsWith('~');
      final value = isNegative || isOr ? token.substring(1) : token;
      final tag = value.toLowerCase();
      if (tag.isEmpty) continue;
      terms.add(BlockedTagTerm(tag: tag, isNegative: isNegative, isOr: isOr));
    }
    return BlockedTagExpression(terms);
  }

  final List<BlockedTagTerm> terms;

  bool get isEmpty => terms.isEmpty;

  bool get isNotEmpty => terms.isNotEmpty;

  /// Whether the post carrying [tags] is hidden by this entry.
  ///
  /// Every non-OR term has to hold, and at least one OR term has to hold when
  /// the entry has any. Text is compared case-insensitively.
  bool matches(Iterable<String> tags) {
    if (terms.isEmpty) return false;
    final normalized = {for (final tag in tags) tag.toLowerCase()};
    return matchesNormalized(normalized);
  }

  /// [matches] for a tag set that is already lowercase.
  bool matchesNormalized(Set<String> tags) {
    if (terms.isEmpty) return false;
    var hasOr = false;
    var orSatisfied = false;
    for (final term in terms) {
      final hit = term.matchesNormalized(tags);
      if (term.isOr) {
        hasOr = true;
        orSatisfied = orSatisfied || hit;
      } else if (!hit) {
        return false;
      }
    }
    return !hasOr || orSatisfied;
  }

  /// The tag this entry hides on its own, when it consists of one positive
  /// term.
  ///
  /// A multi-term entry decides over a combination, so no single suggestion
  /// or search word can be declared blocked from it. A negated term never
  /// hides the tag it names.
  String? get singlePositiveTag {
    if (terms.length != 1) return null;
    final term = terms.single;
    return term.isNegative ? null : term.tag;
  }

  /// [singlePositiveTag] only when the term also carries no OR operator.
  ///
  /// Refusing a whole query is only safe for a tag that is always blocked;
  /// `~foo` still leaves every post without `foo` visible.
  String? get singlePlainTag {
    final tag = singlePositiveTag;
    if (tag == null) return null;
    return terms.single.isOr ? null : tag;
  }
}

/// Parses the stored entries, dropping ones that carry no usable term.
List<BlockedTagExpression> parseBlockedTagExpressions(Iterable<String> raw) {
  final expressions = <BlockedTagExpression>[];
  for (final value in raw) {
    final expression = BlockedTagExpression.parse(value);
    if (expression.isNotEmpty) expressions.add(expression);
  }
  return expressions;
}

/// Whether any entry in [expressions] hides a post carrying [tags].
bool matchesBlockedTagExpressions(
  Iterable<BlockedTagExpression> expressions,
  Iterable<String> tags,
) {
  final normalized = {for (final tag in tags) tag.toLowerCase()};
  for (final expression in expressions) {
    if (expression.matchesNormalized(normalized)) return true;
  }
  return false;
}
