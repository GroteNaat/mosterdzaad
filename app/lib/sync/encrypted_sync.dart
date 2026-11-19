import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:uuid/uuid.dart';

import '../domain/bible.dart';
import '../domain/entry.dart';
import '../storage/vault_repository.dart';
import '../storage/vault_snapshot.dart';
import 'canonical.dart';
import 'crypto_box.dart';
import 'encrypted_cloud.dart';
import 'local_state.dart';

String digest(List<int> bytes) => sha256.convert(bytes).toString();
Uint8List wire(Object? value) =>
    Uint8List.fromList(utf8.encode(canonicalJson(value)));

class SyncJournal {
  SyncJournal(this.dataset, this.actor);
  final String dataset, actor;
  String cursor = '', envelopeHash = '';
  int generation = 0, operationsSinceBackup = 0;
  DateTime? lastSuccess, lastBackup;
  int snapshotEveryOperations = 100,
      snapshotEveryHours = 24,
      retainSnapshots = 7;
  final objects = <String, CloudItem>{};
  final acknowledged =
      <String, String>{}; // operation -> canonical plaintext hash
  final outbox = <String, String>{}; // exact ciphertext persisted before upload
  final verifiedSnapshots = <String, Map<String, dynamic>>{};
  Map<String, dynamic> toJson() => {
    'version': 2,
    'dataset': dataset,
    'actor': actor,
    'cursor': cursor,
    'envelopeHash': envelopeHash,
    'generation': generation,
    'operationsSinceBackup': operationsSinceBackup,
    'lastSuccess': lastSuccess?.toIso8601String(),
    'lastBackup': lastBackup?.toIso8601String(),
    'snapshotEveryOperations': snapshotEveryOperations,
    'snapshotEveryHours': snapshotEveryHours,
    'retainSnapshots': retainSnapshots,
    'objects': {for (final e in objects.entries) e.key: e.value.toJson()},
    'acknowledged': acknowledged,
    'outbox': outbox,
    'verifiedSnapshots': verifiedSnapshots,
  };
  factory SyncJournal.decode(String source) {
    final j = jsonDecode(source) as Map;
    if (j['version'] != 2) {
      throw const FormatException('Onbekende synchronisatiestatus.');
    }
    return SyncJournal(j['dataset'] as String, j['actor'] as String)
      ..cursor = j['cursor'] as String
      ..envelopeHash = j['envelopeHash'] as String
      ..generation = j['generation'] as int
      ..operationsSinceBackup = j['operationsSinceBackup'] as int
      ..lastSuccess = DateTime.tryParse(j['lastSuccess'] as String? ?? '')
      ..lastBackup = DateTime.tryParse(j['lastBackup'] as String? ?? '')
      ..snapshotEveryOperations = j['snapshotEveryOperations'] as int
      ..snapshotEveryHours = j['snapshotEveryHours'] as int
      ..retainSnapshots = j['retainSnapshots'] as int
      ..objects.addAll(
        (j['objects'] as Map).map(
          (k, v) => MapEntry(k as String, CloudItem.fromJson(v as Map)),
        ),
      )
      ..acknowledged.addAll(Map<String, String>.from(j['acknowledged'] as Map))
      ..outbox.addAll(Map<String, String>.from(j['outbox'] as Map))
      ..verifiedSnapshots.addAll(
        (j['verifiedSnapshots'] as Map? ?? {}).map(
          (k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map)),
        ),
      );
  }
}

class RestorePoint {
  RestorePoint(this.id, this.created, this.snapshot, this.covered);
  final String id;
  final DateTime created;
  final VaultSnapshot snapshot;
  final Map<String, String> covered;
}

/// One serialized coordinator per open book. Records are durable operations;
/// snapshots contain the complete causal history (never shallow/GC'd), so an
/// arbitrarily old device can merge them and replay its own pending edits.
class EncryptedSync {
  EncryptedSync(
    this.cloud,
    this.crypto,
    this.stateStore,
    this.secrets,
    this.bible,
  );
  final EncryptedCloud cloud;
  final CryptoBox crypto;
  final LocalStateStore stateStore;
  final SecretStore secrets;
  final Bible bible;
  String root(String dataset) => '/v2/$dataset';
  String keyPath(String dataset) => '${root(dataset)}/key.enc';
  String changePath(String dataset, String op) =>
      '${root(dataset)}/changes/$op.enc';
  String snapshotPath(String dataset, String id) =>
      '${root(dataset)}/snapshots/$id.enc';
  Future<void> persist(String book, SyncJournal journal) =>
      stateStore.write('book-$book', canonicalJson(journal.toJson()));

