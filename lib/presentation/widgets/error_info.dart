import 'dart:async';
import 'dart:io';

import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

class ErrorInfo extends HookWidget {
  const ErrorInfo({
    super.key,
    this.error,
    this.stackTrace,
    this.textAlign = TextAlign.center,
    this.style,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.padding = const EdgeInsets.symmetric(vertical: 16),
  });

  final Object? error;
  final StackTrace? stackTrace;
  final TextAlign textAlign;
  final CrossAxisAlignment crossAxisAlignment;
  final TextStyle? style;
  final EdgeInsets padding;

  String describeError(BuildContext context) {
    final t = TranslationProvider.of(context).translations;
    dynamic e = error;
    String? host;
    if (e == null) {
      return t.error.unknown;
    }

    while (true) {
      if (e is HandshakeException) {
        return host != null
            ? t.error.insecureConnectionHost(host: host)
            : t.error.insecureConnection;
      } else if (e is HttpException || e is SocketException) {
        if (host == null && e is SocketException) {
          host = e.address?.host;
        }
        return host != null
            ? t.error.connectionFailedHost(host: host)
            : t.error.connectionFailed;
      } else if (e is TimeoutException) {
        return t.error.connectionTimeout;
      } else if (e is! DioException) {
        try {
          // let's try to obtain exception message
          return e.message;
        } catch (_) {
          return '$e';
        }
      }
      host = e.requestOptions.uri.host;
      e = e.error;
    }
  }

  bool get traceable =>
      stackTrace != null && error is! TimeoutException && error is! BooruError;

  @override
  Widget build(BuildContext context) {
    final showTrace = useState(false);
    toggleStacktrace() {
      showTrace.value = !showTrace.value;
    }

    return Padding(
      padding: padding,
      child: InkWell(
        onTap: traceable ? toggleStacktrace : null,
        child: Column(
          crossAxisAlignment: crossAxisAlignment,
          children: [
            DefaultTextStyle(
              style: style ?? DefaultTextStyle.of(context).style,
              child: Text(describeError(context), textAlign: textAlign),
            ),
            if (showTrace.value && stackTrace != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 8),
                    child: Text(
                      TranslationProvider.of(
                        context,
                      ).translations.error.stacktrace,
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 128),
                    child: SingleChildScrollView(
                      child: Text(stackTrace.toString()),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
