import 'dart:async';
import 'dart:io';

import 'package:boorusphere/presentation/provider/settings/periodic_backup_state.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'telegram_backup_service.g.dart';

enum TelegramResult {
  success,
  invalidToken,
  invalidChatId,
  networkError,
  fileTooLarge,
  unknownError,
}

/// Kept alive for the session: every caller only reads the notifier and then
/// awaits a request, so an auto-disposed element would be gone by the time the
/// result is written back and that write would throw instead of answering.
@Riverpod(keepAlive: true)
class TelegramBackupService extends _$TelegramBackupService {
  static const _apiBaseUrl = 'https://api.telegram.org';
  static const _maxFileSize = 50 * 1024 * 1024; // 50MB limit for Telegram

  /// A request that never answers must not leave the caller spinning.
  static const _testTimeout = Duration(seconds: 30);

  /// Uploading a backup is slow on a mobile connection, so the send gets room
  /// to finish while still being bounded.
  static const _uploadTimeout = Duration(minutes: 5);

  @override
  TelegramResult? build() => null;

  /// The bot token belongs in the path (`/bot<token>/<method>`): the Bot API has
  /// no Bearer authentication, so a token sent only as a header is rejected
  /// before the method is even read.
  Uri _method(String token, String method) =>
      Uri.parse('$_apiBaseUrl/bot$token/$method');

  TelegramResult _classify(int statusCode) {
    switch (statusCode) {
      case 200:
        return TelegramResult.success;
      case 401:
        return TelegramResult.invalidToken;
      case 413:
        return TelegramResult.fileTooLarge;
      case 400:
      case 403:
        return TelegramResult.invalidChatId;
      default:
        return TelegramResult.unknownError;
    }
  }

  Future<TelegramResult> _run(
    Future<TelegramResult> Function() request, {
    required Duration timeout,
  }) async {
    try {
      final result = await request().timeout(timeout);
      state = result;
      return result;
    } on TimeoutException {
      state = TelegramResult.networkError;
      return TelegramResult.networkError;
    } on SocketException {
      state = TelegramResult.networkError;
      return TelegramResult.networkError;
    } on http.ClientException {
      state = TelegramResult.networkError;
      return TelegramResult.networkError;
    } catch (_) {
      state = TelegramResult.unknownError;
      return TelegramResult.unknownError;
    }
  }

  Future<TelegramResult> testConnection() {
    final settings = ref.read(periodicBackupSettingStateProvider);
    final token = settings.telegramBotToken;
    final chatId = settings.telegramChatId;

    if (token.isEmpty || chatId.isEmpty) {
      return Future.value(TelegramResult.invalidToken);
    }

    return _run(() async {
      final response = await http.post(
        _method(token, 'sendMessage'),
        body: {
          'chat_id': chatId,
          'text':
              '✅ Connection test successful!\nBoorusphere backup bot is ready.',
        },
      );
      return _classify(response.statusCode);
    }, timeout: _testTimeout);
  }

  Future<TelegramResult> sendBackupFile(File file) async {
    final settings = ref.read(periodicBackupSettingStateProvider);
    final token = settings.telegramBotToken;
    final chatId = settings.telegramChatId;

    if (token.isEmpty || chatId.isEmpty) {
      return TelegramResult.invalidToken;
    }

    final fileSize = await file.length();
    if (fileSize > _maxFileSize) {
      state = TelegramResult.fileTooLarge;
      return TelegramResult.fileTooLarge;
    }

    return _run(() async {
      final client = http.Client();
      try {
        final request = http.MultipartRequest(
          'POST',
          _method(token, 'sendDocument'),
        );
        request.fields['chat_id'] = chatId;
        request.fields['caption'] =
            '📦 Boorusphere Backup\n📅 ${DateTime.now().toIso8601String()}';
        request.files.add(
          await http.MultipartFile.fromPath('document', file.path),
        );

        final streamed = await client.send(request);
        final response = await http.Response.fromStream(streamed);
        return _classify(response.statusCode);
      } finally {
        client.close();
      }
    }, timeout: _uploadTimeout);
  }
}
