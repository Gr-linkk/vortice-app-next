import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

class AppRetryPanel extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const AppRetryPanel({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: context.appColors.error, size: 48),
          const SizedBox(height: 12),
          Text(friendlyError(context, error)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: Text(l10n.retry)),
        ],
      ),
    );
  }
}
