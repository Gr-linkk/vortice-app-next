import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'parts_readiness_models.dart';
import 'parts_readiness_repository.dart';
import 'parts_readiness_screen.dart';

/// The work owns its requirements; stock mutations remain in the checked,
/// replay-protected parts editor, with no duplicate consumption action here.
class WorkPartsProgress extends ConsumerWidget {
  const WorkPartsProgress({super.key, required this.jobId});
  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final es = Localizations.localeOf(context).languageCode == 'es';
    final result = ref.watch(partsWorkspaceProvider(jobId));
    final workspace = result.valueOrNull;
    Future<void> open() async {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => PartsReadinessScreen(jobId: jobId),
        ),
      );
      ref.invalidate(partsWorkspaceProvider(jobId));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    es ? 'Repuestos de esta orden' : 'Parts for this work',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (workspace == null)
              Text(
                result.isLoading
                    ? (es ? 'Comprobando repuestos…' : 'Checking parts…')
                    : (es
                          ? 'Estado de repuestos no disponible. Conecta para actualizar.'
                          : 'Parts status unavailable. Connect to refresh.'),
              ),
            if (workspace != null && workspace.requirements.isEmpty)
              Text(
                es
                    ? 'Sin requisitos de repuestos registrados.'
                    : 'No parts requirements recorded.',
              ),
            if (workspace != null)
              for (final requirement in workspace.requirements)
                Builder(
                  builder: (context) {
                    final stock = workspace.stockFor(requirement);
                    final received = workspace.purchases
                        .where((p) => p['requirement_id'] == requirement.id)
                        .fold<double>(
                          0,
                          (total, purchase) =>
                              total + partNumberValue(purchase['received_qty']),
                        );
                    final returned = workspace.events
                        .where(
                          (event) =>
                              event['action'] == 'return' &&
                              (event['payload'] as Map?)?['requirement_id'] ==
                                  requirement.id,
                        )
                        .fold<double>(
                          0,
                          (total, event) =>
                              total +
                              partNumberValue(
                                (event['payload'] as Map?)?['quantity'],
                              ),
                        );
                    String quantity(num value) =>
                        '${partQuantity(value)} ${requirement.unit}';
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            requirement.description,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            '${es ? 'Necesarios' : 'Needed'} ${quantity(requirement.required)} · ${es ? 'Disponibles' : 'Available'} ${quantity(stock?.available ?? 0)} · ${es ? 'Reservados' : 'Reserved'} ${quantity(requirement.reserved)}',
                          ),
                          Text(
                            '${es ? 'Faltantes' : 'Missing'} ${quantity(requirement.shortage(stock))} · ${es ? 'Pedidos pendientes' : 'On order'} ${quantity(workspace.outstanding(requirement.id))} · ${es ? 'Recibidos' : 'Received'} ${quantity(received)}',
                          ),
                          Text(
                            '${es ? 'Usados' : 'Used'} ${quantity(requirement.used)} · ${es ? 'Devueltos' : 'Returned'} ${quantity(returned)}',
                          ),
                        ],
                      ),
                    );
                  },
                ),
            TextButton.icon(
              onPressed: open,
              icon: const Icon(Icons.chevron_right),
              label: Text(es ? 'Revisar repuestos' : 'Review parts'),
            ),
          ],
        ),
      ),
    );
  }
}
