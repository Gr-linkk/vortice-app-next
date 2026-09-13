import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/membership/company_purpose.dart';
import 'package:vortice_app/features/membership/membership_provider.dart';

enum WorkFocus {
  own,
  customer,
  all;

  String label(bool es) => switch (this) {
    own => es ? 'Nuestros equipos' : 'Our equipment',
    customer => es ? 'Trabajo para clientes' : 'Customer work',
    all => es ? 'Todo el trabajo' : 'All work',
  };
  bool includes(bool ownEquipment) =>
      this == all || (this == own) == ownEquipment;
  static WorkFocus forPurpose(CompanyPurpose? purpose) => switch (purpose) {
    CompanyPurpose.fleet => own,
    CompanyPurpose.service => customer,
    _ => all,
  };
}

String workFocusStorageKey(String account, String? organization) =>
    accountStorageKey(account, 'work_focus:${organization ?? 'legacy'}');

class WorkFocusController extends AsyncNotifier<WorkFocus> {
  @override
  Future<WorkFocus> build() async {
    final profile = await ref.watch(profileProvider.future);
    if (profile == null) return WorkFocus.all;
    final company = profile.membershipManaged
        ? (await ref.watch(organizationContextProvider.future)).active
        : null;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(
      workFocusStorageKey(profile.id, profile.orgId),
    );
    return WorkFocus.values.where((value) => value.name == saved).firstOrNull ??
        WorkFocus.forPurpose(company?.companyPurpose);
  }

  Future<void> select(WorkFocus focus) async {
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile == null) return;
    state = AsyncData(focus);
    final prefs = await SharedPreferences.getInstance();
    final current = ref.read(profileProvider).valueOrNull;
    if (profile.id != current?.id || profile.orgId != current?.orgId) return;
    await prefs.setString(
      workFocusStorageKey(profile.id, profile.orgId),
      focus.name,
    );
  }
}

final workFocusProvider = AsyncNotifierProvider<WorkFocusController, WorkFocus>(
  WorkFocusController.new,
);

class WorkFocusSelector extends ConsumerWidget {
  const WorkFocusSelector({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workFocusProvider);
    final selected = state.valueOrNull ?? WorkFocus.all;
    final es = isSpanish(context);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final focus in WorkFocus.values)
          ChoiceChip(
            key: ValueKey('work-focus-${focus.name}'),
            label: Text(focus.label(es)),
            selected: selected == focus,
            onSelected: state.isLoading
                ? null
                : (_) => ref.read(workFocusProvider.notifier).select(focus),
          ),
      ],
    );
  }
}
