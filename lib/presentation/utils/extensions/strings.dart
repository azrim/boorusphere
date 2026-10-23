import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

extension StringExt on String {
  String withDioExceptionCode(DioException err) {
    final code = err.response?.statusCode ?? 0;
    return this + (code > 0 ? ' (HTTP $code)' : '');
  }

  /// Locale-aware uppercase for section labels. Dart's `toUpperCase` is
  /// locale-insensitive, which turns the dotted i into a plain I in Turkish
  /// and Azeri.
  String toUpperLocale(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    return language == 'tr' || language == 'az'
        ? replaceAll('i', 'İ').toUpperCase()
        : toUpperCase();
  }
}
