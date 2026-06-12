import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/work_orders/work_order_edit_support.dart';

Future<List<String>?> showWorkOrderTechPickerSheet({
  required BuildContext context,
  required List<Map<String, dynamic>> employees,
  required List<String> initialSelection,
}) {
  final selected = Set<String>.from(initialSelection);

  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Assigned Technicians',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: employees.map((employee) {
                          final id = employee['id'] as String;
                          return CheckboxListTile(
                            value: selected.contains(id),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            title: Text(employeeDisplayName(employee)),
                            onChanged: (checked) {
                              setModalState(() {
                                if (checked == true) {
                                  selected.add(id);
                                } else {
                                  selected.remove(id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(
                      context,
                      employees
                          .map((employee) => employee['id'] as String)
                          .where(selected.contains)
                          .toList(),
                    ),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
