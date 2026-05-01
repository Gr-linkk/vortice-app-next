import 'package:freezed_annotation/freezed_annotation.dart';

part 'service_report.freezed.dart';
part 'service_report.g.dart';

@freezed
class ServiceReport with _$ServiceReport {
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
  }) = _ServiceReport;

  factory ServiceReport.fromJson(Map<String, dynamic> json) => _$ServiceReportFromJson(json);
}
