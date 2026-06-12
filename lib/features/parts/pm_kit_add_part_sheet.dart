import 'package:flutter/material.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/theme.dart';

void showPmKitAddPartSheet(
  BuildContext context, {
  required String templateId,
  required VoidCallback onSaved,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => PmKitAddPartSheet(templateId: templateId, onSaved: onSaved),
  );
}

class PmKitAddPartSheet extends StatefulWidget {
  final String templateId;
  final VoidCallback onSaved;

  const PmKitAddPartSheet({
    super.key,
    required this.templateId,
    required this.onSaved,
  });

  @override
  State<PmKitAddPartSheet> createState() => _PmKitAddPartSheetState();
}

class _PmKitAddPartSheetState extends State<PmKitAddPartSheet> {
  final _descCtrl = TextEditingController();
  final _pnCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _unitCtrl = TextEditingController(text: 'ea');
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    _pnCtrl.dispose();
    _qtyCtrl.dispose();
    _unitCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Add Part to Kit',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(labelText: 'Description *'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pnCtrl,
            decoration: const InputDecoration(labelText: 'Part Number'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _qtyCtrl,
                  decoration: const InputDecoration(labelText: 'Qty'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _unitCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Unit (ea, L, kg...)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saving || _descCtrl.text.trim().isEmpty ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Add Part'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await supabase.from('pm_parts_requirements').insert({
        'template_id': widget.templateId,
        'description': _descCtrl.text.trim(),
        'part_number':
            _pnCtrl.text.trim().isNotEmpty ? _pnCtrl.text.trim() : null,
        'qty': double.tryParse(_qtyCtrl.text.trim()) ?? 1,
        'unit': _unitCtrl.text.trim().isNotEmpty ? _unitCtrl.text.trim() : 'ea',
        'notes':
            _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
      });
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
