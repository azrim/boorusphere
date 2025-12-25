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

@riverpod
class TelegramBackupService extends _$TelegramBackupService {
  static const _baseUrl = 'https://api.telegram.org/bot';
  static const _maxFileSize = 50 * 1024 * 1024; // 50MB limit for Telegram

  @override
  TelegramResult? build() => null;

  String _getBotUrl(String token, String method) => '$_baseUrl$token/$method';

  Future<TelegramResult> testConnection() async {
    final settings = ref.read(periodicBackupSettingStateProvider);
    final token = settings.telegramBotToken;
    final chatId = settings.telegramChatId;

    if (token.isEmpty || chatId.isEmpty) {
      return TelegramResult.invalidToken;
    }

    try {
      // Test by sending a simple message
      final response = await http.post(
        Uri.parse(_getBotUrl(token, 'sendMessage')),
        body: {
          'chat_id': chatId,
          'text':
              '✅ Connection test successful!\nBoorusphere backup bot is ready.',
        },
      );

      if (response.statusCode == 200) {
        state = TelegramResult.success;
        return TelegramResult.success;
      } else if (response.statusCode == 401) {
        state = TelegramResult.invalidToken;
        return TelegramResult.invalidToken;
      } else if (response.statusCode == 400) {
        state = TelegramResult.invalidChatId;
        return TelegramResult.invalidChatId;
      } else {
        state = TelegramResult.unknownError;
        return TelegramResult.unknownError;
      }
    } on SocketException {
      state = TelegramResult.networkError;
      return TelegramResult.networkError;
    } catch (e) {
      state = TelegramResult.unknownError;
      return TelegramResult.unknownError;
    }
  }

  Future<TelegramResult> sendBackupFile(File file) async {
    final settings = ref.read(periodicBackupSettingStateProvider);
    final token = settings.telegramBotToken;
    final chatId = settings.telegramChatId;

    if (token.isEmpty || chatId.isEmpty) {
      return TelegramResult.invalidToken;
    }

    // Check file size
    final fileSize = await file.length();
    if (fileSize > _maxFileSize) {
      state = TelegramResult.fileTooLarge;
      return TelegramResult.fileTooLarge;
    }

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(_getBotUrl(token, 'sendDocument')),
      );

      request.fields['chat_id'] = chatId;
      request.fields['caption'] =
          '📦 Boorusphere Backup\n📅 ${DateTime.now().toIso8601String()}';

      request.files.add(await http.MultipartFile.fromPath(
        'document',
        file.path,
      ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        state = TelegramResult.success;
        return TelegramResult.success;
      } else if (response.statusCode == 401) {
        state = TelegramResult.invalidToken;
        return TelegramResult.invalidToken;
      } else if (response.statusCode == 400) {
        state = TelegramResult.invalidChatId;
        return TelegramResult.invalidChatId;
      } else {
        state = TelegramResult.unknownError;
        return TelegramResult.unknownError;
      }
    } on SocketException {
      state = TelegramResult.networkError;
      return TelegramResult.networkError;
    } catch (e) {
      state = TelegramResult.unknownError;
      return TelegramResult.unknownError;
    }
  }
}
