import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'coordination_labels.dart';

typedef Subject = ({String kind, String id});
typedef ThreadQuery = ({
  Subject subject,
  String? before,
  String? beforeId,
  String? focus,
});
typedef AttentionQuery = ({String today, String? category, int offset});
typedef PeopleQuery = ({Subject subject, String visibility});
List<Map<String, dynamic>> coordinationRows(dynamic value) =>
    (value as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

@immutable
class HistoryQuery {
  const HistoryQuery({
    required this.asset,
    this.category,
    this.search = '',
    this.from,
    this.to,
    this.before,
    this.beforeId,
    this.asOf,
  });
  final String asset, search;
  final String? category, from, to, before, beforeId, asOf;
  Map<String, dynamic> get params => {
    'p_asset': asset,
    'p_category': category,
    'p_search': search,
    'p_from': from,
    'p_to': to,
    'p_before': before,
    'p_before_id': beforeId,
    'p_as_of': asOf,
  };
  HistoryQuery next(Map<String, dynamic> page) {
    final last = coordinationRows(page['entries']).last;
    return HistoryQuery(
      asset: asset,
      category: category,
      search: search,
      from: from,
      to: to,
      before: last['occurred_at'] as String,
      beforeId: last['id'] as String,
      asOf: page['as_of'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HistoryQuery && mapEquals(params, other.params);
  @override
  int get hashCode =>
      Object.hash(asset, category, search, from, to, before, beforeId, asOf);
}

abstract class CoordinationRepository {
  Future<Map<String, dynamic>> history(HistoryQuery query);
  Future<Map<String, dynamic>> attention(AttentionQuery query);
  Future<Map<String, dynamic>> thread(ThreadQuery query);
  Future<List<Map<String, dynamic>>> people(PeopleQuery query);
  Future<void> post(
    Subject subject,
    String operation,
    Map<String, dynamic> data,
  );
  Future<void> acknowledge(String post);
  Future<List<Map<String, dynamic>>> inbox();
  Future<void> markRead([String? post]);
  Future<void> upload(String path, Uint8List bytes, String contentType);
  Future<String> photoUrl(String path);
}

class SupabaseCoordinationRepository implements CoordinationRepository {
  SupabaseCoordinationRepository(this.client);
  final SupabaseClient client;
  Future<dynamic> _rpc(String name, [Map<String, dynamic>? params]) =>
      client.rpc(name, params: params).timeout(const Duration(seconds: 25));
  @override
  Future<Map<String, dynamic>> history(HistoryQuery query) async =>
      Map<String, dynamic>.from(
        await _rpc('asset_history', query.params) as Map,
      );
  @override
  Future<Map<String, dynamic>> attention(AttentionQuery query) async =>
      Map<String, dynamic>.from(
        await _rpc('fleet_attention', {
              'p_today': query.today,
              'p_category': query.category,
              'p_offset': query.offset,
            })
            as Map,
      );
  @override
  Future<Map<String, dynamic>> thread(ThreadQuery query) async =>
      Map<String, dynamic>.from(
        await _rpc('coordination_thread', {
              'p_kind': query.subject.kind,
              'p_id': query.subject.id,
              'p_before': query.before,
              'p_before_id': query.beforeId,
              'p_focus': query.focus,
            })
            as Map,
      );
  @override
  Future<List<Map<String, dynamic>>> people(PeopleQuery query) async =>
      coordinationRows(
        await _rpc('coordination_people', {
          'p_kind': query.subject.kind,
          'p_id': query.subject.id,
          'p_visibility': query.visibility,
        }),
      );
  @override
  Future<void> post(
    Subject subject,
    String operation,
    Map<String, dynamic> data,
  ) async {
    await _rpc('post_coordination_message', {
      'p_kind': subject.kind,
      'p_id': subject.id,
      'p_operation': operation,
      'p_data': data,
    });
  }

  @override
  Future<void> acknowledge(String post) async {
    await _rpc('acknowledge_handover', {'p_post': post});
  }

  @override
  Future<List<Map<String, dynamic>>> inbox() async =>
      coordinationRows(await _rpc('coordination_inbox'));
  @override
  Future<void> markRead([String? post]) async {
    await _rpc('mark_coordination_read', {'p_post': post});
  }

  @override
  Future<void> upload(String path, Uint8List bytes, String contentType) async {
    try {
      await client.storage
          .from('coordination-attachments')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType),
          )
          .timeout(const Duration(seconds: 30));
    } on StorageException catch (error) {
      if (error.statusCode != '409') rethrow;
      await photoUrl(path);
    }
  }

  @override
  Future<String> photoUrl(String path) => client.storage
      .from('coordination-attachments')
      .createSignedUrl(path, 300)
      .timeout(const Duration(seconds: 20));
}

final coordinationRepositoryProvider = Provider<CoordinationRepository>(
  (ref) => SupabaseCoordinationRepository(supabase),
);
final assetHistoryProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, HistoryQuery>((ref, query) async {
      await ref.watch(profileProvider.future);
      return ref.watch(coordinationRepositoryProvider).history(query);
    });
final fleetAttentionProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, AttentionQuery>((ref, query) async {
      await ref.watch(profileProvider.future);
      return ref.watch(coordinationRepositoryProvider).attention(query);
    });
final coordinationThreadProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ThreadQuery>((ref, query) async {
      await ref.watch(profileProvider.future);
      return ref.watch(coordinationRepositoryProvider).thread(query);
    });
final coordinationPeopleProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, PeopleQuery>((ref, query) async {
      await ref.watch(profileProvider.future);
      return ref.watch(coordinationRepositoryProvider).people(query);
    });
final coordinationPhotoProvider = FutureProvider.autoDispose
    .family<String, String>((ref, path) async {
      await ref.watch(profileProvider.future);
      return ref.watch(coordinationRepositoryProvider).photoUrl(path);
    });
String localCalendarDate([DateTime? value]) =>
    (value ?? DateTime.now()).toIso8601String().substring(0, 10);
String csvCell(String value) {
  if (RegExp(r'^[\s]*[=+@-]').hasMatch(value)) value = "'$value";
  return '"${value.replaceAll('"', '""')}"';
}

Future<String> exportAssetHistory(
  HistoryQuery filter,
  Future<Map<String, dynamic>> Function(HistoryQuery) fetch, {
  required bool spanish,
}) async {
  var query = HistoryQuery(
    asset: filter.asset,
    category: filter.category,
    search: filter.search,
    from: filter.from,
    to: filter.to,
    asOf: filter.asOf,
  );
  final out = StringBuffer('\uFEFF');
  out.writeln(
    (spanish
            ? [
                'Fecha',
                'Categoría',
                'Evento',
                'Título',
                'Detalle',
                'Autor',
                'Información',
              ]
            : [
                'Date',
                'Category',
                'Event',
                'Title',
                'Detail',
                'Author',
                'Information',
              ])
        .map(csvCell)
        .join(','),
  );
  final seen = <String>{};
  while (true) {
    final page = await fetch(query);
    final rows = coordinationRows(page['entries']);
    if (page['has_more'] == true && rows.isEmpty) {
      throw StateError('History page did not advance');
    }
    for (final row in rows) {
      if (!seen.add(row['id'] as String)) {
        throw StateError('History page repeated a record');
      }
      out.writeln(
        [
          row['occurred_at']?.toString() ?? '',
          coordinationLabel(
            historyCategories,
            row['category']?.toString() ?? '',
            spanish,
          ),
          historyKindLabel(row['kind'] as String?, spanish),
          row['title']?.toString() ?? '',
          row['body']?.toString() ?? '',
          row['actor_name']?.toString() ?? '',
          historyDetailText(
            Map<String, dynamic>.from(row['detail'] as Map? ?? {}),
            spanish,
          ),
        ].map(csvCell).join(','),
      );
    }
    if (page['has_more'] != true) return out.toString();
    query = query.next(page);
  }
}
