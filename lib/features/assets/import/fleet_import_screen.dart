import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/core/localized_text.dart';
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
  bool get fr => isFrench(context);
  String t(String en, String esText, [String? frText]) =>
      localizedText(context, en, esText, frText ?? en);
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
      throw FormatException(
        t(
          'Use a file smaller than 5 MB.',
          'Usa un archivo de menos de 5 MB.',
          'Utilisez un fichier de moins de 5 Mo.',
        ),
      );
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
      throw FormatException(
        t(
          'The workbook is empty.',
          'El libro está vacío.',
          'Le classeur est vide.',
        ),
      );
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
    filename = t('Pasted table', 'Tabla pegada', 'Tableau collé');
    sheet = table!.sheets.keys.first;
    header = 0;
    step = 1;
    resetColumns();
  });
  Future<void> inspect() => run(() async {
    if (!sameAccount()) {
      throw StateError(
        t(
          'Company changed. Reopen the import.',
          'La empresa cambió. Vuelve a abrir la importación.',
          'L’entreprise a changé. Rouvrez l’importation.',
        ),
      );
    }
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
    if (!sameAccount()) {
      throw StateError(
        t(
          'Company changed. Reopen the import.',
          'La empresa cambió. Vuelve a abrir la importación.',
          'L’entreprise a changé. Rouvrez l’importation.',
        ),
      );
    }
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
      t('Choose a table', 'Elegir tabla', 'Choisir un tableau'),
      t('Match columns', 'Asignar columnas', 'Associer les colonnes'),
      t('Review import', 'Revisar importación', 'Vérifier l’importation'),
      t('Resolve import', 'Resolver importación', 'Finaliser l’importation'),
      t('Equipment imported', 'Equipos importados', 'Équipement importé'),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          t('Import equipment', 'Importar equipos', 'Importer de l’équipement'),
        ),
      ),
      body: !allowed || changed
          ? Center(
              child: Text(
                t(
                  'Reopen from the equipment list for your current company.',
                  'Vuelve a abrir desde los equipos de tu empresa actual.',
                  'Rouvrez l’importation depuis la liste d’équipement de votre entreprise actuelle.',
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
                            'Connectez-vous pour charger votre parc et les autorisations d’importation.',
                          ),
                        ),
                        TextButton(
                          onPressed: load,
                          child: Text(t('Retry', 'Reintentar', 'Réessayer')),
                        ),
                      ] else ...[
                        if (step < 3 && (data!['clients'] as List).length > 1)
                          dropdown(
                            t('Fleet', 'Flota', 'Parc d’équipement'),
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
                              'Importez une liste de parc depuis Excel, Google Sheets ou un autre système. Choisissez un fichier XLSX, CSV ou TSV, ou collez les lignes ci-dessous. Vous pourrez tout vérifier avant l’enregistrement.',
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: chooseFile,
                            icon: const Icon(Icons.upload_file),
                            label: Text(
                              t(
                                'Choose spreadsheet',
                                'Elegir hoja de cálculo',
                                'Choisir un tableur',
                              ),
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
                                'Ou collez un tableau',
                              ),
                              hintText:
                                  'Name\tType\tSerial\nExcavator 12\tExcavator\t001234',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: fromPaste,
                            child: Text(
                              t(
                                'Use pasted table',
                                'Usar tabla pegada',
                                'Utiliser le tableau collé',
                              ),
                            ),
                          ),
                          note(
                            t(
                              'Keep serials / VINs as text in the source spreadsheet to preserve leading zeroes. Formula cells need to be pasted as values. Photos, PDFs and older XLS files need a table export first.',
                              'Guarda series / VIN como texto para conservar ceros iniciales. Pega fórmulas como valores. Fotos, PDF y XLS antiguos requieren exportar una tabla.',
                              'Dans le tableur source, conservez les numéros de série et NIV comme texte pour préserver les zéros initiaux. Collez les formules comme valeurs. Les photos, PDF et anciens fichiers XLS doivent d’abord être exportés en tableau.',
                            ),
                          ),
                        ],
                        if (step == 1) ...[
                          note(filename),
                          if (table!.sheets.length > 1)
                            dropdown(
                              t('Worksheet', 'Hoja', 'Feuille de calcul'),
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
                              t('Separator', 'Separador', 'Séparateur'),
                              delimiter,
                              {
                                'auto': t(
                                  'Detect automatically',
                                  'Detectar automáticamente',
                                  'Détecter automatiquement',
                                ),
                                ',': t('Comma', 'Coma', 'Virgule'),
                                ';': t(
                                  'Semicolon',
                                  'Punto y coma',
                                  'Point-virgule',
                                ),
                                '\t': t('Tab', 'Tabulación', 'Tabulation'),
                              },
                              (v) {
                                delimiter = v!;
                                run(decode);
                              },
                            ),
                          dropdown(
                            t(
                              'Header row',
                              'Fila de encabezados',
                              'Ligne d’en-tête',
                            ),
                            header,
                            {
                              -1: t(
                                'No header — every row is equipment',
                                'Sin encabezado: cada fila es un equipo',
                                'Sans en-tête — chaque ligne représente un équipement',
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
                              'Associez uniquement les colonnes nécessaires. Les colonnes non associées sont exclues. Plusieurs lignes pour un même équipement peuvent décrire différents composants et plans d’entretien.',
                            ),
                          ),
                          for (final field in fleetImportFields.entries.take(3))
                            mapping(field),
                          dropdown(
                            t(
                              'Type when the cell is blank',
                              'Tipo si la celda está vacía',
                              'Type si la cellule est vide',
                            ),
                            defaultType ?? '',
                            {
                              '': t(
                                'Choose a type',
                                'Elegir tipo',
                                'Choisir un type',
                              ),
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
                                  'Le type « $value » correspond à',
                                ),
                                typeValues[value] ?? '',
                                {
                                  '': t(
                                    'Choose a type',
                                    'Elegir tipo',
                                    'Choisir un type',
                                  ),
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
                            t(
                              'Default meter unit',
                              'Unidad predeterminada',
                              'Unité de compteur par défaut',
                            ),
                            unit,
                            {
                              'hours': t('Hours', 'Horas', 'Heures'),
                              'km': 'km',
                              'mi': t('Miles', 'Millas', 'Milles'),
                            },
                            (v) => setState(() => unit = v!),
                          ),
                          ExpansionTile(
                            title: Text(
                              t(
                                'Equipment details & readings',
                                'Detalles y lecturas del equipo',
                                'Détails et relevés de l’équipement',
                              ),
                            ),
                            children: [
                              for (final f
                                  in fleetImportFields.entries.skip(3).take(7))
                                mapping(f),
                            ],
                          ),
                          ExpansionTile(
                            title: Text(
                              t('Components', 'Componentes', 'Composants'),
                            ),
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
                                'Plans d’entretien et dernier entretien',
                              ),
                            ),
                            children: [
                              note(
                                t(
                                  'Plans use the named component, or the equipment meter if there is no component. Last-service values establish a baseline; they do not create signed service history.',
                                  'Los planes usan el componente indicado o el medidor del equipo. Los valores establecen una referencia; no crean historial firmado.',
                                  'Les plans utilisent le composant indiqué, ou le compteur de l’équipement s’il n’y a pas de composant. Les valeurs du dernier entretien servent de référence et ne créent pas un historique d’entretien signé.',
                                ),
                              ),
                              for (final f in fleetImportFields.entries.skip(
                                16,
                              ))
                                mapping(f),
                              dropdown(
                                t(
                                  'Date format',
                                  'Formato de fecha',
                                  'Format de date',
                                ),
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
                                  'Liste de contrôle pour les plans d’entretien importés',
                                ),
                                template ?? '',
                                {
                                  '': t(
                                    'No checklist',
                                    'Sin lista',
                                    'Aucune liste',
                                  ),
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
                              t(
                                'Decimal comma (12,5)',
                                'Coma decimal (12,5)',
                                'Virgule décimale (12,5)',
                              ),
                            ),
                            subtitle: Text(
                              t(
                                'No thousands separators',
                                'Sin separadores de miles',
                                'Sans séparateur de milliers',
                              ),
                            ),
                            value: comma,
                            onChanged: (v) => setState(() => comma = v),
                          ),
                          FilledButton(
                            onPressed: inspect,
                            child: Text(
                              t(
                                'Preview import',
                                'Vista previa',
                                'Prévisualiser l’importation',
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() => step = 0),
                            child: Text(
                              t(
                                'Choose another table',
                                'Elegir otra tabla',
                                'Choisir un autre tableau',
                              ),
                            ),
                          ),
                        ],
                        if (step == 2 && review != null) ...[
                          note(
                            t(
                              '${review!.assets.length} equipment · ${excluded.length} excluded rows. Existing equipment will not be overwritten.',
                              '${review!.assets.length} equipos · ${excluded.length} filas excluidas. No se sobrescriben equipos existentes.',
                              '${review!.assets.length} équipements · ${excluded.length} lignes exclues. Les équipements existants ne seront pas remplacés.',
                            ),
                          ),
                          for (final e in review!.errors.entries)
                            Card(
                              child: ListTile(
                                title: Text(
                                  '${t('Row', 'Fila', 'Ligne')} ${e.key}',
                                ),
                                subtitle: Text(e.value),
                                trailing: e.key == 0
                                    ? null
                                    : TextButton(
                                        onPressed: () {
                                          excluded.add(e.key);
                                          inspect();
                                        },
                                        child: Text(
                                          t('Exclude', 'Excluir', 'Exclure'),
                                        ),
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
                                  'Importer ${review!.assets.length} équipements',
                                ),
                              ),
                            ),
                          TextButton(
                            onPressed: () => setState(() => step = 1),
                            child: Text(
                              t(
                                'Change column mapping',
                                'Cambiar columnas',
                                'Modifier l’association des colonnes',
                              ),
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
                                  'Rétablir les lignes exclues',
                                ),
                              ),
                            ),
                        ],
                        if (step == 3) ...[
                          note(
                            t(
                              'This import has not yet been acknowledged. Retry to retrieve its receipt or safely complete it. The same records will not be created twice.',
                              'Esta importación aún no está confirmada. Reintenta para obtener el recibo o completarla. No se crearán registros duplicados.',
                              'Cette importation n’a pas encore été confirmée. Réessayez pour récupérer le reçu ou la terminer en toute sécurité. Les mêmes dossiers ne seront pas créés deux fois.',
                            ),
                          ),
                          if (pending != null)
                            note(
                              '${(pending!['p_assets'] as List).length} ${t('equipment records', 'equipos', 'dossiers d’équipement')}',
                            ),
                          FilledButton(
                            onPressed: save,
                            child: Text(
                              t(
                                'Retry same import',
                                'Reintentar importación',
                                'Réessayer la même importation',
                              ),
                            ),
                          ),
                        ],
                        if (step == 4) ...[
                          note(
                            t(
                              '${result!['equipment_count']} equipment imported successfully. Opening readings and service baselines are available from each equipment record.',
                              '${result!['equipment_count']} equipos importados. Las lecturas y referencias de servicio están disponibles en cada equipo.',
                              '${result!['equipment_count']} équipements importés. Les relevés initiaux et les références d’entretien sont accessibles dans chaque dossier d’équipement.',
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
                            child: Text(
                              t(
                                'Go to equipment',
                                'Ir a equipos',
                                'Voir les équipements',
                              ),
                            ),
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

  Widget mapping(MapEntry<String, (String, String, String)> field) {
    final width = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    return dropdown(
      fr ? field.value.$3 : (es ? field.value.$2 : field.value.$1),
      columns[field.key] ?? -1,
      {
        -1: t('Not imported', 'No importar', 'Ne pas importer'),
        for (var i = 0; i < width; i++)
          i: '${i + 1}: ${header < 0 ? t('Column', 'Columna', 'Colonne') : (i < rows[header].length ? rows[header][i] : '')} ${i + 1} · ${rows.skip(header + 1).where((r) => r.length > i && r[i].isNotEmpty).firstOrNull?[i] ?? ''}',
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
        '${t('Rows', 'Filas', 'Lignes')} ${source.join(', ')} · ${asset['serial_number'] ?? t('No serial', 'Sin serie', 'Aucun numéro de série')}',
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final e in asset.entries.where((e) => e.key != 'components'))
                Text(
                  '${fleetImportFields[e.key] == null ? e.key : (fr ? fleetImportFields[e.key]!.$3 : (es ? fleetImportFields[e.key]!.$2 : fleetImportFields[e.key]!.$1))}: ${e.key == 'asset_type_id' ? (ref.read(assetTypesProvider).valueOrNull ?? []).where((t) => t.id == e.value).firstOrNull?.name ?? e.value : e.value}',
                ),
              for (final c in asset['components']) ...[
                const Divider(),
                Text(
                  '${c['label']} · ${c['current_hours'] ?? t('No reading', 'Sin lectura', 'Aucun relevé')} ${c['meter_unit']}',
                ),
                for (final key in ['serial_number', 'make', 'model'])
                  if (c[key] != null)
                    Text(
                      '${fr ? fleetImportFields[key]!.$3 : (es ? fleetImportFields[key]!.$2 : fleetImportFields[key]!.$1)}: ${c[key]}',
                    ),
                for (final p in c['plans'])
                  Text(
                    '${p['interval_label']} · ${p['interval_hours']} ${c['meter_unit']}${p['interval_months'] == null ? '' : ' / ${p['interval_months']} ${t('months', 'meses', 'mois')}'}\n${t('Last service', 'Último servicio', 'Dernier entretien')}: ${p['last_service_hours'] ?? '—'} ${c['meter_unit']} · ${p['last_service_date'] ?? '—'}',
                  ),
              ],
              TextButton(
                onPressed: () {
                  excluded.addAll(source);
                  inspect();
                },
                child: Text(
                  t(
                    'Exclude these rows',
                    'Excluir estas filas',
                    'Exclure ces lignes',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
