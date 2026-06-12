import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/engines/engine_kind_options.dart';
import 'package:vortice_app/features/engines/engine_screen_support.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/models/asset_engine.dart';

class EngineTile extends ConsumerWidget {
  final AssetEngine engine;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const EngineTile({
    super.key,
    required this.engine,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latestHoursAsync = ref.watch(latestEngineHoursProvider(engine.id));
    final latestHours = latestHoursAsync.valueOrNull?.hours;
    final kindColor = engineKindColor(engine.kind);

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
              color: kindColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.engineering, color: kindColor, size: 22),
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
                      color: kindColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      engineKindLabel(engine.kind).toUpperCase(),
                      style: TextStyle(
                        color: kindColor,
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
                formatLatestEngineHoursSubtitle(latestHours),
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
