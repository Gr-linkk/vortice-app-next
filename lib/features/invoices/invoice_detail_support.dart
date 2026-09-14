import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/models/invoice.dart';
import 'package:vortice_app/models/profile.dart';

Color invoiceStatusColor(AppPalette colors, InvoiceStatus status) =>
    switch (status) {
      InvoiceStatus.paid => colors.success,
      InvoiceStatus.sent => colors.warning,
      InvoiceStatus.draft => colors.textSecondary,
      InvoiceStatus.voided => colors.error,
    };

String invoiceStatusLabel(InvoiceStatus status, {required bool spanish}) =>
    switch (status) {
      InvoiceStatus.draft => spanish ? 'Borrador' : 'Draft',
      InvoiceStatus.sent => spanish ? 'Emitida' : 'Issued',
      InvoiceStatus.paid => spanish ? 'Pagada' : 'Paid',
      InvoiceStatus.voided => spanish ? 'Anulada' : 'Voided',
    };

bool isInvoiceEditingLocked(InvoiceStatus status) =>
    status != InvoiceStatus.draft;

bool canMarkInvoicePaidFromList({
  required UserRole? role,
  required InvoiceStatus status,
}) => role == UserRole.owner && status == InvoiceStatus.sent;

enum InvoiceCurrency { usd, mxn, cad }

extension InvoiceCurrencyValues on InvoiceCurrency {
  String get code => name.toUpperCase();
  double? rate(Invoice invoice) => switch (this) {
    InvoiceCurrency.usd => 1,
    InvoiceCurrency.mxn => invoice.exchangeRate,
    InvoiceCurrency.cad => invoice.cadExchangeRate,
  };
  double? total(Invoice invoice) => switch (this) {
    InvoiceCurrency.usd => invoice.totalUsd,
    InvoiceCurrency.mxn => invoice.totalMxn,
    InvoiceCurrency.cad => invoice.totalCad,
  };
  String amount(double? usd, Invoice invoice) => formatInvoiceCurrency(
    rate(invoice) == null ? null : (usd ?? 0) * rate(invoice)!,
    currency: this,
  );
}

String formatInvoiceCurrency(
  double? value, {
  bool mxn = false,
  InvoiceCurrency? currency,
}) {
  final selected =
      currency ?? (mxn ? InvoiceCurrency.mxn : InvoiceCurrency.usd);
  if (value == null && currency != null) return '- ${selected.code}';
  return '\$${(value ?? 0).toStringAsFixed(2)} ${selected.code}';
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
