import 'package:flutter/material.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/parts/pm_kits_support.dart';

class PmKitPartRow extends StatelessWidget {
  final Map<String, dynamic> part;
  final String templateId;
  final VoidCallback onRefresh;

  const PmKitPartRow({
    super.key,
    required this.part,
    required this.templateId,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 6, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(part['description'] as String? ?? '—',
                    style: const TextStyle(fontSize: 13)),
                if (part['part_number'] != null)
                  Text('PN: ${part['part_number']}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          Text(
            formatPmKitPartQty(part['qty'], part['unit'] as String?),
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 16, color: AppColors.error),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () async {
              await supabase
                  .from('pm_parts_requirements')
                  .delete()
                  .eq('id', part['id'] as String);
              onRefresh();
            },
          ),
        ],
      ),
    );
  }
}
