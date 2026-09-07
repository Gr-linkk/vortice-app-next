import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/saved_checklist.dart';
import 'package:vortice_app/models/work_order.dart';

Color workOrderStatusColor(AppPalette colors, WorkOrderStatus status) =>
    switch (status) {
      WorkOrderStatus.draft => colors.textSecondary,
      WorkOrderStatus.assigned => colors.primary,
      WorkOrderStatus.inProgress => colors.warning,
      WorkOrderStatus.onHold => colors.warning,
      WorkOrderStatus.pendingReview => colors.primary,
      WorkOrderStatus.invoiced => colors.success,
      WorkOrderStatus.closed => colors.success,
    };

String workOrderRoutePrefixForRole(UserRole? role) => switch (role) {
  UserRole.owner => '/owner',
  UserRole.employee => '/employee',
  UserRole.client ||
  UserRole.clientAdmin ||
  UserRole.clientMechanic => '/client',
  _ => '/owner',
};

int savedChecklistFlaggedCount(SavedChecklist row) {
  final items = (row.snapshot['items'] as List?)?.cast<Map>() ?? const [];
  return items.where((item) {
    final response = (item['response'] ?? '').toString();
    return response == 'monitor' || response == 'action';
  }).length;
}

void showWorkOrderActionFailedSnackBar(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Work order could not be updated right now. Reconnect and try again.',
      ),
    ),
  );
}