  Future<(SyncJournal, SecureKey)?> load(String book) async {
    final json = await stateStore.read('book-$book');
    if (json == null) return null;
    final journal = SyncJournal.decode(json);
    final stored = await secrets.read('dek/${journal.dataset}');
    if (stored == null) return null;
    final bytes = base64Decode(stored);
    try {
      return (journal, crypto.importKey(bytes));
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<void> rememberKey(String dataset, SecureKey key) async {
    final bytes = key.extractBytes();
    try {
      await secrets.write('dek/$dataset', base64Encode(bytes));
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<List<String>> datasets() async {
    final ids = <String>{};
    String? cursor;
    do {
      final page = await cloud.list('/v2', cursor: cursor);
      for (final item in page.items) {
        final match = RegExp(r'^/v2/([0-9a-f-]{36})/key\.enc$')
            .firstMatch(item.path);
        if (!item.deleted && match != null && uuidPattern.hasMatch(match[1]!)) {
          ids.add(match[1]!);
        }
      }
      if (ids.length > 1000) {
        throw const FormatException('Te veel studieboeken in Dropbox.');
      }
      cursor = page.more ? page.cursor : null;
    } while (cursor != null);
    return ids.toList()..sort();
  }

  Future<(SyncJournal, SecureKey)> create(
    VaultRepository repo,
    String password,
  ) async {
    final dataset = const Uuid().v4(), key = crypto.newKey();
    final journal = SyncJournal(dataset, const Uuid().v4());
    try {
      final envelope = await crypto.wrap(dataset, key, password, 1);
      await _immutable(keyPath(dataset), envelope);
      journal.generation = 1;
      journal.envelopeHash = digest(envelope);
      await rememberKey(dataset, key);
      await persist(repo.id, journal);
      repo.actor = journal.actor;
      await backup(repo, journal, key);
      return (journal, key);
    } catch (_) {
      key.dispose();
      rethrow;
    }
  }

  Future<(SyncJournal, SecureKey, VaultSnapshot)> unlock(
    String dataset,
    String password,
  ) async {
    final envelope = await cloud.download(keyPath(dataset));
    if (envelope == null) {
      throw const FormatException('Het sleutelbestand ontbreekt.');
    }
    final key = await crypto.unwrap(dataset, envelope.bytes, password);
    try {
      final journal = SyncJournal(dataset, const Uuid().v4())
        ..envelopeHash = digest(envelope.bytes)
        ..generation =
            ((jsonDecode(utf8.decode(envelope.bytes)) as Map)['header']
                    as Map)['generation']
                as int;
      final snapshot = await receive(journal, key);
      if (snapshot == null) {
        throw const FormatException(
          'Dit studieboek heeft nog geen volledige reservekopie.',
        );
      }
      return (journal, key, snapshot);
    } catch (_) {
      key.dispose();
      rethrow;
    }
  }

  Future<void> _immutable(String path, Uint8List bytes) async {
    try {
      await cloud.upload(path, bytes);
    } on CloudChanged {
      final existing = await cloud.download(path);
      if (existing == null || digest(existing.bytes) != digest(bytes)) {
        throw const FormatException(
          'Een onveranderbaar Dropbox-bestand is gewijzigd. Synchronisatie is gestopt.',
        );
      }
    }
    final verified = await cloud.download(path);
    if (verified == null || digest(verified.bytes) != digest(bytes)) {
      throw const FormatException(
        'Dropbox heeft het bestand niet bevestigd. Het blijft in de wachtrij.',
      );
    }
  }

  Future<void> _envelope(SyncJournal journal, SecureKey key) async {
    final object = await cloud.download(keyPath(journal.dataset));
    if (object == null) {
      throw const FormatException('Het Dropbox-sleutelbestand ontbreekt.');
    }
    final hash = digest(object.bytes);
    if (journal.envelopeHash == hash) return;
    final transitions = <Map>[];
    String? cursor;
    do {
      final page = await cloud.list(
        '${root(journal.dataset)}/transitions',
        cursor: cursor,
      );
      for (final item in page.items.where((i) => !i.deleted)) {
        final id = item.path.split('/').last.replaceFirst('.enc', '');
        if (!uuidPattern.hasMatch(id)) continue;
        final witness = await cloud.download(item.path);
        if (witness != null) {
          transitions.add(
            jsonDecode(
              utf8.decode(
                crypto.open(
                  journal.dataset,
                  'transition',
                  id,
                  witness.bytes,
                  key,
                ),
              ),
            ) as Map,
          );
        }
      }
      cursor = page.more ? page.cursor : null;
    } while (cursor != null);
    int? walk(String source, int level, Set<String> visited) {
      if (source == hash) return level;
      if (!visited.add(source) || visited.length > 1000) return null;
      for (final t in transitions.where(
        (t) => t['from'] == source && t['generation'] == level + 1,
      )) {
        final result = walk(t['to'] as String, level + 1, {...visited});
        if (result != null) return result;
      }
      return null;
    }

    final reached = walk(journal.envelopeHash, journal.generation, {});
    if (reached != null) {
      journal.envelopeHash = hash;
      journal.generation = reached;
      return;
    }
    throw const FormatException(
      'Het sleutelbestand is teruggezet of onverwacht gewijzigd. Lokale wijzigingen blijven bewaard.',
    );
  }

  Future<VaultSnapshot?> receive(
    SyncJournal journal,
    SecureKey key, {
    VaultSnapshot? local,
  }) async {
    final candidate = Map<String, CloudItem>.from(journal.objects);
    String? cursor = journal.cursor.isEmpty ? null : journal.cursor;
    var full = cursor == null;
    while (true) {
      CloudPage page;
      try {
        page = await cloud.list(root(journal.dataset), cursor: cursor);
      } on CursorReset {
        cursor = null;
        full = true;
        candidate.clear();
        continue;
      }
      if (full && cursor == null) candidate.clear();
      for (final item in page.items) {
        if (item.deleted) {
          candidate.remove(item.path);
        } else {
          candidate[item.path] = item;
        }
      }
      cursor = page.cursor;
      if (!page.more) break;
      if (candidate.length > 100000) {
        throw const FormatException('Te veel synchronisatiebestanden.');
      }
    }
    VaultSnapshot? merged = local;
    final covered = <String, String>{};
    // Union all valid retained snapshots: creation clocks do not select state.
    // A snapshot may have been produced by a formerly offline device.
    final snapshots = candidate.values.where(
      (i) => i.path.startsWith('${root(journal.dataset)}/snapshots/'),
    );
    for (final item in snapshots) {
      final cached = journal.verifiedSnapshots[item.path];
      if (local != null && cached?['revision'] == item.revision) {
        final coverage = Map<String, String>.from(cached!['covered'] as Map);
        final present = {
          for (final p in local.contents.entries.where(
            (p) => p.key.startsWith('records/'),
          ))
            p.key.split('/').last.split('.').first: digest(
              utf8.encode(p.value),
            ),
        };
        if (coverage.entries.every((e) => present[e.key] == e.value)) {
          covered.addAll(coverage);
          continue;
        }
      }
      final id = item.path.split('/').last.replaceFirst('.enc', '');
      if (!uuidPattern.hasMatch(id)) continue;
      try {
        final point = await readPoint(journal.dataset, id, key);
        merged = merged == null ? point.snapshot : merged.union(point.snapshot);
        covered.addAll(point.covered);
        journal.verifiedSnapshots[item.path] = {
          'revision': item.revision,
          'covered': point.covered,
        };
      } on FormatException {
        /* An older valid point remains usable. */
      }
    }
    if (merged == null) return null;
    final files = Map<String, String>.from(merged.contents);
    final received = <String, String>{};
    for (final item in candidate.values.where(
      (i) => i.path.startsWith('${root(journal.dataset)}/changes/'),
    )) {
      final op = item.path.split('/').last.replaceFirst('.enc', '');
      if (!uuidPattern.hasMatch(op)) {
        throw const FormatException('Onbekend wijzigingsbestand.');
      }
      if (journal.objects[item.path]?.revision == item.revision &&
          journal.acknowledged.containsKey(op) &&
          files.entries.any(
            (e) =>
                e.key.startsWith('records/$op.') &&
                digest(utf8.encode(e.value)) == journal.acknowledged[op],
          )) {
        continue;
      }
      final object = await cloud.download(item.path);
      if (object == null) {
        throw const FormatException(
          'Een wijziging verdween tijdens synchronisatie. Probeer opnieuw.',
        );
      }
      final bytes = crypto.open(
        journal.dataset,
        'change',
        op,
        object.bytes,
        key,
      );
      final change = jsonDecode(utf8.decode(bytes)) as Map;
      if (change['operation'] != op || change['book'] != merged.id) {
        throw const FormatException('Verwisselde wijziging.');
      }
      final name = change['filename'] as String,
          text = change['record'] as String;
      final record = Entry.decode(text, name);
      if (record.revision != op) {
        throw const FormatException('Verwisselde wijziging.');
      }
      final hash = digest(utf8.encode(text));
      final old = journal.acknowledged[op] ?? covered[op];
      if (old != null && old != hash) {
        throw const FormatException(
          'Een eerdere wijziging is buiten de app aangepast.',
        );
      }
      final path = 'records/$name';
      if (files.containsKey(path) && files[path] != text) {
        throw const FormatException('Botsende wijzigingsidentiteit.');
      }
      files[path] = text;
      received[op] = hash;
    }
    // Detect rollback/deletion of previously confirmed history unless a valid
    // retained snapshot still contains it. Local data alone is not proof of
    // a surviving remote backup.
    for (final op in journal.acknowledged.keys) {
      if (!candidate.containsKey(changePath(journal.dataset, op)) &&
          covered[op] != journal.acknowledged[op]) {
        throw const FormatException(
          'Dropbox mist eerder bevestigde geschiedenis. Er wordt niets overschreven; controleer de herstelpunten.',
        );
      }
    }
    final result = VaultSnapshot(files);
    await result.validate(bible);
    result.encode();
    // In-memory only until the caller has durably merged the validated batch.
    journal.cursor = cursor;
    journal.objects
      ..clear()
      ..addAll(candidate);
    journal.acknowledged
      ..addAll(covered)
      ..addAll(received);
    return result;
  }

  Future<void> synchronize(
    VaultRepository repo,
    SyncJournal journal,
    SecureKey key,
  ) async {
    await _envelope(journal, key);
    final local = await repo.snapshot();
    final remote = await receive(journal, key, local: local);
    if (remote != null) await repo.mergeSnapshot(remote);
    // A lost upload response can be confirmed by the authenticated download
    // in receive(). Clear its durable retry only after the merge is committed.
    journal.outbox.removeWhere((op, _) => journal.acknowledged.containsKey(op));
    // Cursor is committed only after incoming canonical records are durable.
    await persist(repo.id, journal);
    final snapshot = await repo.snapshot();
    for (final entry in orderedRecords(repo.history)) {
      final text = snapshot.contents['records/${entry.filename}']!,
          hash = digest(utf8.encode(text));
      if (journal.acknowledged[entry.revision] == hash) continue;
      if (journal.acknowledged.containsKey(entry.revision)) {
        throw const FormatException(
          'Een bevestigde lokale revisie is gewijzigd.',
        );
      }
      journal.outbox.putIfAbsent(
        entry.revision,
        () => base64Encode(
          crypto.seal(
            journal.dataset,
            'change',
            entry.revision,
            wire({
              'operation': entry.revision,
              'book': repo.id,
              'filename': entry.filename,
              'record': text,
            }),
            key,
          ),
        ),
      );
      await persist(repo.id, journal);
      await _immutable(
        changePath(journal.dataset, entry.revision),
        base64Decode(journal.outbox[entry.revision]!),
      );
      journal.acknowledged[entry.revision] = hash;
      journal.outbox.remove(entry.revision);
      journal.operationsSinceBackup++;
      await persist(repo.id, journal);
    }
    if (journal.lastBackup == null ||
        journal.operationsSinceBackup >= journal.snapshotEveryOperations ||
        DateTime.now().difference(journal.lastBackup!).inHours >=
            journal.snapshotEveryHours) {
      await backup(repo, journal, key);
    }
    journal.lastSuccess = DateTime.now().toUtc();
    await persist(repo.id, journal);
    await stateStore.write(
      'background-${repo.id}',
      canonicalJson({
        'dataset': journal.dataset,
        'envelopeHash': journal.envelopeHash,
        'outbox': journal.outbox,
      }),
    );
  }

  Future<void> stage(
    VaultRepository repo,
    SyncJournal journal,
    SecureKey key,
  ) async {
    final snapshot = await repo.snapshot();
    for (final entry in orderedRecords(repo.history)) {
      final text = snapshot.contents['records/${entry.filename}']!;
      if (journal.acknowledged[entry.revision] == digest(utf8.encode(text))) {
        continue;
      }
      journal.outbox.putIfAbsent(
        entry.revision,
        () => base64Encode(
          crypto.seal(
            journal.dataset,
            'change',
            entry.revision,
            wire({
              'operation': entry.revision,
              'book': repo.id,
              'filename': entry.filename,
              'record': text,
            }),
            key,
          ),
        ),
      );
    }
    await persist(repo.id, journal);
    await stateStore.write(
      'background-${repo.id}',
      canonicalJson({
        'dataset': journal.dataset,
        'envelopeHash': journal.envelopeHash,
        'outbox': journal.outbox,
      }),
    );
  }

  Future<void> backup(
    VaultRepository repo,
    SyncJournal journal,
    SecureKey key,
  ) async {
    final snapshot = await repo.snapshot(), id = const Uuid().v4();
    final created = DateTime.now().toUtc();
    final covered = {
      for (final e in repo.history)
        e.revision: digest(
          utf8.encode(snapshot.contents['records/${e.filename}']!),
        ),
    };
    final bytes = await crypto.sealSnapshot(
      journal.dataset,
      id,
      wire({
        'snapshot': jsonDecode(snapshot.encode()),
        'covered': covered,
        'created': created.toIso8601String(),
      }),
      key,
    );
    await _immutable(snapshotPath(journal.dataset, id), bytes);
    // Read, decrypt and validate before declaring a backup or acknowledging ops.
    final point = await readPoint(journal.dataset, id, key);
    if (canonicalJson(point.covered) != canonicalJson(covered)) {
      throw const FormatException('Reservekopiecontrole mislukt.');
    }
    journal.acknowledged.addAll(covered);
    journal.outbox.removeWhere((op, _) => covered.containsKey(op));
    journal.lastBackup = created;
    journal.operationsSinceBackup = 0;
    await persist(repo.id, journal);
  }

  Future<RestorePoint> readPoint(
    String dataset,
    String id,
    SecureKey key,
  ) async {
    final object = await cloud.download(snapshotPath(dataset, id));
    if (object == null) throw const FormatException('Herstelpunt ontbreekt.');
    final json = jsonDecode(
      utf8.decode(await crypto.openSnapshot(dataset, id, object.bytes, key)),
    ) as Map;
    final snapshot = VaultSnapshot.decode(jsonEncode(json['snapshot']));
    final repo = await snapshot.validate(bible),
        covered = Map<String, String>.from(json['covered'] as Map);
    final actual = {
      for (final e in repo.history)
        e.revision: digest(
          utf8.encode(snapshot.contents['records/${e.filename}']!),
        ),
    };
    if (canonicalJson(actual) != canonicalJson(covered)) {
      throw const FormatException('Onvolledig herstelpunt.');
    }
    return RestorePoint(
      id,
      DateTime.parse(json['created'] as String),
      snapshot,
      covered,
    );
  }

  Future<List<RestorePoint>> restorePoints(
    String dataset,
    SecureKey key, {
    Iterable<CloudItem>? objects,
  }) async {
    final items = <CloudItem>[];
    if (objects != null) {
      items.addAll(objects);
    } else {
      String? cursor;
      do {
        final page = await cloud.list(root(dataset), cursor: cursor);
        items.addAll(page.items.where((i) => !i.deleted));
        cursor = page.more ? page.cursor : null;
      } while (cursor != null);
    }
    final candidates =
        items
            .where((i) => i.path.startsWith('${root(dataset)}/snapshots/'))
            .toList()
          ..sort((a, b) => b.modified.compareTo(a.modified));
    final points = <RestorePoint>[];
    for (final item in candidates) {
      final id = item.path.split('/').last.replaceFirst('.enc', '');
      if (!uuidPattern.hasMatch(id)) continue;
      try {
        points.add(await readPoint(dataset, id, key));
      } on FormatException {
        /* Keep corrupt objects; try older valid restore points. */
      }
    }
    if (candidates.isNotEmpty && points.isEmpty) {
      throw const FormatException(
        'Geen geldig herstelpunt gevonden. De lokale gegevens blijven behouden.',
      );
    }
    return points..sort((a, b) => b.created.compareTo(a.created));
  }

  Future<void> changePassword(
    String book,
    SyncJournal journal,
    SecureKey key,
    String password,
  ) async {
    final previous = await cloud.download(keyPath(journal.dataset));
    if (previous == null || digest(previous.bytes) != journal.envelopeHash) {
      throw CloudChanged();
    }
    final generation = journal.generation + 1;
    final bytes = await crypto.wrap(journal.dataset, key, password, generation);
    // Publish a DEK-authenticated transition BEFORE CAS. It cannot authorize
    // anything until the exact target envelope hash is observed.
    final witnessId = const Uuid().v4();
    final witness = crypto.seal(
      journal.dataset,
      'transition',
      witnessId,
      wire({
        'from': journal.envelopeHash,
        'to': digest(bytes),
        'generation': generation,
      }),
      key,
    );
    await _immutable(
      '${root(journal.dataset)}/transitions/$witnessId.enc',
      witness,
    );
    await cloud.upload(
      keyPath(journal.dataset),
      bytes,
      revision: previous.revision,
    );
    final check = await cloud.download(keyPath(journal.dataset));
    if (check == null || digest(check.bytes) != digest(bytes)) {
      throw CloudChanged();
    }
    final verified = await crypto.unwrap(
      journal.dataset,
      check.bytes,
      password,
    );
    verified.dispose();
    journal.envelopeHash = digest(bytes);
    journal.generation = generation;
    await persist(book, journal);
  }

  Future<void> compact(
    VaultRepository repo,
    SyncJournal journal,
    SecureKey key,
  ) async {
    await synchronize(repo, journal, key);
    await backup(repo, journal, key);
    final points = await restorePoints(journal.dataset, key);
    if (points.length < 2) return; // Keep redundancy even with retention=1.
    final keep = points.take(maxRetention(journal.retainSnapshots)).toList();
    final coverage = <String, String>{};
    for (final point in keep) {
      coverage.addAll(point.covered);
    }
    final items = <CloudItem>[];
    String? cursor;
    do {
      final page = await cloud.list(root(journal.dataset), cursor: cursor);
      items.addAll(page.items.where((i) => !i.deleted));
      cursor = page.more ? page.cursor : null;
    } while (cursor != null);
    for (final item in items) {
      final op = item.path.split('/').last.replaceFirst('.enc', '');
      if (item.path.startsWith('${root(journal.dataset)}/changes/') &&
          coverage[op] == journal.acknowledged[op] &&
          coverage.containsKey(op)) {
        // Never remove a concurrently replaced object. Dropbox parent_rev is CAS.
        await cloud.delete(item.path, item.revision);
      }
    }
    for (final old in points.skip(keep.length)) {
      if (old.covered.entries.every((e) => coverage[e.key] == e.value)) {
        final item = items
            .where((i) => i.path == snapshotPath(journal.dataset, old.id))
            .firstOrNull;
        if (item != null) await cloud.delete(item.path, item.revision);
      }
    }
    journal.cursor = '';
    await persist(repo.id, journal);
  }

  int maxRetention(int value) => value.clamp(2, 100);
}
