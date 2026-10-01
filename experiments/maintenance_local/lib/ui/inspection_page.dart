import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../lab_store.dart';
import '../model.dart';
import '../local_sync.dart';
import 'common.dart';
import 'inspection_content.dart';
import '../job_progress.dart';
import 'work_progress.dart';

class InspectionPage extends StatefulWidget {
  const InspectionPage({
    super.key,
    required this.store,
    this.jobId,
    this.sync,
    this.updates,
    this.progressController,
    this.correctionSubmissionId,
  });
  final LabStore store;
  final String? jobId;
  final PhoneSync? sync;
  final ValueListenable<int>? updates;
  final WorkProgressController? progressController;
  final String? correctionSubmissionId;
  @override
  State<InspectionPage> createState() => _InspectionPageState();
}

class _InspectionPageState extends State<InspectionPage> {
  LabStore get store => widget.store;
  late final String? jobId;
  late final Json jobContext;
  late final bool legacy;
  Json? alternatives;
  Uint8List? base;
  final notes = TextEditingController(), meter = TextEditingController();
  final answers = <String, TextEditingController>{};
  final dirty = <String, dynamic>{};
  String? message;
  bool busy = false;
  WorkProgressController? progress;
  bool ownsProgress = false;

  @override
  void initState() {
    super.initState();
    legacy = store.catalog == null;
    jobId = legacy ? null : (widget.jobId ?? store.activeJobId);
    jobContext = legacy
        ? Map<String, dynamic>.from(store.workspace!)
        : store.jobContextFor(jobId!);
    if (!legacy) {
      ownsProgress = widget.progressController == null;
      progress = widget.progressController ?? WorkProgressController(store);
      if (ownsProgress) widget.updates?.addListener(refreshProgress);
    }
    for (final item in inspectionItems(jobContext)) {
      if (item['input_type'] != 'check') {
        answers[item['id'] as String] = TextEditingController();
      }
    }
    load();
  }

  Future<void> load() async {
    try {
      base = legacy ? store.document : store.documentFor(jobId!);
      final fields = await store.fields(jobId: jobId);
      if (!mounted) return;
      refill(valuesOf(fields));
      setState(() => alternatives = fields);
      refreshProgress();
    } catch (failure) {
      if (mounted) {
        setState(
          () => message = failure.toString().replaceFirst('Bad state: ', ''),
        );
      }
    }
  }

  void refill(Json values) {
    notes.text = (values['notes'] ?? '').toString();
    meter.text = values['meter']?.toString() ?? '';
    for (final entry in answers.entries) {
      entry.value.text = (jsonMap(values['answer:${entry.key}'])['value'] ?? '')
          .toString();
    }
  }

  void refreshProgress() {
    if (mounted && progress != null) unawaited(progress!.refresh());
  }

  @override
  void dispose() {
    notes.dispose();
    meter.dispose();
    for (final controller in answers.values) {
      controller.dispose();
    }
    if (ownsProgress) {
      widget.updates?.removeListener(refreshProgress);
      progress?.dispose();
    }
    super.dispose();
  }

  Future<bool> save({
    bool submit = false,
    MapEntry<String, dynamic>? resolution,
  }) async {
    if (busy) return false;
    setState(() => busy = true);
    var saved = false;
    try {
      final patch = Map<String, dynamic>.from(dirty);
      if (patch.containsKey('meter') && resolution?.key != 'meter') {
        final raw = meter.text.trim();
        final reading = num.tryParse(raw.replaceAll(',', '.'));
        if (raw.isNotEmpty &&
            (reading == null ||
                !reading.isFinite ||
                reading < 0 ||
                reading > 1e12)) {
          throw StateError(
            'Enter a valid meter reading in ${legacy ? 'hours' : meterUnitLabel(jobContext['meterUnit'])}. Your other changes are still here.',
          );
        }
        patch['meter'] = raw.isEmpty ? null : reading;
      }
      if (resolution != null) patch[resolution.key] = resolution.value;
      if (patch.isNotEmpty) {
        await store.update(patch, base: base, jobId: jobId);
        // This draft is already durable even if decoding or submission fails.
        // Invalidate its earlier exact-version status before the next await.
        refreshProgress();
      }
      dirty.clear();
      base = legacy ? store.document : store.documentFor(jobId!);
      alternatives = await store.fields(jobId: jobId);
      if (resolution != null) {
        refill(valuesOf(alternatives!));
        message = conflicts(alternatives!).isEmpty
            ? 'Conflict resolved. Review the inspection and submit a new version.'
            : 'Selection saved. Resolve the remaining conflicting work before submitting.';
      } else if (submit) {
        final existingIds = store.submissions.map((p) => p['id']).toSet();
        final submitted = await store.submit(jobId: jobId);
        final stored = store.submissions.firstWhere(
          (p) => p['id'] == submitted['id'],
        );
        final receipt = store.receipts
            .where((r) => r['submissionId'] == submitted['id'])
            .firstOrNull;
        message = submissionSavedMessage(
          SubmittedVersion(submission: stored, receipt: receipt),
          existing: existingIds.contains(submitted['id']),
          office: store.office,
          sendingStatusShown: widget.sync != null,
        );
      } else {
        message = 'Work saved on this ${store.office ? 'computer' : 'phone'}.';
      }
      saved = true;
    } catch (failure) {
      message = failure.toString().replaceFirst('Bad state: ', '');
    } finally {
      refreshProgress();
    }
    if (mounted) setState(() => busy = false);
    return saved;
  }

