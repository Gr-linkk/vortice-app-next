import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/localized_text.dart';

bool isSpanish(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'es';

/// Keep server details out of user messages. Callers retain the original error
/// in their state for diagnosis, and supply a retry action where possible.
String friendlyError(BuildContext context, Object? error) {
  if (error is AuthException) {
    if (error.code == 'invalid_credentials') {
      return localizedText(
        context,
        'Check your email and password, then try again.',
        'Revisa tu correo y contraseña e inténtalo de nuevo.',
        'Vérifiez votre adresse courriel et votre mot de passe, puis réessayez.',
      );
    }
    return localizedText(
      context,
      'We could not sign you in. Check your connection and try again.',
      'No pudimos iniciar sesión. Revisa tu conexión e inténtalo de nuevo.',
      'Impossible de vous connecter. Vérifiez votre connexion et réessayez.',
    );
  }
  return localizedText(
    context,
    'We could not complete this action. Check your connection and try again. If it continues, ask your administrator for help.',
    'No pudimos completar esta acción. Revisa tu conexión e inténtalo de nuevo. Si continúa, pide ayuda a tu administrador.',
    'Impossible de terminer cette action. Vérifiez votre connexion et réessayez. Si le problème persiste, demandez de l’aide à votre administrateur.',
  );
}

class AppErrorState extends StatelessWidget {
  const AppErrorState({super.key, required this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 36),
            const SizedBox(height: 12),
            Text(friendlyError(context, error), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(
                localizedText(
                  context,
                  'Try again',
                  'Intentar de nuevo',
                  'Réessayer',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
