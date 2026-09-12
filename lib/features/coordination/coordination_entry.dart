import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/features/fleet/fleet_widgets.dart';

class CoordinationEntry extends StatelessWidget {
  const CoordinationEntry({
    super.key,
    required this.assetId,
    this.kind,
    this.subjectId,
    this.compact = false,
  }) : assert(assetId != null || subjectId != null);
  final String? assetId;
  final String? kind, subjectId;
  final bool compact;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: compact
        ? Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (subjectId == null && assetId != null)
                TextButton.icon(
                  onPressed: () => context.push('/assurance/assets/$assetId'),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(
                    fleetText(
                      context,
                      'Custody & inspections',
                      'Custodia e inspecciones',
                    ),
                  ),
                ),
              TextButton.icon(
                onPressed: () => context.push(
                  '/discussion/${kind ?? 'asset'}/${subjectId ?? assetId}',
                ),
                icon: const Icon(Icons.forum_outlined),
                label: Text(
                  fleetText(
                    context,
                    'Discussion & handover',
                    'Conversación y relevo',
                  ),
                ),
              ),
              if (assetId != null) TextButton.icon(
                onPressed: () => context.push('/history/assets/$assetId'),
                icon: const Icon(Icons.history),
                label: Text(
                  fleetText(context, 'Asset history', 'Historial del equipo'),
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (subjectId == null && assetId != null) ...[
                OutlinedButton.icon(
                  onPressed: () => context.push('/assurance/assets/$assetId'),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(
                    fleetText(
                      context,
                      'Custody & inspections',
                      'Custodia e inspecciones',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              ...[
                OutlinedButton.icon(
                  onPressed: () => context.push(
                    '/discussion/${kind ?? 'asset'}/${subjectId ?? assetId}',
                  ),
                  icon: const Icon(Icons.forum_outlined),
                  label: Text(
                    fleetText(
                      context,
                      'Discussion & handover',
                      'Conversación y relevo',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (assetId != null) OutlinedButton.icon(
                onPressed: () => context.push('/history/assets/$assetId'),
                icon: const Icon(Icons.history),
                label: Text(
                  fleetText(
                    context,
                    'Full asset history',
                    'Historial completo del activo',
                  ),
                ),
              ),
            ],
          ),
  );
}
