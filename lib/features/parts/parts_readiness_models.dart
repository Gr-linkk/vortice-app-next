import 'dart:math' as math;

double partNumberValue(Object? value) => (value as num?)?.toDouble() ?? 0;
String partQuantity(num value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2);

class StockItem {
  StockItem(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get description => data['description'] as String;
  String get location => data['location'] as String? ?? '';
  String get unit => data['unit'] as String? ?? 'ea';
  double get onHand => partNumberValue(data['qty_on_hand']);
  double get reserved => partNumberValue(data['reserved']);
  double get available => math.max(0, onHand - reserved);
  double get minimum => partNumberValue(data['min_stock_level']);
  String get currency => data['cost_currency'] as String? ?? 'USD';
  double get cost => partNumberValue(data['last_unit_cost']);
  bool get low => available < minimum;
}

class JobPartRequirement {
  JobPartRequirement(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get description => data['description'] as String;
  String get unit => data['unit'] as String? ?? 'ea';
  String? get stockId => data['stock_id'] as String?;
  double get required => partNumberValue(data['required_qty']);
  double get reserved => partNumberValue(data['reserved_qty']);
  double get used => partNumberValue(data['used_qty']);
  double get remaining => math.max(0, required - reserved - used);
  double shortage(StockItem? stock) =>
      math.max(0, remaining - (stock?.available ?? 0));
  double reservable(StockItem? stock) =>
      math.min(remaining, stock?.available ?? 0);
}

List<Map<String, dynamic>> partsRows(Object? value) => (value as List? ?? [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();

class PartsWorkspace {
  PartsWorkspace(this.data);
  final Map<String, dynamic> data;
  String get currency => data['cost_currency'] as String? ?? 'USD';
  bool get canManage => data['can_manage'] == true;
  bool get canChange => data['can_change'] == true;
  bool get canIssue => data['can_issue'] == true;
  List<StockItem> get stock =>
      partsRows(data['stock']).map(StockItem.new).toList();
  List<JobPartRequirement> get requirements =>
      partsRows(data['requirements']).map(JobPartRequirement.new).toList();
  List<Map<String, dynamic>> get purchases => partsRows(data['purchases']);
  List<Map<String, dynamic>> get events => partsRows(data['events']);
  StockItem? stockFor(JobPartRequirement requirement) =>
      stock.where((s) => s.id == requirement.stockId).firstOrNull;
  double outstanding(String requirementId) => purchases
      .where(
        (p) =>
            p['requirement_id'] == requirementId &&
            (p['status'] == 'requested' || p['status'] == 'ordered'),
      )
      .fold(
        0,
        (total, p) =>
            total +
            partNumberValue(p['quantity']) -
            partNumberValue(p['received_qty']),
      );
}
