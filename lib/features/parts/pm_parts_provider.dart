import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/models/pm_parts_requirement.dart';

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
      success = true;
    });
    return success;
  }
}

final pmPartsControllerProvider =
    StateNotifierProvider<PmPartsController, AsyncValue<void>>((ref) {
  return PmPartsController(ref);
});
