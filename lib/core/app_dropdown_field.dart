import 'package:flutter/material.dart';

/// Native form dropdowns share a compact selected value and readable menu rows.
/// The surrounding form owns the gap between fields.
class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    this.initialValue,
    required this.items,
    required this.onChanged,
    this.decoration = const InputDecoration(),
    this.validator,
    this.hint,
    this.dropdownColor,
    this.menuMaxHeight = 360,
    this.isExpanded = true,
    this.selectedItemBuilder,
  });

  final T? initialValue;
  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final FormFieldValidator<T>? validator;
  final Widget? hint;
  final Color? dropdownColor;
  final double menuMaxHeight;
  final bool isExpanded;
  final DropdownButtonBuilder? selectedItemBuilder;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
    initialValue: initialValue,
    isExpanded: isExpanded,
    itemHeight: null,
    menuMaxHeight: menuMaxHeight,
    borderRadius: BorderRadius.circular(12),
    dropdownColor:
        dropdownColor ?? Theme.of(context).inputDecorationTheme.fillColor,
    decoration: decoration.copyWith(
      errorMaxLines: decoration.errorMaxLines ?? 3,
      helperMaxLines: decoration.helperMaxLines ?? 3,
    ),
    hint: hint,
    validator: validator,
    onChanged: onChanged,
    selectedItemBuilder:
        selectedItemBuilder ??
        (context) => [
          for (final item in items ?? <DropdownMenuItem<T>>[])
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: DefaultTextStyle.merge(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: item.child,
              ),
            ),
        ],
    items: items
        ?.map(
          (item) => DropdownMenuItem<T>(
            value: item.value,
            enabled: item.enabled,
            onTap: item.onTap,
            alignment: item.alignment,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: item.child,
            ),
          ),
        )
        .toList(),
  );
}
