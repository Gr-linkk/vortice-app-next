import 'dart:io';
import 'package:flutter/material.dart';
import '../model.dart';
import '../office_backup.dart';
import 'common.dart';

/// Restores a verified private backup into an absent Linux office workspace.
/// The caller decides how to open the returned directory.
class RestorePage extends StatefulWidget {
  const RestorePage({super.key});

  @override
  State<RestorePage> createState() => _RestorePageState();
}

class _RestorePageState extends State<RestorePage> {
  final source = TextEditingController();
  final destination = TextEditingController();
  final fingerprint = TextEditingController();
  OfficeBackupSummary? summary;
  String? checkedSource, checkedDestination, error;
  bool busy = false;
  String action = '';

  String get expectedFingerprint =>
      fingerprint.text.trim().replaceAll(RegExp(r'\s'), '').toLowerCase();

  bool get canRestore =>
      Platform.isLinux &&
      !busy &&
      summary != null &&
      checkedSource == source.text.trim() &&
      checkedDestination == destination.text.trim() &&
      destination.text.trim().isNotEmpty &&
      hashPattern.hasMatch(expectedFingerprint) &&
      expectedFingerprint == summary!.fingerprint;

  @override
  void dispose() {
    source.dispose();
    destination.dispose();
    fingerprint.dispose();
    super.dispose();
  }

  void invalidate(String _) => setState(() {
    summary = null;
    checkedSource = null;
    checkedDestination = null;
    error = null;
  });

  Future<void> inspect() async {
    setState(() {
      busy = true;
      action = 'Checking backup…';
      summary = null;
      error = null;
    });
    try {
      if (!Platform.isLinux) {
        throw StateError('Office restore requires Linux.');
      }
      if (source.text.trim().isEmpty) {
        throw StateError('Enter the entire private backup folder.');
      }
      final backup = await OfficeBackup.inspect(Directory(source.text.trim()));
      if (mounted) {
        setState(() {
          summary = backup;
          checkedSource = source.text.trim();
          checkedDestination = destination.text.trim();
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(() => error = _safeError(failure));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> restore() async {
    if (!canRestore) return;
    final verifiedSource = source.text.trim();
    final newWorkspace = destination.text.trim();
    final savedFingerprint = expectedFingerprint;
    setState(() {
      busy = true;
      action = 'Restoring verified office…';
      error = null;
    });
    try {
      final result = await OfficeBackup.restore(
        Directory(verifiedSource),
        Directory(newWorkspace),
        expectedFingerprint: savedFingerprint,
      );
      if (!mounted) return;
      setState(() => busy = false);
      // Release the busy navigation fence before returning the published folder.
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context, result.directory);
    } catch (failure) {
      if (mounted) {
        setState(() => error = _safeError(failure));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _safeError(Object failure) => failure is StateError
      ? failure.message.toString()
      : 'Restore could not finish. Check the private backup and new workspace folder.';

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Restore office computer'),
        automaticallyImplyLeading: !busy,
      ),
      body: page([
        Text(
          'Recover the same office',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Use a trusted, private office backup and the office TLS fingerprint '
          'you saved separately. Compare that saved fingerprint with the checked '
          'backup below. This restores the same office identity and its received '
          'work; it does not transfer ownership.',
        ),
        notice(
          'Choose a new workspace folder. Existing folders are retained. '
          'Close the original office app before opening its restored copy; keep '
          'only one office running for this identity. '
          'After restore, phones require owner confirmation again, revoked '
          'phones remain revoked, and old invitations are discarded.',
        ),
        if (!Platform.isLinux)
          notice('Office restore is available on Linux.', error: true),
        TextField(
          key: const Key('restoreSource'),
          controller: source,
          enabled: !busy && Platform.isLinux,
          onChanged: invalidate,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Private backup folder',
            helperText: 'Use the entire verified office backup directory.',
            helperMaxLines: 3,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('restoreDestination'),
          controller: destination,
          enabled: !busy && Platform.isLinux,
          onChanged: invalidate,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'New workspace folder',
            helperText:
                'The parent folder must exist. Existing workspace folders are retained; choose an absent folder.',
            helperMaxLines: 4,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('restoreFingerprint'),
          controller: fingerprint,
          enabled: !busy && Platform.isLinux,
          onChanged: (_) => setState(() => error = null),
          autocorrect: false,
          enableSuggestions: false,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Saved office fingerprint',
            helperText:
                'Enter the 64 hexadecimal characters saved independently of this backup.',
            helperMaxLines: 4,
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: busy || !Platform.isLinux ? null : inspect,
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('Check backup'),
        ),
        if (summary != null) ...[
          notice(
            'Backup checked: ${displayTime(summary!.createdAt)}. '
            '${summary!.submissions} submitted versions, '
            '${summary!.receipts} decisions and '
            '${summary!.evidenceFiles} complete photos. '
            '${summary!.phonesToReconfirm} phones will require owner confirmation; '
            '${summary!.revokedPhones} revoked phones remain revoked. '
            '${summary!.invitationsToDiscard} old invitations will be discarded.',
          ),
          const Text('Compare with your separately saved fingerprint:'),
          const SizedBox(height: 8),
          SelectableText(summary!.fingerprint),
          if (fingerprint.text.trim().isNotEmpty &&
              expectedFingerprint != summary!.fingerprint)
            notice(
              'The saved fingerprint does not match this backup. Restore requires '
              'the independently saved fingerprint for this office.',
              error: true,
            ),
          const SizedBox(height: 16),
        ],
        FilledButton.icon(
          onPressed: canRestore ? restore : null,
          icon: const Icon(Icons.restore),
          label: const Text('Restore verified office'),
        ),
        if (busy) notice(action),
        if (error != null) notice(error!, error: true),
      ]),
    ),
  );
}
