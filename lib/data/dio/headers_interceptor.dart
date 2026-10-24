import 'package:boorusphere/data/dio/headers_factory.dart';
import 'package:boorusphere/domain/repository/env_repo.dart';
import 'package:dio/dio.dart';

class HeadersInterceptor extends Interceptor {
  HeadersInterceptor(this.envRepo);

  final EnvRepo envRepo;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final defaults = HeadersFactory.builder()
        .setReferer(options.path)
        .setUserAgent(envRepo.appVersion)
        .build();

    // These are defaults for requests that carry none. A caller that sets its
    // own User-Agent or Referer keeps it: the batch download points the
    // Referer at the post page, and the path of the file request would
    // replace it with the file URL a hotlink-protected booru rejects.
    for (final entry in defaults.entries) {
      options.headers.putIfAbsent(entry.key, () => entry.value);
    }
    super.onRequest(options, handler);
  }
}
