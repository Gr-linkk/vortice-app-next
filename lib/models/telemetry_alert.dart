import 'package:freezed_annotation/freezed_annotation.dart';

part 'telemetry_alert.freezed.dart';
part 'telemetry_alert.g.dart';

enum TelemetryAlertType {
  @JsonValue('dtc')
  dtc,
  @JsonValue('threshold')
  threshold,
  @JsonValue('warning')
  warning,
  @JsonValue('critical')
  critical,
  @JsonValue('info')
  info;
}

enum AlertSeverity {
  @JsonValue('info')
  info,
  @JsonValue('warning')
  warning,
  @JsonValue('critical')
  critical;
}

@freezed
abstract class TelemetryAlert with _$TelemetryAlert {
  const factory TelemetryAlert({
    required String id,
    @JsonKey(name: 'asset_id') required String assetId,
    @JsonKey(name: 'engine_id') String? engineId,
    @JsonKey(name: 'alert_type') required TelemetryAlertType alertType,

    // J1939 DTC fields
    int? spn,
    int? fmi,

    // Threshold alert details
    String? parameter,
    double? value,
    double? threshold,
    String? comparison,

    // Alert metadata
    String? message,
    @JsonKey(defaultValue: AlertSeverity.warning)
    required AlertSeverity severity,

    // Status tracking
    @JsonKey(defaultValue: false) required bool acknowledged,
    @JsonKey(name: 'acknowledged_by') String? acknowledgedBy,
    @JsonKey(name: 'acknowledged_at') DateTime? acknowledgedAt,
    @JsonKey(defaultValue: false) required bool resolved,
    @JsonKey(name: 'resolved_at') DateTime? resolvedAt,

    // Source tracking
    String? source,
    @JsonKey(name: 'device_id') String? deviceId,
    @JsonKey(name: 'raw_data') Map<String, dynamic>? rawData,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _TelemetryAlert;

  factory TelemetryAlert.fromJson(Map<String, dynamic> json) =>
      _$TelemetryAlertFromJson(json);
}
