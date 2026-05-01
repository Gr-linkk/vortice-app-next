import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';

class AssetType {
  final String id;
  final String name;

  const AssetType({required this.id, required this.name});

  factory AssetType.fromJson(Map<String, dynamic> json) {
    return AssetType(
      id: json['id'] as String,
      name: json['name'] as String,
    );
  }
}

final assetTypesProvider = FutureProvider<List<AssetType>>((ref) async {
  final data = await supabase
      .from(AppConstants.tAssetTypes)
      .select('id, name')
      .order('name');

  return (data as List)
      .map((e) => AssetType.fromJson(e as Map<String, dynamic>))
      .toList();
});
