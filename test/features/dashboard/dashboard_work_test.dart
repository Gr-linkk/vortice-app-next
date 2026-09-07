import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/dashboard/dashboard_work.dart';
import 'package:vortice_app/features/maintenance/work_list_provider.dart';

WorkListEntry entry(
  String id,
  String status, {
  bool mine = true,
  String? due,
}) => WorkListEntry(
  id: id,
  title: id,
  assetName: 'Pump',
  status: status,
  route: '/maintenance/jobs/$id',
  assignedToMe: mine,
  service: false,
  dueDate: due,
);
void main() {
  test('home shows personally assigned open work, current before queued', () {
    final result = dashboardCurrentWork([
      entry('completed', 'closed'),
      entry('other', 'in_progress', mine: false),
      entry('later', 'assigned', due: '2026-09-12'),
      entry('sooner', 'assigned', due: '2026-09-08'),
      entry('blocked', 'on_hold'),
      entry('current', 'in_progress'),
    ]);
    expect(result.map((e) => e.id), ['current', 'blocked', 'sooner', 'later']);
  });
  test('empty queue does not turn other peoples work into personal work', () {
    expect(
      dashboardCurrentWork([entry('other', 'assigned', mine: false)]),
      isEmpty,
    );
  });
}
