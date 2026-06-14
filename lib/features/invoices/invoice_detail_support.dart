import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/models/invoice.dart';
import 'package:vortice_app/models/profile.dart';

Color invoiceStatusColor(InvoiceStatus status) => switch (status) {
      InvoiceStatus.paid => AppColors.success,
      InvoiceStatus.sent => AppColors.warning,
      InvoiceStatus.draft => AppColors.textSecondary,
      InvoiceStatus.voided => AppColors.error,
    };

bool isInvoiceEditingLocked(InvoiceStatus status) =>
    status == InvoiceStatus.sent || status == InvoiceStatus.paid;

bool canMarkInvoicePaidFromList({
  required UserRole? role,
  required InvoiceStatus status,
}) =>
    role == UserRole.owner &&
    status != InvoiceStatus.paid &&
    status != InvoiceStatus.voided;

String formatInvoiceCurrency(double? value, {bool mxn = false}) {
  if (value == null) return mxn ? '\$0.00 MXN' : '\$0.00 USD';
  return mxn
      ? '\$${value.toStringAsFixed(2)} MXN'
      : '\$${value.toStringAsFixed(2)} USD';
}

double convertInvoiceAmount(
  double? usd, {
  required bool showMxn,
  double? exchangeRate,
}) {
  if (usd == null) return 0;
  return showMxn ? usd * (exchangeRate ?? 1) : usd;
}

double computeLabourTotal(double? hours, double? rate) =>
    (hours ?? 0) * (rate ?? 0);

double computeConsumablesTotal(double hours, double rate) =>
    hours * rate * 0.05;

String formatConsumablesTotal(double hours, double rate) =>
    computeConsumablesTotal(hours, rate).toStringAsFixed(2);

String formatInvoiceDate(DateTime? date) {
  if (date == null) return '-';
  return '${date.day}/${date.month}/${date.year}';
}
