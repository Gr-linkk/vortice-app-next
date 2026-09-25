import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/features/maintenance/maintenance_refresh.dart';
import 'package:vortice_app/features/parts/parts_provider.dart';
import 'parts_readiness_models.dart';
import 'parts_readiness_repository.dart';

part 'parts_readiness_form.dart';

class PartsReadinessScreen extends ConsumerStatefulWidget {
  const PartsReadinessScreen({super.key, this.jobId});
  final String? jobId;
  @override
  ConsumerState<PartsReadinessScreen> createState() =>
      _PartsReadinessScreenState();
}

class _PartsReadinessScreenState extends ConsumerState<PartsReadinessScreen> {
  bool _busy = false;
  Map<String, dynamic>? _pending;
  bool get _es => Localizations.localeOf(context).languageCode == 'es';
  bool get _fr => Localizations.localeOf(context).languageCode == 'fr';
  String t(String en, String es, [String? fr]) => _fr
      ? fr ?? en
      : _es
      ? es
      : en;
  @override
  void initState() {
    super.initState();
    Future.microtask(_readPending);
  }

  Future<void> _readPending() async {
    try {
      final pending = await ref
          .read(partsReadinessRepositoryProvider)
          .pending();
      if (mounted) setState(() => _pending = pending);
    } catch (_) {
      /* Account changes are handled by the workspace load. */
    }
  }

  void _refresh() {
    ref.invalidate(partsWorkspaceProvider(widget.jobId));
    ref.invalidate(partsReadinessSummaryProvider);
    if (widget.jobId != null) {
      refreshMaintenance(ref, jobId: widget.jobId!);
      ref.invalidate(partsProvider(widget.jobId!));
    }
  }

