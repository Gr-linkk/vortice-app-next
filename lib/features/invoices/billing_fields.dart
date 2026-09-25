import 'package:flutter/material.dart';

/// Full labels remain readable at phone width with large text. The floating
/// labels used elsewhere in the app shorten long company/tax names.
class BillingTextField extends StatelessWidget {
  const BillingTextField({
    super.key,
    required this.controller,
    required this.decoration,
    this.enabled = true,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.onChanged,
    this.validator,
  });
  final TextEditingController? controller;
  final InputDecoration decoration;
  final bool enabled;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        decoration.labelText ?? '',
        style: Theme.of(context).textTheme.labelLarge,
      ),
      const SizedBox(height: 6),
      Semantics(
        label: decoration.labelText,
        child: TextFormField(
          controller: controller,
          enabled: enabled,
          maxLines: maxLines,
          maxLength: maxLength,
          keyboardType: keyboardType,
          onChanged: onChanged,
          validator: validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: InputDecoration(
            helperText: decoration.helperText,
            helperMaxLines: 6,
            errorMaxLines: 5,
            counterText: '',
          ),
        ),
      ),
    ],
  );
}

class BillingDropdown extends StatelessWidget {
  const BillingDropdown({
    super.key,
    this.initialValue,
    required this.decoration,
    required this.items,
    required this.onChanged,
    this.validator,
    this.isExpanded = true,
  });
  final String? initialValue;
  final InputDecoration decoration;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?>? onChanged;
  final FormFieldValidator<String>? validator;
  final bool isExpanded;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        decoration.labelText ?? '',
        style: Theme.of(context).textTheme.labelLarge,
      ),
      const SizedBox(height: 6),
      Semantics(
        label: decoration.labelText,
        child: DropdownButtonFormField<String>(
          initialValue: initialValue,
          isExpanded: isExpanded,
          items: items,
          onChanged: onChanged,
          validator: validator,
          decoration: const InputDecoration(errorMaxLines: 5),
        ),
      ),
    ],
  );
}
