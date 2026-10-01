import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'lab_store.dart';
import 'maintenance_domain.dart';
import 'model.dart';
import 'procedure_library.dart';

const _libraryKey = 'procedureLibrary';
const _maxDrafts = 10000;
const _maxReceipts = 100000;
final _identity = RegExp(r'^[a-zA-Z0-9_-]{1,100}$');

Never _invalid(String message) => throw StateError(message);

Json _map(dynamic value, String label) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    _invalid('Invalid $label.');
  }
  return Map<String, dynamic>.from(value);
}

void _shape(Json value, Set<String> keys, String label) {
  if (value.keys.toSet().difference(keys).isNotEmpty ||
      keys.difference(value.keys.toSet()).isNotEmpty) {
    _invalid('Unsupported $label shape.');
  }
}

void _id(dynamic value, String label) {
  if (value is! String || !_identity.hasMatch(value)) {
    _invalid('Invalid $label identity.');
  }
}

void _revision(dynamic value) {
  if (value is! int || value < 1 || value > 1000000) {
    _invalid('Invalid expected procedure draft revision.');
  }
}

List<Json> _rows(dynamic value, String label, int limit) {
  if (value is! List || value.length > limit) _invalid('Invalid $label.');
  return value.map((row) => _map(row, label)).toList();
}

Json _copy(Json value) {
  try {
    return jsonDecode(jsonEncode(value)) as Json;
  } catch (_) {
    _invalid('Invalid procedure library command data.');
  }
}

// Results belong to the caller, but neither historical receipts nor any nested
// saved source/step may be changed through a result or the draft-list getter.
dynamic _immutable(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable({
      for (final entry in value.entries)
        entry.key as String: _immutable(entry.value),
    });
  }
  if (value is List) return List<dynamic>.unmodifiable(value.map(_immutable));
  return value;
}

Json _emptyLibrary() => {
  'version': 1,
  'drafts': <Json>[],
  'receipts': <Json>[],
};

void _arguments(String command, Json arguments) {
  switch (command) {
    case 'copy':
      _shape(arguments, {'publicationId'}, 'procedure copy arguments');
      _id(arguments['publicationId'], 'source publication');
    case 'save':
      _shape(arguments, {
        'draftId',
        'expectedRevision',
        'title',
        'items',
      }, 'procedure save arguments');
      _id(arguments['draftId'], 'procedure draft');
      _revision(arguments['expectedRevision']);
      if (arguments['title'] is! String ||
          (arguments['title'] as String).length > 200) {
        _invalid('Invalid procedure draft title.');
      }
      _rows(arguments['items'], 'procedure steps', 200);
    case 'publish':
      _shape(arguments, {
        'draftId',
        'expectedRevision',
      }, 'procedure publication arguments');
      _id(arguments['draftId'], 'procedure draft');
      _revision(arguments['expectedRevision']);
    default:
      _invalid('Unsupported procedure library command.');
  }
}

Json _currentDraft(Map<String, Json> drafts, Json arguments) {
  final draft = drafts[arguments['draftId']];
  if (draft == null) _invalid('Procedure draft not found.');
  if (draft['revision'] != arguments['expectedRevision']) {
    _invalid(
      'This draft changed since you opened it. Reload the saved draft before saving or publishing.',
    );
  }
  return draft;
}

Map<String, Json> _draftsById(List<Json> drafts) => {
  for (final draft in drafts) draft['id'] as String: draft,
};

