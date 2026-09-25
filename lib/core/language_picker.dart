import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

String languageName(Locale locale) => switch (locale.languageCode) {
  'es' => 'Español',
  'fr' => 'Français',
  _ => 'English',
};

Future<void> showLanguagePicker(BuildContext context, WidgetRef ref) async {
  final selected = ref.read(localeProvider).languageCode;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Text(AppLocalizations.of(context).language),
      children: [
        for (final locale in AppLocalizations.supportedLocales)
          SimpleDialogOption(
            onPressed: () {
              ref.read(localeProvider.notifier).setLocale(locale);
              Navigator.of(dialogContext).pop();
            },
            child: Row(
              children: [
                Expanded(child: Text(languageName(locale))),
                if (locale.languageCode == selected)
                  const Icon(Icons.check, size: 20),
              ],
            ),
          ),
      ],
    ),
  );
}
