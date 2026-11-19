import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../domain/bible.dart';
import '../domain/entry.dart';
import 'vault_repository.dart';
import 'vault_types.dart';

/// One atomic Dropbox object / portable backup. Only canonical studybook data.
/// SQLite, folder permissions and OAuth credentials are never included.
class VaultSnapshot implements VaultFiles {
  VaultSnapshot(Map<String, String> files) : contents = Map.unmodifiable(files);
  static const maxBytes = 20 * 1024 * 1024;
  final Map<String, String> contents;
  Map get manifest => jsonDecode(contents['mosterdzaad.json']!) as Map;
  String get id => manifest['id'] as String;
  String get name => manifest['name'] as String;
  @override
  VaultLocation get location =>
      const VaultLocation('snapshot', '', 'Reservekopie');

  String encode() {
    final keys = contents.keys.toList()..sort();
    final value = jsonEncode({
      'format': 'mosterdzaad-snapshot',
      'version': 1,
      'files': {for (final key in keys) key: contents[key]},
    });
    if (utf8.encode(value).length > maxBytes) {
      throw const FormatException(
        'Dit studieboek is groter dan de synchronisatielimiet van 20 MB. Je lokale gegevens zijn behouden.',
      );
    }
    return value;
  }

  factory VaultSnapshot.decode(String value) {
    if (utf8.encode(value).length > maxBytes) {
      throw const FormatException('De reservekopie is groter dan 20 MB.');
    }
    final json = jsonDecode(value);
    if (json is! Map ||
        json['format'] != 'mosterdzaad-snapshot' ||
        json['version'] != 1 ||
        json['files'] is! Map) {
      throw const FormatException(
        'Geen ondersteunde Mosterdzaad-reservekopie.',
      );
    }
    final files = <String, String>{};
    final recordPath = RegExp(r'^records/[0-9a-f-]{36}\.(md|json)$');
    for (final e in (json['files'] as Map).entries) {
      if (e.key is! String ||
          e.value is! String ||
          (e.key != 'mosterdzaad.json' &&
              !recordPath.hasMatch(e.key as String)) ||
          utf8.encode(e.value as String).length > 8 * 1024 * 1024) {
        throw const FormatException('Ongeldig bestand in de reservekopie.');
      }
      files[e.key as String] = e.value as String;
    }
    if (!files.containsKey('mosterdzaad.json') || files.length > 100001) {
      throw const FormatException('Onvolledige of te grote reservekopie.');
    }
    return VaultSnapshot(files);
  }

  Future<VaultRepository> validate(Bible bible) async {
    final repo = VaultRepository(this, bible);
    await repo.reload();
    if (repo.warnings.isNotEmpty ||
        repo.heads[repo.id] == null ||
        repo.heads[repo.id]!.any((e) => e.deleted || e.kind != 'preferences')) {
      throw const FormatException(
        'De reservekopie bevat onvolledige of ongeldige gegevens.',
      );
    }
    orderedRecords(
      repo.history,
    ); // Detect cycles, including cycles hidden behind a head.
    return repo;
  }

  VaultSnapshot union(VaultSnapshot other) {
    if (id != other.id) {
      throw const FormatException('Dit is een ander studieboek.');
    }
    final combined = {...contents};
    for (final e in other.contents.entries) {
      if (combined.containsKey(e.key) && combined[e.key] != e.value) {
        throw const VaultConflict(
          'Een bestaand revisiebestand is buiten de app gewijzigd. Synchronisatie is gestopt; beide kopieën zijn behouden.',
        );
      }
      combined[e.key] = e.value;
    }
    return VaultSnapshot(combined);
  }

