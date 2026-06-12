import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_detail_body.dart';
import 'package:vortice_app/features/work_orders/work_order_edit_sheet.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/work_order.dart';

class WorkOrderDetailScreen extends ConsumerWidget {
  final String workOrderId;
  const WorkOrderDetailScreen({super.key, required this.workOrderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final woAsync = ref.watch(workOrderByIdProvider(workOrderId));
    final profile = ref.watch(profileProvider).valueOrNull;
    final isOwner = profile?.role == UserRole.owner;
    final canManage =
        profile?.role == UserRole.owner || profile?.role == UserRole.employee;
    final title = canManage ? l10n.workOrderDetail : 'Assigned Work';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (isOwner)
            woAsync.whenOrNull(
                  data: (wo) {
                    if (wo == null || wo.status == WorkOrderStatus.closed) {
                      return null;
                    }
                    return IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: l10n.edit,
                      onPressed: () => showEditWorkOrderSheet(context, wo),
                    );
                  },
                ) ??
                const SizedBox.shrink(),
        ],
      ),
      body: woAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text(
            err.toString(),
            style: const TextStyle(color: AppColors.error),
          ),
        ),
        data: (wo) {
          if (wo == null) return Center(child: Text(l10n.notFound));
          return WorkOrderDetailBody(
            workOrder: wo,
            canManage: canManage,
            profile: profile,
          );
        },
      ),
    );
  }
}
