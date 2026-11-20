import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:loro_crdt/loro_crdt.dart';

import '../domain/bible.dart';
import '../domain/entry.dart';
import '../domain/collaborative_entry.dart';
import 'vault_files.dart';
import 'vault_snapshot.dart';

class VaultConflict implements Exception {
  const VaultConflict(this.message);
  final String message;
  @override
  String toString() => message;
}

class VaultRepository {
  static const formatMarker =
      '{"format":"mosterdzaad-requires-v2","version":2,"message":"Open dit studieboek met Mosterdzaad 0.3 of nieuwer."}\n';
  static Future<void>? _runtime;
  static bool _runtimeReady = false;
  VaultRepository(this.files, this.bible);
  final VaultFiles files;
  final Bible bible;
  String id = '', name = '';
  List<Entry> history = [];
  Map<String, List<Entry>> heads = {};
  Map<String, List<Entry>> causalHeads = {};
  List<List<Entry>> _conflicts = [];
  String actor = const Uuid().v4();
  List<String> warnings = [];
  Map<String, String> _fingerprints = {};
  Map<String, String> _recordContents = {};
  Future<void> _queue = Future.value();
  List<Entry> get entries =>
      heads.values
          .where((v) => v.length == 1 && !v.first.deleted)
          .map((v) => v.first)
          .toList()
        ..sort((a, b) => b.updated.compareTo(a.updated));
  List<List<Entry>> get conflicts => _conflicts;
  String get scheme =>
      heads[id]?.firstOrNull?.text('versification') ?? 'english';
  bool get extra =>
      entries
              .where((e) => e.kind == 'preferences')
              .firstOrNull
              ?.data['deuterocanonical']
          as bool? ??
      false;
  List<Entry> ofKind(String kind) =>
      entries.where((e) => e.kind == kind).toList();
  // History also fixes the scheme: old versions must retain their meaning.
  bool get hasPassages => history.any(
    (e) =>
        e.passages.isNotEmpty ||
        e.sessions.any((s) => (s['passages'] as List).isNotEmpty),
  );

  static Future<VaultRepository> create(
    VaultFiles files,
    Bible bible,
    String name,
    String scheme,
    bool extra,
  ) async {
    if (name.trim().isEmpty || name.length > 100) {
      throw const FormatException(
        'Geef je studieboek een naam van maximaal 100 tekens.',
      );
    }
    if (await files.read('mosterdzaad.json') != null) {
      throw const FormatException(
        'Deze map bevat al een studieboek. Open het bestaande studieboek.',
      );
    }
    final repo = VaultRepository(files, bible)
      ..id = const Uuid().v4()
      ..name = name.trim();
    await files.makeDirectory('records');
    await files.writeNew(
      'mosterdzaad.json',
      '${jsonEncode({'format': 'mosterdzaad-studybook', 'version': 1, 'id': repo.id, 'name': repo.name, 'created': DateTime.now().toUtc().toIso8601String()})}\n',
    );
    await repo.reload();
    await repo.save('preferences', {
      'versification': scheme,
      'deuterocanonical': extra,
    }, entityId: repo.id);
    return repo;
  }

