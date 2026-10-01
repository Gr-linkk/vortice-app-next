import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../agent_service/access_models.dart';
import '../agent_service/agent_host.dart';
import '../lab_store.dart';
import '../model.dart';
import 'common.dart';

/// Office-only controls. Opening this page never enables access or issues a grant.
class AgentConnectionsPage extends StatefulWidget {
  const AgentConnectionsPage({super.key, required this.host});

  final OfficeAgentHost host;

  @override
  State<AgentConnectionsPage> createState() => _AgentConnectionsPageState();
}

class _AgentConnectionsPageState extends State<AgentConnectionsPage> {
  StreamSubscription<void>? _changes;
  Timer? _expiryTimer;
  bool _busy = false;
  String? _message;
  bool _messageError = false;

  bool get _office => widget.host.store.office && widget.host.scope != null;

  @override
  void initState() {
    super.initState();
    _listen();
    // Expiry is independent of listener changes. This timer only redraws labels.
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _listen() {
    _changes = widget.host.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(AgentConnectionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.host != widget.host) {
      _changes?.cancel();
      _message = null;
      _listen();
    }
  }

  @override
  void dispose() {
    _changes?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }

  Future<void> _act(Future<void> Function() action, String failure) async {
    if (_busy || !_office) return;
    setState(() {
      _busy = true;
      _message = null;
      _messageError = false;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = failure;
          _messageError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    if (_busy || !_office || !_listening(widget.host)) return;
    final issued = await Navigator.push<IssuedAgentGrant>(
      context,
      MaterialPageRoute(builder: (_) => _ConnectionEditor(host: widget.host)),
    );
    if (!mounted || issued == null) return;
    // This is the only UI containing the credential. Lists retain summaries only.
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CredentialResult(issued: issued),
    );
  }

  Future<void> _copySettings() async {
    final host = widget.host;
    final path = host.snapshot.socketPath;
    final scope = host.scope;
    if (!_office || !_listening(host) || path == null || scope == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: _settings(host)));
      if (!mounted) return;
      setState(() {
        final current = _listening(host) && host.snapshot.socketPath == path;
        _messageError = !current;
        _message = current
            ? 'Current connection settings copied. Supply the private credential separately through VORTICE_LOCAL_AGENT_TOKEN.'
            : 'The connection settings changed. Copy the current settings again when the office service is listening.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _message =
              'Could not copy settings. Select and copy the current settings below.';
          _messageError = true;
        });
      }
    }
  }

  Future<void> _revoke(OfficeAgentGrantSummary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Revoke connection?'),
        content: Text(
          '${summary.label} will lose access immediately. Notes suggestions already saved remain pending for office review.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-revoke-agent'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke connection'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _act(
        () => widget.host.revoke(summary.grant.id),
        'Could not save revocation. Check the connection status and try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final snapshot = host.snapshot;
    final moving =
        snapshot.state == OfficeAgentHostState.starting ||
        snapshot.state == OfficeAgentHostState.stopping;
    final closed = snapshot.state == OfficeAgentHostState.closed;
    return Scaffold(
      appBar: AppBar(title: const Text('Agent connections')),
      body: !_office
          ? page([
              notice(
                'Agent connections are managed on the office computer after a company workspace is prepared.',
              ),
            ])
          : page([
              Text(
                host.store.catalog!['company'] as String,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                _hostLabel(snapshot.state),
                key: const ValueKey('agent-host-status'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(_hostExplanation(snapshot)),
              const SizedBox(height: 16),
              if (snapshot.enabled)
                OutlinedButton.icon(
                  key: const ValueKey('disable-agent-connections'),
                  onPressed: _busy || moving || closed
                      ? null
                      : () => _act(
                          host.disable,
                          'Could not save the disabled setting. Check the connection status and try again.',
                        ),
                  icon: const Icon(Icons.pause_circle_outline),
                  label: const Text('Disable agent connections'),
                )
              else
                FilledButton.icon(
                  key: const ValueKey('enable-agent-connections'),
                  onPressed: _busy || moving || closed
                      ? null
                      : () => _act(
                          host.enable,
                          'Could not enable connections. Check the status below and try again.',
                        ),
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Enable agent connections'),
                ),
              TextButton.icon(
                key: const ValueKey('refresh-agent-connections'),
                onPressed: _busy || moving || closed
                    ? null
                    : () => _act(
                        host.reload,
                        'Could not refresh connections. Try again after checking the office workspace.',
                      ),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh status'),
              ),
              if (_message != null) notice(_message!, error: _messageError),
              if (snapshot.problem != null)
                notice(snapshot.problem!, error: true),
              if (_listening(host) && snapshot.socketPath != null)
                ExpansionTile(
                  key: const ValueKey('agent-connection-settings'),
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Connection settings for this session'),
                  children: [
                    const Text(
                      'Reopened this app? Copy the current connection settings again. The local address changes when the service restarts.',
                    ),
                    const SizedBox(height: 12),
                    SelectableText(_settings(host)),
                    TextButton.icon(
                      key: const ValueKey('copy-agent-settings'),
                      onPressed: _busy ? null : _copySettings,
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy connection settings'),
                    ),
                  ],
                ),
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const ValueKey('new-agent-connection'),
                onPressed: _busy || !_listening(host) ? null : _create,
                icon: const Icon(Icons.add),
                label: const Text('New agent connection'),
              ),
              if (!_listening(host))
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'The office service must be listening before you create a connection.',
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                'Saved connections',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (host.grants.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No agent connections have been created.'),
                ),
              for (final summary in host.grants)
                _GrantCard(
                  summary: summary,
                  host: host,
                  busy: _busy,
                  revoke: () => _revoke(summary),
                ),
              notice(
                'Connection credentials and pending notes suggestions are private to this computer and excluded from office backups. After restoring a workspace, create new connections.',
              ),
            ]),
    );
  }
}

bool _listening(OfficeAgentHost host) =>
    host.snapshot.enabled &&
    host.snapshot.state == OfficeAgentHostState.listening;

String _settings(OfficeAgentHost host) =>
    const JsonEncoder.withIndent('  ').convert({
      'protocol_version': 1,
      'socket_path': host.snapshot.socketPath,
      'scope': host.scope!.toJson(),
      'token_environment': 'VORTICE_LOCAL_AGENT_TOKEN',
    });

String _hostLabel(OfficeAgentHostState state) => switch (state) {
  OfficeAgentHostState.disabled => 'Disabled',
  OfficeAgentHostState.starting => 'Starting…',
  OfficeAgentHostState.listening => 'Listening on this computer',
  OfficeAgentHostState.stopping => 'Stopping…',
  OfficeAgentHostState.unavailable => 'Unavailable',
  OfficeAgentHostState.closed => 'Closed',
};

String _hostExplanation(
  OfficeAgentHostSnapshot snapshot,
) => switch (snapshot.state) {
  OfficeAgentHostState.disabled =>
    'Agents cannot connect. Enable access when you are ready to create or use a connection.',
  OfficeAgentHostState.starting => 'The office service is starting.',
  OfficeAgentHostState.listening =>
    'Only named, unexpired connections can access the records you selected.',
  OfficeAgentHostState.stopping =>
    'New requests are blocked while the office service finishes stopping.',
  OfficeAgentHostState.unavailable =>
    snapshot.enabled
        ? 'Access is enabled in settings, but the office service is not listening. Refresh status to check again, or disable connections.'
        : 'The office service is unavailable. Agents cannot connect.',
  OfficeAgentHostState.closed =>
    'This office session has ended. Return to the current workspace.',
};

String _time(DateTime time) => displayTime(time.toLocal().toIso8601String());

List<String> _recordNames(List<Json> records, Set<String>? ids, String field) =>
    [
      for (final id in ids ?? <String>{})
        records.where((record) => record['id'] == id).firstOrNull?[field]
                as String? ??
            'Record no longer available',
    ];

class _GrantCard extends StatelessWidget {
  const _GrantCard({
    required this.summary,
    required this.host,
    required this.busy,
    required this.revoke,
  });

  final OfficeAgentGrantSummary summary;
  final OfficeAgentHost host;
  final bool busy;
  final VoidCallback revoke;

  @override
  Widget build(BuildContext context) {
    final grant = summary.grant;
    final revoked = grant.revoked || summary.revokedAt != null;
    final expired = !grant.expiresAt.isAfter(DateTime.now().toUtc());
    final equipment = _recordNames(
      host.store.equipment,
      grant.equipmentIds,
      'name',
    );
    final jobs = _recordNames(host.store.jobs, grant.jobIds, 'title');
    final status = revoked
        ? 'Revoked — access blocked'
        : expired
        ? 'Expired — access blocked'
        : !host.snapshot.enabled
        ? 'Paused — connections disabled'
        : _listening(host)
        ? 'Active'
        : 'Unavailable — office service not listening';
    return Card(
      key: ValueKey('agent-grant-${grant.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(summary.label, style: Theme.of(context).textTheme.titleMedium),
            Text(status),
            Text('Expires: ${_time(grant.expiresAt)}'),
            if (summary.revokedAt != null)
              Text('Revoked: ${_time(summary.revokedAt!)}'),
            const SizedBox(height: 12),
            Text(
              grant.commands.contains('proposals.create')
                  ? 'Read selected records and suggest notes for office review'
                  : 'Read selected records only',
            ),
            _SelectedRecords(title: 'Equipment', names: equipment),
            _SelectedRecords(title: 'Jobs', names: jobs),
            if (jobs.isEmpty)
              const Text(
                'No jobs selected — no equipment details or job records can be read.',
              ),
            if (!revoked)
              OutlinedButton(
                key: ValueKey('revoke-agent-${grant.id}'),
                onPressed: busy ? null : revoke,
                child: const Text('Revoke connection'),
              ),
          ],
        ),
      ),
    );
  }
}

