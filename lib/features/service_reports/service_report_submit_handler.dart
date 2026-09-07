import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/core/app_navigation.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/service_reports/service_report_provider.dart';
import 'package:vortice_app/features/service_reports/service_report_screen_support.dart';
import 'package:vortice_app/features/service_reports/service_report_submit_support.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

class ServiceReportSubmitInput {
  const ServiceReportSubmitInput({
    required this.selectedWorkOrderId,
    required this.pendingReportId,
    required this.complaint,
    required this.cause,
    required this.correction,
    required this.collateral,
    required this.comments,
    required this.signatureBytes,
    required this.photos,
  });

  final String? selectedWorkOrderId;
  final String? pendingReportId;
  final String complaint;
  final String cause;
  final String correction;
  final String collateral;
  final String comments;
  final Uint8List? signatureBytes;
  final List<Uint8List> photos;
}

class ServiceReportSubmitResultState {
  const ServiceReportSubmitResultState({
    this.pendingReportId,
    required this.shouldResetForm,
    required this.shouldPop,
  });

  final String? pendingReportId;
  final bool shouldResetForm;
  final bool shouldPop;
}

class ServiceReportSubmitHandler {
  const ServiceReportSubmitHandler();

  Future<ServiceReportSubmitResultState?> submit({
    required BuildContext context,
    required WidgetRef ref,
    required GlobalKey<FormState> formKey,
    required ServiceReportSubmitInput input,
    required Future<void> Function() onSaveDraft,
    required Future<void> Function(String? pendingReportId) onDraftPersist,
    required Future<void> Function() onClearDraft,
  }) async {
    if (!formKey.currentState!.validate()) return null;
    final missingWorkOrderMessage = validateServiceReportWorkOrderSelection(
      input.selectedWorkOrderId,
    );
    if (missingWorkOrderMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(missingWorkOrderMessage),
          backgroundColor: AppColors.warning,
        ),
      );
      return null;
    }

    final reportId = input.pendingReportId ?? const Uuid().v4();
    // Persist the identity and bytes before the first network attempt.
    await onDraftPersist(reportId);
    await onSaveDraft();
    final result = await ref
        .read(serviceReportControllerProvider.notifier)
        .submitWithEvidence(
          reportId: reportId,
          data: buildServiceReportPayload(
            selectedWorkOrderId: input.selectedWorkOrderId,
            complaint: input.complaint,
            cause: input.cause,
            correction: input.correction,
            collateral: input.collateral,
            comments: input.comments,
          ),
          photos: input.photos,
          signature: input.signatureBytes,
        );
    if (result != null) {
      // The account-owned outbox now contains the complete text/media bundle.
      // Clearing the editor cannot erase rejected or interrupted submissions.
      await onClearDraft();
      if (!context.mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.synced
                ? AppLocalizations.of(context).reportSubmitted
                : isSpanish(context)
                ? 'Guardado en este dispositivo. Revisa Guardado y sincronización.'
                : 'Saved on this device. Check Saved work and sync.',
          ),
        ),
      );
      formKey.currentState!.reset();
      if (context.canPop()) {
        context.pop();
      } else {
        final profile = ref.read(profileProvider).valueOrNull;
        context.go(
          profile == null
              ? '/login'
              : '${roleRoutePrefix(profile.role)}/work-orders/${input.selectedWorkOrderId}',
        );
      }
      return const ServiceReportSubmitResultState(
        shouldResetForm: true,
        shouldPop: true,
      );
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyError(
              context,
              ref.read(serviceReportControllerProvider).error,
            ),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
    return null;
  }
}
