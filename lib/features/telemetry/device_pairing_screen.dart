import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/models/telemetry_reading.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

/// Fetches the device record linked to a given assetId.
/// Returns null if no device is paired.
final devicesProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, assetId) async {
  final data = await supabase
      .from('devices')
      .select()
      .eq('asset_id', assetId)
      .maybeSingle();
  return data;
});

/// Fetches the latest telemetry reading for an asset via its first engine.
final latestTelemetryForAssetProvider =
    FutureProvider.family<TelemetryReading?, String>((ref, assetId) async {
  final engineData = await supabase
      .from(AppConstants.tAssetEngines)
      .select('id')
      .eq('asset_id', assetId)
      .limit(1)
      .maybeSingle();

  if (engineData == null) return null;
  final engineId = engineData['id'] as String;

  final data = await supabase
      .from(AppConstants.tTelemetryReadings)
      .select()
      .eq('engine_id', engineId)
      .order('ts', ascending: false)
      .limit(1)
      .maybeSingle();

  if (data == null) return null;
  return TelemetryReading.fromJson(data as Map<String, dynamic>);
});

// ── DevicePairingSheet ────────────────────────────────────────────────────────

class DevicePairingSheet extends ConsumerStatefulWidget {
  final String assetId;
  final String assetName;

  const DevicePairingSheet({
    super.key,
    required this.assetId,
    required this.assetName,
  });

  @override
  ConsumerState<DevicePairingSheet> createState() => _DevicePairingSheetState();
}

class _DevicePairingSheetState extends ConsumerState<DevicePairingSheet> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      _showError('Please enter the full 6-digit code.');
      return;
    }

    setState(() => _loading = true);

    try {
      // Look up device by pairing code where asset_id IS NULL (not yet linked)
      final data = await supabase
          .from('devices')
          .select()
          .eq('pairing_code', code)
          .isFilter('asset_id', null)
          .maybeSingle();

      if (data == null) {
        // Check if a device with this code exists but is already linked
        final existing = await supabase
            .from('devices')
            .select('asset_id')
            .eq('pairing_code', code)
            .maybeSingle();

        if (existing != null && existing['asset_id'] != null) {
          _showError('This device is already linked to another asset.');
        } else {
          _showError('Code not found. Check the code on your Pi unit.');
        }
        return;
      }

      // Update device with asset_id and linked_at
      final userId = supabase.auth.currentUser?.id;
      await supabase.from('devices').update({
        'asset_id': widget.assetId,
        'linked_at': DateTime.now().toIso8601String(),
        if (userId != null) 'linked_by': userId,
      }).eq('id', data['id'] as String);

      ref.invalidate(devicesProvider(widget.assetId));

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Telemetry device linked!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Link Telemetry Device',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter the 6-digit code shown on your Vórtice Pi unit',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
              letterSpacing: 12,
            ),
            decoration: const InputDecoration(
              hintText: '——————',
              hintStyle: TextStyle(
                fontSize: 32,
                letterSpacing: 12,
                color: AppColors.textSecondary,
              ),
              counterText: '',
            ),
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: _loading ? null : _link,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Link Device'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
