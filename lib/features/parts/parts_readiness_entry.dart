import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'parts_readiness_repository.dart';
import 'parts_readiness_screen.dart';

class PartsReadinessEntry extends StatelessWidget {
  const PartsReadinessEntry({super.key, this.jobId});
  final String? jobId;
  @override
  Widget build(BuildContext context) {
    final es = Localizations.localeOf(context).languageCode == 'es';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.inventory_2_outlined),
        title: Text(
          jobId == null
              ? (es ? 'Existencias y compras' : 'Stock & purchasing')
              : (es ? 'Disponibilidad de repuestos' : 'Parts readiness'),
        ),
        subtitle: Text(
          jobId == null
              ? (es
                    ? 'Ubicaciones, conteos y pedidos pendientes'
                    : 'Locations, counts and outstanding orders')
              : (es
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
    final summary = ref.watch(partsReadinessSummaryProvider);
    final row = summary.valueOrNull?[jobId] as Map?;
    final short = (row?['short'] as num?)?.toInt() ?? 0;
    final unreserved = (row?['unreserved'] as num?)?.toInt() ?? 0;
    final label = summary.hasError
        ? (es ? 'Repuestos: estado no disponible' : 'Parts: status unavailable')
        : summary.isLoading
        ? (es ? 'Comprobando repuestos…' : 'Checking parts…')
        : row == null
        ? (es ? 'Repuestos: sin requisitos' : 'Parts: no requirements')
        : short > 0
        ? (es ? 'Repuestos: $short faltantes' : 'Parts: $short shortages')
        : unreserved > 0
        ? (es
              ? 'Repuestos: pendientes de reserva'
              : 'Parts: awaiting reservation')
        : (es
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
