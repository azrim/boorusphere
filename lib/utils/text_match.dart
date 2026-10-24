/// Rank returned when the candidate does not contain the typed text at all.
const kNoMatch = 4;

/// How closely [candidate] completes [typed].
///
/// `0` exact, `1` prefix, `2` a later word of the candidate (`long_hair` for
/// `hair`), `3` any substring, and [kNoMatch] when the text is not in the
/// candidate at all.
///
/// Booru endpoints answer with substring matches ordered by post count, so the
/// most popular entry that merely *contains* the text arrives first. Ranking by
/// where the match sits keeps the entry the reader is spelling at the top.
int matchRank(String candidate, String typed) {
  final name = candidate.toLowerCase();
  final part = typed.toLowerCase();
  if (name == part) return 0;
  if (name.startsWith(part)) return 1;
  if (name.contains('_$part') || name.contains(' $part')) return 2;
  if (name.contains(part)) return 3;
  return kNoMatch;
}
