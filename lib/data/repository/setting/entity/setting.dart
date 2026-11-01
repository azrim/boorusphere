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
  // Local feed filters applied after the server answer, like blocked tags.
  timelineHideFavorited,
  timelineHideDownloaded,
  serverLastActiveId,
  serverPostLimit,
  serverSafeMode,
  uiMidnightMode,
  uiBlur,
  uiThemeMode,
  uiColorPalette,
  uiTimelineGrid,
  uiLongPressHintSeen,
  // Paged (default) or infinite: how the timeline walks through a result set.
  uiFeedMode,
  uiLanguage,
  videoPlayerMuted,
  // Viewer behaviour that is not about what is shown, but how it is stepped
  // through. Names are stored so a reordered enum keeps its meaning.
  viewerSlideshowDirection,
  viewerSlideshowInterval,
  viewerVideoSeekSeconds,
  viewerVolumeKeyNavigation,
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
