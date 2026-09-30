import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../local_sync.dart';
import 'common.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key, required this.server});
  final OfficeServer server;
  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  List<String> addresses = [];
  String? host, invitation, message;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> load() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    addresses = interfaces
        .where((i) => !i.name.startsWith('docker') && !i.name.startsWith('br-'))
        .expand((i) => i.addresses)
        .map((a) => a.address)
        .where(localAddress)
        .toList();
    if (mounted) setState(() => host = addresses.firstOrNull);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Phones and recovery')),
    body: page([
      Text('Connect a phone', style: Theme.of(context).textTheme.headlineSmall),
      const Text(
        'Keep both apps open on the same Wi-Fi. Create an invitation, copy and paste it on the phone, then compare and confirm the code here. A saved invitation image also works without a camera.',
      ),
      const SizedBox(height: 16),
      if (addresses.isEmpty)
        notice('Join a local Wi-Fi network to invite a phone.', error: true)
      else
        DropdownButtonFormField<String>(
          initialValue: host,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Computer Wi-Fi address',
          ),
          items: addresses
              .map((a) => DropdownMenuItem(value: a, child: Text(a)))
              .toList(),
          onChanged: (value) => setState(() {
            host = value;
            invitation = null;
          }),
        ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: host == null
            ? null
            : () =>
                  setState(() => invitation = widget.server.invitation(host!)),
        child: const Text('Create phone invitation'),
      ),
      if (invitation != null) ...[
        Center(
          child: QrImageView(
            data: invitation!,
            size: 280,
            backgroundColor: Colors.white,
          ),
        ),
        const Text('Expires in 10 minutes. Keep this invitation private.'),
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: invitation!));
            if (mounted) {
              setState(
                () => message =
                    'Invitation copied. Bring this private text to the phone and choose Paste invitation. Compare the confirmation code here before allowing it.',
              );
            }
          },
          child: const Text('Copy invitation'),
        ),
      ],
      if (message != null) notice(message!),
      const SizedBox(height: 24),
      Text('Connected phones', style: Theme.of(context).textTheme.titleLarge),
      if (widget.server.authority.phones.isEmpty)
        const Text('No phones connected yet.'),
      for (final p in widget.server.authority.phones)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  p['label'] as String,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  p['status'] == 'active'
                      ? 'Connected'
                      : p['status'] == 'revoked'
                      ? 'Revoked — connection blocked'
                      : 'Awaiting your confirmation',
                ),
                if (p['status'] == 'pending') ...[
                  Text(
                    'Compare with phone: ${widget.server.authority.confirmationCode(p['id'] as String)}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  FilledButton(
                    onPressed: () => setState(
                      () => widget.server.authority.confirm(p['id'] as String),
                    ),
                    child: const Text('Codes match — allow this phone'),
                  ),
                ],
                if (p['status'] != 'revoked')
                  OutlinedButton(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Revoke this phone?'),
                          content: const Text(
                            'It will lose access immediately. Work already saved on this computer remains available for a replacement. Unsynced work on a lost phone cannot be recovered.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('Revoke phone'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && mounted) {
                        setState(
                          () =>
                              widget.server.authority.revoke(p['id'] as String),
                        );
                      }
                    },
                    child: const Text('Revoke phone'),
                  ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 16),
      notice(
        'Replacing a lost phone: revoke it above, create a new invitation and connect the replacement. Keep both apps open until the phone reports that photos are verified. Only the computer’s saved copy can be restored.',
      ),
      notice(
        'If the phone cannot reach this computer, check the selected Wi-Fi address and local access to TCP 47841. Keep both apps open and retry. No internet service is required.',
      ),
    ]),
  );
}
