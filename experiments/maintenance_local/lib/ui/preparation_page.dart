import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../lab_store.dart';
import '../model.dart';
import 'common.dart';
import 'inspection_content.dart';
import 'procedure_library_page.dart';

enum PreparationStep { company, equipment, checklist, work }

class PreparationPage extends StatefulWidget {
  const PreparationPage({super.key, required this.store, required this.step});
  final LabStore store;
  final PreparationStep step;
  @override
  State<PreparationPage> createState() => _PreparationPageState();
}

class _PreparationPageState extends State<PreparationPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final detail = TextEditingController();
  final steps = <_StepDraft>[];
  final removedSteps = <_StepDraft>[];
  String meterUnit = 'hours';
  String? equipmentId, templateId, error;
  bool busy = false, changed = false, saved = false;

  @override
  void initState() {
    super.initState();
    if (widget.step == PreparationStep.company) {
      detail.text = 'Office coordinator';
    }
    if (widget.step == PreparationStep.checklist) steps.add(_StepDraft());
    if (widget.step == PreparationStep.work) {
      equipmentId = widget.store.equipment.firstOrNull?['id'] as String?;
      templateId = widget.store.templates.firstOrNull?['id'] as String?;
    }
  }

  @override
  void dispose() {
    name.dispose();
    detail.dispose();
    for (final step in [...steps, ...removedSteps]) {
      step.dispose();
    }
    super.dispose();
  }

  String get title => switch (widget.step) {
    PreparationStep.company => 'Create your company',
    PreparationStep.equipment => 'Add equipment',
    PreparationStep.checklist => 'Author a checklist',
    PreparationStep.work => 'Prepare an inspection',
  };

  void markChanged() => setState(() => changed = true);

  Future<void> leave() async {
    if (busy) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: const Text('Keep editing?'),
        content: const Text('This preparation has not been saved yet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Discard preparation'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() => changed = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      switch (widget.step) {
        case PreparationStep.company:
          await widget.store.createCompany(
            name.text.trim(),
            coordinatorName: detail.text.trim(),
          );
        case PreparationStep.equipment:
          await widget.store.addEquipment(
            name: name.text.trim(),
            serial: detail.text.trim(),
            meterUnit: meterUnit,
          );
        case PreparationStep.checklist:
          if (steps.isEmpty) {
            throw StateError('Add at least one checklist step.');
          }
          await widget.store.publishChecklist(
            title: name.text.trim(),
            items: steps.map((s) => s.value()).toList(),
            provenance: {'kind': 'company-authored', 'reference': ''},
          );
        case PreparationStep.work:
          if (equipmentId == null || templateId == null) {
            throw StateError('Select equipment and a published checklist.');
          }
          await widget.store.prepareWork(
            equipmentId: equipmentId!,
            templateId: templateId!,
            title: name.text.trim(),
          );
      }
      saved = true;
      changed = false;
      if (mounted) {
        setState(() => busy = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context, true);
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          busy = false;
          error = failure.toString().replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  String? requiredText(String? value) =>
      (value ?? '').trim().isEmpty ? 'Enter a name.' : null;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: saved || (!changed && !busy),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) leave();
    },
    child: Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Form(
        key: form,
        child: page([
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(switch (widget.step) {
            PreparationStep.company =>
              'One office coordinator prepares work and reviews inspection records. The paired mechanic phone keeps its work offline.',
            PreparationStep.equipment =>
              'Use the equipment name your mechanic recognises. Only choose a meter the equipment actually has.',
            PreparationStep.checklist =>
              'Write the checks and readings for your equipment. Published definitions are copied into each inspection, so later checklist changes cannot rewrite prepared work.',
            PreparationStep.work =>
              'Select the equipment and procedure for this inspection. The prepared work keeps this exact equipment and checklist version.',
          }),
          if (error != null) notice(error!, error: true),
          if (widget.store.office &&
              (widget.step == PreparationStep.checklist ||
                  widget.step == PreparationStep.work)) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('preparation-checklist-library'),
              onPressed: busy
                  ? null
                  : () async {
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ProcedureLibraryPage(store: widget.store),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
              icon: const Icon(Icons.library_books_outlined),
              label: const Text('Checklist library'),
            ),
          ],
          const SizedBox(height: 20),
          if (widget.step == PreparationStep.work) ...[
            DropdownButtonFormField<String>(
              key: const Key('prepare-equipment'),
              initialValue: equipmentId,
              isExpanded: true,
              itemHeight: null,
              decoration: const InputDecoration(labelText: 'Equipment'),
              items: widget.store.equipment
                  .map(
                    (e) => DropdownMenuItem(
                      value: e['id'] as String,
                      child: Text(equipmentName(e)),
                    ),
                  )
                  .toList(),
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      equipmentId = v;
                      changed = true;
                    }),
              validator: (v) =>
                  v == null ? 'Add and select equipment first.' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const Key('prepare-checklist'),
              initialValue: templateId,
              isExpanded: true,
              itemHeight: null,
              decoration: const InputDecoration(
                labelText: 'Published checklist',
              ),
              items: widget.store.templates
                  .map(
                    (t) => DropdownMenuItem(
                      value: t['id'] as String,
                      child: Text('${t['title']} · v${t['version']}'),
                    ),
                  )
                  .toList(),
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      templateId = v;
                      changed = true;
                    }),
              validator: (v) =>
                  v == null ? 'Publish and select a checklist first.' : null,
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            key: const Key('preparation-name'),
            controller: name,
            enabled: !busy,
            maxLength: 160,
            decoration: InputDecoration(
              labelText: switch (widget.step) {
                PreparationStep.company => 'Company name',
                PreparationStep.equipment => 'Equipment name',
                PreparationStep.checklist => 'Checklist title',
                PreparationStep.work => 'Inspection title',
              },
            ),
            validator: requiredText,
            onChanged: (_) => markChanged(),
          ),
          if (widget.step == PreparationStep.company ||
              widget.step == PreparationStep.equipment) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: detail,
              enabled: !busy,
              maxLength: 160,
              decoration: InputDecoration(
                labelText: widget.step == PreparationStep.company
                    ? 'Coordinator name'
                    : 'Serial or equipment ID (optional)',
              ),
              validator: widget.step == PreparationStep.company
                  ? requiredText
                  : null,
              onChanged: (_) => markChanged(),
            ),
          ],
          if (widget.step == PreparationStep.equipment) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: meterUnit,
              decoration: const InputDecoration(labelText: 'Equipment meter'),
              items: const [
                DropdownMenuItem(
                  value: 'hours',
                  child: Text('Operating hours'),
                ),
                DropdownMenuItem(value: 'km', child: Text('Kilometres')),
                DropdownMenuItem(value: 'mi', child: Text('Miles')),
                DropdownMenuItem(value: 'none', child: Text('No meter')),
              ],
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      meterUnit = v!;
                      changed = true;
                    }),
            ),
          ],
          if (widget.step == PreparationStep.checklist) ...[
            for (var i = 0; i < steps.length; i++) stepEditor(steps[i], i),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      steps.add(_StepDraft());
                      changed = true;
                    }),
              icon: const Icon(Icons.add),
              label: const Text('Add step'),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(
              busy
                  ? 'Saving…'
                  : switch (widget.step) {
                      PreparationStep.company => 'Create company',
                      PreparationStep.equipment => 'Save equipment',
                      PreparationStep.checklist => 'Publish checklist',
                      PreparationStep.work => 'Prepare inspection',
                    },
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Local maintenance experiment · Inspection approval records what was inspected. Repairs and equipment availability are separate decisions.',
          ),
        ]),
      ),
    ),
  );

  Widget stepEditor(_StepDraft step, int index) => Card(
    key: ValueKey(step.id),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Step ${index + 1}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Remove step ${index + 1}',
                onPressed: busy
                    ? null
                    : () => setState(() {
                        steps.remove(step);
                        removedSteps.add(step);
                        changed = true;
                      }),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          TextFormField(
            controller: step.label,
            enabled: !busy,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'What should the mechanic inspect?',
            ),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Describe this step.' : null,
            onChanged: (_) => markChanged(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: step.type,
            decoration: const InputDecoration(labelText: 'Response'),
            items: const [
              DropdownMenuItem(value: 'check', child: Text('Check result')),
              DropdownMenuItem(value: 'number', child: Text('Numeric reading')),
              DropdownMenuItem(value: 'text', child: Text('Written response')),
            ],
            onChanged: busy
                ? null
                : (v) => setState(() {
                    step.type = v!;
                    changed = true;
                  }),
          ),
          if (step.type == 'number') ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: step.unit,
              enabled: !busy,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: 'Reading unit (for example psi or °C)',
              ),
              onChanged: (_) => markChanged(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: step.min,
              enabled: !busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Expected minimum (optional)',
              ),
              validator: _StepDraft.validNumber,
              onChanged: (_) => markChanged(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: step.max,
              enabled: !busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Expected maximum (optional)',
              ),
              validator: (v) {
                final problem = _StepDraft.validNumber(v);
                if (problem != null) return problem;
                final min = _StepDraft.number(step.min.text),
                    max = _StepDraft.number(v ?? '');
                return min != null && max != null && min > max
                    ? 'Maximum must be at least the minimum.'
                    : null;
              },
              onChanged: (_) => markChanged(),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Required response'),
            value: step.required,
            onChanged: busy
                ? null
                : (v) => setState(() {
                    step.required = v;
                    changed = true;
                  }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow not applicable'),
            value: step.allowNa,
            onChanged: busy
                ? null
                : (v) => setState(() {
                    step.allowNa = v;
                    changed = true;
                  }),
          ),
        ],
      ),
    ),
  );
}

class _StepDraft {
  final id = const Uuid().v4();
  final label = TextEditingController(), unit = TextEditingController();
  final min = TextEditingController(), max = TextEditingController();
  String type = 'check';
  bool required = true, allowNa = false;
  static num? number(String value) =>
      num.tryParse(value.trim().replaceAll(',', '.'));
  static String? validNumber(String? value) {
    if ((value ?? '').trim().isEmpty) return null;
    final parsed = number(value!);
    return parsed == null || !parsed.isFinite ? 'Enter a valid number.' : null;
  }

  Json value() => {
    'id': id,
    'label': label.text.trim(),
    'input_type': type,
    'required': required,
    'allow_na': allowNa,
    if (type == 'number') 'unit': unit.text.trim(),
    if (type == 'number' && min.text.trim().isNotEmpty) 'min': number(min.text),
    if (type == 'number' && max.text.trim().isNotEmpty) 'max': number(max.text),
  };
  void dispose() {
    label.dispose();
    unit.dispose();
    min.dispose();
    max.dispose();
  }
}
