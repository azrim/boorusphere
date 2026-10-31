enum Setting {
  downloadsGroupByServer,
  downloadsQuality,
  gestureSwipeMode,
  gestureSwipeDownThreshold,
  gestureEnableSwipeToDetails,
  gestureEnableSwipeToDismiss,
  postBlurExplicit,
  postBlurTimelineOnly,
  postLoadOriginal,
  serverLastActiveId,
  serverPostLimit,
  serverSafeMode,
  uiMidnightMode,
  uiBlur,
  uiThemeMode,
  uiColorPalette,
  uiTimelineGrid,
  uiLongPressHintSeen,
  uiLanguage,
  videoPlayerMuted,
  imeIncognito,
  searchRating,
  // Hides the app in the recent-apps preview and blocks screenshots. Stored
  // with the other non-secret preferences; the lock itself lives in secure
  // storage so an archive can never enable a lock without its PIN.
  flagSecure,
  // Periodic backup settings
  periodicBackupEnabled,
  periodicBackupFrequency,
  periodicBackupDeleteOld,
  periodicBackupMaxCount,
  periodicBackupLastTime,
  // Whether new backups are sealed by default. Unlike the passphrase below,
  // this is not a secret, so an archive carries it like any other setting.
  backupEncryption,
  // Kept out of the exported settings: the passphrase is what opens an
  // encrypted backup, so it must never travel inside one.
  backupPassphrase,
  // Telegram backup settings
  telegramBackupEnabled,
  telegramChatId,
  telegramBotToken,
}
