export 'preferences_web.dart' show initializeBrowserPreferences;
import 'package:web/web.dart' as web;

void clearRecoveryAddress() {
  final uri = Uri.parse(web.window.location.href);
  web.window.history.replaceState(
    null,
    '',
    uri.replace(query: '', fragment: '/reset-password').toString(),
  );
}

bool get browserIsOffline => !web.window.navigator.onLine;
