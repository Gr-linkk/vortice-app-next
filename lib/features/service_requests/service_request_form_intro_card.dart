import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';

class ServiceRequestFormIntroCard extends StatelessWidget {
  const ServiceRequestFormIntroCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.support_agent_outlined, color: AppColors.primary),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Send Vórtice the key details so we can prepare faster and build the work order from clean information.',
              style: TextStyle(color: AppColors.textPrimary, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
