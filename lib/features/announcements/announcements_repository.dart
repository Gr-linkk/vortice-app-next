import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/membership/membership_provider.dart';

typedef AnnouncementQuery = ({String? before, String? beforeId});
const firstAnnouncementPage = (before: null, beforeId: null);

abstract class AnnouncementsRepository {
  Future<Map<String, dynamic>> feed(AnnouncementQuery query);
  Future<Map<String, dynamic>> get(String id);
  Future<void> publish(
    String organization,
    String operation,
    Map<String, dynamic> data,
  );
  Future<void> markRead(String id);
  Future<void> upload(String path, Uint8List bytes, String contentType);
  Future<Uint8List> photo(String path);
}

class SupabaseAnnouncementsRepository implements AnnouncementsRepository {
  SupabaseAnnouncementsRepository(this.client, this.account, this.organization);
  final SupabaseClient client;
  final String account;
  final String? organization;
  AccountJsonCache get _cache =>
      AccountJsonCache(account, () => client.auth.currentUser?.id);
  Future<dynamic> _rpc(String name, Map<String, dynamic> params) async {
    _cache.checkAccount();
    final data = await client
        .rpc(name, params: params)
        .timeout(const Duration(seconds: 25));
    _cache.checkAccount();
    return data;
  }

  @override
  Future<Map<String, dynamic>> feed(AnnouncementQuery query) async =>
      Map<String, dynamic>.from(
        await _cache.readThrough(
              'announcements:$organization:${query.before}:${query.beforeId}',
              () => _rpc('organization_announcement_feed', {
                'p_organization': organization,
                'p_before': query.before,
                'p_before_id': query.beforeId,
              }),
            )
            as Map,
      );
  @override
  Future<Map<String, dynamic>> get(String id) async =>
      Map<String, dynamic>.from(
        await _cache.readThrough(
              'announcement:$id',
              () => _rpc('organization_announcement', {'p_id': id}),
            )
            as Map,
      );
  @override
  Future<void> publish(
    String organization,
    String operation,
    Map<String, dynamic> data,
  ) async {
    await _rpc('publish_organization_announcement', {
      'p_organization': organization,
      'p_operation': operation,
      'p_data': data,
    });
  }

  @override
  Future<void> markRead(String id) async {
    await _rpc('mark_organization_announcement_read', {'p_announcement': id});
  }

  @override
  Future<void> upload(String path, Uint8List bytes, String contentType) async {
    _cache.checkAccount();
    try {
      await client.storage
          .from('organization-announcements')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: false),
          )
          .timeout(const Duration(seconds: 30));
    } on StorageException catch (error) {
      if (error.statusCode != '409' && error.error != 'Duplicate') rethrow;
      final previous = await client.storage
          .from('organization-announcements')
          .download(path)
          .timeout(const Duration(seconds: 20));
      if (base64Encode(previous) != base64Encode(bytes)) {
        throw StateError('The uploaded attachment changed');
      }
    }
    _cache.checkAccount();
  }

  @override
  Future<Uint8List> photo(String path) async {
    final data = await _cache.readThrough('announcement_photo:$path', () async {
      _cache.checkAccount();
      final bytes = await client.storage
          .from('organization-announcements')
          .download(path)
          .timeout(const Duration(seconds: 20));
      _cache.checkAccount();
      return base64Encode(bytes);
    });
    return base64Decode(data as String);
  }
}

final announcementsRepositoryProvider = Provider<AnnouncementsRepository>(
  (ref) => SupabaseAnnouncementsRepository(
    supabase,
    ref.watch(sessionProvider)?.user.id ?? '',
    ref.watch(organizationContextProvider).valueOrNull?.active?.organizationId,
  ),
);
final announcementsFeedProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, AnnouncementQuery>((ref, query) async {
      await ref.watch(organizationContextProvider.future);
      return ref.watch(announcementsRepositoryProvider).feed(query);
    });
final announcementProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>(
      (ref, id) => ref.watch(announcementsRepositoryProvider).get(id),
    );
final announcementPhotoProvider = FutureProvider.autoDispose
    .family<Uint8List, String>(
      (ref, path) => ref.watch(announcementsRepositoryProvider).photo(path),
    );
