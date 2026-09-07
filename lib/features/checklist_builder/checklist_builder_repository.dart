import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';

final checklistBuilderRepositoryProvider = Provider(
  (ref) => ChecklistBuilderRepository(),
);
final checklistLibraryProvider = FutureProvider<Map<String, dynamic>>((ref) {
  ref.watch(profileProvider);
  return ref.watch(checklistBuilderRepositoryProvider).library();
});

class ChecklistBuilderRepository {
  Future<Map<String, dynamic>> library() async {
    final account = supabase.auth.currentUser?.id;
    final data = await supabase.rpc('checklist_library');
    if (account != supabase.auth.currentUser?.id) {
      throw const AccountChangedException();
    }
    return Map<String, dynamic>.from(data as Map? ?? {});
  }

  Future<String> save(
    String operation,
    String id,
    int revision,
    String action,
    Map<String, dynamic> data,
  ) async {
    final account = supabase.auth.currentUser?.id;
    final result = await supabase.rpc(
      'save_checklist_procedure',
      params: {
        'p_request': operation,
        'p_id': id,
        'p_revision': revision,
        'p_action': action,
        'p_data': data,
      },
    );
    if (account != supabase.auth.currentUser?.id) {
      throw const AccountChangedException();
    }
    return result as String;
  }

  Future<Map<String, dynamic>> assignments(String asset) async {
    final account = supabase.auth.currentUser?.id;
    final data = await supabase.rpc(
      'checklist_assignment_context',
      params: {'p_asset': asset},
    );
    if (account != supabase.auth.currentUser?.id) {
      throw const AccountChangedException();
    }
    return Map<String, dynamic>.from(data as Map? ?? {});
  }

  Future<void> assign(
    String operation,
    String id,
    Map<String, dynamic> data,
  ) async {
    final account = supabase.auth.currentUser?.id;
    await supabase.rpc(
      'assign_preop_checklist',
      params: {'p_operation': operation, 'p_assignment': id, 'p_data': data},
    );
    if (account != supabase.auth.currentUser?.id) {
      throw const AccountChangedException();
    }
  }
}

List<Map<String, dynamic>> checklistRows(dynamic data) => (data as List? ?? [])
    .whereType<Map>()
    .map((row) => Map<String, dynamic>.from(row))
    .toList();

Map<String, dynamic> copiedChecklistDraft(Map<String, dynamic> template) => {
  'name': '${template['name']} (copy)',
  'description': template['description'] ?? '',
  'checklist_type': template['checklist_type'] ?? 'pm',
  'asset_type_id': template['asset_type_id'],
  'source_template_id': template['id'],
  'source_version': template['version'],
  'items': checklistRows(template['items'])
      .map(
        (item) => {
          'description_en': item['description_en'],
          'description_es': item['description_es'],
          'category': item['category'],
          'requires_photo': item['requires_photo'] ?? false,
          'definition': Map<String, dynamic>.from(
            item['definition'] as Map? ?? {},
          ),
        },
      )
      .toList(),
};
