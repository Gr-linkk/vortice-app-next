import 'package:freezed_annotation/freezed_annotation.dart';

part 'hour_log.freezed.dart';
part 'hour_log.g.dart';

@freezed
abstract class HourLog with _$HourLog {
  const factory HourLog({
    required String id,
    @JsonKey(name: 'engine_id') required String engineId,
    @JsonKey(name: 'logged_by') required String loggedBy,
    required double hours,
    String? source,
    String? notes,
    @JsonKey(name: 'logged_at') DateTime? createdAt,
  }) = _HourLog;

  factory HourLog.fromJson(Map<String, dynamic> json) => _$HourLogFromJson(json);
}
