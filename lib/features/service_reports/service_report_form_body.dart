import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vortice_app/features/service_reports/service_report_footer.dart';
import 'package:vortice_app/features/service_reports/service_report_form_sections.dart';

class ServiceReportFormBody extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final bool canSubmit;
  final bool showLinkedWorkOrderBanner;
  final String? selectedWorkOrderId;
  final TextEditingController complaintController;
  final TextEditingController causeController;
  final TextEditingController correctionController;
  final TextEditingController collateralController;
  final TextEditingController commentsController;
  final List<Uint8List> photos;
  final ValueChanged<String?> onWorkOrderChanged;
  final VoidCallback onPickGallery;
  final VoidCallback onTakeCamera;
  final ValueChanged<int> onRemovePhoto;

  const ServiceReportFormBody({
    super.key,
    required this.formKey,
    required this.canSubmit,
    required this.showLinkedWorkOrderBanner,
    required this.selectedWorkOrderId,
    required this.complaintController,
    required this.causeController,
    required this.correctionController,
    required this.collateralController,
    required this.commentsController,
    required this.photos,
    required this.onWorkOrderChanged,
    required this.onPickGallery,
    required this.onTakeCamera,
    required this.onRemovePhoto,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: Form(
          key: formKey,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 104),
            children: [
              if (!canSubmit) ...[
                const ServiceReportPermissionBanner(),
                const SizedBox(height: 12),
              ],
              if (showLinkedWorkOrderBanner) ...[
                const ServiceReportLinkedWorkOrderBanner(),
                const SizedBox(height: 8),
              ],
              ServiceReportWorkOrderSection(
                selectedWorkOrderId: selectedWorkOrderId,
                onWorkOrderChanged: onWorkOrderChanged,
              ),
              ServiceReportFiveCFieldsSection(
                complaintController: complaintController,
                causeController: causeController,
                correctionController: correctionController,
                collateralController: collateralController,
                commentsController: commentsController,
              ),
              ServiceReportFormFooter(
                photos: photos,
                onPickGallery: onPickGallery,
                onTakeCamera: onTakeCamera,
                onRemovePhoto: onRemovePhoto,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
