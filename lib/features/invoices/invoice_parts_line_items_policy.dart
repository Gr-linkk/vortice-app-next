/// Invoice parts presentation rules for walkthrough backlog A007.
class InvoicePartsLineItemsPolicy {
  const InvoicePartsLineItemsPolicy._();

  /// Each logged part becomes its own invoice line on detail/export.
  static bool detailShowsItemizedPartsLines() => true;

  static bool exportShowsItemizedPartsLines() => true;
}
