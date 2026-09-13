import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';

class AssetType {
  final String id;
  final String name;
  final String category;
  final String trackingUnit;

  const AssetType({
    required this.id,
    required this.name,
    this.category = '',
    this.trackingUnit = 'engine_hours',
  });

  factory AssetType.fromJson(Map<String, dynamic> json) {
    return AssetType(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String? ?? '',
      trackingUnit: json['tracking_unit'] as String? ?? 'engine_hours',
    );
  }
}

final assetTypesProvider = FutureProvider<List<AssetType>>((ref) async {
  final data = await supabase
      .from(AppConstants.tAssetTypes)
      .select('id, name, category, tracking_unit')
      .order('name', ascending: true);

  return (data as List)
      .map((e) => AssetType.fromJson(e as Map<String, dynamic>))
      .toList();
});
