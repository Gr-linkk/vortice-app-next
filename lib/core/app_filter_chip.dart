import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';

/// FilterChip does not use ChipTheme.secondaryLabelStyle for selected text.
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({super.key, required this.label, required this.selected, required this.onSelected});
  final Widget label;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) => FilterChip(
    label: label,
    selected: selected,
    onSelected: onSelected,
    labelStyle: Theme.of(context).chipTheme.labelStyle?.copyWith(
      color: selected ? context.appColors.onPrimary : context.appColors.textPrimary,
    ),
  );
}
