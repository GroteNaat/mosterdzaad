import 'dart:convert';
import 'dart:typed_data';

import 'package:mosterdzaad/domain/bible.dart';
import 'package:mosterdzaad/storage/vault_types.dart';
import 'package:mosterdzaad/storage/vault_repository.dart';
import 'package:mosterdzaad/sync/crypto_box.dart';
import 'package:mosterdzaad/sync/encrypted_cloud.dart';
import 'package:mosterdzaad/sync/encrypted_sync.dart';
import 'package:mosterdzaad/sync/local_state.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> rejects(Future<void> Function() action, String name) async {
  var rejected = false;
  try {
    await action();
  } catch (_) {
    rejected = true;
  }
  check(rejected, name);
}

class ProbeFiles implements VaultFiles {
  final contents = <String, String>{};
  @override
  VaultLocation get location => const VaultLocation('test', '', 'Test');
  @override
  Future<void> makeDirectory(String directory) async {}
  @override
  Future<List<String>> list(String directory) async => contents.keys
      .where((k) => k.startsWith('$directory/'))
      .map((k) => k.substring(directory.length + 1))
      .toList();
  @override
  Future<String?> read(String name) async => contents[name];
  @override
  Future<void> remove(String name) async {
    contents.remove(name);
  }

  @override
  Future<void> writeNew(String name, String value) async {
    if (contents.containsKey(name)) throw StateError('exists');
    contents[name] = value;
  }
}