  Future<void> reload() async {
    // Do not retain a completed Future from a different widget-test zone.
    // Concurrent first opens still share the same initialization.
    if (!_runtimeReady) {
      try {
        await (_runtime ??= initLoro());
        _runtimeReady = true;
      } finally {
        _runtime = null;
      }
    }
    final manifest = await files.read('mosterdzaad.json');
    if (manifest == null) {
      throw const FormatException(
        'Deze map is geen Mosterdzaad-studieboek. Selecteer de map met mosterdzaad.json.',
      );
    }
    final j = jsonDecode(manifest) as Map;
    if (j['format'] != 'mosterdzaad-studybook' ||
        j['version'] != 1 ||
        j['id'] is! String ||
        !uuidPattern.hasMatch(j['id'] as String) ||
        j['name'] is! String) {
      throw const FormatException(
        'Dit studieboekformaat wordt niet ondersteund.',
      );
    }
    if (id.isNotEmpty && j['id'] != id) {
      throw const VaultConflict(
        'De map bevat inmiddels een ander studieboek. Open het opnieuw.',
      );
    }
    final records = <Entry>[];
    final problems = <String>[];
    final prints = <String, String>{};
    final sources = <String, String>{};
    final names = await files.list('records');
    if (names.length > 300001) {
      throw const FormatException(
        'Dit studieboek bevat te veel revisiebestanden.',
      );
    }
    for (final filename in names.where(
      (f) =>
          f != 'format-v2.json' && (f.endsWith('.md') || f.endsWith('.json')),
    )) {
      try {
        final contents = await files.read('records/$filename');
        if (contents == null) {
          throw const FormatException('Bestand verdwenen tijdens openen.');
        }
        final entry = Entry.decode(contents, filename);
        if (entry.kind == 'preferences' && entry.id != j['id']) {
          throw const FormatException('Ongeldige instellingen-ID.');
        }
        records.add(entry);
        sources['records/${entry.filename}'] = contents;
        prints[entry.revision] = sha256
            .convert(utf8.encode(contents))
            .toString();
      } catch (e) {
        // Denied access is not an empty studybook. Propagate I/O failures.
        if (e is! FormatException && e is! TypeError) rethrow;
        problems.add(
          '$filename: onvolledig of ongeldig. Het bestand is behouden.',
        );
      }
    }
    // A commit marker publishes a complete record. Crashes during either
    // write leave an unpublished attempt; retries use a fresh attempt ID.
    // This works even on providers (Android SAF) without atomic file rename.
    for (final marker in names.where((f) => f.endsWith('.commit'))) {
      final text = await files.read('records/$marker');
      Map commit;
      try {
        commit = jsonDecode(text ?? '') as Map;
      } on FormatException {
        continue;
      } // Incomplete marker was never committed.
      if (commit['version'] != 2 ||
          commit['attempt'] != marker.replaceFirst('.commit', '') ||
          !uuidPattern.hasMatch(commit['attempt'] as String? ?? '')) {
        throw const FormatException('Ongeldig lokaal wijzigingenlogboek.');
      }
      final contents = await files.read('records/${commit['attempt']}.pending');
      if (contents == null ||
          sha256.convert(utf8.encode(contents)).toString() != commit['hash']) {
        throw const FormatException(
          'Een bevestigde lokale wijziging is beschadigd.',
        );
      }
      final entry = Entry.decode(contents, commit['filename'] as String);
      final path = 'records/${entry.filename}';
      if (sources.containsKey(path)) {
        if (sources[path] != contents) {
          throw const FormatException('Botsende lokale revisies.');
        }
        continue;
      }
      records.add(entry);
      sources[path] = contents;
      prints[entry.revision] = entry.fileFingerprint!;
    }
    final candidateHeads = revisionHeads(records);
    final prefs = candidateHeads[j['id']];
    if (prefs != null &&
        prefs.map((e) => e.text('versification')).toSet().length > 1) {
      throw const VaultConflict(
        'De kopieën gebruiken verschillende versindelingen. Synchronisatie is gestopt; kies op beide apparaten dezelfde indeling voordat je verdergaat.',
      );
    }
    final currentScheme = prefs?.first.text('versification') ?? 'english';
    final types = <String, String>{};
    final byRevision = {for (final r in records) r.revision: r};
    for (final record in records) {
      if (!record.deleted) {
        validateData(record.kind, record.data, bible, currentScheme);
      }
      if (types.containsKey(record.id) && types[record.id] != record.kind) {
        throw const FormatException('Een record verandert van type.');
      }
      types[record.id] = record.kind;
      for (final parent in record.parents) {
        if (!byRevision.containsKey(parent) ||
            byRevision[parent]!.id != record.id) {
          throw const FormatException(
            'Er ontbreken eerdere revisies in het studieboek.',
          );
        }
      }
    }
    if (candidateHeads.values.any((h) => h.isEmpty)) {
      throw const FormatException('Ongeldige revisiegeschiedenis.');
    }
    final ordered = orderedRecords(records);
    final projected = <String, List<Entry>>{};
    final metadataConflicts = <List<Entry>>[];
    for (final pair in candidateHeads.entries) {
      final entityRecords = ordered.where((e) => e.id == pair.key).toList();
      final collaboration = CollaborativeEntry(entityRecords);
      final entry = collaboration.project(pair.value);
      // Tombstones retain possibly incomplete historical data for recovery.
      if (!entry.deleted) {
        validateData(entry.kind, entry.data, bible, currentScheme);
      }
      projected[pair.key] = [entry];
      if (pair.value.length > 1) {
        metadataConflicts.addAll(collaboration.conflicts(pair.value, entry));
      }
    }
    id = j['id'] as String;
    name = j['name'] as String;
    history = records;
    causalHeads = candidateHeads;
    heads = projected;
    _conflicts = metadataConflicts;
    warnings = problems;
    _fingerprints = prints;
    _recordContents = sources;
  }

