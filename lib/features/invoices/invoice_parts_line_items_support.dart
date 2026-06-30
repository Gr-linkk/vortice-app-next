import 'package:vortice_app/models/part.dart';

/// One invoice line derived from a logged work-order part.
class InvoicePartLineItem {
  final String description;
  final String? partNumber;
  final double quantity;
  final double unitCostUsd;
  final double markupPct;
  final double lineTotalUsd;

  const InvoicePartLineItem({
    required this.description,
    this.partNumber,
    required this.quantity,
    required this.unitCostUsd,
    required this.markupPct,
    required this.lineTotalUsd,
  });
}

List<InvoicePartLineItem> buildInvoicePartLineItems(List<Part> parts) {
  return parts.map(_partToLineItem).toList();
}

InvoicePartLineItem _partToLineItem(Part part) {
  final base = part.quantity * part.unitCost;
  final markup = base * (part.markupPct / 100);
  return InvoicePartLineItem(
    description: part.description,
    partNumber: part.partNumber,
    quantity: part.quantity,
    unitCostUsd: part.unitCost,
    markupPct: part.markupPct,
    lineTotalUsd: base + markup,
  );
}

double sumInvoicePartLineTotals(List<InvoicePartLineItem> items) =>
    items.fold(0.0, (sum, item) => sum + item.lineTotalUsd);

String formatInvoicePartLineDetail(InvoicePartLineItem item) {
  final qty = item.quantity == item.quantity.roundToDouble()
      ? item.quantity.toStringAsFixed(0)
      : item.quantity.toStringAsFixed(2);
  final unit = item.unitCostUsd.toStringAsFixed(2);
  final markup = item.markupPct.toStringAsFixed(0);
  return '$qty × \$$unit + $markup% markup';
}

String formatInvoicePartLineLabel(InvoicePartLineItem item) {
  final number = item.partNumber?.trim();
  if (number == null || number.isEmpty) return item.description;
  return '${item.description} ($number)';
}
