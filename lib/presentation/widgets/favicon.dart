import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class Favicon extends StatelessWidget {
  const Favicon({
    super.key,
    required this.url,
    this.size,
    this.iconSize,
    this.shape,
  });

  final String url;
  final double? size;
  final double? iconSize;
  final BoxShape? shape;

  String get faviconUrl {
    final uri = url.toUri();
    if (!uri.hasAuthority) return '';
    return 'https://icons.duckduckgo.com/ip3/${uri.host}.ico';
  }

  @override
  Widget build(BuildContext context) {
    final fallbackWidget = Icon(
      Icons.public,
      size: iconSize ?? context.iconTheme.size,
    );
    return SizedBox(
      width: size ?? context.iconTheme.size,
      height: size ?? context.iconTheme.size,
      child: Center(
        child: faviconUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: faviconUrl,
                width: iconSize ?? context.iconTheme.size,
                height: iconSize ?? context.iconTheme.size,
                fit: BoxFit.contain,
                imageBuilder: shape == null
                    ? null
                    : (context, provider) => Container(
                        decoration: BoxDecoration(
                          shape: shape!,
                          image: DecorationImage(
                            image: provider,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                placeholder: (context, _) => fallbackWidget,
                errorWidget: (context, _, __) => fallbackWidget,
              )
            : fallbackWidget,
      ),
    );
  }
}
