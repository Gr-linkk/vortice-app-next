import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/features/service_reports/service_report_draft_controller.dart';
import 'package:vortice_app/features/service_reports/service_report_draft_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'leaving immediately after typing preserves the last report edit',
    () async {
      SharedPreferences.setMockInitialValues({});
      final fields = List.generate(5, (_) => TextEditingController());
      final draft = ServiceReportDraftController(
        initialWorkOrderId: 'wo',
        complaintController: fields[0],
        causeController: fields[1],
        correctionController: fields[2],
        collateralController: fields[3],
        commentsController: fields[4],
        onStateChanged: () {},
      );
      draft.selectedWorkOrderId = 'wo';
      draft.bindTextSaveListeners();
      fields[0].text = 'Latest words before pressing Back';
      draft.dispose();
      for (final field in fields) {
        field.dispose();
      }
      await Future<void>.delayed(Duration.zero);
      final saved = await const ServiceReportDraftManager().load(
        draftKey: draft.draftKey,
        draftMediaKey: draft.draftMediaKey,
      );
      expect(saved?.complaint, 'Latest words before pressing Back');
    },
  );
  test(
    'clearing a submitted draft prevents the pending timer from restoring it',
    () async {
      SharedPreferences.setMockInitialValues({});
      final fields = List.generate(5, (_) => TextEditingController());
      final draft = ServiceReportDraftController(
        initialWorkOrderId: 'wo',
        complaintController: fields[0],
        causeController: fields[1],
        correctionController: fields[2],
        collateralController: fields[3],
        commentsController: fields[4],
        onStateChanged: () {},
      );
      draft.bindTextSaveListeners();
      fields[0].text = 'Submitted content';
      await draft.clear();
      draft.dispose();
      for (final field in fields) {
        field.dispose();
      }
      await Future<void>.delayed(Duration.zero);
      final saved = await const ServiceReportDraftManager().load(
        draftKey: draft.draftKey,
        draftMediaKey: draft.draftMediaKey,
      );
      expect(saved, isNull);
    },
  );
}
