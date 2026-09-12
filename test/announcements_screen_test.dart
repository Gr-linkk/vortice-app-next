import 'dart:typed_data';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/announcements/announcements_repository.dart';
import 'package:vortice_app/features/announcements/announcements_screen.dart';

class _Repository implements AnnouncementsRepository {
  final marked = <String>[];
  final post = <String, dynamic>{
    'id': 'announcement',
    'organization_name': 'Fleet A',
    'title': 'Shutdown briefing',
    'body': 'Inspect equipment before the next shift.',
    'author_name': 'Manager A',
    'created_at': '2026-09-12T12:00:00Z',
    'attachments': [],
  };
  @override
  Future<Map<String, dynamic>> get(String id) async => post;
  @override
  Future<void> markRead(String id) async {
    marked.add(id);
  }

  @override
  Future<Map<String, dynamic>> feed(AnnouncementQuery query) async => {
    'organization_id': 'org',
    'organization_name': 'Fleet A',
    'unread_count': 1,
    'participant_count': 2,
    'participants': [],
    'posts': [post],
    'can_publish': false,
    'has_more': false,
  };
  @override
  Future<void> publish(
    String organization,
    String operation,
    Map<String, dynamic> data,
  ) async {}
  @override
  Future<void> upload(String path, Uint8List bytes, String contentType) async {}
  @override
  Future<Uint8List> photo(String path) async => Uint8List(0);
}

void main() {
  setUpAll(() => initializeDateFormatting());
  testWidgets(
    'member opens announcement and records read state without publish controls',
    (tester) async {
      final repository = _Repository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            announcementsRepositoryProvider.overrideWithValue(repository),
            announcementsFeedProvider(
              firstAnnouncementPage,
            ).overrideWith((ref) => repository.feed(firstAnnouncementPage)),
          ],
          child: const MaterialApp(home: OrganizationAnnouncementsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Shutdown briefing'), findsOneWidget);
      expect(find.text('Publish announcement'), findsNothing);
      expect(find.text('1 unread'), findsOneWidget);
      await tester.tap(find.text('Shutdown briefing'));
      await tester.pumpAndSettle();
      expect(
        find.text('Inspect equipment before the next shift.'),
        findsOneWidget,
      );
      expect(repository.marked, ['announcement']);
    },
  );
}
