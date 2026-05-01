import 'package:freezed_annotation/freezed_annotation.dart';

part 'invoice.freezed.dart';
part 'invoice.g.dart';

enum InvoiceStatus {
  @JsonValue('draft') draft,
  @JsonValue('sent') sent,
  @JsonValue('paid') paid,
  @JsonValue('void') voided; // 'void' is a Dart keyword

  String get dbValue => switch (this) {
    InvoiceStatus.voided => 'void',
    _ => name,
  };
}

@freezed
class Invoice with _$Invoice {
  const factory Invoice({
    required String id,
    @JsonKey(name: 'work_order_id') required String workOrderId,
    @JsonKey(name: 'client_id') required String clientId,
    @JsonKey(name: 'invoice_number') required String invoiceNumber,
    @JsonKey(defaultValue: InvoiceStatus.draft) required InvoiceStatus status,
    @JsonKey(name: 'labour_hours') double? labourHours,
    @JsonKey(name: 'billable_rate_usd') double? billableRateUsd,
    @JsonKey(name: 'labour_total_usd') double? labourTotalUsd,
    @JsonKey(name: 'parts_total_usd') double? partsTotalUsd,
    @JsonKey(name: 'consumables_total_usd') double? consumablesTotalUsd,
    @JsonKey(name: 'subtotal_usd') double? subtotalUsd,
    @JsonKey(name: 'iva_pct') @Default(16.0) double ivaPct,
    @JsonKey(name: 'iva_total_usd') double? ivaTotalUsd,
    @JsonKey(name: 'total_usd') double? totalUsd,
    @JsonKey(name: 'exchange_rate') double? exchangeRate,
    @JsonKey(name: 'total_mxn') double? totalMxn,
    String? notes,
    @JsonKey(name: 'pdf_url') String? pdfUrl,
    @JsonKey(name: 'xlsx_url') String? xlsxUrl,
    @JsonKey(name: 'sent_at') DateTime? sentAt,
    @JsonKey(name: 'paid_at') DateTime? paidAt,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _Invoice;

  factory Invoice.fromJson(Map<String, dynamic> json) => _$InvoiceFromJson(json);
}
