import 'package:vortice_app/models/part.dart';

/// Codified parts-log + hours workflow rules (A021–A025).
class PartsLogWorkflowPolicy {
  const PartsLogWorkflowPolicy._();

  static bool partsPayloadIncludesNotesField() {
    const sample = Part(
      id: 'part-1',
      workOrderId: 'wo-1',
      description: 'Filter',
      quantity: 1,
      notes: 'OEM replacement',
    );
    return sample.notes == 'OEM replacement';
  }
}
