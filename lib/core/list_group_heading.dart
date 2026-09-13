import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';

/// A visible, non-collapsing section: all choices remain one tap away.
class ListGroupHeading extends StatelessWidget {
  const ListGroupHeading({super.key, required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: context.appColors.textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$count',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: context.appColors.textSecondary,
            ),
          ),
        ],
      ),
    ),
  );
}
