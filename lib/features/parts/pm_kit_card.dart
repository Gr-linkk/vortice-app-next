import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/parts/pm_kit_add_part_sheet.dart';
import 'package:vortice_app/features/parts/pm_kit_part_row.dart';
import 'package:vortice_app/features/parts/pm_kits_support.dart';

class PmKitCard extends StatefulWidget {
  final Map<String, dynamic> kit;
  final String assetName;
  final VoidCallback onRefresh;

  const PmKitCard({
    super.key,
    required this.kit,
    required this.assetName,
    required this.onRefresh,
  });

  @override
  State<PmKitCard> createState() => _PmKitCardState();
}

class _PmKitCardState extends State<PmKitCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final kit = widget.kit;
    final parts = kit['parts'] as List<Map<String, dynamic>>;
    final templateName = kit['template_name'] as String;
    final intervalLabel = kit['interval_label'] as String;

    return Card(
      margin: const EdgeInsets.fromLTRB(24, 4, 16, 4),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              child: const Icon(Icons.inventory_2_outlined,
                  size: 18, color: AppColors.primary),
            ),
            title: Text(intervalLabel,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              '$templateName • ${pmKitPartCountLabel(parts.length)}',
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.add, size: 20),
                  tooltip: 'Add part',
                  onPressed: () => showPmKitAddPartSheet(
                    context,
                    templateId: kit['template_id'] as String,
                    onSaved: widget.onRefresh,
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            if (parts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No parts added yet.',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
              )
            else
              ...parts.map((part) => PmKitPartRow(
                    part: part,
                    templateId: kit['template_id'] as String,
                    onRefresh: widget.onRefresh,
                  )),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}
