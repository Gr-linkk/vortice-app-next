import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'package:vortice_app/features/maintenance/planning/planning_repository.dart';
import 'package:vortice_app/features/membership/membership_models.dart';

/// The server's cycle ledger makes overlapping foreground/scheduler runs safe.
/// A failed connected attempt never prevents access to saved field work.
class RecurringWorkRefresh {
  String? _key;
  DateTime? _last;
  bool _busy = false;
  Future<int> refresh({
    required String key,
    required bool allowed,
    required String? Function() currentKey,
    required Future<int> Function() generate,
    DateTime? now,
  }) async {
    if (!allowed || _busy || currentKey() != key) return 0;
    final time = now ?? DateTime.now();
    if (_key == key &&
        _last != null &&
        time.difference(_last!) < const Duration(minutes: 5)) {
      return 0;
    }
    _busy = true;
    _key = key;
    _last = time;
    try {
      final count = await generate();
      return currentKey() == key ? count : 0;
    } catch (_) {
      return 0;
    } finally {
      _busy = false;
    }
  }
}

final recurringWorkRefreshProvider = Provider((ref) => RecurringWorkRefresh());

Future<void> refreshRecurringWork(WidgetRef ref) async {
  final profile = ref.read(profileProvider).valueOrNull;
  if (profile == null) return;
  String? currentKey() {
    final current = ref.read(profileProvider).valueOrNull;
    return current == null ? null : '${current.id}:${current.orgId}';
  }

  final count = await ref
      .read(recurringWorkRefreshProvider)
      .refresh(
        key: '${profile.id}:${profile.orgId}',
        currentKey: currentKey,
        allowed: profile.membershipManaged
            ? profile.canInOrganization('planning')
            : isMaintenanceManager(profile.role),
        generate: () async =>
            (await supabase
                        .rpc('generate_recurring_work')
                        .timeout(const Duration(seconds: 20))
                    as num)
                .toInt(),
      );
  if (count > 0) {
    ref.invalidate(maintenanceJobsProvider);
    ref.invalidate(maintenancePlanningProvider);
  }
}
