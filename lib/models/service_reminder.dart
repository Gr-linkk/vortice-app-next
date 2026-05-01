import 'package:freezed_annotation/freezed_annotation.dart';

part 'service_reminder.freezed.dart';
part 'service_reminder.g.dart';

@freezed
class ServiceReminder with _$ServiceReminder {
  const factory ServiceReminder({
    required String id,
    @JsonKey(name: 'asset_id') required String assetId,
    @JsonKey(name: 'engine_id') String? engineId,
    @JsonKey(name: 'interval_hours') required int intervalHours,
    @JsonKey(name: 'due_at_hours') required double dueAtHours,
    @JsonKey(name: 'threshold_50hr_sent') @Default(false) bool threshold50hrSent,
    @JsonKey(name: 'threshold_10hr_sent') @Default(false) bool threshold10hrSent,
    @JsonKey(name: 'threshold_due_sent') @Default(false) bool thresholdDueSent,
    @Default(false) bool acknowledged,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _ServiceReminder;

  factory ServiceReminder.fromJson(Map<String, dynamic> json) => _$ServiceReminderFromJson(json);
}