  Future<void> _publish(Entry entry, String contents) async {
    // v1 clients treat this as an unsupported record and refuse to write/sync.
    // No existing manifest or user record needs an unsafe in-place migration.
    if (await files.read('records/format-v2.json') == null) {
      await files.writeNew('records/format-v2.json', formatMarker);
    }
    final attempt = const Uuid().v4();
    final pending = 'records/$attempt.pending';
    await files.writeNew(pending, contents);
    if (await files.read(pending) != contents) {
      throw const VaultConflict(
        'De wijziging kon niet volledig worden opgeslagen. Je invoer blijft behouden.',
      );
    }
    final marker = jsonEncode({
      'version': 2,
      'attempt': attempt,
      'filename': entry.filename,
      'hash': sha256.convert(utf8.encode(contents)).toString(),
    });
    await files.writeNew('records/$attempt.commit', marker);
    if (await files.read('records/$attempt.commit') != marker) {
      throw const VaultConflict(
        'De lokale opslag heeft de wijziging niet bevestigd.',
      );
    }
  }

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<VaultSnapshot> _snapshot() async {
    await reload();
    if (warnings.isNotEmpty) {
      throw const VaultConflict(
        'Herstel eerst de onvolledige bestanden voordat je synchroniseert of exporteert.',
      );
    }
    final data = <String, String>{
      'mosterdzaad.json': (await files.read('mosterdzaad.json'))!,
    };
    for (final e in history) {
      final path = 'records/${e.filename}';
      final text = _recordContents[path];
      if (text == null) {
        throw const VaultConflict(
          'Een bestand is tijdens het lezen verdwenen.',
        );
      }
      data[path] = text;
    }
    final snapshot = VaultSnapshot(data);
    await snapshot.validate(bible);
    return snapshot;
  }

  Future<VaultSnapshot> snapshot() => _exclusive(_snapshot);

  Future<VaultSnapshot> mergeSnapshot(VaultSnapshot incoming) =>
      _exclusive(() async {
        final remote = await incoming.validate(bible);
        final local = await _snapshot();
        final merged = local.union(incoming);
        final candidate = await merged.validate(bible);
        if ((hasPassages && candidate.scheme != scheme) ||
            (remote.hasPassages && candidate.scheme != remote.scheme)) {
          throw const VaultConflict(
            'De kopieën gebruiken verschillende versindelingen. De gegevens zijn behouden; synchroniseer alleen studieboeken met dezelfde indeling.',
          );
        }
        merged.encode(); // Check size before changing local files.
        for (final e in orderedRecords(candidate.history)) {
          final path = 'records/${e.filename}';
          if (local.contents.containsKey(path)) continue;
          final existing = _recordContents[path];
          if (existing != null && existing != merged.contents[path]) {
            throw const VaultConflict(
              'Het studieboek is tijdens synchronisatie gewijzigd. Probeer opnieuw.',
            );
          }
          if (existing == null) await _publish(e, merged.contents[path]!);
        }
        return _snapshot();
      });