/// Validate the complete durable history rather than trusting a hash alone.
/// A receipt binds its exact arguments/result, and replaying those receipts must
/// produce the stored draft state and every finalized immutable publication.
void _validateLibrary(Json library, Json? catalog) {
  _shape(library, {'version', 'drafts', 'receipts'}, 'procedure library');
  if (library['version'] is! int || library['version'] != 1) {
    _invalid('Unsupported procedure library version.');
  }
  final drafts = _rows(library['drafts'], 'procedure drafts', _maxDrafts);
  final receipts = _rows(
    library['receipts'],
    'procedure receipts',
    _maxReceipts,
  );
  for (final draft in drafts) {
    validateProcedureDraft(draft);
  }
  if (drafts.map((draft) => draft['id']).toSet().length != drafts.length) {
    _invalid('Duplicate procedure draft identity.');
  }
  if (catalog == null && (drafts.isNotEmpty || receipts.isNotEmpty)) {
    _invalid('Procedure library has no company catalog.');
  }
  final publications = <String, Json>{
    if (catalog != null)
      for (final row in catalog['templates'] as List)
        (row as Json)['id'] as String: row,
  };
  final reconstructed = <String, Json>{};
  final operationIds = <String>{};
  final publishedIds = <String>{};
  for (final receipt in receipts) {
    _shape(receipt, {
      'operationId',
      'command',
      'arguments',
      'result',
      'hash',
    }, 'procedure receipt');
    _id(receipt['operationId'], 'procedure operation');
    if (!operationIds.add(receipt['operationId'] as String)) {
      _invalid('Duplicate procedure operation identity.');
    }
    final unhashed = {...receipt}..remove('hash');
    if (receipt['hash'] is! String ||
        !hashPattern.hasMatch(receipt['hash']) ||
        receipt['hash'] != contentHash(unhashed)) {
      _invalid('The procedure receipt failed its integrity check.');
    }
    if (receipt['command'] is! String) {
      _invalid('Invalid procedure receipt command.');
    }
    final command = receipt['command'] as String;
    final arguments = _map(receipt['arguments'], 'procedure receipt arguments');
    final result = _map(receipt['result'], 'procedure receipt result');
    _arguments(command, arguments);
    switch (command) {
      case 'copy':
        validateProcedureDraft(result);
        final publication = publications[arguments['publicationId']];
        if (publication == null || reconstructed.containsKey(result['id'])) {
          _invalid('The procedure copy receipt has no unique source or draft.');
        }
        final expected = copiedProcedureDraft(
          draftId: result['id'] as String,
          publication: publication,
          itemIds: [
            for (final item in result['items'] as List)
              (item as Json)['id'] as String,
          ],
        );
        if (canonical(result) != canonical(expected)) {
          _invalid('The procedure copy receipt differs from its source.');
        }
        reconstructed[result['id'] as String] = result;
      case 'save':
        final previous = _currentDraft(reconstructed, arguments);
        final expected = editedProcedureDraft(
          previous,
          title: arguments['title'] as String,
          items: _rows(arguments['items'], 'procedure steps', 200),
        );
        if (canonical(result) != canonical(expected)) {
          _invalid('The procedure save receipt differs from its command.');
        }
        reconstructed[previous['id'] as String] = result;
      case 'publish':
        final previous = _currentDraft(reconstructed, arguments);
        _id(result['id'], 'published checklist');
        final expected = publicationFromProcedureDraft(
          previous,
          publicationId: result['id'] as String,
        );
        if (canonical(result) != canonical(expected) ||
            canonical(publications[result['id']]) != canonical(expected) ||
            !publishedIds.add(result['id'] as String)) {
          _invalid(
            'The procedure publication receipt differs from its catalog.',
          );
        }
        reconstructed[previous['id'] as String] = {
          ...previous,
          'publishedTemplateId': result['id'],
        };
    }
  }
  if (canonical(_draftsById(drafts)) != canonical(reconstructed)) {
    _invalid('Procedure drafts differ from their durable operation history.');
  }
}

/// Office drafts and retry receipts are private settings. The existing complete
/// office backup includes them; the existing public catalog/bundle does not.
extension ProcedureLibraryStore on LabStore {
  List<Json> get procedureDrafts {
    requireOffice();
    final next = _procedureCatalog();
    final library = _procedureLibrary(next);
    return List<Json>.unmodifiable([
      for (final draft in library['drafts'] as List) _immutable(draft) as Json,
    ]);
  }

  Future<Json> copyProcedureDraft(
    String publicationId, {
    required String operationId,
  }) =>
      _procedureCommand('copy', {'publicationId': publicationId}, operationId);

  Future<Json> saveProcedureDraft({
    required String draftId,
    required int expectedRevision,
    required String title,
    required List<Json> items,
    required String operationId,
  }) => _procedureCommand('save', {
    'draftId': draftId,
    'expectedRevision': expectedRevision,
    'title': title,
    'items': items,
  }, operationId);

  Future<Json> publishProcedureDraft({
    required String draftId,
    required int expectedRevision,
    required String operationId,
  }) => _procedureCommand('publish', {
    'draftId': draftId,
    'expectedRevision': expectedRevision,
  }, operationId);

