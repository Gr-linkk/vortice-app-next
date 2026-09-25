import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';
import 'package:vortice_app/features/maintenance/work_focus.dart';
import 'package:vortice_app/models/work_order.dart';

void main() {
  test(
    'work-order and scheduling labels have Canadian French variants',
    () async {
      await initializeDateFormatting('fr_CA');
      expect(maintenanceStatus('in_progress', false, french: true), 'En cours');
      expect(
        maintenanceStatus('pending_review', false, french: true),
        'En attente de révision',
      );
      expect(maintenancePriority('high', false, french: true), 'Élevée');
      expect(
        WorkFocus.customer.label(false, french: true),
        'Travail pour les clients',
      );
      expect(
        WorkOrderJobType.preventative.label(false, fr: true),
        'Entretien préventif',
      );
      expect(
        maintenanceEvent('submit', false, french: true),
        'Soumis pour révision',
      );
      expect(
        maintenanceDate('2026-03-04', false, french: true),
        contains('mars'),
      );
    },
  );
}
