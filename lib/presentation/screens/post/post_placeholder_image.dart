import 'dart:ui';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class PostPlaceholderImage extends StatelessWidget {
  const PostPlaceholderImage({
    super.key,
    required this.post,
    required this.shouldBlur,
    this.headers,
  });

  final Post post;
  final bool shouldBlur;
  final Map<String, String>? headers;

  static final _blurFilter =
      ImageFilter.blur(sigmaX: 5, sigmaY: 5, tileMode: TileMode.decal);

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: post.previewFile,
      httpHeaders: headers,
      fit: BoxFit.contain,
      imageBuilder: shouldBlur
          ? (context, provider) => ImageFiltered(
                imageFilter: _blurFilter,
                child: Image(
                  image: provider,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                ),
              )
          : null,
      placeholder: (context, _) => const SizedBox.shrink(),
      errorWidget: (context, _, __) => const SizedBox.shrink(),
    );
  }
}
