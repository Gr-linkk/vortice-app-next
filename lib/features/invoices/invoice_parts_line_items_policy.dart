/// Invoice parts presentation rules for walkthrough backlog A007.
class InvoicePartsLineItemsPolicy {
  const InvoicePartsLineItemsPolicy._();

  /// Intended: each logged part becomes its own invoice line on detail/export.
  static bool detailShowsItemizedPartsLines() => false;

  static bool exportShowsItemizedPartsLines() => false;
}
