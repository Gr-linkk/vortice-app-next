import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

class ServiceReportAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool signatureSaved;
  final bool isLoading;
  final bool canSubmit;
  final VoidCallback onOpenSignature;
  final VoidCallback onSubmit;

  const ServiceReportAppBar({
    super.key,
    required this.signatureSaved,
    required this.isLoading,
    required this.canSubmit,
    required this.onOpenSignature,
    required this.onSubmit,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AppBar(
      title: Text(l10n.serviceReportTitle),
      actions: [
        Tooltip(
          message: signatureSaved
              ? l10n.signatureCaptured
              : l10n.technicianSignature,
          child: IconButton(
            onPressed: onOpenSignature,
            icon: Icon(
              signatureSaved ? Icons.check_circle : Icons.draw_outlined,
              color: signatureSaved ? AppColors.success : null,
            ),
          ),
        ),
        Tooltip(
          message: l10n.submitReport,
          child: IconButton(
            onPressed: isLoading || !canSubmit
                ? null
                : () {
                    FocusScope.of(context).unfocus();
                    onSubmit();
                  },
            icon: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
          ),
        ),
      ],
    );
  }
}
