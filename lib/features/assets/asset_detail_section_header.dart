import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';

class AssetDetailSectionHeader extends StatelessWidget {
  final String title;

  const AssetDetailSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.primary,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}
