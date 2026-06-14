import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/models/work_order.dart';
import 'package:vortice_app/models/part.dart';
import 'package:vortice_app/models/work_order_assignment.dart';

/// Invoice calculation and generation service
class InvoiceService {
  InvoiceService._();

  static const double _consumablesPct = 0.05; // 5% of labour
  static const double _ivaPct = 0.16; // 16% IVA
  static const double fallbackExchangeRate = 17.50;

  /// Fetches the current USD to MXN exchange rate from exchangerate-api.com
  static Future<ExchangeRateResult> fetchExchangeRateResult() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.exchangerate-api.com/v4/latest/USD'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rates = data['rates'] as Map<String, dynamic>;
        return ExchangeRateResult.live((rates['MXN'] as num).toDouble());
      }
    } catch (_) {
      // Fallback to a reasonable default if API fails
    }
    return const ExchangeRateResult.fallback(fallbackExchangeRate);
  }

  static Future<double> fetchExchangeRate() async =>
      (await fetchExchangeRateResult()).rate;

  /// Generates a locally unique invoice number without relying on a count query.
  static Future<String> generateInvoiceNumber({DateTime? now}) async =>
      formatInvoiceNumber(now ?? DateTime.now());

  static String formatInvoiceNumber(DateTime now) {
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');

    return 'INV-${now.year}'
        '${two(now.month)}'
        '${two(now.day)}-'
        '${two(now.hour)}'
        '${two(now.minute)}'
        '${two(now.second)}-'
        '${three(now.millisecond)}';
  }

  /// Calculates all invoice amounts from a work order
  static Future<InvoiceCalculation> calculateFromWorkOrder(
      String workOrderId) async {
    // Fetch work order
    final woData = await supabase
        .from(AppConstants.tWorkOrders)
        .select()
        .eq('id', workOrderId)
        .single();
    final workOrder = WorkOrder.fromJson(woData);

    // Fetch parts for this work order
    final partsData = await supabase
        .from(AppConstants.tParts)
        .select()
        .eq('work_order_id', workOrderId);
    final parts = (partsData as List)
        .map((e) => Part.fromJson(e as Map<String, dynamic>))
        .toList();

    // Fetch multi-tech assignments
    final assignmentsData = await supabase
        .from('work_order_assignments')
        .select()
        .eq('work_order_id', workOrderId);
    final assignments = (assignmentsData as List)
        .map((e) => WorkOrderAssignment.fromJson(e as Map<String, dynamic>))
        .toList();

    // Labour calculation — multi-tech or single-tech fallback
    double labourHours;
    double billableRate;
    double labourTotal;

    final techAssignments = assignments.where((a) => a.role == 'tech').toList();
    if (techAssignments.isNotEmpty) {
      labourHours = 0;
      labourTotal = 0;
      for (final assignment in techAssignments) {
        final hrs = assignment.hoursLogged ?? 0;
        final rate =
            assignment.billableRate ?? AppConstants.defaultBillableRate;
        labourHours += hrs;
        labourTotal += hrs * rate;
      }
      billableRate = labourHours > 0
          ? labourTotal / labourHours
          : AppConstants.defaultBillableRate;
    } else {
      // Fallback: use work order fields for single-tech jobs
      labourHours = workOrder.labourHours ?? 0;
      billableRate = workOrder.billableRate ?? AppConstants.defaultBillableRate;
      labourTotal = labourHours * billableRate;
    }

    // Parts calculation (cost + markup)
    double partsCost = 0;
    double partsMarkup = 0;
    for (final part in parts) {
      final lineTotal = part.quantity * part.unitCost;
      partsCost += lineTotal;
      partsMarkup += lineTotal * (part.markupPct / 100);
    }
    final partsTotal = partsCost + partsMarkup;

    // Consumables (5% of labour)
    final consumablesTotal = labourTotal * _consumablesPct;

    // Subtotal
    final subtotal = labourTotal + partsTotal + consumablesTotal;

    // IVA
    final ivaTotal = subtotal * _ivaPct;

    // Total
    final totalUsd = subtotal + ivaTotal;

    // Exchange rate
    final exchangeRate = await fetchExchangeRate();
    final totalMxn = totalUsd * exchangeRate;

    return InvoiceCalculation(
      workOrderId: workOrderId,
      clientId: workOrder.clientId,
      labourHours: labourHours,
      billableRate: billableRate,
      labourTotal: labourTotal,
      partsCost: partsCost,
      partsMarkup: partsMarkup,
      partsTotal: partsTotal,
      consumablesTotal: consumablesTotal,
      subtotal: subtotal,
      ivaPct: _ivaPct * 100,
      ivaTotal: ivaTotal,
      totalUsd: totalUsd,
      exchangeRate: exchangeRate,
      totalMxn: totalMxn,
      parts: parts,
    );
  }

  /// Creates an invoice in the database from a work order
  static Future<String> createFromWorkOrder(String workOrderId) async {
    final calc = await calculateFromWorkOrder(workOrderId);
    final invoiceNumber = await generateInvoiceNumber();

    final result = await supabase
        .from(AppConstants.tInvoices)
        .insert({
          'work_order_id': calc.workOrderId,
          'client_id': calc.clientId,
          'invoice_number': invoiceNumber,
          'status': 'draft',
          'labour_hours': calc.labourHours,
          'billable_rate_usd': calc.billableRate,
          'labour_total_usd': calc.labourTotal,
          'parts_total_usd': calc.partsTotal,
          'consumables_total_usd': calc.consumablesTotal,
          'subtotal_usd': calc.subtotal,
          'iva_pct': calc.ivaPct,
          'iva_total_usd': calc.ivaTotal,
          'total_usd': calc.totalUsd,
          'exchange_rate': calc.exchangeRate,
          'total_mxn': calc.totalMxn,
        })
        .select('id')
        .single();

    // Update work order status to invoiced
    await supabase.from(AppConstants.tWorkOrders).update({
      'status': 'invoiced',
    }).eq('id', workOrderId);

    return result['id'] as String;
  }

  /// Updates an existing invoice with new line item values
  static Future<void> updateInvoice(
    String invoiceId, {
    double? labourHours,
    double? billableRate,
    double? labourTotal,
    double? partsTotal,
    double? consumablesTotal,
    String? notes,
  }) async {
    // Recalculate totals if any line item changes
    final invoiceData = await supabase
        .from(AppConstants.tInvoices)
        .select()
        .eq('id', invoiceId)
        .single();

    final currentLabourTotal =
        labourTotal ?? invoiceData['labour_total_usd'] as double?;
    final currentPartsTotal =
        partsTotal ?? invoiceData['parts_total_usd'] as double?;
    final currentConsumablesTotal =
        consumablesTotal ?? invoiceData['consumables_total_usd'] as double?;

    final subtotal = (currentLabourTotal ?? 0) +
        (currentPartsTotal ?? 0) +
        (currentConsumablesTotal ?? 0);
    final ivaTotal = subtotal * _ivaPct;
    final totalUsd = subtotal + ivaTotal;

    final exchangeRate =
        invoiceData['exchange_rate'] as double? ?? await fetchExchangeRate();
    final totalMxn = totalUsd * exchangeRate;

    await supabase.from(AppConstants.tInvoices).update({
      if (labourHours != null) 'labour_hours': labourHours,
      if (billableRate != null) 'billable_rate_usd': billableRate,
      if (labourTotal != null) 'labour_total_usd': labourTotal,
      if (partsTotal != null) 'parts_total_usd': partsTotal,
      if (consumablesTotal != null) 'consumables_total_usd': consumablesTotal,
      'subtotal_usd': subtotal,
      'iva_total_usd': ivaTotal,
      'total_usd': totalUsd,
      'total_mxn': totalMxn,
      if (notes != null) 'notes': notes,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', invoiceId);
  }

  /// Refreshes exchange rate for an invoice
  static Future<ExchangeRateResult> refreshExchangeRate(
      String invoiceId) async {
    final exchangeRate = await fetchExchangeRateResult();
    final invoiceData = await supabase
        .from(AppConstants.tInvoices)
        .select('total_usd')
        .eq('id', invoiceId)
        .single();

    final totalUsd = invoiceData['total_usd'] as double? ?? 0;
    final totalMxn = totalUsd * exchangeRate.rate;

    await supabase.from(AppConstants.tInvoices).update({
      'exchange_rate': exchangeRate.rate,
      'total_mxn': totalMxn,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', invoiceId);

    return exchangeRate;
  }
}

class ExchangeRateResult {
  final double rate;
  final bool isFallback;

  const ExchangeRateResult._({
    required this.rate,
    required this.isFallback,
  });

  const ExchangeRateResult.live(double rate)
      : this._(rate: rate, isFallback: false);

  const ExchangeRateResult.fallback(double rate)
      : this._(rate: rate, isFallback: true);
}

/// Holds all calculated invoice values
class InvoiceCalculation {
  final String workOrderId;
  final String clientId;
  final double labourHours;
  final double billableRate;
  final double labourTotal;
  final double partsCost;
  final double partsMarkup;
  final double partsTotal;
  final double consumablesTotal;
  final double subtotal;
  final double ivaPct;
  final double ivaTotal;
  final double totalUsd;
  final double exchangeRate;
  final double totalMxn;
  final List<Part> parts;

  const InvoiceCalculation({
    required this.workOrderId,
    required this.clientId,
    required this.labourHours,
    required this.billableRate,
    required this.labourTotal,
    required this.partsCost,
    required this.partsMarkup,
    required this.partsTotal,
    required this.consumablesTotal,
    required this.subtotal,
    required this.ivaPct,
    required this.ivaTotal,
    required this.totalUsd,
    required this.exchangeRate,
    required this.totalMxn,
    required this.parts,
  });
}
