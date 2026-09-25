import 'package:flutter/widgets.dart';

String appLocaleCode(BuildContext context) =>
    Localizations.localeOf(context).languageCode;

bool isFrench(BuildContext context) => appLocaleCode(context) == 'fr';

String localizedText(
  BuildContext context,
  String english,
  String spanish,
  String french,
) => localizedTextFor(appLocaleCode(context), english, spanish, french);

String localizedTextFor(
  String languageCode,
  String english,
  String spanish,
  String french,
) => switch (languageCode) {
  'es' => spanish,
  'fr' => french,
  _ => english,
};
