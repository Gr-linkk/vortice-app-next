import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/coordination/coordination_labels.dart';
import 'package:vortice_app/features/coordination/coordination_repository.dart';
import 'package:vortice_app/core/route_access_policy.dart';
import 'package:vortice_app/core/app_navigation.dart';
import 'package:vortice_app/models/profile.dart';

void main() {
  test('history formats captured costs and labour for English and Spanish', () {
    final detail = {
      'total_cost': 26.055000375,
      'labour_hours': 0.16233334166666666,
      'parts': [
        {'description': 'Seal', 'quantity': 1, 'unit_cost': 18.75},
      ],
    };
    expect(
      historyDetailText(detail, false),
      contains('Internal total cost: 26.06 USD'),
    );
    expect(historyDetailText(detail, false), contains('Labour hours: 0.16'));
    expect(
      historyDetailText(detail, true),
      contains('Costo interno total: 26,06 USD'),
    );
    expect(historyDetailText(detail, true), contains('Horas de trabajo: 0,16'));
    expect(historyDetailText(detail, true), contains('18,75 USD'));
  });
  test(
    'fleet overview is restricted to managers while every role has an inbox',
    () {
      for (final role in UserRole.values) {
        final manager = [
          UserRole.owner,
          UserRole.client,
          UserRole.clientAdmin,
        ].contains(role);
        expect(
          resolveRouteAccessRedirect(
            role: role,
            location: '/fleet/overview',
            dashboardRouteForRole: (_) => '/home',
          ),
          manager ? null : '/home',
        );
        expect(
          toolDestinations(role).any((d) => d.route == '/notifications'),
          isTrue,
        );
      }
    },
  );
  test(
    'CSV export preserves all pages and escapes formulas and punctuation',
    () async {
      final queries = <HistoryQuery>[];
      final csv = await exportAssetHistory(const HistoryQuery(asset: 'asset'), (
        query,
      ) async {
        queries.add(query);
        return {
          'as_of': '2026-09-06T01:00:00Z',
          'entries': [
            {
              'id': queries.length.toString(),
              'occurred_at': '2026-09-05T01:00:00Z',
              'category': 'parts',
              'title': queries.length == 1 ? '  =1+1' : 'Seal, "blue"',
              'body': 'Line one\nLine two',
              'detail': {'quantity': 2},
            },
          ],
          'has_more': queries.length == 1,
        };
      }, spanish: false);
      expect(queries, hasLength(2));
      expect(queries.last.beforeId, '1');
      expect(queries.last.asOf, '2026-09-06T01:00:00Z');
      expect(csv, contains("'  =1+1"));
      expect(csv, contains('Seal, ""blue""'));
      expect(csv, contains('Quantity: 2'));
    },
  );
  test(
    'export fails on a non-advancing page instead of silently truncating',
    () async {
      await expectLater(
        exportAssetHistory(
          const HistoryQuery(asset: 'asset'),
          (_) async => {
            'as_of': '2026-09-06T01:00:00Z',
            'has_more': true,
            'entries': <dynamic>[],
          },
          spanish: false,
        ),
        throwsStateError,
      );
    },
  );
}
