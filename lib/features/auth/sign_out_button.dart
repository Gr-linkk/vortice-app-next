import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';

/// Shared by every dashboard and the account entry in More.
Future<void> confirmSignOut(BuildContext context, WidgetRef ref) async {
  if (ref.read(authControllerProvider).isLoading) return;
  final es = isSpanish(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(es ? '¿Cerrar sesión?' : 'Sign out?'),
      content: Text(
        es
            ? 'Necesitarás tu correo y contraseña para volver.'
            : 'You will need your email and password to sign in again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(es ? 'Cancelar' : 'Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(es ? 'Cerrar sesión' : 'Sign out'),
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
    tooltip: isSpanish(context) ? 'Cerrar sesión' : 'Sign out',
    icon: const Icon(Icons.logout),
    onPressed: ref.watch(authControllerProvider).isLoading
        ? null
        : () => confirmSignOut(context, ref),
  );
}
