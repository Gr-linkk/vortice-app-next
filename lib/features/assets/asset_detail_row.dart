import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';

class AssetDetailRow extends StatelessWidget {
  final String label;
  final String? value;

  const AssetDetailRow({super.key, required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    if (value == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value!,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
