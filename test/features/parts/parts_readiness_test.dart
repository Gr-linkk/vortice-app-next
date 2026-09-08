import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/parts/parts_readiness_models.dart';

void main() {
  test('Friday service exposes shortage without treating orders as stock', () {
    final workspace = PartsWorkspace({
      'stock': [
        {
          'id': 'filter',
          'description': 'Filter',
          'qty_on_hand': 1,
          'reserved': 0,
        },
      ],
      'requirements': [
        {
          'id': 'job-filter',
          'description': 'Filter',
          'required_qty': 2,
          'reserved_qty': 0,
          'used_qty': 0,
          'stock_id': 'filter',
        },
      ],
      'purchases': [
        {
          'requirement_id': 'job-filter',
          'quantity': 1,
          'received_qty': 0,
          'status': 'ordered',
        },
      ],
    });
    final requirement = workspace.requirements.single;
    expect(requirement.shortage(workspace.stockFor(requirement)), 1);
    expect(requirement.reservable(workspace.stockFor(requirement)), 1);
    expect(workspace.outstanding(requirement.id), 1);
  });
  test(
    'other jobs reservations are unavailable and used parts satisfy demand',
    () {
      final stock = StockItem({
        'id': 's',
        'description': 'Seal',
        'qty_on_hand': 3,
        'reserved': 2,
      });
      final requirement = JobPartRequirement({
        'id': 'r',
        'description': 'Seal',
        'required_qty': 4,
        'reserved_qty': 1,
        'used_qty': 1,
      });
      expect(requirement.remaining, 2);
      expect(requirement.reservable(stock), 1);
      expect(requirement.shortage(stock), 1);
    },
  );
}
