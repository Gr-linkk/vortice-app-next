import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/subscription_tier.dart';

/// Shown when a client tries to access a feature above their tier.
class UpgradePrompt extends StatelessWidget {
  final SubscriptionTier requiredTier;

  const UpgradePrompt({super.key, required this.requiredTier});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, color: AppColors.warning, size: 48),
          const SizedBox(height: 16),
          Text(
            l10n.upgradeRequired,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.upgradeMessage(requiredTier.displayName),
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.gotIt),
          ),
        ],
      ),
    );
  }
}

/// Inline banner version — for use inside a screen rather than as a full replacement.
class TierGateBanner extends StatelessWidget {
  final SubscriptionTier requiredTier;
  final Widget child;

  const TierGateBanner({
    super.key,
    required this.requiredTier,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.08),
            border: Border(
              bottom:
                  BorderSide(color: AppColors.warning.withValues(alpha: 0.25)),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock_outline,
                  color: AppColors.warning, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.upgradeMessage(requiredTier.displayName),
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        child,
      ],
    );
  }
}
