import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/service_requests/service_request_form_support.dart';
import 'package:vortice_app/models/service_request.dart';

class ServiceRequestFormRequestTypeField extends StatelessWidget {
  const ServiceRequestFormRequestTypeField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ServiceRequestKind value;
  final ValueChanged<ServiceRequestKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ServiceRequestKind.values
          .map(
            (kind) => ChoiceChip(
              label: Text(kind.label),
              selected: kind == value,
              showCheckmark: false,
              avatar: Icon(
                serviceRequestKindIcon(kind),
                size: 18,
                color: kind == value ? Colors.white : AppColors.textSecondary,
              ),
              onSelected: (_) => onChanged(kind),
              selectedColor: AppColors.primary,
              backgroundColor: AppColors.surfaceVariant,
              labelStyle: TextStyle(
                color: kind == value ? Colors.white : AppColors.textPrimary,
                fontWeight: kind == value ? FontWeight.w700 : FontWeight.w500,
              ),
              side: BorderSide(
                color: kind == value ? AppColors.primary : AppColors.cardBorder,
              ),
            ),
          )
          .toList(),
    );
  }
}
