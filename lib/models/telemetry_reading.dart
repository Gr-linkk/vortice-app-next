import 'package:freezed_annotation/freezed_annotation.dart';

part 'telemetry_reading.freezed.dart';
part 'telemetry_reading.g.dart';

@freezed
class TelemetryReading with _$TelemetryReading {
  const factory TelemetryReading({
    required String id,
    @JsonKey(name: 'engine_id') required String engineId,
    required DateTime ts,

    // Core engine parameters
    double? rpm,
    @JsonKey(name: 'coolant_temp') double? coolantTemp,
    @JsonKey(name: 'oil_pressure') double? oilPressure,
    @JsonKey(name: 'battery_v') double? batteryV,
    @JsonKey(name: 'boost_psi') double? boostPsi,
    @JsonKey(name: 'throttle_pct') double? throttlePct,
    @JsonKey(name: 'fuel_rate') double? fuelRate,
    @JsonKey(name: 'torque_pct') double? torquePct,

    // Engine hours
    @JsonKey(name: 'engine_hours') double? engineHours,

    // Additional diagnostics
    @JsonKey(name: 'intake_temp') double? intakeTemp,
    @JsonKey(name: 'exhaust_temp') double? exhaustTemp,
    @JsonKey(name: 'oil_temp') double? oilTemp,
    @JsonKey(name: 'fuel_pressure') double? fuelPressure,
    @JsonKey(name: 'transmission_temp') double? transmissionTemp,
    @JsonKey(name: 'transmission_pressure') double? transmissionPressure,

    // Source tracking
    String? source,
    @JsonKey(name: 'device_id') String? deviceId,

    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _TelemetryReading;

  factory TelemetryReading.fromJson(Map<String, dynamic> json) =>
      _$TelemetryReadingFromJson(json);
}
