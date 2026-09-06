import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/features/fleet/fleet_widgets.dart';

class CoordinationEntry extends StatelessWidget {
  const CoordinationEntry({
    super.key,
    required this.assetId,
    this.kind,
    this.subjectId,
  });
  final String assetId;
  final String? kind, subjectId;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (subjectId == null) ...[
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
        if (subjectId != null) ...[
          OutlinedButton.icon(
            onPressed: () => context.push('/discussion/$kind/$subjectId'),
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
        OutlinedButton.icon(
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
