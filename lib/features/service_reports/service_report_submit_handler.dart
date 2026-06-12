import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/service_reports/service_report_provider.dart';
import 'package:vortice_app/features/service_reports/service_report_repository.dart';
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
    final missingWorkOrderMessage =
        validateServiceReportWorkOrderSelection(input.selectedWorkOrderId);
    if (missingWorkOrderMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(missingWorkOrderMessage),
          backgroundColor: AppColors.warning,
        ),
      );
      return null;
    }

    await onSaveDraft();

    String? signatureUrl;
    if (input.signatureBytes != null) {
      try {
        signatureUrl = await uploadServiceReportSignature(
          signatureBytes: input.signatureBytes!,
          selectedWorkOrderId: input.selectedWorkOrderId,
        );
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(serviceReportSignatureFailedMessage),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return null;
      }
    }

    final payload = buildServiceReportPayload(
      selectedWorkOrderId: input.selectedWorkOrderId,
      complaint: input.complaint,
      cause: input.cause,
      correction: input.correction,
      collateral: input.collateral,
      comments: input.comments,
      signatureUrl: signatureUrl,
    );

    if (input.pendingReportId != null) {
      try {
        await updatePendingServiceReport(
          reportId: input.pendingReportId!,
          payload: payload,
        );
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(serviceReportSubmitFailedMessage),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return null;
      }
    }

    final selectedWorkOrderId = input.selectedWorkOrderId;
    if (selectedWorkOrderId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).selectWorkOrder),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return null;
    }

    final submitResult = input.pendingReportId == null
        ? await ref.read(serviceReportControllerProvider.notifier).createReport(
              workOrderId: selectedWorkOrderId,
              complaint: input.complaint.trim().isNotEmpty
                  ? input.complaint.trim()
                  : null,
              cause:
                  input.cause.trim().isNotEmpty ? input.cause.trim() : null,
              correction: input.correction.trim().isNotEmpty
                  ? input.correction.trim()
                  : null,
              collateral: input.collateral.trim().isNotEmpty
                  ? input.collateral.trim()
                  : null,
              comments: input.comments.trim().isNotEmpty
                  ? input.comments.trim()
                  : null,
              techSignatureUrl: signatureUrl,
            )
        : ServiceReportSubmitResult(
            reportId: input.pendingReportId!,
            synced: true,
          );
    final reportId = submitResult?.reportId;

    if (reportId != null) {
      await onDraftPersist(reportId);
      var photosUploaded = true;
      if (input.photos.isNotEmpty) {
        try {
          await uploadServiceReportPhotos(
            serviceReportId: reportId,
            photos: input.photos,
          );
        } catch (_) {
          photosUploaded = false;
        }
      }
      final outcome = resolveServiceReportSubmitOutcome(
        reportId: reportId,
        photosUploaded: photosUploaded,
        hadPhotos: input.photos.isNotEmpty,
      );
      if (outcome == null || !context.mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(outcome.showPhotosPendingWarning
              ? serviceReportPhotosPendingMessage
              : AppLocalizations.of(context).reportSubmitted),
          backgroundColor: outcome.showPhotosPendingWarning
              ? AppColors.warning
              : AppColors.success,
        ),
      );
      if (outcome.shouldResetForm) {
        formKey.currentState!.reset();
        await onClearDraft();
        if (context.mounted) context.pop();
      }
      return ServiceReportSubmitResultState(
        pendingReportId: outcome.pendingReportId,
        shouldResetForm: outcome.shouldResetForm,
        shouldPop: outcome.shouldPop,
      );
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(serviceReportSubmitFailedMessage),
          backgroundColor: AppColors.error,
        ),
      );
    }
    return null;
  }
}
