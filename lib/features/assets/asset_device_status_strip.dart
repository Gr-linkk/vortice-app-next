import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_detail_support.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/telemetry/device_pairing_screen.dart';
import 'package:vortice_app/features/telemetry/telemetry_provider.dart';
import 'package:vortice_app/models/profile.dart';

class AssetDeviceStatusStrip extends ConsumerWidget {
  final String assetId;

  const AssetDeviceStatusStrip({super.key, required this.assetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceAsync = ref.watch(devicesProvider(assetId));
    final telemAsync = ref.watch(latestTelemetryForAssetProvider(assetId));
    final role = ref.watch(profileProvider).valueOrNull?.role;
    final isOwner = role == UserRole.owner;

    return deviceAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (device) {
        if (device == null) {
          return AssetStatusStripContainer(
            child: Row(
              children: [
                const AssetStatusDot(live: false),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isOwner
                        ? 'No telemetry device'
                        : 'No telemetry device linked',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),
                if (isOwner)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: AppColors.surface,
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      builder: (_) => DevicePairingSheet(
                        assetId: assetId,
                        assetName: '',
                      ),
                    ),
                    child: const Text('Link Device →',
                        style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          );
        }

        final lastSeenStr = device['last_seen'] as String?;
        final lastSeen = lastSeenStr != null
            ? DateTime.tryParse(lastSeenStr)?.toLocal()
            : null;
        final isLive = lastSeen != null &&
            DateTime.now().difference(lastSeen).inMinutes < 5;

        if (isLive) {
          final reading = telemAsync.valueOrNull;
          return AssetStatusStripContainer(
            child: Row(
              children: [
                const AssetStatusDot(live: true),
                const SizedBox(width: 8),
                const Text(
                  'LIVE',
                  style: TextStyle(
                    color: AppColors.success,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (reading?.rpm != null) ...[
                  const Text(' · ',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                  Text(
                    '${reading!.rpm!.toStringAsFixed(0)} RPM',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 12),
                  ),
                ],
                if (reading?.coolantTemp != null) ...[
                  const Text(' · ',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                  Text(
                    '${reading!.coolantTemp!.toStringAsFixed(1)}°C',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 12),
                  ),
                ],
                const Spacer(),
                Text(
                  'Last seen ${formatDeviceMinutesAgo(lastSeen)}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          );
        } else {
          final lastSeenLabel =
              lastSeen != null ? formatDeviceRelativeTime(lastSeen) : 'Never';
          return AssetStatusStripContainer(
            child: Row(
              children: [
                const AssetStatusDot(live: false),
                const SizedBox(width: 8),
                const Text(
                  'Device linked',
                  style: TextStyle(color: AppColors.warning, fontSize: 12),
                ),
                const Text(
                  ' · No recent data',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const Spacer(),
                Text(
                  'Last seen $lastSeenLabel',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          );
        }
      },
    );
  }
}

class AssetStatusStripContainer extends StatelessWidget {
  final Widget child;

  const AssetStatusStripContainer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: const Border.fromBorderSide(
            BorderSide(color: AppColors.cardBorder)),
      ),
      child: child,
    );
  }
}

class AssetStatusDot extends StatelessWidget {
  final bool live;

  const AssetStatusDot({super.key, required this.live});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: live ? AppColors.success : Colors.transparent,
        border: Border.all(
          color: live ? AppColors.success : AppColors.textSecondary,
          width: 1.5,
        ),
      ),
    );
  }
}
