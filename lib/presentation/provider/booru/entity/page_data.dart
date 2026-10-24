import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'page_data.freezed.dart';

@freezed
abstract class PageData with _$PageData {
  const factory PageData({
    @Default(PageOption(clear: true)) PageOption option,
    @Default(<Post>[]) List<Post> posts,
    // 1-based index of the displayed page.
    @Default(1) int pageIndex,
    // Whether the server may still have another page after this one.
    @Default(false) bool hasNext,
  }) = _PageData;

  const PageData._();

  bool get hasPrev => pageIndex > 1;
}
