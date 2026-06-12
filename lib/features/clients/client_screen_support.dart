import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/clients/client_detail_sheet.dart';
import 'package:vortice_app/features/clients/client_invite_sheet.dart';
import 'package:vortice_app/models/profile.dart';

const clientAlwaysOnCapabilities = [
  'Assets & Documents',
  'Service History',
  'Invoices',
  'Request Vórtice Service',
];

void showClientInviteSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const InviteClientSheet(),
  );
}

void showClientDetailSheet(BuildContext context, Profile client) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => ClientDetailSheet(client: client),
  );
}
