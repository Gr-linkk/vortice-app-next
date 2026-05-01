import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/models/parts_inventory.dart';

// ── Fetch all inventory items ordered by description ───────────────────────

final partsInventoryProvider = FutureProvider<List<PartsInventory>>((ref) async {
  final data = await supabase
      .from(AppConstants.tPartsInventory)
      .select()
      .order('description');
  return (data as List)
      .map((e) => PartsInventory.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ── Filtered by search string ──────────────────────────────────────────────

final inventorySearchProvider =
    FutureProvider.family<List<PartsInventory>, String>((ref, query) async {
  final all = await ref.watch(partsInventoryProvider.future);
  if (query.trim().isEmpty) return all;
  final lower = query.toLowerCase();
  return all.where((item) {
    return item.description.toLowerCase().contains(lower) ||
        (item.partNumber?.toLowerCase().contains(lower) ?? false) ||
        (item.location?.toLowerCase().contains(lower) ?? false) ||
        (item.supplier?.toLowerCase().contains(lower) ?? false);
  }).toList();
});

// ── Controller ─────────────────────────────────────────────────────────────

class PartsInventoryController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  PartsInventoryController(this._ref) : super(const AsyncData(null));

  Future<bool> addItem({
    required String description,
    String? partNumber,
    double qtyOnHand = 0.0,
    double minStockLevel = 0.0,
    String? location,
    String? supplier,
    double lastUnitCost = 0.0,
  }) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tPartsInventory).insert({
        'description': description,
        'part_number': partNumber,
        'qty_on_hand': qtyOnHand,
        'min_stock_level': minStockLevel,
        'location': location,
        'supplier': supplier,
        'last_unit_cost': lastUnitCost,
      });
      _ref.invalidate(partsInventoryProvider);
      success = true;
    });
    return success;
  }

  Future<bool> updateItem(String id, Map<String, dynamic> fields) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase
          .from(AppConstants.tPartsInventory)
          .update(fields)
          .eq('id', id);
      _ref.invalidate(partsInventoryProvider);
      success = true;
    });
    return success;
  }

  Future<bool> deleteItem(String id) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase
          .from(AppConstants.tPartsInventory)
          .delete()
          .eq('id', id);
      _ref.invalidate(partsInventoryProvider);
      success = true;
    });
    return success;
  }

  Future<bool> adjustStock(String id, double delta) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      final row = await supabase
          .from(AppConstants.tPartsInventory)
          .select('qty_on_hand')
          .eq('id', id)
          .single();
      final current = (row['qty_on_hand'] as num?)?.toDouble() ?? 0.0;
      await supabase
          .from(AppConstants.tPartsInventory)
          .update({'qty_on_hand': current + delta})
          .eq('id', id);
      _ref.invalidate(partsInventoryProvider);
      success = true;
    });
    return success;
  }
}

final partsInventoryControllerProvider =
    StateNotifierProvider<PartsInventoryController, AsyncValue<void>>((ref) {
  return PartsInventoryController(ref);
});
