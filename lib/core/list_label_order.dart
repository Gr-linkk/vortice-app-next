/// Compare visible names alphabetically, keeping numbered equipment/services
/// in numeric order (Truck 2 before Truck 10; 250-hour before 1000-hour).
int compareListLabels(String left, String right) {
  final pattern = RegExp(r'\d+|\D+');
  final a = pattern
      .allMatches(left.toLowerCase())
      .map((m) => m.group(0)!)
      .toList();
  final b = pattern
      .allMatches(right.toLowerCase())
      .map((m) => m.group(0)!)
      .toList();
  for (var i = 0; i < a.length && i < b.length; i++) {
    final x = int.tryParse(a[i]), y = int.tryParse(b[i]);
    final compared = x != null && y != null
        ? x.compareTo(y)
        : a[i].compareTo(b[i]);
    if (compared != 0) return compared;
  }
  final length = a.length.compareTo(b.length);
  return length != 0
      ? length
      : left.toLowerCase().compareTo(right.toLowerCase());
}