class _SelectedRecords extends StatelessWidget {
  const _SelectedRecords({required this.title, required this.names});
  final String title;
  final List<String> names;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        if (names.isEmpty) const Text('None — no access'),
        for (final name in names) Text('• $name'),
      ],
    ),
  );
}

class _ConnectionEditor extends StatefulWidget {
  const _ConnectionEditor({required this.host});
  final OfficeAgentHost host;
  @override
  State<_ConnectionEditor> createState() => _ConnectionEditorState();
}

class _ConnectionEditorState extends State<_ConnectionEditor> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _equipment = <String>{};
  final _jobs = <String>{};
  Duration _duration = const Duration(hours: 1);
  bool _allowNotes = false;
  String? _selectionProblem;

  LabStore get _store => widget.host.store;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _chooseEquipment(String id, bool selected) {
    setState(() {
      if (selected) {
        _equipment.add(id);
      } else {
        _equipment.remove(id);
        _jobs.removeWhere(
          (jobId) => _store.jobs.any(
            (job) => job['id'] == jobId && job['equipmentId'] == id,
          ),
        );
      }
      _selectionProblem = null;
    });
  }

  Future<void> _review() async {
    FocusScope.of(context).unfocus();
    final valid = _form.currentState!.validate();
    if (_equipment.isEmpty) {
      setState(
        () => _selectionProblem = 'Select at least one piece of equipment.',
      );
    }
    if (!valid || _equipment.isEmpty) return;
    final request = AgentGrantRequest(
      label: _name.text.trim(),
      expiresAt: DateTime.now().toUtc().add(_duration),
      jobIds: _jobs,
      equipmentIds: _equipment,
      allowNotes: _allowNotes,
    );
    final issued = await Navigator.push<IssuedAgentGrant>(
      context,
      MaterialPageRoute(
        builder: (_) => _ConnectionReview(host: widget.host, request: request),
      ),
    );
    if (mounted && issued != null) Navigator.pop(context, issued);
  }

  @override
  Widget build(BuildContext context) {
    final jobs = _store.jobs.where(
      (job) => _equipment.contains(job['equipmentId']),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('New connection')),
      body: Form(
        key: _form,
        child: FocusTraversalGroup(
          child: page([
            const Text(
              'Choose a name and the exact records this agent may access. Newly added equipment and jobs are not included.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('agent-connection-name'),
              controller: _name,
              maxLength: 80,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
              decoration: const InputDecoration(
                labelText: 'Connection name',
                errorMaxLines: 3,
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return 'Enter a name you will recognize.';
                if (text.length > 80) return 'Use a shorter connection name.';
                if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(text)) {
                  return 'Use a name without control characters.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Duration>(
              key: const ValueKey('agent-connection-expiry'),
              initialValue: _duration,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Expires after'),
              items: const [
                DropdownMenuItem(
                  value: Duration(hours: 1),
                  child: Text('1 hour'),
                ),
                DropdownMenuItem(
                  value: Duration(hours: 4),
                  child: Text('4 hours'),
                ),
                DropdownMenuItem(
                  value: Duration(days: 1),
                  child: Text('1 day'),
                ),
                DropdownMenuItem(
                  value: Duration(days: 7),
                  child: Text('7 days'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _duration = value);
              },
            ),
            const SizedBox(height: 24),
            Text('Equipment', style: Theme.of(context).textTheme.titleLarge),
            const Text(
              'Select at least one. Choose the equipment whose jobs may be accessed.',
            ),
            if (_store.equipment.isEmpty)
              notice('Add equipment in the office workspace first.'),
            for (final equipment in _store.equipment)
              CheckboxListTile(
                key: ValueKey('agent-equipment-${equipment['id']}'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _equipment.contains(equipment['id']),
                title: Text(equipment['name'] as String),
                onChanged: (value) =>
                    _chooseEquipment(equipment['id'] as String, value == true),
              ),
            if (_selectionProblem != null)
              notice(_selectionProblem!, error: true),
            const SizedBox(height: 16),
            Text('Jobs', style: Theme.of(context).textTheme.titleLarge),
            const Text(
              'Optional. Select individual jobs for the equipment above.',
            ),
            const Text(
              'Equipment details are available only when one of its jobs is selected.',
            ),
            if (_equipment.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Choose equipment to see its jobs.'),
              )
            else if (jobs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No jobs are prepared for the selected equipment.'),
              ),
            for (final job in jobs)
              CheckboxListTile(
                key: ValueKey('agent-job-${job['id']}'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _jobs.contains(job['id']),
                title: Text(job['title'] as String),
                subtitle: Text(
                  _recordNames(_store.equipment, {
                    job['equipmentId'] as String,
                  }, 'name').single,
                ),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _jobs.add(job['id'] as String);
                  } else {
                    _jobs.remove(job['id']);
                  }
                }),
              ),
            if (_jobs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No jobs selected — no equipment details or job records can be read.',
                ),
              ),
            const SizedBox(height: 16),
            CheckboxListTile(
              key: const ValueKey('agent-allow-notes'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Allow notes suggestions'),
              subtitle: const Text(
                'Suggestions stay pending until the office reviews them. This does not permit changing or approving inspections.',
              ),
              value: _allowNotes,
              onChanged: (value) => setState(() => _allowNotes = value == true),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('review-agent-connection'),
              onPressed: _store.equipment.isEmpty ? null : _review,
              child: const Text('Review connection'),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ConnectionReview extends StatefulWidget {
  const _ConnectionReview({required this.host, required this.request});
  final OfficeAgentHost host;
  final AgentGrantRequest request;
  @override
  State<_ConnectionReview> createState() => _ConnectionReviewState();
}

class _ConnectionReviewState extends State<_ConnectionReview> {
  bool _creating = false;
  String? _problem;

  Future<void> _create() async {
    if (_creating) return;
    setState(() {
      _creating = true;
      _problem = null;
    });
    try {
      final issued = await widget.host.issue(widget.request);
      if (mounted) Navigator.pop(context, issued);
    } catch (_) {
      if (mounted) {
        setState(
          () => _problem =
              'Could not create this connection. Return to the selections, check the office status and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final store = widget.host.store;
    return Scaffold(
      appBar: AppBar(title: const Text('Review connection')),
      body: page([
        Text(request.label, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text('Expires: ${_time(request.expiresAt)}'),
        const Text(
          'Expiry uses this computer’s local time. Maximum lifetime: 7 days.',
        ),
        const SizedBox(height: 16),
        Text(
          request.allowNotes
              ? 'Read selected records and suggest notes for office review'
              : 'Read selected records only',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (request.allowNotes)
          const Text(
            'Notes suggestions stay pending. The agent cannot apply changes or approve inspections.',
          ),
        _SelectedRecords(
          title: 'Selected equipment',
          names: _recordNames(store.equipment, request.equipmentIds, 'name'),
        ),
        _SelectedRecords(
          title: 'Selected jobs',
          names: _recordNames(store.jobs, request.jobIds, 'title'),
        ),
        if (request.jobIds.isEmpty)
          notice(
            'No jobs selected — no equipment details or job records can be read. Edit selections to include the jobs the agent needs.',
          ),
        const Text(
          'Only these records are included. Newly added records do not expand access.',
        ),
        notice(
          'The private credential is shown once after you create this connection. It is excluded from office backups.',
        ),
        if (_problem != null) notice(_problem!, error: true),
        FilledButton(
          key: const ValueKey('confirm-create-agent-connection'),
          onPressed: _creating ? null : _create,
          child: Text(_creating ? 'Creating…' : 'Create connection'),
        ),
        TextButton(
          key: const ValueKey('edit-agent-connection'),
          onPressed: _creating ? null : () => Navigator.pop(context),
          child: const Text('Edit selections'),
        ),
      ]),
    );
  }
}

class _CredentialResult extends StatefulWidget {
  const _CredentialResult({required this.issued});
  final IssuedAgentGrant issued;
  @override
  State<_CredentialResult> createState() => _CredentialResultState();
}

class _CredentialResultState extends State<_CredentialResult> {
  String? _message;
  bool _copying = false;

  Future<void> _copy() async {
    if (_copying) return;
    setState(() => _copying = true);
    try {
      await Clipboard.setData(ClipboardData(text: widget.issued.token));
      if (mounted) {
        setState(
          () => _message = 'Private credential copied on this computer.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Could not copy the credential. Select and copy the complete text above.',
        );
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Connection created'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.issued.summary.label),
        const SizedBox(height: 12),
        const Text(
          'Save this private credential now. It is shown only once. Share it only with the agent you named.',
        ),
        const SizedBox(height: 16),
        SelectableText(
          widget.issued.token,
          key: const ValueKey('agent-created-credential'),
        ),
        const SizedBox(height: 12),
        Text('Expires: ${_time(widget.issued.summary.grant.expiresAt)}'),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_message!),
          ),
      ],
    ),
    actions: [
      TextButton.icon(
        key: const ValueKey('copy-agent-credential'),
        onPressed: _copying ? null : _copy,
        icon: const Icon(Icons.copy),
        label: const Text('Copy credential'),
      ),
      FilledButton(
        key: const ValueKey('done-agent-credential'),
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}
