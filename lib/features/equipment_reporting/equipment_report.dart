import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/coordination/coordination_repository.dart'
    show csvCell;
import 'package:vortice_app/models/profile.dart';

typedef ReportPeriod = ({DateTime from, DateTime to});
typedef ReportLoader = Future<EquipmentReport> Function(ReportPeriod period);

bool canReadEquipmentReport(UserRole? role) =>
    role == UserRole.owner ||
    role == UserRole.client ||
    role == UserRole.clientAdmin;

List<Map<String, dynamic>> reportRows(dynamic value) => (value as List? ?? [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();
double reportNumber(Map<String, dynamic> row, String key) =>
    (row[key] as num?)?.toDouble() ?? 0;
int possibleRepeatCount(Map<String, dynamic> asset) => reportRows(
  asset['repeats'],
).fold(0, (sum, group) => sum + (group['count'] as num).toInt() - 1);

class EquipmentReport {
  EquipmentReport(this.data);
  final Map<String, dynamic> data;
  String get currency => data['currency'] as String? ?? 'USD';
  List<String> get currencies =>
      (data['currencies'] as List? ?? [currency]).cast<String>();
  EquipmentReport inCurrency(String selected) => EquipmentReport({
    ...data,
    'currency': selected,
    'assets': [for (final a in assets) _assetCurrency(a, selected)],
  });
  Map<String, dynamic> _assetCurrency(
    Map<String, dynamic> asset,
    String selected,
  ) {
    final amounts = Map<String, dynamic>.from(
      asset['amounts_by_currency'] as Map? ??
          {
            currency: {
              for (final key in ['labour', 'parts', 'outside', 'total'])
                key: asset[key] ?? 0,
            },
          },
    );
    return {
      ...asset,
      'amounts_by_currency': amounts,
      for (final key in ['labour', 'parts', 'outside', 'total'])
        key: (amounts[selected] as Map?)?[key] ?? 0,
      'records': [
        for (final r in reportRows(asset['records']))
          {...r, 'currency': r['currency'] ?? currency},
      ],
    };
  }

  List<Map<String, dynamic>> get assets => reportRows(data['assets']);
  double total(String key) =>
      assets.fold(0, (sum, row) => sum + reportNumber(row, key));
}

final equipmentReportLoaderProvider = Provider<ReportLoader>((ref) {
  final client = supabase;
  return (period) async => EquipmentReport(
    Map<String, dynamic>.from(
      await client
              .rpc(
                'equipment_report',
                params: {
                  'p_from': period.from.toUtc().toIso8601String(),
                  'p_to': period.to.toUtc().toIso8601String(),
                },
              )
              .timeout(const Duration(seconds: 45))
          as Map,
    ),
  );
});

final equipmentReportProvider = FutureProvider.autoDispose
    .family<EquipmentReport, ReportPeriod>((ref, period) async {
      final profile = await ref.watch(profileProvider.future);
      if (!canReadEquipmentReport(profile?.role)) {
        throw StateError('Access denied');
      }
      return ref.watch(equipmentReportLoaderProvider)(period);
    });

String reportRecordDestination(
  Map<String, dynamic> row,
  String assetId,
  UserRole? role,
) => switch (row['kind']) {
  'internal' => '/maintenance/jobs/${row['id']}',
  'internal_missing' => '/maintenance/jobs/${row['id']}',
  'invoice' =>
    '${role == UserRole.owner ? '/owner' : '/client'}/invoices/${row['id']}',
  'fault' => '/fleet/faults/${row['id']}',
  'downtime' => '/fleet/assets/$assetId',
  'uncosted' when role == UserRole.owner => '/owner/work-orders/${row['id']}',
  'uncosted' => '/client/service-reports?workOrderId=${row['id']}',
  _ => '/history/assets/$assetId',
};

String reportKind(String kind, bool es, {bool french = false}) =>
    switch (kind) {
      'internal' =>
        french
            ? 'Travail interne approuvé'
            : es
            ? 'Trabajo interno aprobado'
            : 'Approved internal work',
      'internal_missing' =>
        french
            ? 'Travail approuvé sans justificatif de coût'
            : es
            ? 'Trabajo aprobado sin recibo de costos'
            : 'Approved work missing cost receipt',
      'invoice' =>
        french
            ? 'Facture du fournisseur (taxes comprises)'
            : es
            ? 'Factura del proveedor (con impuestos)'
            : 'Provider invoice (including tax)',
      'uncosted' =>
        french
            ? 'Travail sans facture émise'
            : es
            ? 'Trabajo sin factura emitida'
            : 'Work without an issued invoice',
      'downtime' =>
        french
            ? 'Indisponible'
            : es
            ? 'Fuera de servicio'
            : 'Unavailable',
      _ =>
        french
            ? 'Défaillance consignée'
            : es
            ? 'Falla registrada'
            : 'Recorded fault',
    };

String equipmentReportCsv(EquipmentReport report, {bool spanish = false}) {
  final es = spanish;
  final rows = <List<String>>[
    [es ? 'Informe de equipos' : 'Equipment report', report.currency],
    [es ? 'Desde (UTC)' : 'From (UTC)', '${report.data['from']}'],
    [
      es ? 'Hasta (exclusivo, UTC)' : 'Until (exclusive, UTC)',
      '${report.data['to']}',
    ],
    [
      es ? 'Generado (UTC)' : 'Generated (UTC)',
      '${report.data['generated_at']}',
    ],
    [
      es ? 'Base' : 'Basis',
      es
          ? 'Costos internos aprobados; facturas enviadas o pagadas con impuestos. No es un libro contable.'
          : 'Approved internal costs; sent or paid invoices including tax. Not an accounting ledger.',
    ],
    [
      es ? 'Cobertura' : 'Coverage',
      es
          ? 'Los costos cero pueden estar sin registrar. Fallas repetidas: descripciones coincidentes, no diagnosticos confirmados.'
          : 'Zero costs may be unrecorded. Repeat faults: matching descriptions, not confirmed diagnoses.',
    ],
    [],
    [
      es ? 'Equipo' : 'Equipment',
      'ID',
      es ? 'Ubicación' : 'Location',
      es ? 'Mano de obra ${report.currency}' : 'Labour ${report.currency}',
      es ? 'Repuestos ${report.currency}' : 'Parts ${report.currency}',
      es
          ? 'Servicio externo ${report.currency}'
          : 'Outside service ${report.currency}',
      es
          ? 'Total registrado ${report.currency}'
          : 'Recorded total ${report.currency}',
      es ? 'Horas no disponible' : 'Unavailable hours',
      es ? 'Horas sin historial' : 'Unknown availability hours',
      es ? 'Costos incompletos' : 'Cost gaps',
      es ? 'Fallas' : 'Faults',
      es ? 'Grupos coincidentes' : 'Matching groups',
    ],
    for (final a in report.assets)
      [
        '${a['name']}',
        '${a['id']}',
        '${a['location'] ?? ''}',
        for (final key in [
          'labour',
          'parts',
          'outside',
          'total',
          'unavailable_hours',
          'unknown_hours',
        ])
          reportNumber(a, key).toStringAsFixed(2),
        '${a['cost_gaps']}',
        '${a['fault_count']}',
        '${reportRows(a['repeats']).length}',
      ],
    [],
    [
      es ? 'Equipo' : 'Equipment',
      es ? 'Tipo' : 'Type',
      'ID',
      es ? 'Registro' : 'Record',
      es ? 'Fecha (UTC)' : 'Date (UTC)',
      es ? 'Moneda' : 'Currency',
      es ? 'Mano de obra' : 'Labour',
      es ? 'Repuestos' : 'Parts',
      es ? 'Servicio externo' : 'Outside service',
      es ? 'Horas' : 'Hours',
      es ? 'Costos incompletos' : 'Cost gaps',
    ],
    for (final a in report.assets)
      for (final r in reportRows(a['records']))
        [
          '${a['name']}',
          reportKind('${r['kind']}', es),
          '${r['id']}',
          '${r['title']}',
          '${r['occurred_at']}',
          '${r['currency'] ?? report.currency}',
          for (final key in ['labour', 'parts', 'outside', 'hours'])
            reportNumber(r, key).toStringAsFixed(2),
          '${r['gaps']}',
        ],
    [],
    [
      es ? 'Equipo' : 'Equipment',
      es ? 'Descripción coincidente' : 'Matching description',
      es ? 'Cantidad' : 'Count',
      'IDs',
    ],
    for (final a in report.assets)
      for (final r in reportRows(a['repeats']))
        [
          '${a['name']}',
          '${r['description']}',
          '${r['count']}',
          (r['ids'] as List).join(' '),
        ],
  ];
  return '\uFEFF${rows.map((r) => r.map(csvCell).join(',')).join('\r\n')}\r\n';
}
