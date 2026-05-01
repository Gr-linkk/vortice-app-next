import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';

const _tAssignments = 'checklist_assignments';
const _tTemplates = 'checklist_templates';

/// Assignments for the current user (mechanic/operator sees own)
final myChecklistAssignmentsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return [];

  final data = await supabase
      .from(_tAssignments)
      .select('''
        id, status, due_date, notes, created_at,
        checklist_templates(id, name, checklist_type, interval_label),
        assets(id, name)
      ''')
      .eq('assigned_to', userId)
      .neq('status', 'cancelled')
      .order('created_at', ascending: false);

  return List<Map<String, dynamic>>.from(data as List);
});

/// Assignments issued by this org (client_admin sees all in their org)
final orgChecklistAssignmentsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = ref.watch(profileProvider).valueOrNull;
  final orgId = profile?.orgId;
  if (orgId == null) return [];

  final data = await supabase
      .from(_tAssignments)
      .select('''
        id, status, due_date, notes, created_at,
        checklist_templates(id, name, checklist_type, interval_label),
        assets(id, name),
        assignee:profiles!checklist_assignments_assigned_to_fkey(id, full_name, role)
      ''')
      .eq('org_id', orgId)
      .order('created_at', ascending: false);

  return List<Map<String, dynamic>>.from(data as List);
});

/// PM checklist templates (for mechanics)
final pmChecklistTemplatesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await supabase
      .from(_tTemplates)
      .select('id, name, checklist_type, interval_label, interval_hours')
      .eq('checklist_type', 'pm')
      .eq('is_active', true)
      .order('interval_hours');

  return List<Map<String, dynamic>>.from(data as List);
});

/// Pre-op checklist templates (for operators)
final preOpChecklistTemplatesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await supabase
      .from(_tTemplates)
      .select('id, name, checklist_type, interval_label')
      .eq('checklist_type', 'operator_daily')
      .eq('is_active', true)
      .order('name');

  return List<Map<String, dynamic>>.from(data as List);
});

/// Controller for creating/updating assignments
class ChecklistAssignmentController {
  static Future<void> assign({
    required String templateId,
    required String assignedTo,
    required String assignedBy,
    required String orgId,
    String? assetId,
    DateTime? dueDate,
    String? notes,
  }) async {
    await supabase.from(_tAssignments).insert({
      'template_id': templateId,
      'assigned_to': assignedTo,
      'assigned_by': assignedBy,
      'org_id': orgId,
      'asset_id': assetId,
      'due_date': dueDate?.toIso8601String(),
      'notes': notes,
      'status': 'pending',
    });
  }

  static Future<void> markComplete(String assignmentId) async {
    await supabase.from(_tAssignments).update({
      'status': 'completed',
      'completed_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', assignmentId);
  }

  static Future<void> markInProgress(String assignmentId) async {
    await supabase.from(_tAssignments).update({
      'status': 'in_progress',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', assignmentId);
  }

  static Future<void> cancel(String assignmentId) async {
    await supabase.from(_tAssignments).update({
      'status': 'cancelled',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', assignmentId);
  }
}
