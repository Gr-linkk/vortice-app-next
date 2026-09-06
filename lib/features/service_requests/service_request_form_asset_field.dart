import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/service_requests/service_request_form_support.dart';
import 'package:vortice_app/models/asset.dart';

class ServiceRequestFormAssetField extends StatelessWidget {
  const ServiceRequestFormAssetField({
    super.key,
    required this.assets,
    required this.value,
    required this.onChanged,
  });

  final List<Asset> assets;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppDropdownField<String>(
      initialValue: value,
      decoration: const InputDecoration(
        hintText: 'Select asset',
        prefixIcon: Icon(Icons.directions_boat_outlined),
      ),
      dropdownColor: AppColors.surfaceVariant,
      items: [
        ...assets.map(
          (asset) => DropdownMenuItem<String>(
            value: asset.id,
            child: Text(asset.name),
          ),
        ),
        const DropdownMenuItem<String>(
          value: kServiceRequestOtherAssetValue,
          child: Text('Other'),
        ),
      ],
      onChanged: onChanged,
      validator: validateServiceRequestAssetSelection,
    );
  }
}
