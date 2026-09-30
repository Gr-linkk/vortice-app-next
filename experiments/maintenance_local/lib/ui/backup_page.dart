import 'dart:io';
import 'package:flutter/material.dart';
import '../lab_store.dart';
import '../office_backup.dart';
import 'common.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.store});
  final LabStore store;
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final destination = TextEditingController();
  bool busy = false;
  String? message;
  bool failed = false;
  @override
  void initState() {
    super.initState();
    destination.text =
        '${widget.store.root.parent.path}/office-backup-${DateTime.now().toUtc().millisecondsSinceEpoch}';
  }

  @override
  void dispose() {
    destination.dispose();
    super.dispose();
  }

  Future<void> create() async {
    setState(() {
      busy = true;
      message = null;
      failed = false;
    });
    try {
      if (destination.text.trim().isEmpty) {
        throw StateError('Choose a new backup folder.');
      }
      final backup = await OfficeBackup.create(
        widget.store,
        Directory(destination.text.trim()),
      );
      if (mounted) {
        setState(
          () => message =
              'Backup verified: ${backup.submissions} submitted versions, ${backup.receipts} decisions and ${backup.evidenceFiles} complete photos. Saved to ${backup.directory.path}. Copy this entire private folder to storage separate from this computer.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          failed = true;
          message = error.toString().replaceFirst('Bad state: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Back up office computer')),
    body: page([
      Text(
        'Keep a recoverable office copy',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      const Text(
        'Save work, submitted versions, decisions, complete photos and this computer’s identity together. Only work already received by this computer is included. An unfinished or damaged photo must finish transferring before a complete backup can be made.',
      ),
      notice(
        'This backup contains the office’s private identity. Keep it private and store a copy separately from this computer. Restoring it keeps the same office identity; phones must be confirmed again before reconnecting.',
      ),
      const Text('Save this office fingerprint separately from the backup:'),
      SelectableText(
        widget.store.setting('officeFingerprint') as String? ??
            'Office identity unavailable; reopen local connections before backing up.',
      ),
      const SizedBox(height: 16),
      TextField(
        key: const Key('backupDestination'),
        controller: destination,
        enabled: !busy,
        decoration: const InputDecoration(
          labelText: 'New backup folder',
          helperText:
              'An existing folder will be retained; choose a new location.',
          helperMaxLines: 3,
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: busy ? null : create,
        icon: const Icon(Icons.save_outlined),
        label: Text(busy ? 'Verifying backup…' : 'Create verified backup'),
      ),
      if (message != null) notice(message!, error: failed),
      const SizedBox(height: 12),
      const Text(
        'Recovery uses the entire verified backup in a fresh workspace. Existing workspaces are never overwritten. A backup restores this authorized office; it does not turn a phone into an office or transfer ownership.',
      ),
    ]),
  );
}
