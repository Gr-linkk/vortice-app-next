import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import '../asset_provider.dart';
import '../asset_type_provider.dart';
import '../asset_workspace.dart';
import '../asset_workflow_policy.dart';
import 'fleet_import_table.dart';
import 'fleet_import_mapping.dart';
import 'fleet_import_repository.dart';

class FleetImportScreen extends ConsumerStatefulWidget {
  const FleetImportScreen({super.key});
  @override
  ConsumerState<FleetImportScreen> createState() => _FleetImportScreenState();
}

class _FleetImportScreenState extends ConsumerState<FleetImportScreen> {
  final paste = TextEditingController();
  Map<String, dynamic>? data, pending, result;
  FleetImportTable? table;
  String? sheet, client, defaultType, template, error;
  String unit = 'hours', dateFormat = 'iso', delimiter = 'auto', filename = '';
  bool comma = false, busy = false;
  int header = 0, step = 0;
  Map<String, int> columns = {};
  final excluded = <int>{};
  final typeValues = <String, String>{};
  FleetImportReview? review;
  Uint8List? sourceBytes;
  String? actor, organization;
  bool get es => isSpanish(context);
  String t(String en, String esText) => es ? esText : en;
  FleetImportRepository get repo => ref.read(fleetImportRepositoryProvider);
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  @override
  void dispose() {
    paste.dispose();
    super.dispose();
  }

