import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';

class InvoiceDetailCurrencyToggle extends StatelessWidget {
  final bool showMxn;
  final ValueChanged<bool> onChanged;

  const InvoiceDetailCurrencyToggle({
    super.key,
    required this.showMxn,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InvoiceDetailCurrencyButton(
          label: 'USD',
          flag: '\u{1F1FA}\u{1F1F8}',
          selected: !showMxn,
          onTap: () => onChanged(false),
        ),
        const SizedBox(width: 8),
        InvoiceDetailCurrencyButton(
          label: 'MXN',
          flag: '\u{1F1F2}\u{1F1FD}',
          selected: showMxn,
          onTap: () => onChanged(true),
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
          color: selected ? const Color(0xFF1E3A5F) : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          '$flag $label',
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
