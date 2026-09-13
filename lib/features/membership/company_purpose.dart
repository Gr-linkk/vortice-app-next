import 'package:flutter/material.dart';

enum CompanyPurpose {
  fleet,
  service,
  both;

  bool get providesService => this != fleet;
  String label(bool es) => switch (this) {
    fleet => es ? 'Mantener nuestros equipos' : 'Maintaining our own equipment',
    service =>
      es
          ? 'Trabajar en equipos de clientes'
          : 'Working on customers’ equipment',
    both => es ? 'Ambos' : 'Both',
  };
  static CompanyPurpose? parse(String? value) =>
      values.where((item) => item.name == value).firstOrNull;
}

class CompanyPurposePicker extends StatelessWidget {
  const CompanyPurposePicker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.spanish,
  });
  final CompanyPurpose? value;
  final ValueChanged<CompanyPurpose>? onChanged;
  final bool spanish;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        spanish
            ? '¿Para qué usará tu empresa la aplicación?'
            : 'What will your company use the app for?',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      for (final purpose in CompanyPurpose.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton(
            key: ValueKey('company-purpose-${purpose.name}'),
            onPressed: onChanged == null ? null : () => onChanged!(purpose),
            style: OutlinedButton.styleFrom(
              alignment: AlignmentDirectional.centerStart,
              padding: const EdgeInsets.all(16),
              backgroundColor: value == purpose
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : null,
              side: BorderSide(
                color: value == purpose
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Semantics(
              selected: value == purpose,
              child: Row(
                children: [
                  Icon(
                    value == purpose
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(purpose.label(spanish))),
                ],
              ),
            ),
          ),
        ),
      Text(
        spanish
            ? 'Todas las opciones incluyen tus propios equipos y mantenimiento. El trabajo para clientes añade trabajos para otras empresas.'
            : 'Every option includes your own equipment and maintenance. Customer work adds jobs for other companies.',
      ),
    ],
  );
}
