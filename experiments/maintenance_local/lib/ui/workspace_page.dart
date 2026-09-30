import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../lab_store.dart';
import '../local_sync.dart';
import '../model.dart';
import '../qr_scanner.dart';
import 'common.dart';
import 'inspection_page.dart';
import 'review_page.dart';
import 'devices_page.dart';
import 'backup_page.dart';
import 'restore_page.dart';
import 'preparation_page.dart';
import 'inspection_content.dart';

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({
    super.key,
    required this.store,
    this.onRestored,
    this.officePort = 47841,
  });
  final LabStore store;
  final ValueChanged<LabStore>? onRestored;
  final int officePort;
  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage>
    with WidgetsBindingObserver {
  LabStore get store => widget.store;
  OfficeServer? server;
  PhoneSync? sync;
  Timer? timer;
  final reviewUpdates = ValueNotifier<int>(0);
  bool active = true, working = false;
  String? error;
  @override
  void initState() {
    super.initState();
    error = store.setting('photoRecoveryError') as String?;
    WidgetsBinding.instance.addObserver(this);
    start();
  }

  Future<void> start() async {
    if (store.office) {
      try {
        server = await OfficeServer.start(store, port: widget.officePort);
        server!.onChange = refresh;
      } catch (e) {
        error = 'Local connections are unavailable: $e';
      }
    } else {
      sync = PhoneSync(store)..onChange = refresh;
    }
    timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (active) {
        sync?.sync().catchError((Object e) {});
        refresh();
      }
    });
    refresh();
  }

  void refresh() {
    if (mounted) {
      reviewUpdates.value++;
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active) refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    server?.onChange = null;
    sync?.onChange = null;
    server?.close();
    reviewUpdates.dispose();
    super.dispose();
  }

  Future<void> act(Future<void> Function() fn) async {
    setState(() {
      working = true;
      error = null;
    });
    try {
      await fn();
    } catch (e) {
      error = connectionProblem(e);
    }
    if (mounted) setState(() => working = false);
  }

  Future<void> pair({bool scan = false}) async {
    String? value;
    if (scan) {
      value = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const InvitationScanner()),
      );
    } else {
      value = await askText(
        context,
        'Paste computer invitation',
        'Invitation',
        multiline: true,
      );
    }
    if (value != null && value.trim().isNotEmpty) {
      await act(() => sync!.enroll(value!));
    }
  }

  Future<void> restoreOffice() async {
    if (store.catalog != null ||
        store.workspace != null ||
        widget.onRestored == null) {
      return;
    }
    setState(() => working = true);
    LabStore? next;
    try {
      final target = await Navigator.push<Directory>(
        context,
        MaterialPageRoute(builder: (_) => const RestorePage()),
      );
      if (target == null || !mounted) return;
      next = await LabStore.open(target, office: true);
      final fingerprint = (await OfficeIdentity.load(next)).fingerprint;
      timer?.cancel();
      server?.onChange = null;
      await server?.close();
      server = null;
      store.setSetting('officeRestoredTo', {
        'path': target.absolute.path,
        'device': next.device,
        'fingerprint': fingerprint,
      });
      widget.onRestored!(next);
      next = null;
      await store.close();
    } catch (failure) {
      await next?.close();
      if (mounted) setState(() => error = connectionProblem(failure));
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (store.catalog != null) return realWorkspace();
    final workspace = store.workspace;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vortice · Local Maintenance'),
        actions: [
          IconButton(
            tooltip: 'About local maintenance',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'Vortice Local Maintenance',
              applicationVersion: '0.1.2 · internal experiment',
              children: [
                const Text(
                  'A separate local maintenance experiment for one office coordinator and one mechanic phone. Equipment, authored checklists and inspection records stay on your devices.',
                ),
              ],
            ),
          ),
        ],
      ),
      body: page([
        Text(
          store.office ? 'OFFICE COMPUTER' : 'INSPECTION PHONE',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Local maintenance experiment · Your normal Vortice app is separate.',
        ),
        if (error != null) notice(error!, error: true),
        if (workspace == null) ...[
          const SizedBox(height: 24),
          Text(
            store.office
                ? 'Start with your company'
                : 'Connect to your computer',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          Text(
            store.office
                ? 'Create your company, add equipment and author a checklist. Prepare an inspection for the mechanic, then review its submitted record here.'
                : 'On the office computer, choose Connect or replace a phone. Copy its invitation, bring the text to this phone and paste it below. Keep both apps open on the same Wi-Fi, then compare the confirmation code.',
          ),
          const SizedBox(height: 20),
          if (store.office) ...[
            FilledButton(
              onPressed: working
                  ? null
                  : () => prepare(PreparationStep.company),
              child: const Text('Create company'),
            ),
            if (widget.onRestored != null)
              OutlinedButton(
                onPressed: working ? null : restoreOffice,
                child: const Text('Restore office backup'),
              ),
          ] else ...[
            FilledButton(
              onPressed: working ? null : pair,
              child: const Text('Paste invitation'),
            ),
            OutlinedButton(
              onPressed: working ? null : () => pair(scan: true),
              child: const Text('Scan invitation'),
            ),
            if (sync?.pairing != null) notice(sync!.message),
            if (sync?.pairing != null)
              OutlinedButton(
                onPressed: sync!.busy ? null : () => act(sync!.sync),
                child: const Text('Check confirmation'),
              ),
          ],
        ] else ...[
          const SizedBox(height: 20),
          Text(
            workspace['company'] as String,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (!store.office) ...[
            notice(sync?.message ?? 'Saved on this phone.'),
            OutlinedButton.icon(
              onPressed: sync == null || sync!.busy
                  ? null
                  : () => act(sync!.sync),
              icon: const Icon(Icons.sync),
              label: const Text('Sync now'),
            ),
            const Text(
              'Automatic sending runs while both apps are open. Only work saved on the computer can be restored to a replacement phone.',
            ),
            TextButton(
              onPressed: sync == null || sync!.busy ? null : pair,
              child: const Text('Update computer connection'),
            ),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    workspace['equipment'] as String,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(workspace['job'] as String),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => InspectionPage(store: store),
                        ),
                      );
                      refresh();
                    },
                    child: Text(
                      store.office ? 'Open inspection' : 'Continue inspection',
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (store.office)
            OutlinedButton.icon(
              onPressed: server == null
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DevicesPage(server: server!),
                      ),
                    ),
              icon: const Icon(Icons.devices),
              label: const Text('Connect or replace a phone'),
            ),
          if (store.office) ...[
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => BackupPage(store: store)),
              ),
              icon: const Icon(Icons.backup_outlined),
              label: const Text('Back up office computer'),
            ),
            if (store.setting('officeRestore') != null)
              notice(
                'Office backup restored. Create a new invitation for each retained phone, compare its code and confirm it again under Connect or replace a phone. Revoked phones remain blocked. Work saved after the backup is not included.',
              ),
          ],
          const SizedBox(height: 16),
          Text(
            store.office ? 'Review submitted work' : 'Submitted versions',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (store.submissions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No submitted work yet. Complete the inspection, attach a photo and submit it.',
              ),
            ),
          for (final p in store.submissions.reversed) submissionCard(p),
          if (store.receipts.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Reviewed versions stay in history when the inspection changes.',
              ),
            ),
        ],
      ]),
    );
  }

  Future<void> prepare(PreparationStep step) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreparationPage(store: store, step: step),
      ),
    );
    refresh();
  }

  Future<void> openJob(String id) async {
    store.selectJob(id);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InspectionPage(store: store, jobId: id),
      ),
    );
    refresh();
  }

  Widget realWorkspace() {
    final catalog = store.catalog!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vortice · Local Maintenance'),
        actions: [
          IconButton(
            tooltip: 'About local maintenance',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'Vortice Local Maintenance',
              applicationVersion: '0.1.2 · internal experiment',
              children: const [
                Text(
                  'A separate local maintenance experiment for one office coordinator and one mechanic phone. Equipment, authored checklists and inspection records stay on your devices. Your normal Vortice app is separate.',
                ),
              ],
            ),
          ),
        ],
      ),
      body: page([
        Text(
          store.office ? 'OFFICE COMPUTER' : 'INSPECTION PHONE',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Local maintenance experiment · Your normal Vortice app is separate.',
        ),
        if (error != null) notice(error!, error: true),
        const SizedBox(height: 20),
        Text(
          catalog['company'] as String,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text('Coordinator: ${catalog['coordinatorName']}'),
        if (!store.office) ...[
          notice(sync?.message ?? 'Saved on this phone.'),
          OutlinedButton.icon(
            onPressed: sync == null || sync!.busy
                ? null
                : () => act(sync!.sync),
            icon: const Icon(Icons.sync),
            label: const Text('Sync now'),
          ),
          const Text(
            'Automatic sending runs while both apps are open. Only work saved on the computer can be restored to a replacement phone.',
          ),
          TextButton(
            onPressed: sync == null || sync!.busy ? null : pair,
            child: const Text('Update computer connection'),
          ),
        ],
        const SizedBox(height: 20),
        Text('Inspections', style: Theme.of(context).textTheme.titleLarge),
        if (store.jobs.isEmpty)
          notice(
            store.office
                ? (store.equipment.isEmpty
                      ? 'Add your first equipment, then author its checklist and prepare an inspection.'
                      : store.templates.isEmpty
                      ? 'Author and publish a checklist, then prepare an inspection for your equipment.'
                      : 'Your equipment and checklist are ready. Prepare an inspection to start work.')
                : 'No inspections have been prepared yet. The office coordinator prepares work and sends it when both devices connect.',
          ),
        if (store.office &&
            store.equipment.isNotEmpty &&
            store.templates.isNotEmpty)
          FilledButton.icon(
            onPressed: working ? null : () => prepare(PreparationStep.work),
            icon: const Icon(Icons.playlist_add),
            label: const Text('Prepare inspection'),
          ),
        for (final job in store.jobs) jobCard(job),
        if (store.office) ...[
          const SizedBox(height: 20),
          Text('Equipment', style: Theme.of(context).textTheme.titleLarge),
          OutlinedButton.icon(
            onPressed: working
                ? null
                : () => prepare(PreparationStep.equipment),
            icon: const Icon(Icons.add),
            label: const Text('Add equipment'),
          ),
          for (final equipment in store.equipment)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      equipmentName(equipment),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if ((equipment['serial'] ?? '').toString().isNotEmpty)
                      Text('Equipment ID: ${equipment['serial']}'),
                    Text('Meter: ${meterUnitLabel(equipment['meterUnit'])}'),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          Text('Checklists', style: Theme.of(context).textTheme.titleLarge),
          OutlinedButton.icon(
            onPressed: working
                ? null
                : () => prepare(PreparationStep.checklist),
            icon: const Icon(Icons.edit_note),
            label: const Text('Author checklist'),
          ),
          for (final template in store.templates)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      template['title'] as String,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Published v${template['version']} · ${(template['items'] as List).length} steps · Company-authored',
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: server == null
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DevicesPage(server: server!),
                    ),
                  ),
            icon: const Icon(Icons.devices),
            label: const Text('Connect or replace a phone'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => BackupPage(store: store)),
            ),
            icon: const Icon(Icons.backup_outlined),
            label: const Text('Back up office computer'),
          ),
          if (store.setting('officeRestore') != null)
            notice(
              'Office backup restored. Create a new invitation for each retained phone, compare its code and confirm it again under Connect or replace a phone. Revoked phones remain blocked. Work saved after the backup is not included.',
            ),
        ],
        const SizedBox(height: 24),
        Text(
          store.office ? 'Review submitted work' : 'Submitted versions',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (store.submissions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No submitted work yet. Open an inspection, record its checks and readings, add notes and a photo, then submit for review.',
            ),
          ),
        for (final submission in store.submissions.reversed)
          submissionCard(submission),
        if (store.receipts.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Reviewed versions stay in history when an inspection changes.',
            ),
          ),
        const Padding(
          padding: EdgeInsets.only(top: 20),
          child: Text(
            'An approved inspection records what was inspected. Repairs, equipment availability and recurring maintenance are separate decisions.',
          ),
        ),
      ]),
    );
  }

  Widget jobCard(Json job) {
    final id = (job['id'] ?? job['jobId']) as String;
    final jobContext = store.jobContextFor(id);
    final latest = store.submissions.where((p) => p['jobId'] == id).lastOrNull;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              equipmentName(jobContext['equipment']),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(jobTitle(jobContext['job'])),
            const SizedBox(height: 8),
            Text(
              latest == null
                  ? 'Prepared · Ready to inspect'
                  : submissionStatus(latest),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => openJob(id),
              child: Text(
                store.office ? 'Open inspection' : 'Continue inspection',
              ),
            ),
          ],
        ),
      ),
    );
  }

  String submissionStatus(Json p) {
    final receipt = store.receipts
        .where((r) => r['submissionId'] == p['id'])
        .firstOrNull;
    return receipt == null
        ? (p['_state'] == 'queued' ? 'Waiting to send' : 'Awaiting review')
        : receipt['decision'] == 'approved'
        ? (p['context'] == null ? 'Approved' : 'Approved inspection')
        : 'Returned — ${receipt['reason']}';
  }

  Widget submissionCard(Json p) {
    final submittedContext = jsonMap(p['context']);
    final values = jsonMap(p['values']);
    return Card(
      child: ListTile(
        title: Text(submissionStatus(p)),
        subtitle: Text(
          [
            if (submittedContext.isNotEmpty)
              '${equipmentName(submittedContext['equipment'])} · ${jobTitle(submittedContext['job'])}',
            'Submitted ${displayTime(p['createdAt'] as String)}',
            if (submittedContext.isEmpty ||
                submittedContext['meterRequired'] == true)
              'Meter: ${values['meter']} ${submittedContext.isEmpty ? 'hours' : meterUnitLabel(submittedContext['meterUnit'])}',
            if (submittedContext.isNotEmpty)
              'Version ${p['submissionRevision'] ?? 1}',
          ].join('\n'),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReviewPage(
                store: store,
                submission: p,
                updates: reviewUpdates,
              ),
            ),
          );
          refresh();
        },
      ),
    );
  }
}
