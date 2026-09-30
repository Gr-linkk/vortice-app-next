import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'model.dart';

/// Photos are immutable, content-addressed files. Partial files never count as evidence.
class EvidenceStore {
  EvidenceStore(this.root);
  final Directory root;
  static const maxBytes = 20 * 1024 * 1024;
  static const chunkBytes = 256 * 1024;
  final _queue = SerialQueue();

  File file(String hash) {
    if (!hashPattern.hasMatch(hash)) {
      throw const FormatException('Invalid evidence identity.');
    }
    return File('${root.path}/$hash');
  }

  File _partial(String hash) => File('${file(hash).path}.part');

  Future<bool> complete(String hash) async {
    final f = file(hash);
    return await f.exists() && digest(await f.readAsBytes()) == hash;
  }

  Future<String> add(List<int> bytes) async {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw StateError('Photo must be between 1 byte and 20 MB.');
    }
    final hash = digest(bytes);
    if ((await status(hash))['complete'] == true) return hash;
    for (var offset = 0; offset < bytes.length; offset += chunkBytes) {
      await append(
        hash,
        offset,
        bytes.length,
        bytes.sublist(offset, min(offset + chunkBytes, bytes.length)),
      );
    }
    if ((await status(hash))['complete'] != true) {
      throw StateError('Photo save did not finish. Retry saving it.');
    }
    return hash;
  }

  Future<Json> status(
    String hash, {
    void Function()? checkAuthority,
  }) => _queue.run(() async {
    checkAuthority?.call();
    // Recover a crash after flushing the last chunk but before publishing it.
    final partial = _partial(hash);
    if (!await complete(hash) &&
        await partial.exists() &&
        digest(await partial.readAsBytes()) == hash) {
      checkAuthority?.call();
      // Keep the final authority decision and publication in one event turn.
      partial.renameSync(file(hash).path);
    }
    final done = await complete(hash);
    return {
      'complete': done,
      'offset': done
          ? await file(hash).length()
          : (await partial.exists() ? await partial.length() : 0),
    };
  });

  Future<void> append(
    String hash,
    int offset,
    int total,
    List<int> bytes, {
    void Function()? checkAuthority,
  }) => _queue.run(() async {
    checkAuthority?.call();
    if (offset < 0 ||
        total <= 0 ||
        total > maxBytes ||
        bytes.isEmpty ||
        bytes.length > chunkBytes ||
        offset + bytes.length > total) {
      throw StateError('Invalid photo chunk.');
    }
    await root.create(recursive: true);
    if (await complete(hash)) {
      final existing = await file(hash).readAsBytes();
      if (existing.length != total ||
          offset + bytes.length > existing.length ||
          digest(existing.sublist(offset, offset + bytes.length)) !=
              digest(bytes)) {
        throw StateError('Photo retry changed content.');
      }
      return;
    }
    final partial = _partial(hash);
    final length = await partial.exists() ? await partial.length() : 0;
    var remaining = bytes;
    if (offset < length) {
      final overlap = min(length - offset, bytes.length);
      final handle = await partial.open();
      try {
        await handle.setPosition(offset);
        final prior = await handle.read(overlap);
        if (digest(prior) != digest(bytes.sublist(0, overlap))) {
          throw StateError('Photo retry changed content.');
        }
      } finally {
        await handle.close();
      }
      if (overlap == bytes.length) return;
      offset += overlap;
      remaining = bytes.sublist(overlap);
    }
    if (offset != length) {
      throw StateError(
        'Photo transfer has a gap. Retry from the saved offset.',
      );
    }
    checkAuthority?.call();
    final handle = await partial.open(mode: FileMode.append);
    try {
      await handle.writeFrom(remaining);
      await handle.flush();
    } finally {
      await handle.close();
    }
    if (await partial.length() == total) {
      if (digest(await partial.readAsBytes()) != hash) {
        await partial.delete();
        throw StateError('Photo integrity check failed. Send the photo again.');
      }
      checkAuthority?.call();
      // Async disk IO above can outlive a revocation. Publish only after a
      // fresh check, synchronously so no revocation can run between them.
      partial.renameSync(file(hash).path);
    }
  });

  Future<Uint8List> chunk(String hash, int offset) async {
    final f = file(hash);
    if (!await complete(hash)) {
      throw StateError('Complete photo is not available.');
    }
    final length = await f.length();
    if (offset < 0 || offset >= length) {
      throw StateError('Invalid photo offset.');
    }
    final h = await f.open();
    try {
      await h.setPosition(offset);
      return await h.read(min(chunkBytes, length - offset));
    } finally {
      await h.close();
    }
  }

  Future<List<Json>> manifest() async {
    if (!await root.exists()) return [];
    final items = <Json>[];
    await for (final f in root.list()) {
      final hash = f.uri.pathSegments.last;
      if (f is File && hashPattern.hasMatch(hash) && await complete(hash)) {
        items.add({'hash': hash, 'size': await f.length()});
      }
    }
    items.sort((a, b) => (a['hash'] as String).compareTo(b['hash'] as String));
    return items;
  }
}
