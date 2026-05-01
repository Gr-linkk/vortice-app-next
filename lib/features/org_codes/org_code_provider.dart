import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';

// ── Org code model (lightweight, no Freezed needed) ────────────────────────

class OrgCode {
  final String id;
  final String code;
  final String intendedRole;
  final bool singleUse;
  final int maxUses;
  final int useCount;
  final DateTime? expiresAt;
  final String? notes;
  final String? orgId;
  final DateTime? createdAt;

  OrgCode({
    required this.id,
    required this.code,
    required this.intendedRole,
    this.singleUse = true,
    this.maxUses = 1,
    this.useCount = 0,
    this.expiresAt,
    this.notes,
    this.orgId,
    this.createdAt,
  });

  factory OrgCode.fromJson(Map<String, dynamic> json) => OrgCode(
        id: json['id'] as String,
        code: json['code'] as String,
        intendedRole: json['intended_role'] as String,
        singleUse: json['single_use'] as bool? ?? true,
        maxUses: json['max_uses'] as int? ?? 1,
        useCount: json['use_count'] as int? ?? 0,
        expiresAt: json['expires_at'] != null
            ? DateTime.parse(json['expires_at'] as String)
            : null,
        notes: json['notes'] as String?,
        orgId: json['org_id'] as String?,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : null,
      );

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool get isFullyUsed => useCount >= maxUses;
}

// ── Fetch all org codes ────────────────────────────────────────────────────

final orgCodesProvider = FutureProvider<List<OrgCode>>((ref) async {
  final remote = await supabase
      .from(AppConstants.tOrgCodes)
      .select()
      .order('created_at', ascending: false);

  return (remote as List)
      .map((e) => OrgCode.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ── Org code controller ────────────────────────────────────────────────────

class OrgCodeController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  OrgCodeController(this._ref) : super(const AsyncData(null));

  static String generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  Future<bool> createCode({
    required String code,
    required String intendedRole,
    required int maxUses,
    required bool singleUse,
    DateTime? expiresAt,
    String? notes,
    String? orgId,
  }) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tOrgCodes).insert({
        'code': code.toUpperCase(),
        'intended_role': intendedRole,
        'max_uses': maxUses,
        'single_use': singleUse,
        if (expiresAt != null) 'expires_at': expiresAt.toIso8601String(),
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (orgId != null) 'org_id': orgId,
      });
      _ref.invalidate(orgCodesProvider);
      success = true;
    });
    return success;
  }

  Future<bool> deleteCode(String id) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tOrgCodes).delete().eq('id', id);
      _ref.invalidate(orgCodesProvider);
      success = true;
    });
    return success;
  }
}

final orgCodeControllerProvider =
    StateNotifierProvider<OrgCodeController, AsyncValue<void>>((ref) {
  return OrgCodeController(ref);
});
