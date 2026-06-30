import 'package:vortice_app/models/pm_parts_requirement.dart';
import 'package:vortice_app/models/work_order.dart';

String formatPmPartsForWorkOrderNotes(List<PmPartsRequirement> parts) {
  if (parts.isEmpty) return '';
  return parts
      .map((part) {
        final unit = part.unit?.trim();
        final qtyLabel = part.qty == part.qty.roundToDouble()
            ? part.qty.toStringAsFixed(0)
            : part.qty.toStringAsFixed(1);
        final unitLabel = unit == null || unit.isEmpty ? 'ea' : unit;
        final number = part.partNumber?.trim();
        if (number == null || number.isEmpty) {
          return '${part.description} ($qtyLabel $unitLabel)';
        }
        return '${part.description} ($number, $qtyLabel $unitLabel)';
      })
      .join(', ');
}

bool shouldShowPmPartsKitPreview({
  required WorkOrderJobType jobType,
  required String? checklistTemplateId,
}) {
  return checklistTemplateId != null &&
      (jobType == WorkOrderJobType.preventative ||
          jobType == WorkOrderJobType.repair);
}

bool pmKitSelectionPrefillsWorkOrderPartsField() => true;
