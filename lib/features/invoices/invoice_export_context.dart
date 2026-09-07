import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/models/invoice.dart';
import 'package:vortice_app/models/part.dart';

class InvoiceExportContext {
  final Invoice? currentInvoice;
  final String? clientName;
  final String? clientEmail;
  final String? clientPhone;
  final String? workOrderTitle;
  final String? assetName;
  final String? assetMakeModel;
  final String? assetSerialNumber;
  final List<Part> invoiceParts;

  const InvoiceExportContext({
    this.currentInvoice,
    this.clientName,
    this.clientEmail,
    this.clientPhone,
    this.workOrderTitle,
    this.assetName,
    this.assetMakeModel,
    this.assetSerialNumber,
    this.invoiceParts = const [],
  });

  String get billingLabel => _fallback(clientName, 'Client unavailable');

  String get workOrderLabel =>
      _fallback(workOrderTitle, 'Work order unavailable');

  String get assetLabel {
    final parts = [
      assetName,
      assetMakeModel,
      if (assetSerialNumber != null) 'S/N $assetSerialNumber',
    ].whereType<String>().where((value) => value.trim().isNotEmpty).toList();

    return parts.isEmpty ? 'Asset unavailable' : parts.join(' - ');
  }
}

class InvoiceExportContextService {
  const InvoiceExportContextService._();

  static Future<InvoiceExportContext> load(Invoice invoice) async {
    // Re-read through RLS before exporting so a stale screen cannot export
    // after access is revoked. Never rebuild issued documents from live parts.
    final current = await supabase
        .from(AppConstants.tInvoices)
        .select()
        .eq('id', invoice.id)
        .single();
    return fromSnapshot(Invoice.fromJson(current));
  }

  static InvoiceExportContext fromSnapshot(Invoice invoice) {
    final snapshot = invoice.exportSnapshot;
    if (snapshot == null) {
      throw StateError(
        'Invoice snapshot unavailable. Refresh before exporting.',
      );
    }
    return InvoiceExportContext(
      currentInvoice: invoice,
      clientName: snapshot['client_name'] as String?,
      clientEmail: snapshot['client_email'] as String?,
      clientPhone: snapshot['client_phone'] as String?,
      workOrderTitle: snapshot['work_order_title'] as String?,
      assetName: snapshot['asset_name'] as String?,
      assetMakeModel: snapshot['asset_make_model'] as String?,
      assetSerialNumber: snapshot['asset_serial_number'] as String?,
      invoiceParts: (snapshot['parts'] as List? ?? const [])
          .map((part) => Part.fromJson(Map<String, dynamic>.from(part as Map)))
          .toList(),
    );
  }
}

String _fallback(String? value, String fallback) =>
    value == null || value.trim().isEmpty ? fallback : value.trim();
