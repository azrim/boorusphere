enum BooruError {
  empty,
  tagsBlocked,
  unparsable,

  /// The server answered with its browser check instead of a result. The API
  /// client cannot solve it, so the screen offers the built-in browser.
  cloudflareChallenge,

  /// The engine behind this server has no observed tag endpoint. The sheet
  /// says so plainly instead of requesting an endpoint that was guessed.
  tagInfoUnsupported,
}
