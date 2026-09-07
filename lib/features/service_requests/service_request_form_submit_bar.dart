import 'package:vortice_app/features/service_requests/service_request_form_support.dart';
import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';

class ServiceRequestFormSubmitBar extends StatelessWidget {
  const ServiceRequestFormSubmitBar({
    super.key,
    required this.isLoading,
    required this.onSubmit,
  });

  final bool isLoading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: context.appColors.background,
        border: Border(top: BorderSide(color: context.appColors.divider)),
      ),
      child: ElevatedButton.icon(
        onPressed: isLoading ? null : onSubmit,
        icon: isLoading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.appColors.onPrimary,
                ),
              )
            : const Icon(Icons.send_outlined),
        label: Text(requestText(context, 'Send Request')),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}