  bool sameAccount() {
    final p = ref.read(profileProvider).valueOrNull;
    return p?.id == actor && p?.orgId == organization;
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        error = e is FormatException ? e.message : friendlyError(context, e);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load() => run(() async {
    final p = await ref.read(profileProvider.future);
    if (!mounted) return;
    actor = p?.id;
    organization = p?.orgId;
    final saved = await repo.pending();
    final loaded = await repo.context(saved?['p_client'] as String? ?? client);
    if (!mounted || !sameAccount()) return;
    pending = saved;
    data = loaded;
    client = loaded['client_id'] as String;
    if (saved != null) step = 3;
  });
  List<List<String>> get rows => table?.sheets[sheet] ?? [];
  void resetColumns() {
    columns = header < 0 ? {'name': 0} : suggestFleetColumns(rows[header]);
    excluded.clear();
    typeValues.clear();
    review = null;
  }

  Future<void> chooseFile() => run(() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Spreadsheets',
          extensions: ['xlsx', 'csv', 'tsv', 'txt'],
          uniformTypeIdentifiers: [
            'public.spreadsheet',
            'public.comma-separated-values-text',
            'public.tab-separated-values-text',
            'public.plain-text',
          ],
        ),
      ],
    );
    if (file == null) return;
    if (await file.length() > FleetImportTable.maxBytes) {
      throw const FormatException('Use a file smaller than 5 MB.');
    }
    sourceBytes = await file.readAsBytes();
    filename = file.name;
    await decode();
  });
  Future<void> decode() async {
    final bytes = sourceBytes!,
        name = filename,
        sep = delimiter == 'auto' ? null : delimiter;
    final parsed = await compute(
      (_) => FleetImportTable.bytes(bytes, name, delimiter: sep),
      null,
    );
    if (!mounted) return;
    if (parsed.sheets.isEmpty || parsed.sheets.values.every((r) => r.isEmpty)) {
      throw const FormatException('The workbook is empty.');
    }
    table = parsed;
    sheet = parsed.sheets.entries.firstWhere((e) => e.value.isNotEmpty).key;
    header = 0;
    step = 1;
    resetColumns();
  }

  Future<void> fromPaste() => run(() async {
    table = FleetImportTable.text(
      paste.text,
      delimiter: delimiter == 'auto' ? null : delimiter,
    );
    sourceBytes = null;
    filename = t('Pasted table', 'Tabla pegada');
    sheet = table!.sheets.keys.first;
    header = 0;
    step = 1;
    resetColumns();
  });
  Future<void> inspect() => run(() async {
    if (!sameAccount()) throw StateError('Company changed. Reopen the import.');
    final types = await ref.read(assetTypesProvider.future);
    final fresh = await repo.context(client);
    if (!mounted || !sameAccount()) return;
    data = fresh;
    review =
        FleetImportMapping(
          columns: columns,
          types: types,
          defaultType: defaultType,
          defaultUnit: unit,
          dateFormat: dateFormat,
          decimalComma: comma,
          template: template,
          typeValues: typeValues,
        ).review(
          rows,
          header,
          excluded: excluded,
          existing: (data!['assets'] as List)
              .map((r) => Map<String, dynamic>.from(r as Map))
              .toList(),
        );
    if (review!.assets.isNotEmpty && review!.errors.isEmpty) {
      final checked = await repo.preview(client!, review!.assets);
      for (final e in checked['errors'] as List) {
        final index = (e['row'] as int) - 1;
        for (final row in review!.rows[index]) {
          review!.errors[row] = e['message'].toString();
        }
      }
    }
    if (mounted) step = 2;
  });
  Future<void> save() => run(() async {
    if (!sameAccount()) throw StateError('Company changed. Reopen the import.');
    final assets = pending == null
        ? review!.assets
        : (pending!['p_assets'] as List)
              .map((a) => Map<String, dynamic>.from(a as Map))
              .toList();
    pending = {'p_client': client, 'p_assets': assets, 'p_preview': false};
    step = 3;
    Map<String, dynamic> saved;
    try {
      saved = await repo.commit(client!, assets);
    } on PostgrestException {
      // A database rejection acknowledges rollback; editing is safe again.
      await repo.discard();
      pending = null;
      step = table == null ? 0 : 1;
      rethrow;
    }
    if (!mounted || !sameAccount()) return;
    result = saved;
    pending = null;
    step = 4;
    ref.invalidate(visibleAssetsProvider);
    ref.invalidate(assetWorkspaceProvider);
  });
  Widget dropdown<T>(
    String label,
    T value,
    Map<T, String> options,
    ValueChanged<T?> change, {
    String? id,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (MediaQuery.textScalerOf(context).scale(1) > 1.3)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label),
          ),
        AppDropdownField<T>(
          key: ValueKey('${id ?? label}-$value'),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: MediaQuery.textScalerOf(context).scale(1) > 1.3
                ? null
                : label,
          ),
          items: [
            for (final e in options.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: change,
        ),
      ],
    ),
  );
  Widget title(String text) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 12),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );
  Widget note(String text) =>
      Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(text));
  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final types = ref.watch(assetTypesProvider).valueOrNull ?? [];
    final allowed = AssetWorkflowPolicy.canManageProfile(profile);
    final changed = actor != null && !sameAccount();
    final steps = [
      t('Choose a table', 'Elegir tabla'),
      t('Match columns', 'Asignar columnas'),
      t('Review import', 'Revisar importación'),
      t('Resolve import', 'Resolver importación'),
      t('Equipment imported', 'Equipos importados'),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(t('Import equipment', 'Importar equipos'))),
      body: !allowed || changed
          ? Center(
              child: Text(
                t(
                  'Reopen from the equipment list for your current company.',
                  'Vuelve a abrir desde los equipos de tu empresa actual.',
                ),
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: AbsorbPointer(
                  absorbing: busy,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      title(steps[step]),
                      if (busy) const LinearProgressIndicator(),
                      if (error != null)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(error!, key: const Key('import-error')),
                          ),
                        ),
                      if (data == null) ...[
                        note(
                          t(
                            'Connect to load your fleet and import permissions.',
                            'Conéctate para cargar tu flota y permisos.',
                          ),
                        ),
                        TextButton(
                          onPressed: load,
                          child: Text(t('Retry', 'Reintentar')),
                        ),
                      ] else ...[
                        if (step < 3 && (data!['clients'] as List).length > 1)
                          dropdown(
                            'Fleet / Flota',
                            client!,
                            {
                              for (final c in data!['clients'])
                                c['id'] as String: c['name'] as String,
                            },
                            (v) {
                              client = v;
                              step = 0;
                              load();
                            },
                          ),
                        if (step == 0) ...[
                          note(
                            t(
                              'Bring a fleet list from Excel, Google Sheets or another system. Choose XLSX, CSV or TSV, or paste rows below. You will review everything before saving.',
                              'Trae una lista de Excel, Google Sheets u otro sistema. Elige XLSX, CSV o TSV, o pega las filas. Revisarás todo antes de guardar.',
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: chooseFile,
                            icon: const Icon(Icons.upload_file),
                            label: Text(
                              t('Choose spreadsheet', 'Elegir hoja de cálculo'),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            key: const Key('import-paste'),
                            controller: paste,
                            maxLines: 6,
                            decoration: InputDecoration(
                              labelText: t(
                                'Or paste a table',
                                'O pega una tabla',
                              ),
                              hintText:
                                  'Name\tType\tSerial\nExcavator 12\tExcavator\t001234',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: fromPaste,
                            child: Text(
                              t('Use pasted table', 'Usar tabla pegada'),
                            ),
                          ),
                          note(
                            t(
                              'Keep serials / VINs as text in the source spreadsheet to preserve leading zeroes. Formula cells need to be pasted as values. Photos, PDFs and older XLS files need a table export first.',
                              'Guarda series / VIN como texto para conservar ceros iniciales. Pega fórmulas como valores. Fotos, PDF y XLS antiguos requieren exportar una tabla.',
                            ),
                          ),
                        ],
                        if (step == 1) ...[
                          note(filename),
                          if (table!.sheets.length > 1)
                            dropdown(
                              t('Worksheet', 'Hoja'),
                              sheet!,
                              {
                                for (final k in table!.sheets.keys)
                                  if (table!.sheets[k]!.isNotEmpty) k: k,
                              },
                              (v) => setState(() {
                                sheet = v;
                                header = 0;
                                resetColumns();
                              }),
                            ),
                          if (sourceBytes != null &&
                              !filename.toLowerCase().endsWith('.xlsx'))
                            dropdown(
                              t('Separator', 'Separador'),
                              delimiter,
                              {
                                'auto': t(
                                  'Detect automatically',
                                  'Detectar automáticamente',
                                ),
                                ',': t('Comma', 'Coma'),
                                ';': t('Semicolon', 'Punto y coma'),
                                '\t': t('Tab', 'Tabulación'),
                              },
                              (v) {
                                delimiter = v!;
                                run(decode);
                              },
                            ),
                          dropdown(
                            t('Header row', 'Fila de encabezados'),
                            header,
                            {
                              -1: t(
                                'No header — every row is equipment',
                                'Sin encabezado: cada fila es un equipo',
                              ),
                              for (var i = 0; i < rows.length && i < 25; i++)
                                i: '${i + 1}: ${rows[i].take(3).join(' · ')}',
                            },
                            (v) => setState(() {
                              header = v!;
                              resetColumns();
                            }),
                          ),
                          note(
                            t(
                              'Match only the columns you need. Unmapped columns stay out of the import. Repeated equipment rows can describe different components and service plans.',
                              'Asigna solo las columnas necesarias. Las demás no se importan. Filas repetidas pueden describir distintos componentes y planes.',
                            ),
                          ),
                          for (final field in fleetImportFields.entries.take(3))
                            mapping(field),
                          dropdown(
                            t(
                              'Type when the cell is blank',
                              'Tipo si la celda está vacía',
                            ),
                            defaultType ?? '',
                            {
                              '': t('Choose a type', 'Elegir tipo'),
                              for (final type in types) type.id: type.name,
                            },
                            (v) => setState(
                              () => defaultType = v == '' ? null : v,
                            ),
                          ),
                          if (columns.containsKey('asset_type_id')) ...[
                            for (final value
                                in rows
                                    .skip(header + 1)
                                    .map(
                                      (r) =>
                                          r.length > columns['asset_type_id']!
                                          ? r[columns['asset_type_id']!].trim()
                                          : '',
                                    )
                                    .where(
                                      (s) =>
                                          s.isNotEmpty &&
                                          !types.any(
                                            (t) =>
                                                t.name.toLowerCase() ==
                                                    s.toLowerCase() ||
                                                t.id == s,
                                          ),
                                    )
                                    .toSet())
                              dropdown(
                                t(
                                  'Type "$value" means',
                                  'Tipo "$value" significa',
                                ),
                                typeValues[value] ?? '',
                                {
                                  '': t('Choose a type', 'Elegir tipo'),
                                  for (final type in types) type.id: type.name,
                                },
                                (v) => setState(() {
                                  if (v == '') {
                                    typeValues.remove(value);
                                  } else {
                                    typeValues[value] = v!;
                                  }
                                }),
                                id: 'type-$value',
                              ),
                          ],
                          dropdown(
                            t('Default meter unit', 'Unidad predeterminada'),
                            unit,
                            {
                              'hours': t('Hours', 'Horas'),
                              'km': 'km',
                              'mi': t('Miles', 'Millas'),
                            },
                            (v) => setState(() => unit = v!),
                          ),
                          ExpansionTile(
                            title: Text(
                              t(
                                'Equipment details & readings',
                                'Detalles y lecturas del equipo',
                              ),
                            ),
                            children: [
                              for (final f
                                  in fleetImportFields.entries.skip(3).take(7))
                                mapping(f),
                            ],
                          ),
                          ExpansionTile(
                            title: Text(t('Components', 'Componentes')),
                            children: [
                              for (final f
                                  in fleetImportFields.entries.skip(10).take(6))
                                mapping(f),
                            ],
                          ),
                          ExpansionTile(
                            title: Text(
                              t(
                                'Service plans & last service',
                                'Planes y último servicio',
                              ),
                            ),
                            children: [
                              note(
                                t(
                                  'Plans use the named component, or the equipment meter if there is no component. Last-service values establish a baseline; they do not create signed service history.',
                                  'Los planes usan el componente indicado o el medidor del equipo. Los valores establecen una referencia; no crean historial firmado.',
                                ),
                              ),
                              for (final f in fleetImportFields.entries.skip(
                                16,
                              ))
                                mapping(f),
                              dropdown(
                                t('Date format', 'Formato de fecha'),
                                dateFormat,
                                {
                                  'iso': 'YYYY-MM-DD',
                                  'mdy': 'MM/DD/YYYY',
                                  'dmy': 'DD/MM/YYYY',
                                },
                                (v) => setState(() => dateFormat = v!),
                              ),
                              dropdown(
                                t(
                                  'Checklist for imported service plans',
                                  'Lista para los planes importados',
                                ),
                                template ?? '',
                                {
                                  '': t('No checklist', 'Sin lista'),
                                  for (final c in data!['templates'])
                                    c['id'] as String: c['name'] as String,
                                },
                                (v) => setState(
                                  () => template = v == '' ? null : v,
                                ),
                              ),
                            ],
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              t('Decimal comma (12,5)', 'Coma decimal (12,5)'),
                            ),
                            subtitle: Text(
                              t(
                                'No thousands separators',
                                'Sin separadores de miles',
                              ),
                            ),
                            value: comma,
                            onChanged: (v) => setState(() => comma = v),
                          ),
                          FilledButton(
                            onPressed: inspect,
                            child: Text(t('Preview import', 'Vista previa')),
                          ),
                          TextButton(
                            onPressed: () => setState(() => step = 0),
                            child: Text(
                              t('Choose another table', 'Elegir otra tabla'),
                            ),
                          ),
                        ],
                        if (step == 2 && review != null) ...[
                          note(
                            t(
                              '${review!.assets.length} equipment · ${excluded.length} excluded rows. Existing equipment will not be overwritten.',
                              '${review!.assets.length} equipos · ${excluded.length} filas excluidas. No se sobrescriben equipos existentes.',
                            ),
                          ),
                          for (final e in review!.errors.entries)
                            Card(
                              child: ListTile(
                                title: Text('${t('Row', 'Fila')} ${e.key}'),
                                subtitle: Text(e.value),
                                trailing: e.key == 0
                                    ? null
                                    : TextButton(
                                        onPressed: () {
                                          excluded.add(e.key);
                                          inspect();
                                        },
                                        child: Text(t('Exclude', 'Excluir')),
                                      ),
                              ),
                            ),
                          for (var i = 0; i < review!.assets.length; i++)
                            reviewCard(review!.assets[i], review!.rows[i]),
                          if (review!.errors.isEmpty &&
                              review!.assets.isNotEmpty)
                            FilledButton(
                              key: const Key('import-confirm'),
                              onPressed: save,
                              child: Text(
                                t(
                                  'Import ${review!.assets.length} equipment',
                                  'Importar ${review!.assets.length} equipos',
                                ),
                              ),
                            ),
                          TextButton(
                            onPressed: () => setState(() => step = 1),
                            child: Text(
                              t('Change column mapping', 'Cambiar columnas'),
                            ),
                          ),
                          if (excluded.isNotEmpty)
                            TextButton(
                              onPressed: () {
                                excluded.clear();
                                inspect();
                              },
                              child: Text(
                                t(
                                  'Restore excluded rows',
                                  'Restaurar filas excluidas',
                                ),
                              ),
                            ),
                        ],
                        if (step == 3) ...[
                          note(
                            t(
                              'This import has not yet been acknowledged. Retry to retrieve its receipt or safely complete it. The same records will not be created twice.',
                              'Esta importación aún no está confirmada. Reintenta para obtener el recibo o completarla. No se crearán registros duplicados.',
                            ),
                          ),
                          if (pending != null)
                            note(
                              '${(pending!['p_assets'] as List).length} ${t('equipment records', 'equipos')}',
                            ),
                          FilledButton(
                            onPressed: save,
                            child: Text(
                              t('Retry same import', 'Reintentar importación'),
                            ),
                          ),
                        ],
                        if (step == 4) ...[
                          note(
                            t(
                              '${result!['equipment_count']} equipment imported successfully. Opening readings and service baselines are available from each equipment record.',
                              '${result!['equipment_count']} equipos importados. Las lecturas y referencias de servicio están disponibles en cada equipo.',
                            ),
                          ),
                          for (final a in result!['assets'])
                            ListTile(
                              title: Text(a['name'].toString()),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push('/assets/${a['id']}'),
                            ),
                          FilledButton(
                            onPressed: () => context.go('/assets'),
                            child: Text(t('Go to equipment', 'Ir a equipos')),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget mapping(MapEntry<String, (String, String)> field) {
    final width = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    return dropdown(
      es ? field.value.$2 : field.value.$1,
      columns[field.key] ?? -1,
      {
        -1: t('Not imported', 'No importar'),
        for (var i = 0; i < width; i++)
          i: '${i + 1}: ${header < 0 ? 'Column ${i + 1}' : (i < rows[header].length ? rows[header][i] : '')} · ${rows.skip(header + 1).where((r) => r.length > i && r[i].isNotEmpty).firstOrNull?[i] ?? ''}',
      },
      (v) => setState(() {
        if (v == -1) {
          columns.remove(field.key);
        } else {
          columns[field.key] = v!;
        }
      }),
      id: field.key,
    );
  }

  Widget reviewCard(Map<String, dynamic> asset, List<int> source) => Card(
    child: ExpansionTile(
      initiallyExpanded: review!.assets.length == 1,
      title: Text(asset['name'].toString()),
      subtitle: Text(
        '${t('Rows', 'Filas')} ${source.join(', ')} · ${asset['serial_number'] ?? t('No serial', 'Sin serie')}',
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final e in asset.entries.where((e) => e.key != 'components'))
                Text(
                  '${fleetImportFields[e.key] == null ? e.key : (es ? fleetImportFields[e.key]!.$2 : fleetImportFields[e.key]!.$1)}: ${e.key == 'asset_type_id' ? (ref.read(assetTypesProvider).valueOrNull ?? []).where((t) => t.id == e.value).firstOrNull?.name ?? e.value : e.value}',
                ),
              for (final c in asset['components']) ...[
                const Divider(),
                Text(
                  '${c['label']} · ${c['current_hours'] ?? t('No reading', 'Sin lectura')} ${c['meter_unit']}',
                ),
                for (final key in ['serial_number', 'make', 'model'])
                  if (c[key] != null)
                    Text(
                      '${es ? fleetImportFields[key]!.$2 : fleetImportFields[key]!.$1}: ${c[key]}',
                    ),
                for (final p in c['plans'])
                  Text(
                    '${p['interval_label']} · ${p['interval_hours']} ${c['meter_unit']}${p['interval_months'] == null ? '' : ' / ${p['interval_months']} ${t('months', 'meses')}'}\n${t('Last service', 'Último servicio')}: ${p['last_service_hours'] ?? '—'} ${c['meter_unit']} · ${p['last_service_date'] ?? '—'}',
                  ),
              ],
              TextButton(
                onPressed: () {
                  excluded.addAll(source);
                  inspect();
                },
                child: Text(t('Exclude these rows', 'Excluir estas filas')),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
