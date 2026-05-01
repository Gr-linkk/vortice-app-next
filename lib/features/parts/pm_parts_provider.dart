import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/parts/parts_inventory_provider.dart';
import 'package:vortice_app/models/parts_inventory.dart';
import 'package:vortice_app/models/pm_parts_requirement.dart';

// ── Readiness types ────────────────────────────────────────────────────────

enum ReadinessLevel { ready, partial, notReady }

class PartsReadiness {
  final ReadinessLevel level;
  final int totalRequired;
  final int onHand;
  final List<String> missingParts;

  const PartsReadiness({
    required this.level,
    required this.totalRequired,
    required this.onHand,
    required this.missingParts,
  });
}

// ── Fetch PM parts requirements for a template ─────────────────────────────

final pmPartsRequirementsProvider =
    FutureProvider.family<List<PmPartsRequirement>, String>(
        (ref, templateId) async {
  final data = await supabase
      .from(AppConstants.tPmPartsRequirements)
      .select()
      .eq('template_id', templateId)
      .order('created_at');
  return (data as List)
      .map((e) => PmPartsRequirement.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ── Readiness provider ─────────────────────────────────────────────────────

final pmReadinessProvider =
    FutureProvider.family<PartsReadiness, String>((ref, templateId) async {
  final requirements =
      await ref.watch(pmPartsRequirementsProvider(templateId).future);
  final inventory = await ref.watch(partsInventoryProvider.future);

  if (requirements.isEmpty) {
    return const PartsReadiness(
      level: ReadinessLevel.ready,
      totalRequired: 0,
      onHand: 0,
      missingParts: [],
    );
  }

  final missingParts = <String>[];
  int onHandCount = 0;

  for (final req in requirements) {
    final match = _findInventoryMatch(req, inventory);
    if (match != null && match.qtyOnHand >= req.qty) {
      onHandCount++;
    } else {
      missingParts.add(req.description);
    }
  }

  final ReadinessLevel level;
  if (missingParts.isEmpty) {
    level = ReadinessLevel.ready;
  } else if (onHandCount > 0) {
    level = ReadinessLevel.partial;
  } else {
    level = ReadinessLevel.notReady;
  }

  return PartsReadiness(
    level: level,
    totalRequired: requirements.length,
    onHand: onHandCount,
    missingParts: missingParts,
  );
});

PartsInventory? _findInventoryMatch(
    PmPartsRequirement req, List<PartsInventory> inventory) {
  // Exact part number match first
  if (req.partNumber != null && req.partNumber!.isNotEmpty) {
    final byPartNumber = inventory.where((item) =>
        item.partNumber != null &&
        item.partNumber!.toLowerCase() ==
            req.partNumber!.toLowerCase());
    if (byPartNumber.isNotEmpty) return byPartNumber.first;
  }
  // Case-insensitive description contains match
  final lower = req.description.toLowerCase();
  final byDescription = inventory.where(
      (item) => item.description.toLowerCase().contains(lower));
  if (byDescription.isNotEmpty) return byDescription.first;
  return null;
}

// ── Controller ─────────────────────────────────────────────────────────────

class PmPartsController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  PmPartsController(this._ref) : super(const AsyncData(null));

  Future<bool> addRequirement({
    required String templateId,
    required String description,
    String? partNumber,
    double qty = 1.0,
    String? unit,
    String? notes,
  }) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tPmPartsRequirements).insert({
        'template_id': templateId,
        'description': description,
        'part_number': partNumber,
        'qty': qty,
        'unit': unit,
        'notes': notes,
      });
      _ref.invalidate(pmPartsRequirementsProvider(templateId));
      _ref.invalidate(pmReadinessProvider(templateId));
      success = true;
    });
    return success;
  }

  Future<bool> removeRequirement(String id, String templateId) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase
          .from(AppConstants.tPmPartsRequirements)
          .delete()
          .eq('id', id);
      _ref.invalidate(pmPartsRequirementsProvider(templateId));
      _ref.invalidate(pmReadinessProvider(templateId));
      success = true;
    });
    return success;
  }

  Future<bool> updateRequirement(
      String id, String templateId, Map<String, dynamic> fields) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase
          .from(AppConstants.tPmPartsRequirements)
          .update(fields)
          .eq('id', id);
      _ref.invalidate(pmPartsRequirementsProvider(templateId));
      _ref.invalidate(pmReadinessProvider(templateId));
      success = true;
    });
    return success;
  }
}

final pmPartsControllerProvider =
    StateNotifierProvider<PmPartsController, AsyncValue<void>>((ref) {
  return PmPartsController(ref);
});
