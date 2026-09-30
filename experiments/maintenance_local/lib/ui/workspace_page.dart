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
    if (store.workspace != null || widget.onRestored == null) return;
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
    final workspace = store.workspace;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vortice · Local Maintenance'),
        actions: [
          IconButton(
            tooltip: 'About Sync Lab',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'Vortice Local Maintenance',
              applicationVersion: '0.1.2 · internal experiment',
              children: [
                const Text(
                  'Synthetic workspace for two trusted devices. Public release and project license selection are separate work.',
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
          'Synthetic test workspace · Your normal Vortice app is separate.',
        ),
        if (error != null) notice(error!, error: true),
        if (workspace == null) ...[
          const SizedBox(height: 24),
          Text(
            store.office ? 'Start one inspection' : 'Connect to your computer',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          Text(
            store.office
                ? 'Create a demo company, generator and fixed inspection checklist. Everything stays on your devices.'
                : 'Open Sync Lab on the computer and choose Connect or replace a phone. Copy its invitation, bring the text to this phone and paste it below. Keep both apps open on the same Wi-Fi, then compare the confirmation code.',
          ),
          const SizedBox(height: 20),
          if (store.office) ...[
            FilledButton(
              onPressed: working ? null : () => act(store.createWorkspace),
              child: const Text('Create demo workspace'),
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

  Widget submissionCard(Json p) {
    final receipt = store.receipts
        .where((r) => r['submissionId'] == p['id'])
        .firstOrNull;
    final status = receipt == null
        ? (p['_state'] == 'queued' ? 'Waiting to send' : 'Awaiting review')
        : receipt['decision'] == 'approved'
        ? 'Approved'
        : 'Returned — ${receipt['reason']}';
    return Card(
      child: ListTile(
        isThreeLine: true,
        title: Text(status),
        subtitle: Text(
          'Submitted ${displayTime(p['createdAt'] as String)}\nMeter: ${(p['values'] as Json)['meter']} hours',
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
