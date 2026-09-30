import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

typedef Json = Map<String, dynamic>;

Object? ordered(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final k in keys) k: ordered(value[k])};
  }
  if (value is List) return value.map(ordered).toList();
  return value;
}

String canonical(Object? value) => jsonEncode(ordered(value));
String digest(List<int> bytes) => sha256.convert(bytes).toString();
String contentHash(Object? value) => digest(utf8.encode(canonical(value)));
String secret() =>
    base64UrlEncode(List.generate(32, (_) => Random.secure().nextInt(256)));
final hashPattern = RegExp(r'^[a-f0-9]{64}$');

const fieldNames = {'fluid', 'guards', 'meter', 'unit', 'notes', 'photo'};
const checklist = {
  'fluid': 'Check fluid levels',
  'guards': 'Inspect guards and visible leaks',
};
const initialFields = <String, dynamic>{
  'fluid': null,
  'guards': null,
  'meter': null,
  'unit': 'hours',
  'notes': '',
  'photo': null,
};

void validateDocument(Json alternatives) {
  if (alternatives.keys.toSet().difference(fieldNames).isNotEmpty ||
      fieldNames.difference(alternatives.keys.toSet()).isNotEmpty) {
    throw StateError('This job has an unsupported document shape.');
  }
  for (final e in alternatives.entries) {
    if (e.value is! List ||
        (e.value as List).isEmpty ||
        (e.value as List).length > 32) {
      throw StateError('Invalid alternatives in ${e.key}.');
    }
    for (final value in e.value as List) {
      final valid = switch (e.key) {
        'fluid' ||
        'guards' => value == null || value == 'pass' || value == 'attention',
        'meter' =>
          value == null ||
              (value is num && value.isFinite && value >= 0 && value <= 1e12),
        'unit' => value == 'hours',
        'notes' => value is String && value.length <= 10000,
        'photo' =>
          value == null || (value is String && hashPattern.hasMatch(value)),
        _ => false,
      };
      if (!valid) throw StateError('Invalid value for ${e.key}.');
    }
  }
}

List<String> conflicts(Json alternatives) => alternatives.entries
    .where((e) => (e.value as List).length > 1)
    .map((e) => e.key)
    .toList();
Json valuesOf(Json alternatives) => {
  for (final e in alternatives.entries) e.key: (e.value as List).first,
};

String? incomplete(Json alternatives) {
  validateDocument(alternatives);
  if (conflicts(alternatives).isNotEmpty) {
    return 'Resolve conflicting answers before submitting.';
  }
  final v = valuesOf(alternatives);
  if (v['fluid'] == null || v['guards'] == null) {
    return 'Answer both inspection checks.';
  }
  if (v['meter'] == null) return 'Record the meter reading; do not guess.';
  if ((v['notes'] as String).trim().isEmpty) {
    return 'Add work notes, including anything needing attention.';
  }
  if (v['photo'] == null) return 'Attach a photo of the inspection.';
  return null;
}

class SerialQueue {
  Future<void> _tail = Future.value();
  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<void> get idle => _tail;
}
