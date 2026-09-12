import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_support.dart';
import 'package:vortice_app/models/work_order.dart';
import 'planning_models.dart';
import 'dart:convert';

/// Display context for an already authorized set of provider orders.
class PlanningServiceData {
  const PlanningServiceData({
    this.assetNames = const {},
    this.componentNames = const {},
    this.componentAssets = const {},
    this.workerNames = const {},
    this.workersByOrder = const {},
  });

  final Map<String, String> assetNames,
      componentNames,
      componentAssets,
      workerNames;
  final Map<String, Set<String>> workersByOrder;

  PlanningJob project(WorkOrder order, String userId, String routePrefix) {
    final workerIds = {
      if (order.assignedTo != null) order.assignedTo!,
      ...workersByOrder[order.id] ?? <String>{},
    };
    final workers = {
      for (final id in workerIds) id: workerNames[id] ?? unnamedTechLabel,
    };
    return PlanningJob({
      'id': order.id,
      'asset_id': order.assetId,
      'asset_name': assetNames[order.assetId] ?? '',
      'title': order.title,
      'job_type': order.jobType.dbValue,
      'status': order.status.dbValue,
      'assigned_to': order.assignedTo,
      'assigned_to_me': workerIds.contains(userId),
      'assignee_name': workers.values.join(', '),
      'workers': workers,
      'component_name': componentAssets[order.engineId] == order.assetId
          ? componentNames[order.engineId]
          : null,
      'provider_service': true,
      'service_date': order.scheduledDate?.toIso8601String().split('T').first,
      'on_hold_reason': order.onHoldReason,
      'route': order.providerOrganizationId != null
          ? '/work-orders/${order.id}'
          : '$routePrefix/work-orders/${order.id}',
    });
  }
}

abstract class PlanningServiceRepository {
  Future<PlanningServiceData> load(
    List<WorkOrder> orders, {
    required String accountId,
  });
}

class SupabasePlanningServiceRepository implements PlanningServiceRepository {
  SupabasePlanningServiceRepository(this.client);
  final SupabaseClient client;

  void _check(String accountId) {
    if (client.auth.currentUser?.id != accountId) {
      throw const AccountChangedException();
    }
  }

  // Bound URL length and page every result, including assignment tables where
  // one order can have many workers. Every read still runs under the user's RLS.
  Future<List<Map<String, dynamic>>> _rows(
    String table,
    String columns,
    String filter,
    Set<String> ids,
    String accountId,
  ) async {
    final values = ids.toList()..sort();
    if (values.isEmpty) return [];
    final raw =
        await AccountJsonCache(
          accountId,
          () => client.auth.currentUser?.id,
        ).readThrough(
          'planning_service:$table:$columns:$filter:${jsonEncode(values)}',
          () async {
            final result = <Map<String, dynamic>>[];
            for (var start = 0; start < values.length; start += 100) {
              final chunk = values.skip(start).take(100).toList();
              for (var offset = 0; ; offset += 500) {
                _check(accountId);
                final page = await client
                    .from(table)
                    .select(columns)
                    .inFilter(filter, chunk)
                    .order('id')
                    .range(offset, offset + 499)
                    .timeout(const Duration(seconds: 6));
                _check(accountId);
                result.addAll(page);
                if (page.length < 500) break;
              }
            }
            _check(accountId);
            return result;
          },
        );
    _check(accountId);
    return (raw as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  @override
  Future<PlanningServiceData> load(
    List<WorkOrder> orders, {
    required String accountId,
  }) async {
    _check(accountId);
    if (orders.isEmpty) return const PlanningServiceData();
    try {
      final result = await _load(orders, accountId);
      _check(accountId);
      return result;
    } catch (_) {
      // Parallel reads may wrap failures. Surface an account change directly
      // and never return a mixture of results from two sessions.
      _check(accountId);
      rethrow;
    }
  }

  Future<PlanningServiceData> _load(
    List<WorkOrder> orders,
    String accountId,
  ) async {
    final (assets, components, assignments) = await (
      _rows('assets', 'id,name', 'id', {
        for (final order in orders) order.assetId,
      }, accountId),
      _rows('asset_engines', 'id,asset_id,label', 'id', {
        for (final order in orders)
          if (order.engineId != null) order.engineId!,
      }, accountId),
      _rows(
        'work_order_assignments',
        'id,work_order_id,profile_id',
        'work_order_id',
        {for (final order in orders) order.id},
        accountId,
      ),
    ).wait;
    _check(accountId);
    final workersByOrder = <String, Set<String>>{};
    for (final assignment in assignments) {
      (workersByOrder[assignment['work_order_id'] as String] ??= {}).add(
        assignment['profile_id'] as String,
      );
    }
    final profiles = await _rows('profiles', 'id,full_name', 'id', {
      for (final order in orders)
        if (order.assignedTo != null) order.assignedTo!,
      for (final ids in workersByOrder.values) ...ids,
    }, accountId);
    _check(accountId);
    return PlanningServiceData(
      assetNames: {
        for (final asset in assets)
          asset['id'] as String: asset['name'] as String? ?? '',
      },
      componentNames: {
        for (final component in components)
          component['id'] as String: component['label'] as String? ?? '',
      },
      componentAssets: {
        for (final component in components)
          component['id'] as String: component['asset_id'] as String,
      },
      workerNames: {
        for (final profile in profiles)
          profile['id'] as String: formatProfileName(profile['full_name'])!,
      },
      workersByOrder: workersByOrder,
    );
  }
}

final planningServiceRepositoryProvider = Provider<PlanningServiceRepository>((
  ref,
) {
  ref.watch(sessionProvider);
  return SupabasePlanningServiceRepository(supabase);
});
