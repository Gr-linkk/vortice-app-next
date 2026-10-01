import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../agent_service/agent_host.dart';
import '../agent_service/access_scope.dart';
import '../agent_service/proposal_review.dart';
import '../lab_store.dart';
import '../local_sync.dart';
import '../model.dart';
import '../job_progress.dart';
import '../work_progress_reader.dart';
import '../qr_scanner.dart';
import 'common.dart';
import 'inspection_page.dart';
import 'review_page.dart';
import 'devices_page.dart';
import 'backup_page.dart';
import 'restore_page.dart';
import 'preparation_page.dart';
import 'inspection_content.dart';
import 'work_progress.dart';
import 'agent_connections_page.dart';
import 'agent_proposals_page.dart';
import 'manual_fault_intake_page.dart';
import 'corrective_planning_page.dart';

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({
    super.key,
    required this.store,
    this.onRestored,
    this.officePort = 47841,
    this.phoneSyncFactory = PhoneSync.new,
    this.progressReader,
    this.progressTokenReader,
    this.agentHost,
  });
  final LabStore store;
  final ValueChanged<LabStore>? onRestored;
  final int officePort;
  final PhoneSync Function(LabStore) phoneSyncFactory;
  final ProgressReader? progressReader;
  final ProgressTokenReader? progressTokenReader;
  final OfficeAgentHost? agentHost;
  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage>
    with WidgetsBindingObserver {
  LabStore get store => widget.store;
  OfficeServer? server;
  PhoneSync? sync;
  Timer? timer;
  OfficeAgentHost? agentHost;
  Future<void>? starting;
  bool ending = false;
  final reviewUpdates = ValueNotifier<int>(0);
  late final WorkProgressController progress;
  bool active = true, working = false;
  String? error;
  ConnectionGuidance? guidance;
  bool responseClearsGuidance = false;
  int guidanceResponse = 0;
  @override
  void initState() {
    super.initState();
    if (store.office) {
      if (widget.agentHost != null && widget.agentHost!.store != store) {
        throw ArgumentError(
          'Agent connections must use this office workspace.',
        );
      }
      agentHost = widget.agentHost ?? OfficeAgentHost(store: store);
    }
    progress = WorkProgressController(
      store,
      reader: widget.progressReader ?? readWorkProgress,
      tokenReader: widget.progressTokenReader ?? workProgressToken,
    )..addListener(progressChanged);
    active =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    starting = start();
  }

  Future<void> start() async {
    if (store.office) {
      await agentHost?.initialize();
      if (ending || !mounted) return;
      try {
        final nextServer = await OfficeServer.start(
          store,
          port: widget.officePort,
        );
        if (ending || !mounted) {
          await nextServer.close();
          return;
        }
        server = nextServer;
        server!.onChange = refresh;
      } catch (e) {
        if (e is SocketException) {
          guidance = const ConnectionGuidance(
            'Phone connections are unavailable on this computer.',
            'Close any other local maintenance window, then reopen this app.',
            details:
                'If it still fails, ask whoever manages this computer to check local app connections on port 47841. Your saved work stays on this computer.',
          );
        } else {
          error = connectionProblem(e);
        }
      }
    } else {
      sync = widget.phoneSyncFactory(store)..onChange = refreshAfterSync;
    }
    if (ending || !mounted) return;
    timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (active && !working) {
        sync?.sync().catchError((Object e) {});
        refresh();
      }
    });
    refresh();
  }

  void refreshAfterSync() {
    final current = sync;
    if (responseClearsGuidance &&
        current != null &&
        current.connectionResponses > guidanceResponse) {
      // A new response resolves only this action's connection guidance. Persisted
      // photo recovery and unrelated application failures remain independent.
      guidance = null;
      responseClearsGuidance = false;
    }
    refresh();
  }

  List<Widget> errorNotices() => [
    if (store.setting('photoRecoveryError') case final String photoError)
      notice(photoError, error: true),
    if (error != null) notice(error!, error: true),
    if (guidance != null) connectionNotice(guidance!),
  ];

  void refresh() {
    if (mounted) {
      reviewUpdates.value++;
      setState(() {});
      if (store.realWorkspace) unawaited(progress.refresh());
    }
  }

  void progressChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active) refreshAfterSync();
  }

  @override
  void dispose() {
    ending = true;
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    server?.onChange = null;
    sync?.onChange = null;
    server?.close();
    if (widget.agentHost == null) {
      final owned = agentHost;
      if (owned != null) unawaited(owned.close());
    }
    reviewUpdates.dispose();
    progress.dispose();
    super.dispose();
  }

  Future<void> act(Future<void> Function() fn, {bool showError = true}) async {
    if (!mounted || working) return;
    setState(() {
      working = true;
    });
    try {
      await fn();
    } catch (e) {
      if (showError) {
        final help = connectionGuidance(e);
        if (help != null) {
          guidance = help;
          responseClearsGuidance = true;
          guidanceResponse = sync?.connectionResponses ?? 0;
        } else {
          error = connectionProblem(e);
        }
      }
    }
    if (mounted) setState(() => working = false);
  }

  Future<void> pair({bool scan = false}) async {
    if (working || sync == null || sync!.busy) return;
    // Fence the whole manual action, including the time spent entering an
    // invitation. The automatic timer must not start an exchange behind it.
    await act(() async {
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
          instructions: phoneInvitationInstructions,
        );
      }
      if (mounted && value != null && value.trim().isNotEmpty) {
        await sync!.enroll(value);
      }
    });
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
      next = await LabStore.open(target, office: true, maintenanceOnly: true);
      final fingerprint = (await OfficeIdentity.load(next)).fingerprint;
      ending = true;
      timer?.cancel();
      // Fence and drain agent commands before the previous SQLite workspace
      // closes. Restored access sidecars are absent and the new host starts off.
      await agentHost?.close();
      // Startup may still be awaiting native identity/listener work. Its ending
      // fence closes any late listener before the old SQLite store is closed.
      await starting;
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
      if (mounted) {
        setState(() {
          final help = connectionGuidance(failure);
          if (help != null) {
            guidance = help;
            responseClearsGuidance = false;
          } else {
            error = connectionProblem(failure);
          }
        });
      }
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
              applicationVersion: '0.2.10 · internal experiment',
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
        ...errorNotices(),
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
            if (sync?.pairing != null) phoneSaveNotice(sync!),
            if (sync?.pairing != null)
              OutlinedButton(
                onPressed: working || sync!.busy
                    ? null
                    : () => act(sync!.sync, showError: false),
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
            if (sync != null)
              phoneSaveNotice(sync!)
            else
              notice('Saved on this phone.'),
            OutlinedButton.icon(
              onPressed: working || sync == null || sync!.busy
                  ? null
                  : () => act(sync!.sync, showError: false),
              icon: const Icon(Icons.sync),
              label: const Text('Sync now'),
            ),
            const Text(
              'Automatic sending runs while both apps are open. Only work saved on the computer can be restored to a replacement phone.',
            ),
            TextButton(
              onPressed: working || sync == null || sync!.busy ? null : pair,
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
                          builder: (_) => InspectionPage(
                            store: store,
                            sync: sync,
                            updates: reviewUpdates,
                          ),
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
    await agentHost?.initialize();
    refresh();
  }

  Future<void> openAgentConnections() async {
    final host = agentHost;
    if (!store.office || !store.realWorkspace || host == null || working) {
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => AgentConnectionsPage(host: host)),
    );
    refresh();
  }

  Future<void> openAgentSuggestions() async {
    final scope = AgentAccessScope.forOffice(store);
    if (scope == null || working) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AgentProposalsPage(
          reviewer: AgentProposalReviewer(
            store: store,
            workspaceId: scope.workspaceId,
            serviceDeviceId: store.device,
          ),
        ),
      ),
    );
    refresh();
  }

  Future<void> openJob(String id, {String? correctionSubmissionId}) async {
    store.selectJob(id);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InspectionPage(
          store: store,
          jobId: id,
          sync: sync,
          updates: reviewUpdates,
          progressController: progress,
          correctionSubmissionId: correctionSubmissionId,
        ),
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
              applicationVersion: '0.2.10 · internal experiment',
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
        ...errorNotices(),
        const SizedBox(height: 20),
        Text(
          catalog['company'] as String,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text('Coordinator: ${catalog['coordinatorName']}'),
        if (!store.office) ...[
          if (sync != null)
            phoneSaveNotice(sync!)
          else
            notice('Saved on this phone.'),
          OutlinedButton.icon(
            onPressed: working || sync == null || sync!.busy
                ? null
                : () => act(sync!.sync, showError: false),
            icon: const Icon(Icons.sync),
            label: const Text('Sync now'),
          ),
          const Text(
            'Automatic sending runs while both apps are open. Only work saved on the computer can be restored to a replacement phone.',
          ),
          TextButton(
            onPressed: working || sync == null || sync!.busy ? null : pair,
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
        if (store.jobs.isNotEmpty)
          Text(
            progress.loading ? 'Updating work status…' : 'Saved work status',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        // Keep the last captured layout while its replacement is read. Editors
        // still use the fresh snapshot; these displayed records cannot be
        // opened by pointer or keyboard until the read finishes.
        AbsorbPointer(
          absorbing: progress.loading,
          child: ExcludeFocus(
            excluding: progress.loading,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final job in store.jobs) jobCard(job),
                if (progress.error != null)
                  notice(progress.error!, error: true),
                if (store.office) ...reviewSections(),
              ],
            ),
          ),
        ),
        if (store.office) ...[
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: working
                ? null
                : () async {
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ManualFaultIntakePage(store: store),
                      ),
                    );
                    if (mounted) refresh();
                  },
            icon: const Icon(Icons.report_problem_outlined),
            label: const Text('Reported faults'),
          ),
          OutlinedButton.icon(
            key: const Key('office-corrective-planning'),
            onPressed: working
                ? null
                : () async {
                    if (working || !mounted) return;
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CorrectivePlanningPage(store: store),
                      ),
                    );
                    if (mounted) refresh();
                  },
            icon: const Icon(Icons.build_outlined),
            label: const Text('Corrective planning'),
          ),
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
            onPressed: working ? null : openAgentConnections,
            icon: const Icon(Icons.terminal),
            label: const Text('Agent connections'),
          ),
          OutlinedButton.icon(
            onPressed: working ? null : openAgentSuggestions,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Agent suggestions'),
          ),
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
        if (!store.office) ...reviewSections(),
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
    final currentProgress = progress.displaySnapshot?.jobs[id];
    return Card(
      key: ValueKey('inspection:$id'),
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
            if (currentProgress != null)
              DraftProgressView(
                progress: currentProgress,
                localDevice: store.device,
              )
            else
              const Text('Reading current work status…'),
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

  List<Widget> reviewSections() {
    final snapshot = progress.displaySnapshot;
    return [
      const SizedBox(height: 24),
      Text(
        store.office
            ? 'Awaiting review (${snapshot?.undecided.length ?? '…'})'
            : 'Submitted versions',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      if (snapshot == null)
        const Text('Reading submitted versions…')
      else ...[
        if (snapshot.undecided.isEmpty)
          Text(
            store.office
                ? 'No submitted versions are awaiting a decision.'
                : 'No versions are waiting to send or be reviewed.',
          ),
        for (final version in snapshot.undecided.reversed)
          submissionCard(version.submission, version: version),
        const SizedBox(height: 20),
        Text(
          'Reviewed history (${snapshot.reviewed.length})',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'Each decision belongs to its exact submitted record. Device version numbers belong to separate device histories.',
        ),
        if (snapshot.reviewed.isEmpty) const Text('No reviewed versions yet.'),
        for (final version in snapshot.reviewed.reversed)
          submissionCard(version.submission, version: version),
      ],
    ];
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

  Widget submissionCard(Json p, {SubmittedVersion? version}) {
    final submittedContext = jsonMap(p['context']);
    final values = jsonMap(p['values']);
    return Card(
      key: ValueKey('submitted-version:${p['id']}'),
      child: ListTile(
        title: Text(
          version == null ? submissionStatus(p) : versionStatus(version),
        ),
        subtitle: Text(
          [
            if (submittedContext.isNotEmpty)
              '${equipmentName(submittedContext['equipment'])} · ${jobTitle(submittedContext['job'])}',
            'Submitted ${displayTime(p['createdAt'] as String)}',
            if (submittedContext.isEmpty ||
                submittedContext['meterRequired'] == true)
              'Meter: ${values['meter']} ${submittedContext.isEmpty ? 'hours' : meterUnitLabel(submittedContext['meterUnit'])}',
            if (submittedContext.isNotEmpty)
              'Device version ${p['submissionRevision'] ?? 1}',
            if (version != null &&
                version.decision == null &&
                version.photoState != PhotoState.complete)
              photoStateLabel(version.photoState),
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
                onOpenCurrentInspection: store.realWorkspace
                    ? () => openJob(
                        p['jobId'] as String,
                        correctionSubmissionId: p['id'] as String,
                      )
                    : null,
              ),
            ),
          );
          refresh();
        },
      ),
    );
  }
}
