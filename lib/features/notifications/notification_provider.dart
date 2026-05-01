import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class AppNotification {
  final String id;
  final String? userId;
  final String title;
  final String body;
  final String type;
  final String? referenceId;
  final bool read;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    this.referenceId,
    required this.read,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      userId: json['user_id'] as String?,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      type: json['type'] as String? ?? 'general',
      referenceId: json['reference_id'] as String?,
      read: json['read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final notificationsProvider = FutureProvider<List<AppNotification>>((ref) async {
  final profile = ref.watch(profileProvider).valueOrNull;
  if (profile == null) return [];

  final data = await supabase
      .from(AppConstants.tNotifications)
      .select()
      .eq('user_id', profile.id)
      .order('created_at', ascending: false)
      .limit(50);

  return (data as List).map((e) => AppNotification.fromJson(e)).toList();
});

final unreadCountProvider = Provider<int>((ref) {
  final notifications = ref.watch(notificationsProvider).valueOrNull ?? [];
  return notifications.where((n) => !n.read).length;
});

// ── Controller ────────────────────────────────────────────────────────────────

class NotificationController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> markRead(String notificationId) async {
    await supabase
        .from(AppConstants.tNotifications)
        .update({'read': true})
        .eq('id', notificationId);
    ref.invalidate(notificationsProvider);
  }

  Future<void> markAllRead() async {
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile == null) return;
    await supabase
        .from(AppConstants.tNotifications)
        .update({'read': true})
        .eq('user_id', profile.id)
        .eq('read', false);
    ref.invalidate(notificationsProvider);
  }
}

final notificationControllerProvider =
    AsyncNotifierProvider<NotificationController, void>(NotificationController.new);
