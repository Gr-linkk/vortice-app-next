import 'package:flutter/material.dart';
import 'invoice_detail_support.dart';
import 'package:vortice_app/core/theme.dart';

class InvoiceDetailCurrencyToggle extends StatelessWidget {
  final InvoiceCurrency currency;
  final ValueChanged<InvoiceCurrency> onChanged;

  const InvoiceDetailCurrencyToggle({
    super.key,
    required this.currency,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in InvoiceCurrency.values)
          InvoiceDetailCurrencyButton(
            label: value.code,
            flag: switch (value) {
              InvoiceCurrency.usd => '🇺🇸',
              InvoiceCurrency.mxn => '🇲🇽',
              InvoiceCurrency.cad => '🇨🇦',
            },
            selected: currency == value,
            onTap: () => onChanged(value),
          ),
      ],
    );
  }
}

class InvoiceDetailCurrencyButton extends StatelessWidget {
  final String label;
  final String flag;
  final bool selected;
  final VoidCallback onTap;

  const InvoiceDetailCurrencyButton({
    super.key,
    required this.label,
    required this.flag,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? context.appColors.primary
              : context.appColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? context.appColors.primary
                : context.appColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          '$flag $label',
          style: TextStyle(
            color: selected
                ? context.appColors.onPrimary
                : context.appColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
