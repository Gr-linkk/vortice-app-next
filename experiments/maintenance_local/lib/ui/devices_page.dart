import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../local_sync.dart';
import 'common.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({
    super.key,
    required this.server,
    this.addressLoader = availableLocalAddresses,
  });
  final OfficeServer server;
  final Future<List<String>> Function() addressLoader;
  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

Future<List<String>> availableLocalAddresses() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  );
  return interfaces
      .where((i) => !i.name.startsWith('docker') && !i.name.startsWith('br-'))
      .expand((i) => i.addresses)
      .map((a) => a.address)
      .where((a) => localAddress(a) && !a.startsWith('127.'))
      .toSet()
      .toList();
}

class _DevicesPageState extends State<DevicesPage> with WidgetsBindingObserver {
  List<String> addresses = [];
  String? host, invitation, invitationHost, message, addressProblem;
  Timer? timer, addressTimer;
  int refreshVersion = 0;
  bool loading = true, creating = false, foreground = true;
  bool addressesVerified = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refreshAddresses();
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && foreground) setState(() {});
    });
    addressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (foreground && !loading && !creating) refreshAddresses();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) refreshAddresses();
  }

  Future<bool> refreshAddresses() async {
    final version = ++refreshVersion;
    setState(() => loading = true);
    try {
      final latest = (await widget.addressLoader())
          .where((a) => localAddress(a) && !a.startsWith('127.'))
          .toSet()
          .toList();
      if (!mounted || version != refreshVersion) return false;
      setState(() {
        addresses = latest;
        if (!latest.contains(host)) host = latest.firstOrNull;
        if (invitationHost != null && !latest.contains(invitationHost)) {
          invitation = invitationHost = message = null;
          addressProblem =
              'The computer address changed. Create a new invitation and paste it on the phone.';
        } else {
          addressProblem = null;
        }
        loading = false;
        addressesVerified = true;
      });
      return true;
    } catch (_) {
      if (!mounted || version != refreshVersion) return false;
      setState(() {
        loading = false;
        addressesVerified = false;
        invitation = invitationHost = message = null;
        addressProblem =
            'Could not check the computer address. Choose Refresh addresses and try again.';
      });
      return false;
    }
  }

  Future<void> createInvitation() async {
    final selected = host;
    if (selected == null || creating) return;
    setState(() => creating = true);
    try {
      final fresh = await refreshAddresses();
      if (!mounted || !fresh) return;
      if (host != selected || !addresses.contains(selected)) {
        setState(
          () => addressProblem =
              'The computer address changed. Check the address below, then create a new invitation.',
        );
        return;
      }
      final created = widget.server.invitation(selected);
      setState(() {
        invitation = created;
        invitationHost = selected;
        message = addressProblem = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          invitation = invitationHost = message = null;
          addressProblem =
              'Could not create an invitation. Refresh addresses, then try again.';
        });
      }
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }

  @override
  void dispose() {
    ++refreshVersion;
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    addressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Phones and recovery')),
    body: page([
      Text('Connect a phone', style: Theme.of(context).textTheme.headlineSmall),
      const Text(
        '1. Keep this app and the phone app open on the same Wi-Fi or phone hotspot.\n2. Check the computer address below, then create an invitation.',
      ),
      const SizedBox(height: 16),
      TextButton.icon(
        key: const ValueKey('refresh-addresses'),
        onPressed: creating ? null : refreshAddresses,
        icon: const Icon(Icons.refresh),
        label: Text(loading ? 'Checking addresses…' : 'Refresh addresses'),
      ),
      if (addressProblem != null) notice(addressProblem!, error: true),
      if (addresses.isEmpty && !loading)
        notice('Join a local Wi-Fi network to invite a phone.', error: true),
      if (addresses.isNotEmpty)
        DropdownButtonFormField<String>(
          key: ValueKey('computer-address-$host'),
          initialValue: host,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Computer Wi-Fi address',
          ),
          items: addresses
              .map((a) => DropdownMenuItem(value: a, child: Text(a)))
              .toList(),
          onChanged: creating
              ? null
              : (value) => setState(() {
                  host = value;
                  invitation = invitationHost = message = null;
                }),
        ),
      const SizedBox(height: 16),
      FilledButton(
        key: const ValueKey('create-invitation'),
        onPressed: host == null || loading || creating || !addressesVerified
            ? null
            : createInvitation,
        child: Text(creating ? 'Checking address…' : 'Create phone invitation'),
      ),
      if (invitation != null) ...[
        Center(
          child: QrImageView(
            data: invitation!,
            size: 280,
            backgroundColor: Colors.white,
          ),
        ),
        const Text(
          '3. Copy this private invitation. On the phone, choose Paste invitation and paste the complete text. A saved invitation image also works without a camera.\n4. Compare the code on both screens, then allow the phone here.\nExpires in 10 minutes.',
        ),
        TextButton(
          onPressed: () async {
            final copied = invitation;
            if (copied == null) return;
            await Clipboard.setData(ClipboardData(text: copied));
            if (mounted && invitation == copied) {
              setState(
                () => message =
                    'Invitation copied on this computer only. Send the complete private text to yourself using a method you trust, then copy it on the phone and choose Paste invitation. Compare the confirmation code here before allowing it.',
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
                      ? 'Allowed to connect'
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
