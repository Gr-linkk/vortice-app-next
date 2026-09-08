import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'equipment_report.dart';

final shareEquipmentReportProvider =
    Provider<Future<void> Function(String, Rect?)>(
      (ref) => (csv, rect) async {
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                Uint8List.fromList(utf8.encode(csv)),
                mimeType: 'text/csv',
              ),
            ],
            fileNameOverrides: ['equipment-report.csv'],
            sharePositionOrigin: rect,
          ),
        );
      },
    );

class EquipmentReportScreen extends ConsumerStatefulWidget {
  const EquipmentReportScreen({super.key});
  @override
  ConsumerState<EquipmentReportScreen> createState() =>
      _EquipmentReportScreenState();
}

class _EquipmentReportScreenState extends ConsumerState<EquipmentReportScreen> {
  late ReportPeriod _period;
  String _sort = 'total';
  bool _exporting = false;
  Object? _exportError;
  bool get es => Localizations.localeOf(context).languageCode == 'es';
  String text(String en, String spanish) => es ? spanish : en;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _period = (
      from: DateTime(now.year, now.month),
      to: DateTime(now.year, now.month, now.day + 1),
    );
  }

  void selectPeriod(ReportPeriod period) => setState(() {
    _period = period;
    _exportError = null;
  });

  Future<void> pickPeriod() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: _period.from,
        end: _period.to.subtract(const Duration(days: 1)),
      ),
    );
    if (!mounted || picked == null) return;
    final end = DateTime(picked.end.year, picked.end.month, picked.end.day + 1);
    if (end.difference(picked.start).inHours > 366 * 24) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            text('Choose at most 366 days.', 'Elige un máximo de 366 días.'),
          ),
        ),
      );
      return;
    }
    selectPeriod((from: picked.start, to: end));
  }

  Future<void> export() async {
    final period = _period;
    final identity = ref.read(profileProvider).valueOrNull;
    setState(() {
      _exporting = true;
      _exportError = null;
    });
    try {
      // Re-authorize and query all data in one database snapshot for every export.
      final report = await ref.read(equipmentReportLoaderProvider)(period);
      if (!mounted ||
          ref.read(profileProvider).isLoading ||
          ref.read(profileProvider).hasError ||
          identity != ref.read(profileProvider).valueOrNull ||
          !canReadEquipmentReport(
            ref.read(profileProvider).valueOrNull?.role,
          )) {
        return;
      }
      final box = context.findRenderObject() as RenderBox?;
      await ref.read(shareEquipmentReportProvider)(
        equipmentReportCsv(report, spanish: es),
        box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (error) {
      if (mounted) setState(() => _exportError = error);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final role = profile.valueOrNull?.role;
    final allowed =
        !profile.isLoading && !profile.hasError && canReadEquipmentReport(role);
    final report = allowed ? ref.watch(equipmentReportProvider(_period)) : null;
    final now = DateTime.now();
    final formatter = DateFormat.yMMMd(es ? 'es' : 'en');
    return Scaffold(
      appBar: AppBar(
        title: Text(text('Equipment report', 'Informe de equipos')),
        actions: [
          if (allowed)
            IconButton(
              tooltip: text('Refresh', 'Actualizar'),
              onPressed: () => ref.invalidate(equipmentReportProvider(_period)),
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: SafeArea(
        child: !allowed
            ? Center(
                child: profile.isLoading
                    ? const CircularProgressIndicator()
                    : Text(
                        text(
                          'Available to fleet managers.',
                          'Disponible para administradores de flota.',
                        ),
                      ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    text(
                      'Where is maintenance costing you most?',
                      '¿Qué equipos cuestan más mantener?',
                    ),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: _exporting
                            ? null
                            : () => selectPeriod((
                                from: DateTime(now.year, now.month),
                                to: DateTime(now.year, now.month, now.day + 1),
                              )),
                        child: Text(text('This month', 'Este mes')),
                      ),
                      OutlinedButton(
                        onPressed: _exporting
                            ? null
                            : () => selectPeriod((
                                from: DateTime(now.year, now.month - 1),
                                to: DateTime(now.year, now.month),
                              )),
                        child: Text(text('Last month', 'Mes anterior')),
                      ),
                      OutlinedButton(
                        onPressed: _exporting
                            ? null
                            : () => selectPeriod((
                                from: DateTime(
                                  now.year,
                                  ((now.month - 1) ~/ 3) * 3 + 1,
                                ),
                                to: DateTime(now.year, now.month, now.day + 1),
                              )),
                        child: Text(text('This quarter', 'Este trimestre')),
                      ),
                      OutlinedButton.icon(
                        onPressed: _exporting ? null : pickPeriod,
                        icon: const Icon(Icons.date_range),
                        label: Text(text('Choose dates', 'Elegir fechas')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${formatter.format(_period.from)} – ${formatter.format(_period.to.subtract(const Duration(days: 1)))}',
                  ),
                  const SizedBox(height: 16),
                  report!.when(
                    skipLoadingOnRefresh: false,
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => AppErrorState(
                      error: error,
                      onRetry: () =>
                          ref.invalidate(equipmentReportProvider(_period)),
                    ),
                    data: (data) {
                      final assets = data.assets
                        ..sort((a, b) {
                          final compared = _sort == 'repeats'
                              ? possibleRepeatCount(
                                  b,
                                ).compareTo(possibleRepeatCount(a))
                              : reportNumber(
                                  b,
                                  _sort,
                                ).compareTo(reportNumber(a, _sort));
                          return compared == 0
                              ? '${a['name']}'.compareTo('${b['name']}')
                              : compared;
                        });
                      if (assets.isEmpty) {
                        return Text(
                          text(
                            'No equipment is available in your fleet.',
                            'No hay equipos disponibles en tu flota.',
                          ),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    text(
                                      'Recorded maintenance cost',
                                      'Costo de mantenimiento registrado',
                                    ),
                                  ),
                                  Text(
                                    'USD ${data.total('total').toStringAsFixed(2)}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${text('Labour', 'Mano de obra')}: ${data.total('labour').toStringAsFixed(2)} · ${text('Parts', 'Repuestos')}: ${data.total('parts').toStringAsFixed(2)} · ${text('Outside service', 'Servicio externo')}: ${data.total('outside').toStringAsFixed(2)}',
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${data.total('unavailable_hours').toStringAsFixed(1)} ${text('equipment-hours unavailable', 'horas de equipos no disponibles')}',
                                  ),
                                  Text(
                                    text(
                                      'Approved internal costs and sent or paid provider invoices, including invoice tax.',
                                      'Costos internos aprobados y facturas enviadas o pagadas del proveedor, con impuestos.',
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${text('Updated', 'Actualizado')}: ${DateFormat.yMMMd(es ? 'es' : 'en').add_Hm().format(DateTime.parse(data.data['generated_at'] as String).toLocal())}',
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (data.total('cost_gaps') > 0 ||
                              data.total('unknown_hours') > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                '${data.total('cost_gaps').toInt()} ${text('cost gaps or zero-cost entries to check', 'costos incompletos o en cero por revisar')}. ${data.total('unknown_hours').toStringAsFixed(1)} ${text('equipment-hours without availability history', 'horas de equipos sin historial de disponibilidad')}.',
                              ),
                            ),
                          Text(
                            text(
                              'Totals reflect recorded data, not full ownership cost. Matching fault descriptions are possible repeats, not confirmed diagnoses.',
                              'Los totales reflejan datos registrados, no el costo total de propiedad. Descripciones coincidentes son posibles repeticiones, no diagnósticos confirmados.',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final entry in {
                                'total': text('Cost', 'Costo'),
                                'unavailable_hours': text(
                                  'Downtime',
                                  'Inactividad',
                                ),
                                'repeats': text(
                                  'Repeat faults',
                                  'Fallas repetidas',
                                ),
                              }.entries)
                                ChoiceChip(
                                  label: Text(entry.value),
                                  selected: _sort == entry.key,
                                  onSelected: (_) =>
                                      setState(() => _sort = entry.key),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          for (final a in assets)
                            Card(
                              child: ExpansionTile(
                                key: ValueKey('${_period.from}-${a['id']}'),
                                title: Text('${a['name']}'),
                                subtitle: Text(
                                  'USD ${reportNumber(a, 'total').toStringAsFixed(2)} · ${reportNumber(a, 'unavailable_hours').toStringAsFixed(1)} h · ${a['fault_count']} ${text('faults', 'fallas')}${possibleRepeatCount(a) > 0 ? '\n${text('Possible repeats', 'Posibles repeticiones')}: ${possibleRepeatCount(a)}' : ''}',
                                ),
                                childrenPadding: const EdgeInsets.all(12),
                                expandedCrossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  if (a['location'] != null)
                                    Text('${a['location']}'),
                                  Text(
                                    '${text('Labour / parts / outside service (USD)', 'Mano de obra / repuestos / servicio externo (USD)')}: ${reportNumber(a, 'labour').toStringAsFixed(2)} / ${reportNumber(a, 'parts').toStringAsFixed(2)} / ${reportNumber(a, 'outside').toStringAsFixed(2)}',
                                  ),
                                  Text(
                                    '${a['cost_gaps']} ${text('cost gaps', 'costos incompletos')} · ${reportNumber(a, 'unknown_hours').toStringAsFixed(1)} h ${text('without availability history', 'sin historial de disponibilidad')}',
                                  ),
                                  for (final repeat in reportRows(a['repeats']))
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Text(
                                        '${text('Possible repeat', 'Posible repetición')}: ${repeat['description']} (${repeat['count']})',
                                      ),
                                    ),
                                  if (reportRows(a['records']).isEmpty)
                                    Text(
                                      text(
                                        'No records in this period.',
                                        'Sin registros en este período.',
                                      ),
                                    ),
                                  for (final r in reportRows(a['records']))
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        '${r['title']}'.isEmpty
                                            ? reportKind('${r['kind']}', es)
                                            : '${r['title']}',
                                      ),
                                      subtitle: Text(
                                        '${reportKind('${r['kind']}', es)} · ${formatter.format(DateTime.parse(r['occurred_at'] as String).toLocal())}\n${r['kind'] == 'downtime'
                                            ? '${reportNumber(r, 'hours').toStringAsFixed(1)} h'
                                            : r['kind'] == 'fault'
                                            ? ''
                                            : 'USD ${(reportNumber(r, 'labour') + reportNumber(r, 'parts') + reportNumber(r, 'outside')).toStringAsFixed(2)}'}',
                                      ),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () => context.push(
                                        reportRecordDestination(
                                          r,
                                          '${a['id']}',
                                          role,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _exporting ? null : export,
                            icon: const Icon(Icons.ios_share),
                            label: Text(
                              _exporting
                                  ? text(
                                      'Preparing export…',
                                      'Preparando exportación…',
                                    )
                                  : text('Export report', 'Exportar informe'),
                            ),
                          ),
                          if (_exportError != null)
                            AppErrorState(
                              error: _exportError!,
                              onRetry: export,
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
      ),
    );
  }
}