  /// Copy a complete local history into a different book without reusing IDs
  /// or modifying the source. Its v1 representation is deterministically
  /// converted to Loro on read. This is an explicit merge/restore operation.
  Future<VaultSnapshot> copyInto(VaultSnapshot target, Bible bible) async {
    final source = await validate(bible),
        destination = await target.validate(bible);
    if (source.scheme != destination.scheme && source.hasPassages) {
      throw const FormatException(
        'Deze studieboeken gebruiken verschillende versindelingen. Open ze afzonderlijk.',
      );
    }
    final entities = {for (final e in source.history) e.id: const Uuid().v4()};
    final revisions = {
      for (final e in source.history) e.revision: const Uuid().v4(),
    };
    final files = Map<String, String>.from(target.contents);
    for (final e in orderedRecords(source.history)) {
      if (e.kind == 'preferences') continue;
      final data = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(e.data)) as Map,
      );
      for (final field in ['themes', 'plans', 'studies']) {
        if (data[field] is List) {
          data[field] = (data[field] as List)
              .map((id) => entities[id] ?? id)
              .toList();
        }
      }
      if (data['group'] is String) {
        data['group'] = entities[data['group']] ?? data['group'];
      }
      final copy = Entry(
        id: entities[e.id]!,
        revision: revisions[e.revision]!,
        parents: e.parents.map((p) => revisions[p]!).toList(),
        kind: e.kind,
        data: data,
        updated: e.updated,
        created: e.created,
        deleted: e.deleted,
      );
      files['records/${copy.filename}'] = copy.encode();
    }
    final result = VaultSnapshot(files);
    await result.validate(bible);
    return result;
  }

  Future<VaultSnapshot> separateCopy(Bible bible) async {
    final source = await validate(bible), id = const Uuid().v4();
    final prefs = Entry(
      id: id,
      revision: const Uuid().v4(),
      parents: [],
      kind: 'preferences',
      data: {'versification': source.scheme, 'deuterocanonical': source.extra},
      updated: DateTime.now().toUtc(),
    );
    return copyInto(
      VaultSnapshot({
        'mosterdzaad.json': jsonEncode({
          ...manifest,
          'id': id,
          'name': '$name — hersteld',
          'created': DateTime.now().toUtc().toIso8601String(),
        }),
        'records/${prefs.filename}': prefs.encode(),
      }),
      bible,
    );
  }

  Future<void> restoreTo(VaultFiles target, Bible bible) async {
    final repo = await validate(bible);
    if (await target.read('mosterdzaad.json') != null) {
      throw const FormatException('Herstel in een nieuwe studieboekmap.');
    }
    await target.makeDirectory('records');
    for (final e in orderedRecords(repo.history)) {
      final path = 'records/${e.filename}';
      await target.writeNew(path, contents[path]!);
    }
    // Publish the manifest last so an interrupted import is never a usable book.
    await target.writeNew('mosterdzaad.json', contents['mosterdzaad.json']!);
  }

  @override
  Future<List<String>> list(String directory) async => contents.keys
      .where((k) => k.startsWith('$directory/'))
      .map((k) => k.substring(directory.length + 1))
      .toList();
  @override
  Future<String?> read(String name) async => contents[name];
  @override
  Future<void> writeNew(String name, String contents) async =>
      throw UnsupportedError('Read-only snapshot');
  @override
  Future<void> makeDirectory(String name) async =>
      throw UnsupportedError('Read-only snapshot');
}

List<Entry> orderedRecords(List<Entry> entries) {
  final byId = {for (final e in entries) e.revision: e};
  final remaining = {
    for (final e in entries) e.revision: e.parents.toSet().length,
  };
  final children = <String, List<String>>{};
  for (final e in entries) {
    for (final parent in e.parents.toSet()) {
      (children[parent] ??= []).add(e.revision);
    }
  }
  final ready = entries.where((e) => e.parents.isEmpty).toList();
  final result = <Entry>[];
  for (var i = 0; i < ready.length; i++) {
    final e = ready[i];
    result.add(e);
    for (final child in children[e.revision] ?? <String>[]) {
      remaining[child] = remaining[child]! - 1;
      if (remaining[child] == 0) ready.add(byId[child]!);
    }
  }
  if (result.length != entries.length || byId.length != entries.length) {
    throw const FormatException('Ongeldige revisiegeschiedenis.');
  }
  return result;
}
