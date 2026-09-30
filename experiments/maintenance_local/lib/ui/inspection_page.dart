import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../lab_store.dart';
import '../model.dart';
import 'common.dart';

class InspectionPage extends StatefulWidget {
  const InspectionPage({super.key, required this.store});
  final LabStore store;
  @override
  State<InspectionPage> createState() => _InspectionPageState();
}

class _InspectionPageState extends State<InspectionPage> {
  LabStore get store => widget.store;
  Json? alternatives;
  Uint8List? base;
  final notes = TextEditingController(), meter = TextEditingController();
  final dirty = <String, dynamic>{};
  String? message;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    base = store.document;
    final fields = await store.fields();
    if (!mounted) return;
    final v = valuesOf(fields);
    notes.text = v['notes'] as String;
    meter.text = v['meter']?.toString() ?? '';
    setState(() => alternatives = fields);
  }

  @override
  void dispose() {
    notes.dispose();
    meter.dispose();
    super.dispose();
  }

  Future<bool> save({
    bool submit = false,
    MapEntry<String, dynamic>? resolution,
  }) async {
    setState(() => busy = true);
    var saved = false;
    try {
      final patch = Map<String, dynamic>.from(dirty);
      if (patch.containsKey('meter') && resolution?.key != 'meter') {
        final reading = num.tryParse(meter.text.trim());
        if (reading == null || !reading.isFinite || reading < 0) {
          throw StateError('Enter a valid meter reading in hours.');
        }
        patch['meter'] = reading;
      }
      if (resolution != null) patch[resolution.key] = resolution.value;
      if (patch.isNotEmpty) {
        await store.update(patch, base: base);
      }
      dirty.clear();
      base = store.document;
      alternatives = await store.fields();
      if (resolution != null) {
        final values = valuesOf(alternatives!);
        notes.text = values['notes'] as String;
        meter.text = values['meter']?.toString() ?? '';
        message = conflicts(alternatives!).isEmpty
            ? 'Conflict resolved. Review the inspection and submit a new version.'
            : 'Selection saved. Resolve the remaining conflicting work before submitting.';
      } else if (submit) {
        await store.submit();
        message = store.office
            ? 'Submitted for computer review.'
            : 'Saved on this phone—waiting to send.';
      } else {
        message = 'Work saved on this ${store.office ? 'computer' : 'phone'}.';
      }
      saved = true;
    } catch (e) {
      message = e.toString().replaceFirst('Bad state: ', '');
    }
    if (mounted) setState(() => busy = false);
    return saved;
  }

  Future<void> photo(ImageSource source) async {
    try {
      if (!await save()) return;
      store.setSetting('pendingInspectionPhoto', store.workspace!['jobId']);
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2000,
        imageQuality: 85,
      );
      if (file == null) return;
      await store.attach(await file.readAsBytes());
      store.setSetting('photoRecoveryError', null);
      base = store.document;
      alternatives = await store.fields();
      if (mounted) {
        setState(
          () => message =
              'Photo saved on this ${store.office ? 'computer' : 'phone'}.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => message = 'Could not save the photo: $e');
    } finally {
      store.setSetting('pendingInspectionPhoto', null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = alternatives == null
        ? <String, dynamic>{}
        : valuesOf(alternatives!);
    return PopScope(
      canPop: dirty.isEmpty,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          await save();
          if (context.mounted && dirty.isEmpty) Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Equipment inspection')),
        body: alternatives == null
            ? const Center(child: CircularProgressIndicator())
            : page([
                Text(
                  store.workspace!['equipment'] as String,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Text(
                  'Complete both checks, record the meter, add notes and a photo. Saving work keeps it on this device; submit when it is ready for review.',
                ),
                if (message != null) notice(message!),
                if (dirty.isNotEmpty)
                  notice(
                    'Unsaved changes — choose Save work before leaving this inspection.',
                  ),
                if (conflicts(alternatives!).isNotEmpty) ...[
                  notice(
                    'This inspection has conflicting work. Choose the correct value for each item before submitting.',
                    error: true,
                  ),
                  for (final key in conflicts(alternatives!))
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Resolve ${checklist[key] ?? key}'),
                            for (final value in alternatives![key] as List)
                              OutlinedButton(
                                onPressed: busy
                                    ? null
                                    : () => save(
                                        resolution: MapEntry(key, value),
                                      ),
                                child: Text('Use: ${value ?? 'Not recorded'}'),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
                for (final entry in checklist.entries)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            entry.value,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              for (final option in ['pass', 'attention'])
                                ChoiceChip(
                                  label: Text(
                                    option == 'pass'
                                        ? 'Pass'
                                        : 'Needs attention',
                                  ),
                                  selected:
                                      (dirty[entry.key] ?? v[entry.key]) ==
                                      option,
                                  onSelected: busy
                                      ? null
                                      : (_) => setState(
                                          () => dirty[entry.key] = option,
                                        ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('meter'),
                  controller: meter,
                  enabled: !busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Meter reading (hours)',
                    helperText: 'Leave no guessed or default reading.',
                    helperMaxLines: 3,
                  ),
                  onChanged: (value) => setState(() => dirty['meter'] = value),
                ),
                const SizedBox(height: 20),
                TextField(
                  key: const Key('notes'),
                  controller: notes,
                  enabled: !busy,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 10000,
                  decoration: const InputDecoration(
                    labelText: 'Inspection notes',
                  ),
                  onChanged: (value) => setState(() => dirty['notes'] = value),
                ),
                if (v['photo'] != null)
                  evidenceImage(store, v['photo'] as String),
                if (!store.office) ...[
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => photo(ImageSource.gallery),
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Choose a saved photo'),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => photo(ImageSource.camera),
                    child: const Text('Take inspection photo'),
                  ),
                ] else
                  const Text(
                    'Choose or take the inspection photo on the paired phone.',
                  ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: busy ? null : save,
                  child: const Text('Save work'),
                ),
                FilledButton(
                  onPressed: busy ? null : () => save(submit: true),
                  child: const Text('Submit for review'),
                ),
              ]),
      ),
    );
  }
}
