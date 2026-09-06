import 'package:vortice_app/l10n/app_localizations.dart';

String? validateWorkOrderHours(
  String? text,
  AppLocalizations l10n, {
  bool required = false,
}) {
  final value = text?.trim() ?? '';
  if (value.isEmpty) return required ? l10n.fieldRequired : null;
  final number = double.tryParse(value);
  if (number == null || !number.isFinite || number < 0) {
    return l10n.localeName.startsWith('es')
        ? 'Introduce un número válido igual o mayor que cero.'
        : 'Enter a valid number that is zero or greater.';
  }
  return null;
}
