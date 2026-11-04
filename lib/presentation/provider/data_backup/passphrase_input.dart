/// The passphrase a field hands to the backup flow.
///
/// Sealing an archive and storing its passphrase have to be given *the same
/// string*: the key comes straight out of the bytes of the passphrase, so a
/// space kept in one and dropped in the other produces an archive that the
/// passphrase the app shows as saved cannot open. The field is where the value
/// becomes a value, so it is where it is trimmed once, for both uses.
///
/// [confirm] marks the flows that create a key (setting a new passphrase,
/// sealing a backup). Restoring passes the text through untouched: an archive
/// written by an older build can carry a passphrase with surrounding spaces,
/// and dropping them here would lock that archive out for good.
String preparePassphrase(String raw, {required bool confirm}) {
  return confirm ? raw.trim() : raw;
}
