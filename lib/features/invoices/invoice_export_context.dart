import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/models/invoice.dart';

class InvoiceExportContext {
  final String? clientName;
  final String? clientEmail;
  final String? clientPhone;
  final String? workOrderTitle;
  final String? assetName;
  final String? assetMakeModel;
  final String? assetSerialNumber;

  const InvoiceExportContext({
    this.clientName,
    this.clientEmail,
    this.clientPhone,
    this.workOrderTitle,
    this.assetName,
    this.assetMakeModel,
    this.assetSerialNumber,
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
    String? clientName;
    String? clientEmail;
    String? clientPhone;
    String? workOrderTitle;
    String? assetId;
    String? assetName;
    String? assetMakeModel;
    String? assetSerialNumber;

    try {
      final profile = await supabase
          .from(AppConstants.tProfiles)
          .select('full_name,email,phone')
          .eq('id', invoice.clientId)
          .maybeSingle();
      clientName = _trimToNull(profile?['full_name'] as String?);
      clientEmail = _trimToNull(profile?['email'] as String?);
      clientPhone = _trimToNull(profile?['phone'] as String?);
    } catch (_) {
      // Export should still succeed if optional context is unavailable.
    }

    try {
      final workOrder = await supabase
          .from(AppConstants.tWorkOrders)
          .select('title,asset_id')
          .eq('id', invoice.workOrderId)
          .maybeSingle();
      workOrderTitle = _trimToNull(workOrder?['title'] as String?);
      assetId = _trimToNull(workOrder?['asset_id'] as String?);
    } catch (_) {
      // Export should still succeed if optional context is unavailable.
    }

    if (assetId != null) {
      try {
        final asset = await supabase
            .from(AppConstants.tAssets)
            .select('name,make,model,serial_number')
            .eq('id', assetId)
            .maybeSingle();
        assetName = _trimToNull(asset?['name'] as String?);
        final make = _trimToNull(asset?['make'] as String?);
        final model = _trimToNull(asset?['model'] as String?);
        assetMakeModel = [make, model]
            .whereType<String>()
            .where((value) => value.isNotEmpty)
            .join(' ');
        assetMakeModel = _trimToNull(assetMakeModel);
        assetSerialNumber = _trimToNull(asset?['serial_number'] as String?);
      } catch (_) {
        // Export should still succeed if optional context is unavailable.
      }
    }

    return InvoiceExportContext(
      clientName: clientName,
      clientEmail: clientEmail,
      clientPhone: clientPhone,
      workOrderTitle: workOrderTitle,
      assetName: assetName,
      assetMakeModel: assetMakeModel,
      assetSerialNumber: assetSerialNumber,
    );
  }
}

String _fallback(String? value, String fallback) =>
    value == null || value.trim().isEmpty ? fallback : value.trim();

String? _trimToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