  Future<void> photo(ImageSource source) async {
    if (!await save()) return;
    if (!mounted) return;
    setState(() => busy = true);
    try {
      store.setSetting(
        'pendingInspectionPhoto',
        legacy ? jobContext['jobId'] : jobId,
      );
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2000,
        imageQuality: 85,
      );
      if (file == null) {
        message =
            'No photo selected. Your inspection notes and readings are saved.';
        return;
      }
      await store.attach(await file.readAsBytes(), jobId: jobId);
      store.setSetting('photoRecoveryError', null);
      base = legacy ? store.document : store.documentFor(jobId!);
      alternatives = await store.fields(jobId: jobId);
      message = 'Photo saved on this ${store.office ? 'computer' : 'phone'}.';
    } catch (failure) {
      message =
          'Could not save the photo. Your notes and readings are saved. Choose the photo again. ${failure.toString().replaceFirst('Bad state: ', '')}';
    } finally {
      store.setSetting('pendingInspectionPhoto', null);
      refreshProgress();
      if (mounted) setState(() => busy = false);
    }
  }

  Json answerFor(Json item, Json values) {
    final key = 'answer:${item['id']}';
    return jsonMap(dirty.containsKey(key) ? dirty[key] : values[key]);
  }

  void changeAnswer(
    Json item,
    Json values, {
    String? result,
    String? value,
    bool typed = false,
  }) {
    final answer = answerFor(item, values);
    final text = value ?? (answer['value'] ?? '').toString();
    Object? next = result ?? answer['result'];
    if (typed && next != 'na') {
      if (item['input_type'] == 'number') {
        final reading = num.tryParse(text.trim().replaceAll(',', '.'));
        if (reading == null || !reading.isFinite) {
          next = null;
        } else if ((item['min'] is num && reading < item['min']) ||
            (item['max'] is num && reading > item['max'])) {
          next = 'action';
        } else if (next != 'action') {
          next = 'pass';
        }
      } else if (item['input_type'] == 'text') {
        next = text.trim().isEmpty
            ? null
            : (next == 'action' ? 'action' : 'pass');
      }
    }
    setState(
      () => dirty['answer:${item['id']}'] = {'result': next, 'value': text},
    );
  }

  String conflictName(String key) {
    if (legacy) return checklist[key] ?? key;
    for (final item in inspectionItems(jobContext)) {
      if (key == 'answer:${item['id']}') return item['label'] as String;
    }
    return switch (key) {
      'meter' => 'Meter reading',
      'notes' => 'Inspection notes',
      'photo' => 'Inspection photo',
      _ => key,
    };
  }

  String conflictValue(String key, Object? value) {
    if (value is Map) {
      final item =
          inspectionItems(
            jobContext,
          ).where((s) => key == 'answer:${s['id']}').firstOrNull ??
          {};
      return answerSummary(value, item);
    }
    if (key == 'photo') {
      return value == null
          ? 'No photo'
          : 'Photo ${value.toString().substring(0, 12)}…';
    }
    return value?.toString() ?? 'Not recorded';
  }

  @override
  Widget build(BuildContext context) {
    final values = alternatives == null
        ? <String, dynamic>{}
        : valuesOf(alternatives!);
    final snapshot = jsonMap(jobContext['checklistSnapshot']);
    return PopScope(
      canPop: dirty.isEmpty && !busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && !busy) {
          final saved = await save();
          if (saved && mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) Navigator.pop(context);
            });
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Equipment inspection')),
        body: alternatives == null
            ? (message == null
                  ? const Center(child: CircularProgressIndicator())
                  : page([notice(message!, error: true)]))
            : page([
                Text(
                  equipmentName(jobContext['equipment']),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (!legacy) ...[
                  Text(
                    jobTitle(jobContext['job']),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${snapshot['title']} · checklist v${snapshot['version']}',
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  legacy
                      ? 'Complete both checks, record the meter, add notes and a photo. Saving work keeps it on this device; submit when it is ready for review.'
                      : 'Record what you inspect, add notes and a photo, then submit for office review. Needs action records a finding; approval of this inspection does not confirm a repair.',
                ),
                if (progress != null)
                  AnimatedBuilder(
                    animation: progress!,
                    builder: (_, child) {
                      final current = progress!.snapshot?.jobs[jobId];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: current == null
                            ? Text(
                                progress!.error ??
                                    'Reading current work status…',
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (dirty.isNotEmpty)
                                    const Text('Current draft: Unsaved changes')
                                  else
                                    DraftProgressView(
                                      progress: current,
                                      localDevice: store.device,
                                    ),
                                  ReturnedWorkView(
                                    progress: current,
                                    correctionSubmissionId:
                                        widget.correctionSubmissionId,
                                  ),
                                ],
                              ),
                      );
                    },
                  ),
                if (widget.sync != null)
                  const Text('Sending status for this phone (all inspections)'),
                if (widget.sync != null)
                  if (widget.updates != null)
                    ValueListenableBuilder<int>(
                      valueListenable: widget.updates!,
                      builder: (_, value, child) => dirty.isNotEmpty
                          ? notice('Changes are not saved yet.')
                          : phoneSaveNotice(widget.sync!),
                    )
                  else if (dirty.isNotEmpty)
                    notice('Changes are not saved yet.')
                  else
                    phoneSaveNotice(widget.sync!),
                if (message != null) notice(message!),
                if (dirty.isNotEmpty)
                  notice(
                    'Unsaved changes — Save work keeps your draft on this device. Leaving this inspection also saves your changes.',
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
                            Text('Resolve ${conflictName(key)}'),
                            for (final value in alternatives![key] as List)
                              OutlinedButton(
                                onPressed: busy
                                    ? null
                                    : () => save(
                                        resolution: MapEntry(key, value),
                                      ),
                                child: Text(
                                  'Use: ${conflictValue(key, value)}',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
                if (legacy)
                  for (final entry in checklist.entries)
                    legacyCheck(entry, values)
                else
                  for (final item in inspectionItems(jobContext))
                    stepCard(item, values),
                if (legacy || jobContext['meterRequired'] == true) ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('meter'),
                    controller: meter,
                    enabled: !busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText:
                          'Meter reading (${legacy ? 'hours' : meterUnitLabel(jobContext['meterUnit'])})',
                      helperText:
                          'Record the actual reading. Leave it blank if it is not known yet.',
                      helperMaxLines: 3,
                    ),
                    onChanged: (value) =>
                        setState(() => dirty['meter'] = value),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  const Text('This equipment has no meter reading to record.'),
                ],
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
                    helperText:
                        'Describe the inspection and anything needing action.',
                    helperMaxLines: 6,
                  ),
                  onChanged: (value) => setState(() => dirty['notes'] = value),
                ),
                if (values['photo'] is String)
                  evidenceImage(store, values['photo'] as String),
                if (!legacy || !store.office) ...[
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => photo(ImageSource.gallery),
                    icon: const Icon(Icons.image_outlined),
                    label: Text(
                      values['photo'] == null
                          ? 'Choose a saved photo'
                          : 'Replace inspection photo',
                    ),
                  ),
                  if (!store.office && (Platform.isAndroid || Platform.isIOS))
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
                  child: Text(busy ? 'Saving…' : 'Save work'),
                ),
                FilledButton(
                  onPressed: busy ? null : () => save(submit: true),
                  child: const Text('Submit for review'),
                ),
                if (!legacy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Local maintenance experiment · Saving and submission work offline. The office receives saved versions when both devices reconnect.',
                    ),
                  ),
              ]),
      ),
    );
  }

  Widget legacyCheck(MapEntry<String, String> entry, Json values) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(entry.value, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final option in ['pass', 'attention'])
                ChoiceChip(
                  label: Text(option == 'pass' ? 'Pass' : 'Needs attention'),
                  selected: (dirty[entry.key] ?? values[entry.key]) == option,
                  onSelected: busy
                      ? null
                      : (_) => setState(() => dirty[entry.key] = option),
                ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget stepCard(Json item, Json values) {
    final answer = answerFor(item, values);
    final id = item['id'] as String;
    final type = item['input_type'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              item['label'] as String,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(stepDefinition(item)),
            if (type == 'number' || type == 'text') ...[
              const SizedBox(height: 12),
              TextField(
                key: ValueKey('answer:$id'),
                controller: answers[id],
                enabled: !busy && answer['result'] != 'na',
                minLines: type == 'text' ? 2 : 1,
                maxLines: type == 'text' ? 5 : 1,
                maxLength: type == 'text' ? 4000 : 100,
                keyboardType: type == 'number'
                    ? const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      )
                    : TextInputType.multiline,
                decoration: InputDecoration(
                  labelText: type == 'number'
                      ? 'Reading${(item['unit'] ?? '').toString().isEmpty ? '' : ' (${item['unit']})'}'
                      : 'Response',
                ),
                onChanged: (text) =>
                    changeAnswer(item, values, value: text, typed: true),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in [
                  'pass',
                  'action',
                  if (item['allow_na'] == true) 'na',
                ])
                  ChoiceChip(
                    label: Text(resultLabel(option)),
                    selected: answer['result'] == option,
                    onSelected: busy
                        ? null
                        : (_) => changeAnswer(item, values, result: option),
                  ),
              ],
            ),
            if (answer['result'] == 'action')
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Finding recorded. Explain the action needed in the inspection notes.',
                ),
              ),
            if (item['required'] == false)
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        dirty['answer:$id'] = null;
                        answers[id]?.clear();
                      }),
                child: const Text('Leave optional step unanswered'),
              ),
          ],
        ),
      ),
    );
  }
}
