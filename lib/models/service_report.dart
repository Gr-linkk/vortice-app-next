import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:vortice_app/sync/sync_status.dart';

part 'service_report.freezed.dart';
part 'service_report.g.dart';

@freezed
abstract class ServiceReport with _$ServiceReport {
  const factory ServiceReport({
    required String id,
    @JsonKey(name: 'work_order_id') required String workOrderId,
    String? complaint,
    String? cause,
    String? correction,
    String? collateral,
    String? comments,
    @JsonKey(name: 'tech_signature_url') String? techSignatureUrl,
    @JsonKey(name: 'signed_at') DateTime? signedAt,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
    @JsonKey(name: 'sync_status')
    @Default(SyncStatusValues.synced)
    String syncStatus,
    @JsonKey(name: 'last_synced_at') DateTime? lastSyncedAt,
    @JsonKey(name: 'last_error') String? lastError,
  }) = _ServiceReport;

  factory ServiceReport.fromJson(Map<String, dynamic> json) =>
      _$ServiceReportFromJson(json);
}
