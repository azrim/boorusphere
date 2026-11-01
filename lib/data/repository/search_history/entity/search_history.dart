import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hive_ce/hive.dart';

part 'search_history.freezed.dart';
part 'search_history.g.dart';

@freezed
@HiveType(typeId: 1, adapterName: 'SearchHistoryAdapter')
abstract class SearchHistory with _$SearchHistory {
  const factory SearchHistory({
    @HiveField(0, defaultValue: '') @Default('*') String query,
    @HiveField(1, defaultValue: '') @Default('') String server,
    // How many times this query has been searched. Entries written before the
    // field existed decode as 0, so old boxes and archives stay readable.
    @HiveField(2, defaultValue: 0) @Default(0) int count,
  }) = _SearchHistory;
  factory SearchHistory.fromJson(Map<String, dynamic> json) =>
      _$SearchHistoryFromJson(json);
}