  Json? _procedureCatalog() {
    final saved = setting('catalog');
    if (saved == null) return null;
    final next = _map(saved, 'company catalog');
    validateCatalog(next);
    return next;
  }

  Json _procedureLibrary(Json? next) {
    dynamic saved;
    try {
      saved = setting(_libraryKey);
    } on FormatException {
      _invalid('Invalid saved procedure library.');
    }
    if (saved == null) {
      // Distinguish a genuinely absent new setting from malformed JSON null.
      if (db.select('SELECT key FROM settings WHERE key=?', [
        _libraryKey,
      ]).isNotEmpty) {
        _invalid('Invalid saved procedure library.');
      }
      return _emptyLibrary();
    }
    final library = _map(saved, 'procedure library');
    _validateLibrary(library, next);
    return library;
  }

  Future<Json> _procedureCommand(
    String command,
    Json commandArguments,
    String operationId,
  ) {
    // Capture mutable editor input now, before it waits behind another command.
    final arguments = _copy(commandArguments);
    return queue.run(() async {
      requireOffice();
      late Json result;
      transaction(() {
        final next = _procedureCatalog();
        final library = _procedureLibrary(next);
        _id(operationId, 'procedure operation');
        _arguments(command, arguments);
        final receipts = library['receipts'] as List;
        final previous = receipts
            .where((row) => row['operationId'] == operationId)
            .firstOrNull;
        if (previous != null) {
          if (previous['command'] != command ||
              canonical(previous['arguments']) != canonical(arguments)) {
            _invalid(
              'This operation identity was already used with different procedure inputs. Retry with a new operation identity.',
            );
          }
          // Historical results remain exact even after later draft revisions or
          // finalization. A replay must precede all stale/current-state checks.
          result = _immutable(previous['result']) as Json;
          return;
        }
        if (next == null) _invalid('Create a company first.');
        final drafts = _rows(library['drafts'], 'procedure drafts', _maxDrafts);
        final byId = _draftsById(drafts);
        late Json eventData;
        switch (command) {
          case 'copy':
            final publication = (next['templates'] as List)
                .where((row) => row['id'] == arguments['publicationId'])
                .firstOrNull;
            if (publication == null) _invalid('Published procedure not found.');
            result = copiedProcedureDraft(
              draftId: const Uuid().v4(),
              publication: publication as Json,
              itemIds: [
                for (final _ in publication['items'] as List) const Uuid().v4(),
              ],
            );
            drafts.add(result);
            eventData = {
              'draftId': result['id'],
              'sourcePublicationId': publication['id'],
              'revision': result['revision'],
            };
          case 'save':
            final draft = _currentDraft(byId, arguments);
            result = editedProcedureDraft(
              draft,
              title: arguments['title'] as String,
              items: _rows(arguments['items'], 'procedure steps', 200),
            );
            drafts[drafts.indexOf(draft)] = result;
            eventData = {
              'draftId': result['id'],
              'revision': result['revision'],
            };
          case 'publish':
            final draft = _currentDraft(byId, arguments);
            result = publicationFromProcedureDraft(
              draft,
              publicationId: const Uuid().v4(),
            );
            (next['templates'] as List).add(result);
            drafts[drafts.indexOf(draft)] = {
              ...draft,
              'publishedTemplateId': result['id'],
            };
            eventData = {
              'draftId': draft['id'],
              'revision': draft['revision'],
              'publicationId': result['id'],
              'hash': result['hash'],
            };
        }
        final receipt = <String, dynamic>{
          'operationId': operationId,
          'command': command,
          'arguments': arguments,
          'result': _copy(result),
        };
        receipt['hash'] = contentHash(receipt);
        receipts.add(receipt);
        library['drafts'] = drafts;
        validateCatalog(next);
        _validateLibrary(library, next);
        setSetting(_libraryKey, library);
        if (command == 'publish') setSetting('catalog', next);
        event(
          'procedure-draft-${switch (command) {
            'copy' => 'copied',
            'save' => 'saved',
            _ => 'published',
          }}',
          {...eventData, 'operationId': operationId},
        );
        result = _immutable(result) as Json;
      });
      return result;
    });
  }
}
