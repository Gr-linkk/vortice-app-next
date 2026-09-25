import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/localized_text.dart';
import 'parts_readiness_repository.dart';
import 'parts_readiness_screen.dart';

class PartsReadinessEntry extends StatelessWidget {
  const PartsReadinessEntry({super.key, this.jobId});
  final String? jobId;
  @override
  Widget build(BuildContext context) {
    final es = Localizations.localeOf(context).languageCode == 'es';
    final fr = isFrench(context);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.inventory_2_outlined),
        title: Text(
          jobId == null
              ? localizedText(
                  context,
                  'Stock & purchasing',
                  'Existencias y compras',
                  'Stocks et achats',
                )
              : localizedText(
                  context,
                  'Parts readiness',
                  'Disponibilidad de repuestos',
                  'Disponibilité des pièces',
                ),
        ),
        subtitle: Text(
          jobId == null
              ? (fr
                    ? 'Emplacements, inventaires et commandes en attente'
                    : es
                    ? 'Ubicaciones, conteos y pedidos pendientes'
                    : 'Locations, counts and outstanding orders')
              : (fr
                    ? 'Besoins du nécessaire, réservations, ruptures et utilisation'
                    : es
                    ? 'Requisitos del kit, reservas, faltantes y uso'
                    : 'Kit requirements, reservations, shortages and use'),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => PartsReadinessScreen(jobId: jobId),
          ),
        ),
      ),
    );
  }
}

class PartsPlanningStatus extends ConsumerWidget {
  const PartsPlanningStatus({super.key, required this.jobId});
  final String jobId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final es = Localizations.localeOf(context).languageCode == 'es';
    final fr = isFrench(context);
    final summary = ref.watch(partsReadinessSummaryProvider);
    final row = summary.valueOrNull?[jobId] as Map?;
    final short = (row?['short'] as num?)?.toInt() ?? 0;
    final unreserved = (row?['unreserved'] as num?)?.toInt() ?? 0;
    final label = summary.hasError
        ? localizedText(
            context,
            'Parts: status unavailable',
            'Repuestos: estado no disponible',
            'Pièces : état indisponible',
          )
        : summary.isLoading
        ? localizedText(
            context,
            'Checking parts…',
            'Comprobando repuestos…',
            'Vérification des pièces…',
          )
        : row == null
        ? localizedText(
            context,
            'Parts: no requirements',
            'Repuestos: sin requisitos',
            'Pièces : aucun besoin',
          )
        : short > 0
        ? (fr
              ? 'Pièces : $short manquantes'
              : es
              ? 'Repuestos: $short faltantes'
              : 'Parts: $short shortages')
        : unreserved > 0
        ? (fr
              ? 'Pièces : en attente de réservation'
              : es
              ? 'Repuestos: pendientes de reserva'
              : 'Parts: awaiting reservation')
        : (fr
              ? 'Pièces : besoins couverts'
              : es
              ? 'Repuestos: requisitos cubiertos'
              : 'Parts: requirements covered');
    return TextButton.icon(
      style: short > 0
          ? TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            )
          : null,
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => PartsReadinessScreen(jobId: jobId),
        ),
      ),
      icon: const Icon(Icons.inventory_2_outlined, size: 18),
      label: Text(label),
    );
  }
}
