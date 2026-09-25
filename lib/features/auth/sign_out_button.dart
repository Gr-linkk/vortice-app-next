import 'package:flutter/material.dart';
import 'package:vortice_app/core/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';

/// Shared by every dashboard and the account entry in More.
Future<void> confirmSignOut(BuildContext context, WidgetRef ref) async {
  if (ref.read(authControllerProvider).isLoading) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        localizedText(
          context,
          'Sign out?',
          '¿Cerrar sesión?',
          'Se déconnecter?',
        ),
      ),
      content: Text(
        localizedText(
          context,
          'Sign in again to return to your company.',
          'Vuelve a iniciar sesión para acceder a tu empresa.',
          'Connectez-vous de nouveau pour accéder à votre entreprise.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(localizedText(context, 'Cancel', 'Cancelar', 'Annuler')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            localizedText(
              context,
              'Sign out',
              'Cerrar sesión',
              'Se déconnecter',
            ),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await ref.read(authControllerProvider.notifier).signOut();
  if (context.mounted && ref.read(authControllerProvider).hasError) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          friendlyError(context, ref.read(authControllerProvider).error),
        ),
      ),
    );
  }
}

class SignOutButton extends ConsumerWidget {
  const SignOutButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    tooltip: localizedText(
      context,
      'Sign out',
      'Cerrar sesión',
      'Se déconnecter',
    ),
    icon: const Icon(Icons.logout),
    onPressed: ref.watch(authControllerProvider).isLoading
        ? null
        : () => confirmSignOut(context, ref),
  );
}
