String pmKitPartCountLabel(int count) =>
    '$count part${count == 1 ? '' : 's'}';

String? formatAssetMakeModel(String? make, String? model) {
  final parts = [make, model].whereType<String>().where((s) => s.isNotEmpty);
  if (parts.isEmpty) return null;
  return parts.join(' ');
}

String formatPmKitPartQty(dynamic qty, String? unit) =>
    '${qty ?? 1} ${unit ?? 'ea'}';
