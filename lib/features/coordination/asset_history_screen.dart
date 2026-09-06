import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/features/fleet/fleet_widgets.dart';
import 'coordination_repository.dart';
import 'coordination_labels.dart';

class AssetHistoryScreen extends ConsumerStatefulWidget {
  const AssetHistoryScreen({super.key, required this.assetId});
  final String assetId;
  @override
  ConsumerState<AssetHistoryScreen> createState() => _AssetHistoryScreenState();
}

class _AssetHistoryScreenState extends ConsumerState<AssetHistoryScreen> {
  final _search = TextEditingController();
  late HistoryQuery _query = HistoryQuery(asset: widget.assetId);
  final _pages = <HistoryQuery>[];
  String? _category;
  DateTimeRange? _dates;
  bool _exporting = false;
  Object? _exportError;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _filter() => setState(() {
    _pages.clear();
    _query = HistoryQuery(
      asset: widget.assetId,
      category: _category,
      search: _search.text.trim(),
      from: _dates?.start.toUtc().toIso8601String(),
      to: _dates == null
          ? null
          : DateTime(
              _dates!.end.year,
              _dates!.end.month,
              _dates!.end.day + 1,
            ).toUtc().toIso8601String(),
    );
    ref.invalidate(assetHistoryProvider(_query));
  });
  Future<void> _export(Map<String, dynamic> page) async {
    setState(() {
      _exporting = true;
      _exportError = null;
    });
    final es = fleetSpanish(context);
    try {
      final filter = HistoryQuery(
        asset: widget.assetId,
        category: _query.category,
        search: _query.search,
        from: _query.from,
        to: _query.to,
        asOf: page['as_of'] as String,
      );
      final csv = await exportAssetHistory(
        filter,
        ref.read(coordinationRepositoryProvider).history,
        spanish: es,
      );
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          title:
              '${es ? 'Historial' : 'Service history'} — ${page['asset_name']}',
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(csv)),
              mimeType: 'text/csv',
            ),
          ],
          fileNameOverrides: ['Vortice-history-${localCalendarDate()}.csv'],
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _exportError = error);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final es = fleetSpanish(context);
    final result = ref.watch(assetHistoryProvider(_query));
    return Scaffold(
      appBar: AppBar(
        title: Text(es ? 'Historial del activo' : 'Asset history'),
        actions: [
          IconButton(
            tooltip: es ? 'Actualizar' : 'Refresh',
            onPressed: _exporting ? null : _filter,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              es
                  ? 'Lecturas, fallas, trabajo y relevo en un solo registro.'
                  : 'Readings, faults, work and handovers in one record.',
            ),
            const SizedBox(height: 16),
            AppDropdownField<String>(
              initialValue: _category ?? 'all',
              decoration: InputDecoration(
                labelText: es ? 'Categoría' : 'Category',
              ),
              items: [
                DropdownMenuItem(
                  value: 'all',
                  child: Text(es ? 'Todo el historial' : 'All history'),
                ),
                for (final key in historyCategories.keys)
                  DropdownMenuItem(
                    value: key,
                    child: Text(coordinationLabel(historyCategories, key, es)),
                  ),
              ],
              onChanged: _exporting
                  ? null
                  : (value) {
                      _category = value == 'all' ? null : value;
                      _filter();
                    },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _search,
              maxLength: 200,
              enabled: !_exporting,
              decoration: InputDecoration(
                labelText: es ? 'Buscar en el historial' : 'Search history',
                counterText: '',
                suffixIcon: IconButton(
                  tooltip: es ? 'Buscar' : 'Search',
                  onPressed: _exporting ? null : _filter,
                  icon: const Icon(Icons.search),
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _filter(),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    _dates == null
                        ? (es ? 'Filtrar fechas' : 'Filter dates')
                        : '${localCalendarDate(_dates!.start)} – ${localCalendarDate(_dates!.end)}',
                  ),
                  onPressed: _exporting
                      ? null
                      : () async {
                          final dates = await showDateRangePicker(
                            context: context,
                            initialDateRange: _dates,
                            firstDate: DateTime(1970),
                            lastDate: DateTime(DateTime.now().year + 5),
                          );
                          if (dates != null && mounted) {
                            _dates = dates;
                            _filter();
                          }
                        },
                ),
                if (_dates != null)
                  TextButton(
                    onPressed: _exporting
                        ? null
                        : () {
                            _dates = null;
                            _filter();
                          },
                    child: Text(es ? 'Todas las fechas' : 'All dates'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_exportError != null)
              FleetError(
                error: _exportError!,
                onRetry: () {
                  if (result.valueOrNull != null) _export(result.valueOrNull!);
                },
              ),
            result.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => FleetError(
                error: error,
                onRetry: () => ref.invalidate(assetHistoryProvider(_query)),
              ),
              data: (page) {
                final rows = coordinationRows(page['entries']);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      page['asset_name'] as String? ?? '',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _exporting ? null : () => _export(page),
                      icon: const Icon(Icons.ios_share),
                      label: Text(
                        _exporting
                            ? (es
                                  ? 'Preparando todas las páginas…'
                                  : 'Preparing all pages…')
                            : (es
                                  ? 'Exportar historial filtrado'
                                  : 'Export filtered history'),
                      ),
                    ),
                    if (rows.isEmpty)
                      FleetEmpty(
                        title: es ? 'Sin eventos' : 'No events',
                        message: es
                            ? 'Prueba otra categoría, fecha o búsqueda.'
                            : 'Try another category, date or search.',
                      ),
                    for (final row in rows) _HistoryEvent(row: row),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        if (_pages.isNotEmpty)
                          OutlinedButton(
                            onPressed: _exporting
                                ? null
                                : () => setState(
                                    () => _query = _pages.removeLast(),
                                  ),
                            child: Text(es ? 'Más recientes' : 'Newer'),
                          ),
                        if (page['has_more'] == true)
                          FilledButton(
                            onPressed: _exporting
                                ? null
                                : () => setState(() {
                                    _pages.add(_query);
                                    _query = _query.next(page);
                                  }),
                            child: Text(es ? 'Más antiguos' : 'Older'),
                          ),
                      ],
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

class _HistoryEvent extends ConsumerWidget {
  const _HistoryEvent({required this.row});
  final Map<String, dynamic> row;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final es = fleetSpanish(context);
    final detail = Map<String, dynamic>.from(row['detail'] as Map? ?? {});
    String? route;
    if (row['post_id'] != null) {
      route =
          '/discussion/${detail['subject_kind']}/${detail['subject_id']}?post=${row['post_id']}';
    } else if (row['category'] == 'fault') {
      route = '/fleet/faults/${row['source_id']}';
    } else if (row['managed'] == true && row['job_id'] != null) {
      route = '/maintenance/jobs/${row['job_id']}';
    } else if (row['category'] == 'availability') {
      route = '/fleet/assets/${row['asset_id']}';
    } else if (row['job_id'] != null &&
        !(row['kind'] as String? ?? '').endsWith('removed')) {
      final role = ref.watch(profileProvider).valueOrNull?.role;
      if (role == UserRole.owner || role == UserRole.employee) {
        route =
            '/${role == UserRole.owner ? 'owner' : 'employee'}/work-orders/${row['job_id']}';
      }
    }
    final destination = route;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(historyKindLabel(row['kind'] as String?, es)),
        subtitle: Text(
          '${coordinationLabel(historyCategories, row['category'] as String? ?? '', es)} · ${fleetDate(context, DateTime.tryParse(row['occurred_at'] as String? ?? ''))}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((row['title'] as String? ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                row['title'] as String,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          if ((row['body'] as String? ?? '').isNotEmpty)
            Text(row['body'] as String),
          if (row['actor_name'] != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(row['actor_name'] as String),
            ),
          if (historyDetailText(detail, es).isNotEmpty)
            SelectableText(historyDetailText(detail, es)),
          if (destination != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(
                onPressed: () => context.push(destination),
                icon: const Icon(Icons.open_in_new),
                label: Text(es ? 'Abrir registro' : 'Open record'),
              ),
            ),
        ],
      ),
    );
  }
}
