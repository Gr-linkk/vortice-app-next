import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/core/meter_units.dart';
import 'package:vortice_app/core/retryable_rpc.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/engines/engine_provider.dart';
import 'package:vortice_app/features/hours/hour_log_screen.dart';
import 'package:vortice_app/features/membership/membership_models.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/profile.dart';

abstract class AssetMeterRepository {
  Future<void> configure(String asset, String unit, double reading);
}

class SupabaseAssetMeterRepository implements AssetMeterRepository {
  @override
  Future<void> configure(String asset, String unit, double reading) async {
    await authenticatedRetryableRpc().call('configure_asset_meter', {
      'p_asset': asset,
      'p_unit': unit,
      'p_value': reading,
    });
  }
}

final assetMeterRepositoryProvider = Provider<AssetMeterRepository>(
  (_) => SupabaseAssetMeterRepository(),
);

class AssetMeterCard extends ConsumerStatefulWidget {
  const AssetMeterCard({super.key, required this.asset});
  final Asset asset;
  @override
  ConsumerState<AssetMeterCard> createState() => _AssetMeterCardState();
}

class _AssetMeterCardState extends ConsumerState<AssetMeterCard> {
  String _display = 'original';
  String? _key;
  void _loadPreference(String? account, String? org) {
    final key = account == null
        ? null
        : accountStorageKey(
            account,
            'distance_display:$org:${widget.asset.id}',
          );
    if (key == _key) return;
    _key = key;
    _display = 'original';
    if (key == null) return;
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted || _key != key) return;
      final saved = prefs.getString(key);
      setState(
        () => _display = ['km', 'mi'].contains(saved) ? saved! : 'original',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    _loadPreference(profile?.id, profile?.orgId);
    final es = isSpanish(context);
    final asset = widget.asset;
    final meter = asset.primaryMeterEngineId == null
        ? null
        : ref.watch(engineByIdProvider(asset.primaryMeterEngineId!));
    final reading = meter?.valueOrNull;
    final manager = profile?.membershipManaged == true
        ? profile!.canInOrganization('assets_manage')
        : [
            UserRole.owner,
            UserRole.client,
            UserRole.clientAdmin,
          ].contains(profile?.role);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              es ? 'Medidor del equipo' : 'Asset meter',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (asset.primaryMeterEngineId == null)
              Text(
                es
                    ? 'Sin lectura principal registrada'
                    : 'No primary meter reading recorded',
              )
            else if (meter!.isLoading)
              const LinearProgressIndicator()
            else if (meter.hasError || reading == null)
              Text(
                es
                    ? 'No se pudo cargar la lectura'
                    : 'Meter reading unavailable',
              )
            else ...[
              Text(
                formatMeter(reading.currentHours, reading.meterUnit),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (reading.meterUnit != 'hours') ...[
                if (_display != 'original' && _display != reading.meterUnit)
                  Text(
                    '${es ? 'Equivalente' : 'Equivalent'}: ${formatMeter(convertDistance(reading.currentHours, reading.meterUnit, _display), _display)}',
                  ),
                AppDropdownField<String>(
                  initialValue: _display,
                  key: ValueKey('$_key:$_display'),
                  decoration: InputDecoration(
                    labelText: es ? 'Mostrar distancias' : 'Distance display',
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'original',
                      child: Text(es ? 'Unidad original' : 'Original unit'),
                    ),
                    ...['km', 'mi'].map(
                      (unit) => DropdownMenuItem(
                        value: unit,
                        child: Text(meterName(unit, es)),
                      ),
                    ),
                  ],
                  onChanged: (unit) async {
                    if (unit == null) return;
                    final key = _key;
                    setState(() => _display = unit);
                    final prefs = await SharedPreferences.getInstance();
                    if (key != null && key == _key) {
                      await prefs.setString(key, unit);
                    }
                  },
                ),
              ],
            ],
            if (asset.primaryMeterEngineId != null)
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => HourLogScreen(
                      engineId: asset.primaryMeterEngineId!,
                      assetId: asset.id,
                    ),
                  ),
                ),
                icon: const Icon(Icons.speed),
                label: Text(
                  es ? 'Lecturas e historial' : 'Readings and history',
                ),
              ),
            if (asset.primaryMeterEngineId == null && manager)
              TextButton.icon(
                onPressed: () async {
                  final saved = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AssetMeterSetupScreen(asset: asset),
                    ),
                  );
                  if (saved == true) {
                    ref.invalidate(assetByIdProvider(asset.id));
                    ref.invalidate(enginesForAssetProvider(asset.id));
                  }
                },
                icon: const Icon(Icons.add),
                label: Text(es ? 'Configurar medidor' : 'Set up meter'),
              ),
          ],
        ),
      ),
    );
  }
}

class AssetMeterSetupScreen extends ConsumerStatefulWidget {
  const AssetMeterSetupScreen({super.key, required this.asset});
  final Asset asset;
  @override
  ConsumerState<AssetMeterSetupScreen> createState() =>
      _AssetMeterSetupScreenState();
}

class _AssetMeterSetupScreenState extends ConsumerState<AssetMeterSetupScreen> {
  final _form = GlobalKey<FormState>();
  final _reading = TextEditingController();
  late String _unit;
  bool _busy = false;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _unit = widget.asset.meterUnit;
  }

  @override
  void dispose() {
    _reading.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(assetMeterRepositoryProvider)
          .configure(widget.asset.id, _unit, double.parse(_reading.text));
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    return Scaffold(
      appBar: AppBar(title: Text(es ? 'Configurar medidor' : 'Set up meter')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.asset.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Text(
              es
                  ? 'Elige la unidad física del medidor. Las lecturas conservarán esta unidad en el historial.'
                  : 'Choose the physical meter unit. Recorded readings will retain this unit in history.',
            ),
            const SizedBox(height: 16),
            AppDropdownField<String>(
              initialValue: _unit,
              decoration: InputDecoration(labelText: es ? 'Unidad' : 'Unit'),
              items: meterUnits
                  .map(
                    (unit) => DropdownMenuItem(
                      value: unit,
                      child: Text(meterName(unit, es)),
                    ),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value != null) setState(() => _unit = value);
                    },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _reading,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText:
                    '${es ? 'Lectura actual' : 'Current reading'} (${meterSymbol(_unit)})',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (value) {
                final number = double.tryParse(value?.trim() ?? '');
                return number == null ||
                        !number.isFinite ||
                        number < 0 ||
                        number >= 1000000000
                    ? (es
                          ? 'Introduce una lectura válida'
                          : 'Enter a valid reading')
                    : null;
              },
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(friendlyError(context, _error)),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(
                _busy
                    ? (es ? 'Guardando…' : 'Saving…')
                    : (es ? 'Guardar lectura' : 'Save reading'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
