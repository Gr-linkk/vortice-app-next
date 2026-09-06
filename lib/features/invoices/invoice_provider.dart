import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/core/invoice_service.dart';
import 'package:vortice_app/features/work_orders/work_order_read_providers.dart';
import 'package:vortice_app/models/invoice.dart';

final invoicesProvider = FutureProvider<List<Invoice>>((ref) async {
  if (await ref.watch(profileProvider.future) == null) return [];
  final data = await supabase
      .from(AppConstants.tInvoices)
      .select()
      .order('created_at', ascending: false);
  return (data as List)
      .map((e) => Invoice.fromJson(e as Map<String, dynamic>))
      .toList();
});

final invoiceByIdProvider =
    FutureProvider.family<Invoice?, String>((ref, id) async {
  if (await ref.watch(profileProvider.future) == null) return null;
  final data = await supabase
      .from(AppConstants.tInvoices)
      .select()
      .eq('id', id)
      .maybeSingle();
  if (data == null) return null;
  return Invoice.fromJson(data);
});

class InvoiceController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  InvoiceController(this._ref) : super(const AsyncData(null));

  Future<bool> createInvoice(Map<String, dynamic> data) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tInvoices).insert(data);
      _ref.invalidate(invoicesProvider);
      success = true;
    });
    return success;
  }

  Future<bool> markAsPaid(String invoiceId) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tInvoices).update({
        'status': InvoiceStatus.paid.dbValue,
        'paid_at': DateTime.now().toIso8601String(),
      }).eq('id', invoiceId);
      _ref.invalidate(invoicesProvider);
      _ref.invalidate(invoiceByIdProvider(invoiceId));
      success = true;
    });
    return success;
  }

  Future<bool> updateStatus(String invoiceId, InvoiceStatus status) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tInvoices).update({
        'status': status.dbValue,
      }).eq('id', invoiceId);
      _ref.invalidate(invoicesProvider);
      _ref.invalidate(invoiceByIdProvider(invoiceId));
      success = true;
    });
    return success;
  }

  /// Generate invoice from work order with all calculations
  Future<String?> generateFromWorkOrder(String workOrderId) async {
    state = const AsyncLoading();
    String? invoiceId;
    state = await AsyncValue.guard(() async {
      invoiceId = await InvoiceService.createFromWorkOrder(workOrderId);
      _ref.invalidate(invoicesProvider);
      _ref.invalidate(workOrdersProvider);
      _ref.invalidate(workOrderByIdProvider(workOrderId));
    });
    return invoiceId;
  }

  /// Update invoice line items (owner can manually adjust)
  Future<bool> updateLineItems(
    String invoiceId, {
    double? labourHours,
    double? billableRate,
    double? labourTotal,
    double? partsTotal,
    double? consumablesTotal,
    String? notes,
  }) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await InvoiceService.updateInvoice(
        invoiceId,
        labourHours: labourHours,
        billableRate: billableRate,
        labourTotal: labourTotal,
        partsTotal: partsTotal,
        consumablesTotal: consumablesTotal,
        notes: notes,
      );
      _ref.invalidate(invoicesProvider);
      _ref.invalidate(invoiceByIdProvider(invoiceId));
      success = true;
    });
    return success;
  }

  /// Refresh exchange rate for an invoice
  Future<ExchangeRateResult?> refreshExchangeRate(String invoiceId) async {
    state = const AsyncLoading();
    ExchangeRateResult? result;
    state = await AsyncValue.guard(() async {
      result = await InvoiceService.refreshExchangeRate(invoiceId);
      _ref.invalidate(invoicesProvider);
      _ref.invalidate(invoiceByIdProvider(invoiceId));
    });
    return result;
  }
}

final invoiceControllerProvider =
    StateNotifierProvider<InvoiceController, AsyncValue<void>>((ref) {
  return InvoiceController(ref);
});
