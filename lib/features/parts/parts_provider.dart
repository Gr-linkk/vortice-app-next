import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/models/part.dart';

final partsProvider =
    FutureProvider.family<List<Part>, String>((ref, workOrderId) async {
  final data = await supabase
      .from(AppConstants.tParts)
      .select()
      .eq('work_order_id', workOrderId)
      .order('created_at');
  return (data as List)
      .map((e) => Part.fromJson(e as Map<String, dynamic>))
      .toList();
});

final allPartsProvider = FutureProvider<List<Part>>((ref) async {
  final data = await supabase
      .from(AppConstants.tParts)
      .select()
      .order('created_at', ascending: false);
  return (data as List)
      .map((e) => Part.fromJson(e as Map<String, dynamic>))
      .toList();
});

class PartsController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  PartsController(this._ref) : super(const AsyncData(null));

  Future<bool> addPart({
    required String workOrderId,
    required String description,
    String? partNumber,
    required double quantity,
    required double unitCost,
    double markupPct = 15.0,
    String? supplier,
    String? notes,
    required String loggedBy,
  }) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tParts).insert({
        'work_order_id': workOrderId,
        'description': description,
        'part_number': partNumber,
        'quantity': quantity,
        'unit_cost': unitCost,
        'markup_pct': markupPct,
        'supplier': supplier,
        'notes': notes,
        'logged_by': loggedBy,
      });
      _ref.invalidate(partsProvider(workOrderId));
      _ref.invalidate(allPartsProvider);
      success = true;
    });
    return success;
  }

  Future<bool> deletePart(String partId, String workOrderId) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tParts).delete().eq('id', partId);
      _ref.invalidate(partsProvider(workOrderId));
      _ref.invalidate(allPartsProvider);
      success = true;
    });
    return success;
  }
}

final partsControllerProvider =
    StateNotifierProvider<PartsController, AsyncValue<void>>((ref) {
  return PartsController(ref);
});
