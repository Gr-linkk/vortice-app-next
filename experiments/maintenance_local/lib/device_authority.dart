import 'dart:convert';
import 'lab_store.dart';
import 'model.dart';

/// The computer's local database is the sole enrollment/revocation authority.
/// These rows are never part of a document or a recovery bundle.
class DeviceAuthority {
  DeviceAuthority(this.store);
  final LabStore store;
  String invite() {
    store.requireOffice();
    final code = secret();
    store.db.execute('INSERT INTO invites VALUES (?,?,NULL)', [
      digest(utf8.encode(code)),
      store.now().add(const Duration(minutes: 10)).toUtc().toIso8601String(),
    ]);
    return code;
  }

  List<Json> get phones => store.db
      .select('SELECT id,label,status FROM phones ORDER BY rowid')
      .map((r) => Map<String, dynamic>.from(r))
      .toList();

  Json request(Json p) {
    store.requireOffice();
    final id = p['device'],
        label = p['label'],
        token = p['token'],
        invitation = p['invitation'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 100 ||
        label is! String ||
        label.isEmpty ||
        label.length > 80 ||
        token is! String ||
        token.length != 44 ||
        invitation is! String) {
      throw StateError('Invalid pairing request.');
    }
    final tokenHash = digest(utf8.encode(token));
    store.transaction(() {
      final rows = store.db.select('SELECT * FROM invites WHERE hash=?', [
        digest(utf8.encode(invitation)),
      ]);
      if (rows.isEmpty) throw StateError('Invitation is not recognized.');
      final invite = rows.first;
      final existing = store.db.select('SELECT * FROM phones WHERE id=?', [id]);
      if (invite['used_by'] == id &&
          existing.isNotEmpty &&
          existing.first['token_hash'] == tokenHash) {
        return;
      }
      if (invite['used_by'] != null ||
          DateTime.parse(invite['expires'] as String).isBefore(store.now())) {
        throw StateError(
          'Invitation expired or already used. Make a new invitation on the computer.',
        );
      }
      if (existing.isNotEmpty) {
        if (existing.first['token_hash'] != tokenHash ||
            existing.first['status'] == 'revoked') {
          throw StateError('This device credential cannot enroll again.');
        }
      } else {
        store.db.execute("INSERT INTO phones VALUES (?,?,?,'pending')", [
          id,
          label,
          tokenHash,
        ]);
      }
      store.db.execute('UPDATE invites SET used_by=? WHERE hash=?', [
        id,
        digest(utf8.encode(invitation)),
      ]);
    });
    final row = store.db.select('SELECT status FROM phones WHERE id=?', [
      id,
    ]).first;
    return {'status': row['status'], 'code': tokenHash.substring(0, 8)};
  }

  void confirm(String id) {
    store.requireOffice();
    store.db.execute(
      "UPDATE phones SET status='active' WHERE id=? AND status='pending'",
      [id],
    );
  }

  void revoke(String id) {
    store.requireOffice();
    store.db.execute("UPDATE phones SET status='revoked' WHERE id=?", [id]);
  }

  String confirmationCode(String id) =>
      (store.db.select('SELECT token_hash FROM phones WHERE id=?', [
                id,
              ]).first['token_hash']
              as String)
          .substring(0, 8);
  String authenticate(String? bearer) {
    if (bearer == null || !bearer.startsWith('Bearer ')) {
      throw StateError('A paired device credential is required.');
    }
    final rows = store.db.select(
      'SELECT id FROM phones WHERE token_hash=? AND status=\'active\'',
      [digest(utf8.encode(bearer.substring(7)))],
    );
    if (rows.isEmpty) {
      throw StateError('Device is awaiting confirmation or has been revoked.');
    }
    return rows.first['id'] as String;
  }
}
