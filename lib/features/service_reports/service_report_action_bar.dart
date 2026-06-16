import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

class ServiceReportActionBar extends StatelessWidget {
  const ServiceReportActionBar({
    super.key,
    required this.signatureSaved,
    required this.isLoading,
    required this.canSubmit,
    required this.onOpenSignature,
    required this.onSubmit,
  });

  final bool signatureSaved;
  final bool isLoading;
  final bool canSubmit;
  final VoidCallback onOpenSignature;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.divider),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onOpenSignature,
                icon: Icon(
                  signatureSaved ? Icons.check_circle : Icons.draw_outlined,
                  color: signatureSaved ? AppColors.success : null,
                ),
                label: Text(
                  signatureSaved
                      ? l10n.signatureCaptured
                      : l10n.technicianSignature,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: isLoading || !canSubmit
                    ? null
                    : () {
                        FocusScope.of(context).unfocus();
                        onSubmit();
                      },
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(l10n.submitReport),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