  Future<Entry> save(
    String kind,
    Map<String, dynamic> data, {
    String? entityId,
    List<String> expected = const [],
    Map<String, String>? expectedHashes,
    bool deleted = false,
  }) {
    final beforePrints =
        expectedHashes ?? Map<String, String>.from(_fingerprints);
    final result = _queue.then((_) async {
      await reload();
      if (warnings.isNotEmpty) {
        throw const VaultConflict(
          'Er zijn onvolledige bestanden. Herstel deze eerst; je invoer blijft in dit venster staan.',
        );
      }
      final targetId = entityId ?? const Uuid().v4();
      if (!uuidPattern.hasMatch(targetId) ||
          !entryKinds.contains(kind) ||
          (kind == 'preferences' && (targetId != id || deleted))) {
        throw const FormatException('Ongeldige record-identiteit.');
      }
      final current = causalHeads[targetId] ?? [];
      final actual = current.map((e) => e.revision).toSet();
      final known = history
          .where((e) => e.id == targetId)
          .map((e) => e.revision)
          .toSet();
      if (!known.containsAll(expected) ||
          (actual.isNotEmpty && expected.isEmpty) ||
          expected.any((r) => beforePrints[r] != _fingerprints[r])) {
        throw const VaultConflict(
          'Dit onderdeel is elders gewijzigd. Je tekst is nog aanwezig. Kopieer je tekst en open de nieuwste versie voordat je opslaat.',
        );
      }
      if (kind == 'preferences' &&
          hasPassages &&
          data['versification'] != scheme) {
        throw const FormatException(
          'De versindeling staat vast zodra er passages zijn opgeslagen.',
        );
      }
      if (deleted &&
          kind == 'group' &&
          ofKind('study').any((e) => e.data['group'] == targetId)) {
        throw const FormatException(
          'Deze groep wordt nog gebruikt door een studie.',
        );
      }
      if (!deleted) {
        validateData(
          kind,
          data,
          bible,
          kind == 'preferences' ? data['versification'] as String : scheme,
        );
        if (['theme', 'group'].contains(kind) &&
            ofKind(kind).any(
              (e) =>
                  e.id != targetId &&
                  e.text('name').toLowerCase() ==
                      (data['name'] as String).trim().toLowerCase(),
            )) {
          throw const FormatException('Deze naam bestaat al.');
        }
        for (final pair in {
          'themes': 'theme',
          'plans': 'plan',
          'studies': 'study',
        }.entries) {
          for (final link in data[pair.key] as List? ?? []) {
            if (!ofKind(pair.value).any((e) => e.id == link)) {
              throw const FormatException(
                'Een gekoppeld onderdeel is verwijderd of heeft een conflict.',
              );
            }
          }
        }
        if (kind == 'study' &&
            data['kind'] == 'group' &&
            !ofKind('group').any((e) => e.id == data['group'])) {
          throw const FormatException('Kies een bestaande groep.');
        }
      }
      final revision = const Uuid().v4();
      final collaborative = CollaborativeEntry(
        orderedRecords(history).where((e) => e.id == targetId).toList(),
      );
      final record = Entry(
        id: targetId,
        revision: revision,
        parents: expected,
        kind: kind,
        data: Map<String, dynamic>.from(jsonDecode(jsonEncode(data)) as Map),
        updated: DateTime.now().toUtc(),
        deleted: deleted,
        crdt: base64Encode(collaborative.edit(revision, expected, data)),
        actor: actor,
        created: heads[targetId]?.first.created ?? DateTime.now().toUtc(),
      );
      final encoded = record.encode();
      await _publish(record, encoded);
      await reload();
      return record;
    });
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