class ProbeState extends LocalStateStore {
  ProbeState() : super('');
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class ProbeSecrets extends SecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class ProbeCloud implements EncryptedCloud {
  final objects = <String, CloudObject>{};
  final deleted = <String>{};
  int sequence = 0, writes = 0, downloads = 0;
  bool offline = false, reset = false, loseResponse = false;
  bool loseDeleteResponse = false;
  @override
  Future<CloudObject?> download(String path) async {
    if (offline) throw CloudOffline();
    downloads++;
    return objects[path];
  }

  @override
  Future<String> upload(
    String path,
    Uint8List bytes, {
    String? revision,
  }) async {
    if (offline) throw CloudOffline();
    if (objects[path]?.revision != revision) throw CloudChanged();
    final rev = '${++sequence}';
    objects[path] = CloudObject(Uint8List.fromList(bytes), rev);
    deleted.remove(path);
    writes++;
    if (loseResponse) {
      loseResponse = false;
      throw CloudOffline();
    }
    return rev;
  }

  @override
  Future<CloudPage> list(String path, {String? cursor}) async {
    if (offline) throw CloudOffline();
    if (reset && cursor != null) {
      reset = false;
      throw CursorReset();
    }
    return CloudPage(
      [
        for (final e in objects.entries.where(
          (e) => e.key.startsWith('$path/'),
        ))
          CloudItem(e.key, e.value.revision, false, '2026-11-19T00:00:00Z'),
        for (final name in deleted.where((name) => name.startsWith('$path/')))
          CloudItem(name, '', true, ''),
      ],
      'cursor-$sequence',
      false,
    );
  }

  @override
  Future<void> delete(String path, String revision) async {
    if (!objects.containsKey(path)) return;
    if (objects[path]?.revision != revision) throw CloudChanged();
    objects.remove(path);
    deleted.add(path);
    sequence++;
    if (loseDeleteResponse) {
      loseDeleteResponse = false;
      throw CloudOffline();
    }
  }
}

Future<void> runSyncChecks(Bible bible, CryptoBox crypto) async {
  await runPurgeChecks(bible, crypto);
  final cloud = ProbeCloud(), state = ProbeState(), secrets = ProbeSecrets();
  final engine = EncryptedSync(cloud, crypto, state, secrets, bible);
  final a = await VaultRepository.create(
    ProbeFiles(),
    bible,
    'Privé studieboek',
    'english',
    false,
  );
  Map<String, dynamic> note(String body) => {
    'title': 'Geheime titel',
    'body': body,
    'references': 'Johannes 3:16',
    'passages': bible
        .parse('Johannes 3:16', 'english')
        .map((p) => p.toJson())
        .toList(),
    'themes': <String>[],
    'plans': <String>[],
    'studies': <String>[],
  };
  final initial = await a.save(
    'note',
    note('Eerste alinea.\nTweede alinea 🌱.'),
  );
  final (ja, key) = await engine.create(a, 'correct horse battery staple');
  await rejects(
    () => engine.unlock(ja.dataset, 'een verkeerd wachtwoord'),
    'wrong password',
  );
  final (jb, kb, snapshot) = await engine.unlock(
    ja.dataset,
    'correct horse battery staple',
  );
  final bf = ProbeFiles();
  await snapshot.restoreTo(bf, bible);
  final b = VaultRepository(bf, bible);
  await b.reload();
  final (jc, kc, third) = await engine.unlock(
    ja.dataset,
    'correct horse battery staple',
  );
  final cf = ProbeFiles();
  await third.restoreTo(cf, bible);
  final c = VaultRepository(cf, bible);
  await c.reload();
  final baseA = a.ofKind('note').single, baseB = b.ofKind('note').single;
  await a.save(
    'note',
    note('Eerste gewijzigde alinea.\nTweede alinea 🌱.'),
    entityId: initial.id,
    expected: baseA.causalHeads!,
  );
  await b.save(
    'note',
    note('Eerste alinea.\nTweede alinea 🌱 met hoop.'),
    entityId: initial.id,
    expected: baseB.causalHeads!,
  );
  await engine.synchronize(a, ja, key);
  await engine.synchronize(b, jb, kb);
  await engine.synchronize(a, ja, key);
  check(
    a.ofKind('note').single.text('body') ==
        'Eerste gewijzigde alinea.\nTweede alinea 🌱 met hoop.',
    'concurrent paragraph merge',
  );
  check(
    a.ofKind('note').single.text('body') ==
        b.ofKind('note').single.text('body'),
    'replica convergence',
  );
  final before = cloud.writes;
  await engine.synchronize(a, ja, key);
  check(cloud.writes == before, 'idempotent sync');
  for (final object in cloud.objects.values) {
    final text = utf8.decode(object.bytes);
    check(
      !text.contains('Geheime titel') &&
          !text.contains('Privé studieboek') &&
          !text.contains('alinea'),
      'cloud plaintext leak',
    );
  }
  // A stale editor saves its base, preserving changes received in the meantime.
  await a.save(
    'note',
    note('Eerste alinea.\nTweede alinea 🌱.\nEen derde alinea.'),
    entityId: initial.id,
    expected: baseA.causalHeads!,
    expectedHashes: baseA.causalHashes,
  );
  check(
    a.ofKind('note').single.text('body').contains('gewijzigde'),
    'stale editor loses remote edits',
  );
  cloud.offline = true;
  await rejects(() => engine.synchronize(a, ja, key), 'offline queue');
  cloud.offline = false;
  await engine.synchronize(a, ja, key);
  // Long-offline client can replay its unsent edits after cloud consolidation.
  await c.save(
    'note',
    note('Eerste alinea.\nTweede alinea 🌱.\nLang offline.'),
    entityId: initial.id,
    expected: c.ofKind('note').single.causalHeads!,
  );
  await engine.backup(a, ja, key);
  await engine.compact(a, ja, key);
  cloud.reset = true;
  await engine.synchronize(c, jc, kc);
  await engine.synchronize(a, ja, key);
  check(
    a.ofKind('note').single.text('body').contains('Lang offline.'),
    'long offline replay',
  );
  await engine.changePassword(a.id, ja, key, 'nieuw en heel lang wachtwoord');
  await engine.synchronize(
    b,
    jb,
    kb,
  ); // already-unlocked devices follow authenticated rewrap
  await rejects(
    () => engine.unlock(ja.dataset, 'correct horse battery staple'),
    'old password accepted',
  );
  final (_, fresh, restored) = await engine.unlock(
    ja.dataset,
    'nieuw en heel lang wachtwoord',
  );
  fresh.dispose();
  check(
    (await restored.validate(bible))
        .ofKind('note')
        .single
        .text('body')
        .contains('Lang offline.'),
    'second device restore',
  );
  final current = a.ofKind('note').single;
  await b.save(
    'note',
    {...b.ofKind('note').single.data, 'body': 'Een gelijktijdige bewerking'},
    entityId: initial.id,
    expected: b.ofKind('note').single.causalHeads!,
  );
  await a.save(
    'note',
    current.data,
    entityId: initial.id,
    expected: current.causalHeads!,
    deleted: true,
  );
  await engine.synchronize(a, ja, key);
  await engine.synchronize(b, jb, kb);
  check(b.ofKind('note').isEmpty, 'delete must win');
  final trash = b.heads[initial.id]!.single;
  check(
    trash.text('body').contains('gelijktijdige'),
    'deleted edit must remain recoverable',
  );
  await b.save(
    'note',
    trash.data,
    entityId: trash.id,
    expected: trash.causalHeads!,
  );
  check(b.ofKind('note').isNotEmpty, 'explicit restore');
  await engine.synchronize(b, jb, kb);
  await engine.synchronize(a, ja, key);
  // Concurrent title choices remain visible, while the OR-set merges links.
  final t1 = await a.save('theme', {'name': 'Een', 'description': ''});
  final t2 = await a.save('theme', {'name': 'Twee', 'description': ''});
  final t3 = await a.save('theme', {'name': 'Drie', 'description': ''});
  final n = a.ofKind('note').single;
  await a.save(
    'note',
    {
      ...n.data,
      'themes': [t1.id],
    },
    entityId: n.id,
    expected: n.causalHeads!,
  );
  await engine.synchronize(a, ja, key);
  await engine.synchronize(b, jb, kb);
  final na = a.ofKind('note').single, nb = b.ofKind('note').single;
  await a.save(
    'note',
    {
      ...na.data,
      'title': 'Titel A',
      'themes': [t2.id],
    },
    entityId: na.id,
    expected: na.causalHeads!,
  );
  await b.save(
    'note',
    {
      ...nb.data,
      'title': 'Titel B',
      'themes': [t1.id, t3.id],
    },
    entityId: nb.id,
    expected: nb.causalHeads!,
  );
  await engine.synchronize(a, ja, key);
  await engine.synchronize(b, jb, kb);
  check(
    b.ofKind('note').single.links('themes').toSet().containsAll([
          t2.id,
          t3.id,
        ]) &&
        !b.ofKind('note').single.links('themes').contains(t1.id),
    'observed-remove set',
  );
  check(
    b.conflicts.any((c) => c.first.conflictField == 'title'),
    'concurrent title alternatives',
  );
  final choice = b.conflicts
      .firstWhere((c) => c.first.conflictField == 'title')
      .first;
  await b.save(
    'note',
    choice.data,
    entityId: choice.id,
    expected: choice.causalHeads!,
  );
  check(b.conflicts.isEmpty, 'explicit title resolution');
  await engine.synchronize(b, jb, kb);
  await engine.synchronize(a, ja, key);
  final newNote = await a.save(
    'note',
    note('Antwoord van Dropbox raakt kwijt.'),
  );
  await engine.stage(a, ja, key);
  cloud.loseResponse = true;
  await rejects(() => engine.synchronize(a, ja, key), 'lost upload response');
  final saved = SyncJournal.decode(state.values['book-${a.id}']!);
  check(
    saved.outbox.containsKey(newNote.revision),
    'unconfirmed upload must stay durable',
  );
  final pending = saved.outbox[newNote.revision];
  await engine.synchronize(a, saved, key);
  check(saved.outbox.isEmpty, 'retry acknowledges duplicate upload');
  check(
    base64Encode(
          cloud.objects[engine.changePath(ja.dataset, newNote.revision)]!.bytes,
        ) ==
        pending,
    'retry must reuse exact ciphertext',
  );
  // A confirmed operation may disappear only if a validated snapshot covers it.
  final path = engine.changePath(ja.dataset, newNote.revision),
      remote = cloud.objects.remove(
        engine.changePath(ja.dataset, newNote.revision),
      )!;
  saved.cursor = '';
  await rejects(
    () => engine.synchronize(a, saved, key),
    'confirmed remote history deletion',
  );
  cloud.objects[path] = remote;
  await engine.synchronize(a, saved, key);
  // A tampered ciphertext must never be applied or overwritten automatically.
  final bad = Uint8List.fromList(remote.bytes);
  bad[bad.length - 8] ^= 1;
  cloud.objects[path] = CloudObject(bad, 'tampered');
  saved.cursor = '';
  await rejects(
    () => engine.synchronize(a, saved, key),
    'tampered remote operation',
  );
  cloud.objects[path] = remote;
  await engine.synchronize(a, saved, key);
  final plain = Uint8List.fromList(List.generate(200000, (i) => i % 251));
  const object = '11111111-1111-4111-8111-111111111111';
  final encrypted = await crypto.sealSnapshot(ja.dataset, object, plain, key);
  check(
    digest(await crypto.openSnapshot(ja.dataset, object, encrypted, key)) ==
        digest(plain),
    'secretstream roundtrip',
  );
  final truncated = jsonDecode(utf8.decode(encrypted)) as Map;
  (truncated['frames'] as List).removeLast();
  await rejects(
    () => crypto.openSnapshot(ja.dataset, object, wire(truncated), key),
    'truncated snapshot',
  );
  final cipher = crypto.seal(ja.dataset, 'change', object, plain, key);
  final altered = jsonDecode(utf8.decode(cipher)) as Map;
  final bytes = base64Decode(altered['ciphertext'] as String);
  bytes[0] ^= 1;
  altered['ciphertext'] = base64Encode(bytes);
  await rejects(() async {
    crypto.open(ja.dataset, 'change', object, wire(altered), key);
  }, 'tamper rejection');
  await rejects(() async {
    crypto.open(ja.dataset, 'change', initial.id, cipher, key);
  }, 'AAD context substitution');
  key.dispose();
  kb.dispose();
  kc.dispose();
}

Future<void> runPurgeChecks(Bible bible, CryptoBox crypto) async {
  final cloud = ProbeCloud(), state = ProbeState(), secrets = ProbeSecrets();
  final engine = EncryptedSync(cloud, crypto, state, secrets, bible);
  final files = ProbeFiles();
  final a = await VaultRepository.create(
    files,
    bible,
    'Purge test',
    'english',
    false,
  );
  Map<String, dynamic> data(String text) => {
    'title': '',
    'body': text,
    'references': 'Psalm 23',
    'passages': bible
        .parse('Psalm 23', 'english')
        .map((p) => p.toJson())
        .toList(),
    'themes': <String>[],
    'plans': <String>[],
    'studies': <String>[],
  };
  final original = await a.save('note', data('DELETE-SECRET-original'));
  final kept = await a.save('note', data('Keep this other note'));
  final (initialJournal, key) = await engine.create(
    a,
    'a long enough purge password',
  );
  var journal = initialJournal;
  final (offlineJournal, offlineKey, beforePurge) = await engine.unlock(
    journal.dataset,
    'a long enough purge password',
  );
  final offlineFiles = ProbeFiles();
  await beforePurge.restoreTo(offlineFiles, bible);
  final offline = VaultRepository(offlineFiles, bible);
  await offline.reload();
  await offline.save(
    'note',
    data('DELETE-SECRET-offline-edit'),
    entityId: original.id,
    expected: [original.revision],
  );
  await engine.stage(offline, offlineJournal, offlineKey);
  check(
    await backgroundMayUpload(cloud, journal.dataset, {}),
    'background uploads allowed before any permanent deletion',
  );
  final edit = await a.save(
    'note',
    data('DELETE-SECRET-new-version'),
    entityId: original.id,
    expected: [original.revision],
  );
  await engine.synchronize(a, journal, key);
  final deleted = await a.save(
    'note',
    edit.data,
    entityId: original.id,
    expected: [edit.revision],
    deleted: true,
  );
  await a.permanentlyDelete(deleted);
  check(
    !files.contents.values.any((s) => s.contains('DELETE-SECRET')),
    'purge must remove physical local revision payloads',
  );
  check(
    a.ofKind('note').single.id == kept.id,
    'purge must preserve unrelated notes',
  );
  await rejects(
    () => a.save(
      'note',
      original.data,
      entityId: original.id,
      expected: [deleted.revision],
    ),
    'purge rejects stale restore',
  );
  await a.mergeSnapshot(beforePurge);
  check(
    !files.contents.values.any((s) => s.contains('DELETE-SECRET')),
    'old backup must not resurrect purged history',
  );
  final restored = await beforePurge
      .applyDeletions(await a.snapshot())
      .separateCopy(bible);
  check(
    !restored.encode().contains('DELETE-SECRET'),
    'restoring to new identities must honor permanent deletions',
  );
  check(
    (await restored.validate(bible)).ofKind('note').single.text('body') ==
        kept.text('body'),
    'cleaned restore point keeps unrelated data',
  );
  await engine.stage(a, journal, key);
  cloud.loseDeleteResponse = true;
  await rejects(
    () => engine.synchronize(a, journal, key),
    'interrupted remote cleanup',
  );
  journal = SyncJournal.decode(state.values['book-${a.id}']!);
  await engine.synchronize(a, journal, key);
  check(
    !await backgroundMayUpload(cloud, journal.dataset, {}),
    'unknown erasure barrier stops a stale background worker',
  );
  for (final e in cloud.objects.entries) {
    final id = e.key.split('/').last.replaceFirst('.enc', '');
    if (e.key.contains('/changes/')) {
      final plaintext = utf8.decode(
        crypto.open(journal.dataset, 'change', id, e.value.bytes, key),
      );
      check(
        !plaintext.contains('DELETE-SECRET'),
        'purge removes encrypted remote changes',
      );
    } else if (e.key.contains('/snapshots/')) {
      final point = await engine.readPoint(journal.dataset, id, key);
      check(
        !point.snapshot.encode().contains('DELETE-SECRET'),
        'purge removes historical remote snapshots',
      );
    }
  }
  await engine.synchronize(offline, offlineJournal, offlineKey);
  check(
    await backgroundMayUpload(
      cloud,
      journal.dataset,
      offline.history
          .where((e) => e.kind == 'purge')
          .map((e) => e.revision)
          .toSet(),
    ),
    'reconciled background worker may send again',
  );
  check(
    offlineJournal.outbox.isEmpty,
    'offline erased edits leave the outgoing queue',
  );
  check(
    !offlineFiles.contents.values.any((s) => s.contains('DELETE-SECRET')),
    'offline device removes historical and unpublished erased content',
  );
  check(
    offline.ofKind('note').single.id == kept.id,
    'offline merge keeps unrelated notes',
  );
  journal.cursor = '';
  await engine.synchronize(a, journal, key);
  final (_, recoveredKey, recovered) = await engine.unlock(
    journal.dataset,
    'a long enough purge password',
  );
  check(
    !recovered.encode().contains('DELETE-SECRET'),
    'fresh device cannot restore erased content',
  );
  recoveredKey.dispose();
  final backupPath = cloud.objects.keys.firstWhere(
    (p) => p.contains('/snapshots/'),
  );
  final intact = cloud.objects[backupPath]!;
  cloud.objects[backupPath] = CloudObject(
    Uint8List.fromList([1, 2, 3]),
    'damaged',
  );
  var incompleteReported = false;
  try {
    await engine.synchronize(a, journal, key);
  } on FormatException catch (error) {
    incompleteReported = error.message.contains('Dropbox-herstelpunt');
  }
  check(
    incompleteReported,
    'unverified backup must prevent claiming erasure is complete',
  );
  cloud.objects[backupPath] = intact;
  await engine.synchronize(a, journal, key);
  offlineKey.dispose();
  key.dispose();
}
