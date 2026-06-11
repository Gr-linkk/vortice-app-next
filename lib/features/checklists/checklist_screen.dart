import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/features/checklists/checklist_screen_body.dart';

class ChecklistScreen extends ConsumerWidget {
  final String? workOrderId;
  final String? assetId;
  final String? assetClientId;
  final String? assetName;
  final String? assetTypeId;
  final bool clientHistoryOnly;
  final String? preSelectedTemplateId;

  const ChecklistScreen({
    super.key,
    this.workOrderId,
    this.assetId,
    this.assetClientId,
    this.assetName,
    this.assetTypeId,
    this.clientHistoryOnly = false,
    this.preSelectedTemplateId,
  }) : assert(
          workOrderId != null || (assetId != null && assetClientId != null),
          'ChecklistScreen needs a work order or asset/client pair.',
        );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ChecklistScreenBody(
      workOrderId: workOrderId,
      assetId: assetId,
      assetClientId: assetClientId,
      assetName: assetName,
      assetTypeId: assetTypeId,
      clientHistoryOnly: clientHistoryOnly,
      preSelectedTemplateId: preSelectedTemplateId,
    );
  }
}