  Future<bool> _run(String action, Map<String, dynamic> data) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      final repository = ref.read(partsReadinessRepositoryProvider);
      if (action == 'retry') {
        await repository.retry();
      } else {
        await repository.change(widget.jobId, action, data);
      }
      if (!mounted) return false;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('Parts updated', 'Repuestos actualizados', 'Pièces mises à jour'),
          ),
        ),
      );
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is PostgrestException
                  ? partsSaveError(error.message, _es, french: _fr)
                  : t(
                      'Could not confirm the change. Connect and retry the saved change.',
                      'No se pudo confirmar el cambio. Conéctate y reintenta el cambio guardado.',
                      'Impossible de confirmer le changement. Connectez-vous et réessayez le changement enregistré.',
                    ),
            ),
            duration: const Duration(seconds: 8),
          ),
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _readPending();
      }
    }
  }

  Future<Map<String, dynamic>?> _form(String title, List<PartInput> fields) =>
      showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) =>
            _PartsForm(title: title, fields: fields, es: _es, french: _fr),
      );
  Future<void> _quantity(
    String action,
    String title,
    Map<String, dynamic> identity,
    double initial, {
    List<PartInput> extra = const [],
  }) async {
    final data = await _form(title, [
      PartInput(
        'quantity',
        t('Quantity', 'Cantidad', 'Quantité'),
        value: partQuantity(initial),
        number: true,
      ),
      ...extra,
    ]);
    if (data != null && mounted) await _run(action, {...identity, ...data});
  }

  Future<void> _createStock([JobPartRequirement? requirement]) async {
    final currency =
        ref.read(partsWorkspaceProvider(widget.jobId)).valueOrNull?.currency ??
        'USD';
    final data = await _form(
      t('Add stock item', 'Añadir artículo', 'Ajouter un article en stock'),
      [
        PartInput(
          'description',
          t('Description', 'Descripción', 'Description'),
          value: requirement?.description ?? '',
        ),
        PartInput(
          'part_number',
          t('Part number', 'Número de parte', 'Numéro de pièce'),
          value: requirement?.data['part_number'] as String? ?? '',
          required: false,
        ),
        PartInput(
          'unit',
          t('Unit (ea, L, kg)', 'Unidad (ea, L, kg)', 'Unité (un, L, kg)'),
          value: requirement?.unit ?? 'ea',
        ),
        PartInput(
          'location',
          t(
            'Stock location',
            'Ubicación de existencias',
            'Emplacement du stock',
          ),
        ),
        PartInput(
          'unit_cost',
          t(
            'Unit cost ($currency)',
            'Costo unitario ($currency)',
            'Coût unitaire ($currency)',
          ),
          value: '0',
          number: true,
        ),
      ],
    );
    if (data != null && mounted) {
      await _run('stock_create', {...data, 'cost_currency': currency});
    }
  }

  Map<String, dynamic> _identity(JobPartRequirement r) => {
    'requirement_id': r.id,
    'revision': r.data['revision'],
  };
  Future<void> _link(JobPartRequirement r, PartsWorkspace workspace) async {
    final stock = workspace.stock
        .where(
          (s) =>
              s.unit.toLowerCase() == r.unit.toLowerCase() &&
              s.currency == workspace.currency,
        )
        .toList();
    final selection = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(
          t(
            'Choose stock location',
            'Elegir existencias',
            'Choisir un emplacement de stock',
          ),
        ),
        children: [
          if (stock.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                t(
                  'No stock in this unit and ${workspace.currency} yet. Add a separate stock item with costs in the job currency.',
                  'Aún no hay existencias con esta unidad y ${workspace.currency}. Añade otro artículo con costos en la moneda del trabajo.',
                  'Aucun stock dans cette unité et en ${workspace.currency} pour le moment. Ajoutez un article distinct dont le coût est dans la devise du bon de travail.',
                ),
              ),
            ),
          for (final s in stock)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, s.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '${s.description}${s.data['part_number'] == null ? '' : ' · ${s.data['part_number']}'}\n${s.location} · ${partQuantity(s.available)} ${s.unit} ${t('available', 'disponibles', 'disponible')}',
                ),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'new'),
            child: Text(
              t(
                'Add stock item…',
                'Añadir artículo…',
                'Ajouter un article en stock…',
              ),
            ),
          ),
        ],
      ),
    );
    if (selection == 'new') {
      await _createStock(r);
    } else if (selection != null && mounted) {
      await _run('link', {..._identity(r), 'stock_id': selection});
    }
  }

  Future<void> _requirementAction(
    String action,
    JobPartRequirement r,
    PartsWorkspace w,
  ) async {
    final stock = w.stockFor(r);
    switch (action) {
      case 'link':
        await _link(r, w);
      case 'requirement_edit':
        await _quantity(
          action,
          t('Required quantity', 'Cantidad necesaria', 'Quantité requise'),
          _identity(r),
          r.required,
        );
      case 'reserve':
        await _quantity(
          action,
          t(
            'Reserve for this job',
            'Reservar para este trabajo',
            'Réserver pour ce bon de travail',
          ),
          _identity(r),
          r.reservable(stock),
        );
      case 'release':
        await _quantity(
          action,
          t('Release reservation', 'Liberar reserva', 'Libérer la réservation'),
          _identity(r),
          r.reserved,
        );
      case 'issue':
        await _quantity(
          action,
          t(
            'Record parts used',
            'Registrar repuestos utilizados',
            'Consigner les pièces utilisées',
          ),
          _identity(r),
          r.reserved,
        );
      case 'return':
        await _quantity(
          action,
          t(
            'Return unused parts',
            'Devolver repuestos no utilizados',
            'Retourner les pièces inutilisées',
          ),
          _identity(r),
          r.used,
        );
      case 'request':
        await _quantity(
          action,
          t(
            'Request missing parts',
            'Solicitar repuestos faltantes',
            'Demander les pièces manquantes',
          ),
          _identity(r),
          math.max(0, r.remaining - w.outstanding(r.id)),
        );
    }
  }

  Future<void> _purchaseAction(String action, Map<String, dynamic> p) async {
    final identity = {'purchase_id': p['id'], 'revision': p['revision']};
    if (action == 'order') {
      final data = await _form(
        t('Record order', 'Registrar pedido', 'Consigner la commande'),
        [
          PartInput('supplier', t('Supplier', 'Proveedor', 'Fournisseur')),
          PartInput(
            'reference',
            t(
              'Order reference',
              'Referencia del pedido',
              'Référence de commande',
            ),
            required: false,
          ),
          PartInput(
            'expected_date',
            t(
              'Expected date (YYYY-MM-DD)',
              'Fecha prevista (AAAA-MM-DD)',
              'Date prévue (AAAA-MM-JJ)',
            ),
            required: false,
            date: true,
          ),
        ],
      );
      if (data != null && mounted) await _run(action, {...identity, ...data});
    } else if (action == 'receive') {
      final workspace = ref
          .read(partsWorkspaceProvider(widget.jobId))
          .valueOrNull;
      final currency =
          workspace?.stock
              .where((s) => s.id == p['stock_id'])
              .firstOrNull
              ?.currency ??
          workspace?.currency ??
          'USD';
      await _quantity(
        action,
        t('Receive delivery', 'Recibir entrega', 'Réceptionner la livraison'),
        identity,
        partNumberValue(p['quantity']) - partNumberValue(p['received_qty']),
        extra: [
          PartInput(
            'unit_cost',
            t(
              'Unit cost ($currency)',
              'Costo unitario ($currency)',
              'Coût unitaire ($currency)',
            ),
            value: '0',
            number: true,
          ),
        ],
      );
    } else if (action == 'cancel_purchase') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            t(
              'Cancel remaining order?',
              '¿Cancelar el pedido restante?',
              'Annuler le solde de la commande?',
            ),
          ),
          content: Text(
            t(
              'Received stock stays available. This only cancels the outstanding quantity.',
              'Las existencias recibidas se conservan. Solo se cancela la cantidad pendiente.',
              'Le stock reçu reste disponible. Seule la quantité restante est annulée.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                t('Keep order', 'Conservar pedido', 'Garder la commande'),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                t('Cancel remaining', 'Cancelar restante', 'Annuler le solde'),
              ),
            ),
          ],
        ),
      );
      if (confirm == true && mounted) await _run(action, identity);
    }
  }

  bool get _disabled => _busy || _pending != null;
  @override
  Widget build(BuildContext context) {
    final job = widget.jobId != null;
    return DefaultTabController(
      length: job ? 4 : 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            job
                ? t(
                    'Parts readiness',
                    'Disponibilidad de repuestos',
                    'État des pièces',
                  )
                : t(
                    'Stock & purchasing',
                    'Existencias y compras',
                    'Stock et achats',
                  ),
          ),
          actions: [
            IconButton(
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
              tooltip: t('Refresh', 'Actualizar', 'Actualiser'),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              if (job)
                Tab(
                  text: t(
                    'Job parts',
                    'Repuestos del trabajo',
                    'Pièces du bon de travail',
                  ),
                ),
              Tab(text: t('Stock', 'Existencias', 'Stock')),
              Tab(text: t('Orders', 'Pedidos', 'Commandes')),
              Tab(text: t('Activity', 'Actividad', 'Activité')),
            ],
          ),
        ),
        body: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_pending != null)
              MaterialBanner(
                content: Text(
                  t(
                    'A saved change is unconfirmed. Retry it before making another stock change.',
                    'Hay un cambio guardado sin confirmar. Reinténtalo antes de realizar otro cambio.',
                    'Un changement enregistré n’est pas confirmé. Réessayez-le avant de modifier le stock.',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: _busy ? null : () => _run('retry', {}),
                    child: Text(
                      t(
                        'Retry saved change',
                        'Reintentar cambio',
                        'Réessayer le changement enregistré',
                      ),
                    ),
                  ),
                ],
              ),
            Expanded(
              child: ref
                  .watch(partsWorkspaceProvider(widget.jobId))
                  .when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, __) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              t(
                                'Current stock is unavailable. Check your connection and access, then try again.',
                                'Las existencias no están disponibles. Revisa tu conexión y acceso e inténtalo de nuevo.',
                                'Le stock actuel est indisponible. Vérifiez votre connexion et vos autorisations, puis réessayez.',
                              ),
                            ),
                            TextButton(
                              onPressed: _refresh,
                              child: Text(
                                t('Try again', 'Reintentar', 'Réessayer'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    data: (w) => TabBarView(
                      children: [
                        if (job) _requirements(w),
                        _stock(w),
                        _orders(w),
                        _events(w),
                      ],
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(List<Widget> children) =>
      ListView(padding: const EdgeInsets.all(16), children: children);
  Widget _requirements(PartsWorkspace w) => _list([
    if (w.data['job_title'] != null)
      Text(
        w.data['job_title'] as String,
        style: Theme.of(context).textTheme.titleLarge,
      ),
    const SizedBox(height: 8),
    Text(
      t(
        'This job keeps its own parts list. Editing the standard kit affects future jobs.',
        'Este trabajo conserva su lista de repuestos. Los cambios del kit estándar afectan a trabajos futuros.',
        'Ce bon de travail conserve sa propre liste de pièces. La modification du kit standard s’applique aux prochains bons de travail.',
      ),
    ),
    if (!w.canChange)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          t(
            'Parts are read-only while work is closed or awaiting review.',
            'Los repuestos son de solo lectura al cerrar el trabajo o durante la revisión.',
            'La liste des pièces est en lecture seule lorsque le travail est fermé ou en attente de révision.',
          ),
        ),
      ),
    if (w.canManage && w.canChange)
      Wrap(
        spacing: 12,
        children: [
          TextButton.icon(
            onPressed: _disabled
                ? null
                : () async {
                    final data = await _form(
                      t(
                        'Add job requirement',
                        'Añadir requisito del trabajo',
                        'Ajouter un besoin au bon de travail',
                      ),
                      [
                        PartInput(
                          'description',
                          t('Description', 'Descripción', 'Description'),
                        ),
                        PartInput(
                          'part_number',
                          t(
                            'Part number',
                            'Número de parte',
                            'Numéro de pièce',
                          ),
                          required: false,
                        ),
                        PartInput(
                          'unit',
                          t('Unit', 'Unidad', 'Unité'),
                          value: 'ea',
                        ),
                        PartInput(
                          'quantity',
                          t(
                            'Required quantity',
                            'Cantidad necesaria',
                            'Quantité requise',
                          ),
                          value: '1',
                          number: true,
                        ),
                      ],
                    );
                    if (data != null && mounted) {
                      await _run('requirement_add', data);
                    }
                  },
            icon: const Icon(Icons.add),
            label: Text(
              t('Add requirement', 'Añadir requisito', 'Ajouter un besoin'),
            ),
          ),
          if (w.data['kit_captured'] != true && w.data['has_kit'] == true)
            TextButton(
              onPressed: _disabled ? null : () => _run('import_kit', {}),
              child: Text(
                t(
                  'Import current PM kit',
                  'Importar kit PM actual',
                  'Importer le kit d’entretien préventif actuel',
                ),
              ),
            ),
        ],
      ),
    if (w.requirements.isEmpty)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text(
          t(
            'No required parts yet. Add a requirement or import the linked PM kit.',
            'Aún no hay repuestos necesarios. Añade un requisito o importa el kit PM vinculado.',
            'Aucune pièce requise pour le moment. Ajoutez un besoin ou importez le kit d’entretien préventif associé.',
          ),
        ),
      ),
    for (final r in w.requirements) _requirementCard(r, w),
  ]);
  Widget _requirementCard(JobPartRequirement r, PartsWorkspace w) {
    final stock = w.stockFor(r);
    final actions = <String, String>{
      if (w.canManage)
        'requirement_edit': t(
          'Edit required quantity',
          'Editar cantidad necesaria',
          'Modifier la quantité requise',
        ),
      if (w.canManage && r.reserved + r.used == 0 && w.outstanding(r.id) == 0)
        'link': t('Choose stock', 'Elegir existencias', 'Choisir le stock'),
      if (w.canManage && r.reservable(stock) > 0)
        'reserve': t(
          'Reserve parts',
          'Reservar repuestos',
          'Réserver des pièces',
        ),
      if (w.canManage && stock != null && r.remaining > w.outstanding(r.id))
        'request': t(
          'Request parts',
          'Solicitar repuestos',
          'Demander des pièces',
        ),
      if (r.reserved > 0)
        'release': t(
          'Release reservation',
          'Liberar reserva',
          'Libérer la réservation',
        ),
      if (w.canIssue && r.reserved > 0)
        'issue': t('Record use', 'Registrar uso', 'Consigner l’utilisation'),
      if (w.canIssue && r.used > 0)
        'return': t(
          'Return unused parts',
          'Devolver repuestos',
          'Retourner les pièces inutilisées',
        ),
    };
    final primary = stock == null && w.canManage
        ? 'link'
        : w.canIssue && r.reserved > 0
        ? 'issue'
        : w.canManage && r.reservable(stock) > 0
        ? 'reserve'
        : w.canManage && stock != null && r.remaining > w.outstanding(r.id)
        ? 'request'
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    r.description,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (w.canChange && actions.isNotEmpty)
                  PopupMenuButton<String>(
                    enabled: !_disabled,
                    tooltip: t(
                      'Part actions',
                      'Acciones del repuesto',
                      'Actions sur les pièces',
                    ),
                    onSelected: (a) => _requirementAction(a, r, w),
                    itemBuilder: (_) => [
                      for (final entry in actions.entries)
                        PopupMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                  ),
              ],
            ),
            if (r.data['part_number'] != null)
              Text(r.data['part_number'] as String),
            const SizedBox(height: 8),
            Text(
              '${t('Required', 'Necesarios', 'Requis')}: ${partQuantity(r.required)} ${r.unit} · ${t('Reserved', 'Reservados', 'Réservé')}: ${partQuantity(r.reserved)} · ${t('Used', 'Utilizados', 'Utilisé')}: ${partQuantity(r.used)}',
            ),
            const SizedBox(height: 8),
            Text(
              stock == null
                  ? t(
                      'Choose a stock item and location to check availability.',
                      'Elige un artículo y ubicación para comprobar disponibilidad.',
                      'Choisissez un article en stock et son emplacement pour vérifier la disponibilité.',
                    )
                  : '${stock.description}${stock.data['part_number'] == null ? '' : ' · ${stock.data['part_number']}'}\n${stock.location} · ${partQuantity(stock.available)} ${r.unit} ${t('available', 'disponibles', 'disponible')}',
            ),
            if (r.shortage(stock) > 0)
              Text(
                '${t('Shortage', 'Faltantes', 'Manque')}: ${partQuantity(r.shortage(stock))} ${r.unit}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (w.outstanding(r.id) > 0)
              Text(
                '${t('Requested / on order', 'Solicitados / en pedido', 'Demandé / commandé')}: ${partQuantity(w.outstanding(r.id))} ${r.unit}',
              ),
            if (r.remaining == 0)
              Text(
                t(
                  'Requirement covered',
                  'Requisito cubierto',
                  'Besoin couvert',
                ),
              ),
            if (primary != null && w.canChange)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: FilledButton(
                  onPressed: _disabled
                      ? null
                      : () => _requirementAction(primary, r, w),
                  child: Text(actions[primary]!),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stock(PartsWorkspace w) => _list([
    Text(
      t(
        'Available stock excludes reservations for all jobs. Stock changes require a connection.',
        'Las existencias disponibles excluyen las reservas de todos los trabajos. Los cambios requieren conexión.',
        'Le stock disponible tient compte des réservations de tous les bons de travail. Une connexion est nécessaire pour le modifier.',
      ),
    ),
    if (w.canManage)
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _disabled ? null : _createStock,
          icon: const Icon(Icons.add),
          label: Text(
            t(
              'Add stock item',
              'Añadir artículo',
              'Ajouter un article en stock',
            ),
          ),
        ),
      ),
    if (w.stock.isEmpty)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text(
          t(
            'No stock items yet. Add an item and record an opening count.',
            'Aún no hay existencias. Añade un artículo y registra el conteo inicial.',
            'Aucun article en stock pour le moment. Ajoutez-en un et saisissez le stock initial.',
          ),
        ),
      ),
    for (final s in w.stock)
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.description,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text('${s.data['part_number'] ?? ''} · ${s.location}'),
              Text(
                '${t('On hand', 'En existencia', 'En stock')}: ${partQuantity(s.onHand)} ${s.unit} · ${t('Reserved', 'Reservados', 'Réservé')}: ${partQuantity(s.reserved)}',
              ),
              Text(
                '${t('Available', 'Disponibles', 'Disponible')}: ${partQuantity(s.available)} · ${t('Minimum', 'Mínimo', 'Minimum')}: ${partQuantity(s.minimum)}',
              ),
              Text(
                '${t('Last unit cost', 'Último costo unitario', 'Dernier coût unitaire')}: ${s.cost.toStringAsFixed(2)} ${s.currency}',
              ),
              Text(
                '${t('Average stock cost', 'Costo promedio', 'Coût moyen du stock')}: ${partNumberValue(s.data['average_unit_cost']).toStringAsFixed(2)} ${s.currency}',
              ),
              if (s.low)
                Text(
                  t(
                    'Below minimum stock',
                    'Por debajo del mínimo',
                    'Sous le stock minimum',
                  ),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (w.canManage)
                TextButton(
                  onPressed: _disabled
                      ? null
                      : () => _quantity(
                          'stock_count',
                          t(
                            'Count / adjust stock',
                            'Contar / ajustar existencias',
                            'Compter / ajuster le stock',
                          ),
                          {'stock_id': s.id, 'revision': s.data['revision']},
                          s.onHand,
                          extra: [
                            PartInput(
                              'minimum',
                              t(
                                'Minimum stock',
                                'Existencia mínima',
                                'Stock minimum',
                              ),
                              value: partQuantity(s.minimum),
                              number: true,
                            ),
                            PartInput(
                              'note',
                              t(
                                'Reason for adjustment',
                                'Motivo del ajuste',
                                'Motif de l’ajustement',
                              ),
                            ),
                          ],
                        ),
                  child: Text(
                    t(
                      'Count / adjust',
                      'Contar / ajustar',
                      'Compter / ajuster',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
  ]);
  Widget _orders(PartsWorkspace w) => _list([
    Text(
      t(
        'Record supplier orders here. No order is sent to a supplier automatically.',
        'Registra los pedidos aquí. No se envían pedidos automáticamente a proveedores.',
        'Consignez les commandes des fournisseurs ici. Aucune commande n’est envoyée automatiquement.',
      ),
    ),
    if (w.purchases.isEmpty)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text(
          t(
            'No purchase requests. Request missing parts from a job.',
            'No hay solicitudes de compra. Solicita los repuestos faltantes desde un trabajo.',
            'Aucune demande d’achat. Demandez les pièces manquantes depuis un bon de travail.',
          ),
        ),
      ),
    for (final p in w.purchases)
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p['description'] as String,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(partsActionLabel(p['status'] as String, _es, french: _fr)),
              Text(
                '${t('Received', 'Recibidos', 'Reçu')}: ${p['received_qty']} / ${p['quantity']}',
              ),
              if ((p['supplier'] as String? ?? '').isNotEmpty)
                Text('${p['supplier']} · ${p['reference']}'),
              if (p['expected_date'] != null)
                Text(
                  '${t('Expected', 'Previsto', 'Prévu')}: ${p['expected_date']}',
                ),
              if (widget.jobId == null)
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PartsReadinessScreen(
                        jobId: p['work_order_id'] as String,
                      ),
                    ),
                  ),
                  child: Text(
                    t(
                      'Open job parts',
                      'Abrir repuestos del trabajo',
                      'Ouvrir les pièces du bon de travail',
                    ),
                  ),
                ),
              if (widget.jobId != null &&
                  w.canManage &&
                  (p['status'] == 'requested' || p['status'] == 'ordered'))
                Wrap(
                  spacing: 12,
                  children: [
                    if (w.canChange || p['status'] == 'ordered')
                      FilledButton(
                        onPressed: _disabled
                            ? null
                            : () => _purchaseAction(
                                p['status'] == 'requested'
                                    ? 'order'
                                    : 'receive',
                                p,
                              ),
                        child: Text(
                          p['status'] == 'requested'
                              ? t(
                                  'Record order',
                                  'Registrar pedido',
                                  'Consigner la commande',
                                )
                              : t(
                                  'Receive delivery',
                                  'Recibir entrega',
                                  'Réceptionner la livraison',
                                ),
                        ),
                      ),
                    TextButton(
                      onPressed: _disabled
                          ? null
                          : () => _purchaseAction('cancel_purchase', p),
                      child: Text(
                        t(
                          'Cancel remaining',
                          'Cancelar restante',
                          'Annuler le solde',
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
  ]);
  Widget _events(PartsWorkspace w) => _list([
    Text(
      t(
        'Latest 100 changes',
        'Últimos 100 cambios',
        '100 changements les plus récents',
      ),
    ),
    if (w.events.isEmpty)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text(
          t(
            'No stock activity yet.',
            'Aún no hay actividad de existencias.',
            'Aucune activité de stock pour le moment.',
          ),
        ),
      ),
    for (final event in w.events)
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          partsActionLabel(event['action'] as String, _es, french: _fr),
        ),
        subtitle: Text(
          [
            event['description'],
            event['location'],
            event['actor_name'],
            event['created_at'],
            if ((event['payload'] as Map?)?['quantity'] != null)
              '${t('Quantity', 'Cantidad', 'Quantité')}: ${(event['payload'] as Map)['quantity']}',
            (event['payload'] as Map?)?['note'],
          ].where((v) => v != null && v.toString().isNotEmpty).join('\n'),
        ),
      ),
  ]);
}

String partsActionLabel(String action, bool es, {bool french = false}) {
  const labels = {
    'stock_create': [
      'Stock item added',
      'Artículo añadido',
      'Article en stock ajouté',
    ],
    'stock_count': [
      'Stock counted',
      'Existencias contadas',
      'Stock inventorié',
    ],
    'import_kit': [
      'PM kit imported',
      'Kit PM importado',
      'Nécessaire d’entretien préventif importé',
    ],
    'requirement_add': [
      'Requirement added',
      'Requisito añadido',
      'Besoin ajouté',
    ],
    'requirement_edit': [
      'Requirement changed',
      'Requisito modificado',
      'Besoin modifié',
    ],
    'link': [
      'Stock selected',
      'Existencias seleccionadas',
      'Article en stock sélectionné',
    ],
    'reserve': ['Parts reserved', 'Repuestos reservados', 'Pièces réservées'],
    'release': [
      'Reservation released',
      'Reserva liberada',
      'Réservation libérée',
    ],
    'request': ['Parts requested', 'Repuestos solicitados', 'Pièces demandées'],
    'order': ['Order recorded', 'Pedido registrado', 'Commande consignée'],
    'receive': ['Delivery received', 'Entrega recibida', 'Livraison reçue'],
    'issue': ['Parts used', 'Repuestos utilizados', 'Pièces utilisées'],
    'return': ['Parts returned', 'Repuestos devueltos', 'Pièces retournées'],
    'cancel_purchase': [
      'Order cancelled',
      'Pedido cancelado',
      'Commande annulée',
    ],
    'requested': ['Requested', 'Solicitado', 'Demandé'],
    'ordered': ['Ordered', 'Pedido', 'Commandé'],
    'received': ['Received', 'Recibido', 'Reçu'],
    'cancelled': ['Cancelled', 'Cancelado', 'Annulé'],
  };
  return labels[action]?[french
          ? 2
          : es
          ? 1
          : 0] ??
      action;
}

String partsSaveError(String message, bool es, {bool french = false}) {
  if (french) {
    if (message.contains('changed')) {
      return 'Les données ont changé. Actualisez et réessayez.';
    }
    if (message.contains('Not enough')) {
      return 'Le stock disponible est insuffisant ou la quantité dépasse le besoin.';
    }
    if (message.contains('exceeds')) {
      return 'La quantité dépasse le solde permis. Vérifiez les quantités actuelles.';
    }
    if (message.contains('below reserved')) {
      return 'Le décompte ne peut pas être inférieur au stock réservé.';
    }
    if (message.contains('Manager') || message.contains('Access')) {
      return 'Votre compte n’est pas autorisé à effectuer cette modification.';
    }
    if (message.contains('unit')) {
      return 'L’unité de stock doit correspondre au besoin.';
    }
    if (message.contains('Explain')) {
      return 'Expliquez le motif de l’ajustement.';
    }
    if (message.contains('Start work')) {
      return 'Commencez le travail avant d’enregistrer l’utilisation des pièces.';
    }
    return 'Enregistrement impossible. Vérifiez les données, les autorisations et l’état du travail, puis réessayez.';
  }
  if (!es) return message;
  if (message.contains('changed')) {
    return 'Los datos cambiaron. Actualiza e inténtalo de nuevo.';
  }
  if (message.contains('Not enough')) {
    return 'No hay suficientes existencias disponibles o la cantidad supera lo necesario.';
  }
  if (message.contains('exceeds')) {
    return 'La cantidad supera el saldo permitido. Revisa las cantidades actuales.';
  }
  if (message.contains('below reserved')) {
    return 'El conteo no puede ser menor que las existencias reservadas.';
  }
  if (message.contains('Manager') || message.contains('Access')) {
    return 'Tu cuenta no tiene permiso para este cambio.';
  }
  if (message.contains('unit')) {
    return 'La unidad de existencias debe coincidir con el requisito.';
  }
  if (message.contains('Explain')) {
    return 'Explica el motivo del ajuste.';
  }
  if (message.contains('Start work')) {
    return 'Inicia el trabajo antes de registrar el uso de repuestos.';
  }
  return 'No se pudo guardar. Revisa los datos, permisos y estado del trabajo e inténtalo de nuevo.';
}
