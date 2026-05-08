import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/engines/engine_kind_options.dart';
import 'package:vortice_app/features/engines/engine_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/models/asset_engine.dart';

class EngineScreen extends ConsumerWidget {
  final String assetId;
  const EngineScreen({super.key, required this.assetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final enginesAsync = ref.watch(enginesForAssetProvider(assetId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.enginesTitle)),
      body: enginesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 48),
              const SizedBox(height: 12),
              Text(err.toString()),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () =>
                    ref.invalidate(enginesForAssetProvider(assetId)),
                child: Text(l10n.retry),
              ),
            ],
          ),
        ),
        data: (engines) {
          if (engines.isEmpty) {
            return Center(
              child: Text(l10n.noEngines,
                  style: const TextStyle(color: AppColors.textSecondary)),
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(enginesForAssetProvider(assetId)),
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: engines.length,
              itemBuilder: (_, i) => _EngineTile(
                engine: engines[i],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _EngineDetailScreen(
                      assetId: assetId,
                      engine: engines[i],
                    ),
                  ),
                ),
                onEdit: () =>
                    _showEngineSheet(context, ref, l10n, assetId, engines[i]),
                onDelete: () => _confirmDelete(context, ref, l10n, engines[i]),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEngineSheet(context, ref, l10n, assetId, null),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref,
      AppLocalizations l10n, AssetEngine engine) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(l10n.confirmDelete),
        content: Text(l10n.confirmDeleteMessage),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => ctx.pop(true),
            child: Text(l10n.delete,
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(engineControllerProvider.notifier)
          .deleteEngine(engine.id, assetId);
    }
  }

  void _showEngineSheet(BuildContext context, WidgetRef ref,
      AppLocalizations l10n, String assetId, AssetEngine? engine) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _EngineForm(
        assetId: assetId,
        engine: engine,
      ),
    );
  }
}

class _EngineDetailScreen extends ConsumerWidget {
  final String assetId;
  final AssetEngine engine;

  const _EngineDetailScreen({
    required this.assetId,
    required this.engine,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(engine.label),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: l10n.edit,
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: AppColors.surface,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                builder: (ctx) => _EngineForm(
                  assetId: assetId,
                  engine: engine,
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            engineKindLabel(engine.kind),
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 16),
          _EngineInfoRow(label: 'Label', value: engine.label),
          _EngineInfoRow(label: 'Manufacturer', value: engine.make),
          _EngineInfoRow(label: 'Model', value: engine.model),
          _EngineInfoRow(label: 'Serial Number', value: engine.serialNumber),
          ref.watch(latestEngineHoursProvider(engine.id)).when(
                loading: () => const _EngineInfoRow(
                  label: 'Latest Work Order Hours',
                  value: 'Loading…',
                ),
                error: (_, __) => const _EngineInfoRow(
                  label: 'Latest Work Order Hours',
                  value: '—',
                ),
                data: (snapshot) => Column(
                  children: [
                    _EngineInfoRow(
                      label: 'Latest Work Order Hours',
                      value: snapshot.hours != null
                          ? '${snapshot.hours!.toStringAsFixed(1)} hrs'
                          : '—',
                    ),
                    if (snapshot.title != null)
                      _EngineInfoRow(
                        label: 'Source Work Order',
                        value: snapshot.title,
                      ),
                  ],
                ),
              ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: AppColors.surface,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                builder: (ctx) => _EngineForm(
                  assetId: assetId,
                  engine: engine,
                ),
              );
            },
            child: Text(l10n.edit),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _EngineInfoRow extends StatelessWidget {
  final String label;
  final String? value;

  const _EngineInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final displayValue = value?.trim().isNotEmpty == true ? value! : '—';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            displayValue,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _EngineTile extends ConsumerWidget {
  final AssetEngine engine;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EngineTile({
    required this.engine,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  Color _kindColor() => switch (engine.kind) {
        'main' || 'port' || 'starboard' || 'wing' => AppColors.primary,
        'generator' => AppColors.success,
        'auxiliary' => AppColors.warning,
        _ => AppColors.textSecondary,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latestHoursAsync = ref.watch(latestEngineHoursProvider(engine.id));
    final latestHours = latestHoursAsync.valueOrNull?.hours;

    return Dismissible(
      key: ValueKey(engine.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      child: Card(
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _kindColor().withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.engineering, color: _kindColor(), size: 22),
          ),
          title:
              Text(engine.label, style: Theme.of(context).textTheme.titleSmall),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _kindColor().withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      engineKindLabel(engine.kind).toUpperCase(),
                      style: TextStyle(
                        color: _kindColor(),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (engine.make != null || engine.model != null)
                    Text(
                      [engine.make, engine.model].whereType<String>().join(' '),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                latestHours != null
                    ? '${latestHours.toStringAsFixed(1)} hrs · latest WO'
                    : 'No work order hours yet',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
          trailing:
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          onTap: onTap,
          onLongPress: onEdit,
          isThreeLine: true,
        ),
      ),
    );
  }
}

class _EngineForm extends ConsumerStatefulWidget {
  final String assetId;
  final AssetEngine? engine;

  const _EngineForm({required this.assetId, this.engine});

  @override
  ConsumerState<_EngineForm> createState() => _EngineFormState();
}

class _EngineFormState extends ConsumerState<_EngineForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _makeCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _serialCtrl;
  String _kind = 'main';

  bool get _isEdit => widget.engine != null;

  @override
  void initState() {
    super.initState();
    _makeCtrl = TextEditingController(text: widget.engine?.make ?? '');
    _modelCtrl = TextEditingController(text: widget.engine?.model ?? '');
    _serialCtrl =
        TextEditingController(text: widget.engine?.serialNumber ?? '');
    _kind = normalizeEngineKind(widget.engine?.kind);
  }

  @override
  void dispose() {
    _makeCtrl.dispose();
    _modelCtrl.dispose();
    _serialCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final data = {
      'asset_id': widget.assetId,
      'label': suggestedEngineLabel(_kind),
      'kind': normalizeEngineKind(_kind),
      'make': _makeCtrl.text.trim().isEmpty ? null : _makeCtrl.text.trim(),
      'model': _modelCtrl.text.trim().isEmpty ? null : _modelCtrl.text.trim(),
      'serial_number':
          _serialCtrl.text.trim().isEmpty ? null : _serialCtrl.text.trim(),
    };

    bool success;
    if (_isEdit) {
      success = await ref
          .read(engineControllerProvider.notifier)
          .updateEngine(widget.engine!.id, widget.assetId, data);
    } else {
      success =
          await ref.read(engineControllerProvider.notifier).addEngine(data);
    }
    if (success && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controllerState = ref.watch(engineControllerProvider);
    final isLoading = controllerState is AsyncLoading;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textSecondary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isEdit ? l10n.editEngine : l10n.addEngine,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Title'),
                dropdownColor: AppColors.surfaceVariant,
                items: kEngineKindOptions
                    .map((option) => DropdownMenuItem(
                          value: option.value,
                          child: Text(option.suggestedLabel),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _kind = v);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _makeCtrl,
                decoration: InputDecoration(labelText: l10n.manufacturer),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _modelCtrl,
                decoration: InputDecoration(labelText: l10n.model),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _serialCtrl,
                decoration: InputDecoration(labelText: l10n.serialNumber),
              ),
              const SizedBox(height: 12),
              const Text(
                'Hours are pulled from the most recent work order for this engine.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: isLoading ? null : _submit,
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
