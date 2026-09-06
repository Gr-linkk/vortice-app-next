import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/core/push_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/notifications/notification_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/profile.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final notificationsAsync = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.notificationsTitle),
        actions: [
          IconButton(
            tooltip: isSpanish(context) ? 'Actualizar' : 'Refresh',
            onPressed: () => ref.invalidate(notificationsProvider),
            icon: const Icon(Icons.refresh),
          ),
          notificationsAsync.maybeWhen(
            data: (list) {
              final hasUnread = list.any((n) => !n.read);
              if (!hasUnread) return const SizedBox.shrink();
              return TextButton(
                onPressed: () async {
                  try {
                    await ref
                        .read(notificationControllerProvider.notifier)
                        .markAllRead();
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(friendlyError(context, error))),
                      );
                    }
                  }
                },
                child: Text(
                  l10n.markAllRead,
                  style: const TextStyle(color: AppColors.primary),
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: Column(
        children: [
          const PushNotificationSettings(),
          Expanded(
            child: notificationsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => AppErrorState(
                error: err,
                onRetry: () => ref.invalidate(notificationsProvider),
              ),
              data: (notifications) {
                if (notifications.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.notifications_none,
                          size: 56,
                          color: AppColors.textSecondary.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.noNotifications,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final profile = ref.watch(profileProvider).valueOrNull;
                final role = profile?.role ?? UserRole.client;

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: notifications.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: AppColors.divider),
                  itemBuilder: (context, index) {
                    final n = notifications[index];
                    return _NotificationTile(notification: n, role: role);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  final AppNotification notification;
  final UserRole role;
  const _NotificationTile({required this.notification, required this.role});

  IconData _iconFor(String type) => switch (type) {
    'maintenance_flag' => Icons.flag,
    'telemetry_alert' => Icons.monitor_heart,
    'work_order' => Icons.build,
    'invoice' => Icons.receipt_long,
    _ => Icons.notifications,
  };

  Color _colorFor(String type) => switch (type) {
    'maintenance_flag' => AppColors.warning,
    'telemetry_alert' => AppColors.error,
    'work_order' => AppColors.primary,
    'invoice' => AppColors.success,
    _ => AppColors.textSecondary,
  };

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  String? _destinationRoute() {
    final ref = notification.referenceId;
    if (ref == null) return null;
    final prefix = switch (role) {
      UserRole.owner => '/owner',
      UserRole.employee => '/employee',
      UserRole.client => '/client',
      UserRole.operator => '/operator',
      UserRole.clientAdmin => '/client',
      UserRole.clientMechanic => '/client',
      UserRole.clientOperator => '/client',
    };
    return switch (notification.type) {
      'maintenance_assignment' ||
      'maintenance_return' => '/maintenance/jobs/$ref',
      'urgent_fault' => '/fleet/faults/$ref',
      'inspection_due' => '/assurance/assets/$ref',
      'discussion_job' => '/discussion/job/$ref?post=${notification.id}',
      'discussion_fault' => '/discussion/fault/$ref?post=${notification.id}',
      'maintenance_flag' => '$prefix/assets/$ref/flags?name=Asset',
      'work_order' => '$prefix/work-orders/$ref',
      // Invoices only visible to owner and client
      'invoice' when role == UserRole.owner || role == UserRole.client =>
        '$prefix/invoices/$ref',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUnread = !notification.read;
    final route = _destinationRoute();
    final tappable = isUnread || route != null;

    return InkWell(
      onTap: tappable
          ? () async {
              if (isUnread) {
                try {
                  await ref
                      .read(notificationControllerProvider.notifier)
                      .markRead(
                        notification.id,
                        discussion: notification.type.startsWith('discussion_'),
                      );
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(friendlyError(context, error))),
                    );
                  }
                }
              }
              if (route != null && context.mounted) {
                context.push(route);
              }
            }
          : null,
      child: Container(
        color: isUnread
            ? AppColors.primary.withValues(alpha: 0.06)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _colorFor(notification.type).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _iconFor(notification.type),
                size: 20,
                color: _colorFor(notification.type),
              ),
            ),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: isUnread
                                ? FontWeight.w600
                                : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (isUnread)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    notification.body,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _timeAgo(notification.createdAt),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
