import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';

class OperatorChecklistStatusButton extends StatelessWidget {
  final String label;
  final String value;
  final String? current;
  final Color color;
  final VoidCallback onTap;

  const OperatorChecklistStatusButton({
    super.key,
    required this.label,
    required this.value,
    required this.current,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = current == value;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.18)
                : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: selected ? color : AppColors.divider,
              width: selected ? 1.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? color : AppColors.textSecondary,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}
