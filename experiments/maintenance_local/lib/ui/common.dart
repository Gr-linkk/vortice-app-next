import 'package:flutter/material.dart';
import '../lab_store.dart';

Widget page(List<Widget> children) => SafeArea(
  child: SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  ),
);
Widget notice(String text, {bool error = false}) => Container(
  margin: const EdgeInsets.symmetric(vertical: 12),
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: error ? const Color(0xffffe3df) : const Color(0xffe4ece6),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Text(text),
);
String displayTime(String iso) =>
    DateTime.tryParse(iso)?.toLocal().toString().split('.').first ?? iso;
Future<String?> askText(
  BuildContext context,
  String title,
  String label, {
  bool multiline = false,
}) async {
  final text = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      scrollable: true,
      title: Text(title),
      content: TextField(
        controller: text,
        minLines: multiline ? 3 : 1,
        maxLines: multiline ? 6 : 1,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, text.text),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  // The dialog reverse transition may still hold the controller during this frame.
  Future<void>.delayed(const Duration(seconds: 1), text.dispose);
  return result;
}

Widget evidenceImage(LabStore store, String hash) => FutureBuilder<bool>(
  future: store.evidence.complete(hash),
  builder: (context, snapshot) {
    if (snapshot.data != true) {
      return notice('Waiting for the complete inspection photo.');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          store.evidence.file(hash),
          height: 220,
          fit: BoxFit.contain,
          errorBuilder: (_, error, stack) => notice(
            'This evidence file cannot be displayed as a photo.',
            error: true,
          ),
        ),
      ),
    );
  },
);
