import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/fleet/fleet_models.dart';
import 'package:vortice_app/features/fleet/fleet_policy.dart';
import 'package:vortice_app/models/profile.dart';

void main() {
  test(
    'an assigned mechanic submits repair for review, but cannot resolve it',
    () {
      final fault = FleetFault.fromJson({
        'id': 'fault',
        'asset_id': 'asset',
        'description': 'Hydraulic leak',
        'status': 'in_progress',
        'assigned_to': 'mechanic',
        'revision': 2,
      });
      final actions = availableFaultActions(
        fault: fault,
        role: UserRole.clientMechanic,
        userId: 'mechanic',
      );
      expect(actions, contains(FaultAction.submit));
      expect(actions, isNot(contains(FaultAction.resolve)));
      expect(
        availableFaultActions(
          fault: fault,
          role: UserRole.clientMechanic,
          userId: 'someone-else',
        ),
        isEmpty,
      );
    },
  );

  test('unassessed equipment never defaults to available', () {
    final asset = FleetAsset.fromJson({'id': 'a', 'name': 'Generator'});
    expect(asset.state, OperatingState.unknown);
    expect(asset.revision, 0);
  });

  test('downtime combines finished episodes with the current outage', () {
    final asset = FleetAsset.fromJson({
      'id': 'a',
      'name': 'Generator',
      'operating_state': 'under_maintenance',
      'unavailable_since': '2026-09-05T10:00:00Z',
      'downtime_seconds': 3600,
    });
    expect(
      asset.totalDowntime(DateTime.utc(2026, 9, 5, 12)),
      const Duration(hours: 3),
    );
  });
}
