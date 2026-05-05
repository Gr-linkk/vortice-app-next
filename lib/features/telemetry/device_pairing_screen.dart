import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/telemetry/telemetry_provider.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

/// Fetches the device record linked to a given assetId.
/// Returns null if no device is paired.
final devicesProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, assetId) async {
  return ref.watch(telemetryRepositoryProvider).deviceForAsset(assetId);
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
      final userId = supabase.auth.currentUser?.id;
      final result = await ref.read(telemetryRepositoryProvider).pairDevice(
            assetId: widget.assetId,
            pairingCode: code,
            linkedBy: userId,
          );

      if (!result.linked) {
        _showError(result.errorMessage ?? 'Unable to link this device.');
        return;
      }

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
