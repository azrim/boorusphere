enum BooruError {
  empty,
  tagsBlocked,
  unparsable,

  /// The server would answer, but only to an authenticated client. Some engines
  /// refuse with HTTP 401, others answer **200** and put the complaint in the
  /// body, so both forms end here: the fix is a key in the server settings, not
  /// a different search.
  authRequired,

  /// The server answered with its browser check instead of a result. The API
  /// client cannot solve it, so the screen offers the built-in browser.
  cloudflareChallenge,

  /// The engine behind this server has no observed tag endpoint. The sheet
  /// says so plainly instead of requesting an endpoint that was guessed.
  tagInfoUnsupported,
}
