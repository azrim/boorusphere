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
    // Whether an earlier page can be reached. Tracked rather than derived from
    // [pageIndex]: a backward fetch comes back empty when every earlier page
    // was skipped, and the index alone would keep offering a dead control.
    @Default(false) bool hasPrev,
  }) = _PageData;

  const PageData._();
}
