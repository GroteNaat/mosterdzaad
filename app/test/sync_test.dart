import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mosterdzaad/storage/vault_repository.dart';
import 'package:mosterdzaad/storage/vault_snapshot.dart';
import 'package:mosterdzaad/sync/dropbox_auth.dart';
import 'package:mosterdzaad/sync/dropbox_client.dart';
import 'package:mosterdzaad/sync/sync_engine.dart';
import 'helpers.dart';

class FakeCloud implements CloudStore {
  CloudVersion? current;
  int revision = 0, writes = 0;
  bool fail = false;
  Future<void> Function()? beforeWrite;
  @override
  Future<CloudVersion?> read(String id) async => current;
  @override
  Future<void> write(
    String id,
    VaultSnapshot snapshot,
    String? expectedRevision,
  ) async {
    final race = beforeWrite;
    beforeWrite = null;
    await race?.call();
    if (fail) throw const DropboxFailure('Offline');
    if (expectedRevision != current?.revision) throw CloudChanged();
    current = CloudVersion(
      VaultSnapshot.decode(snapshot.encode()),
      '${++revision}',
    );
    writes++;
  }
}

void main() {
  final bible = testBible();
  late VaultRepository a, b;
  late MemoryFiles aFiles, bFiles;
  late FakeCloud cloud;
  setUp(() async {
    aFiles = MemoryFiles();
    bFiles = MemoryFiles();
    cloud = FakeCloud();
    a = await VaultRepository.create(
      aFiles,
      bible,
      'Mijn boek',
      'english',
      false,
    );
    await (await a.snapshot()).restoreTo(bFiles, bible);
    b = VaultRepository(bFiles, bible);
    await b.reload();
  });
  test(
    'Offline additions on two devices merge, and repeated sync does not upload',
    () async {
      await a.save('note', noteData(bible, body: 'Apparaat A'));
      await b.save('note', noteData(bible, body: 'Apparaat B'));
      await SyncEngine(cloud).synchronize(a);
      await SyncEngine(cloud).synchronize(b);
      await SyncEngine(cloud).synchronize(a);
      expect(a.ofKind('note').map((e) => e.text('body')).toSet(), {
        'Apparaat A',
        'Apparaat B',
      });
      expect((await a.snapshot()).encode(), (await b.snapshot()).encode());
      final writes = cloud.writes;
      await SyncEngine(cloud).synchronize(a);
      expect(cloud.writes, writes);
    },
  );
  test(
    'Concurrent edit/delete keeps both heads and propagates manual resolution',
    () async {
      final note = await a.save('note', noteData(bible));
      await b.mergeSnapshot(await a.snapshot());
      final edit = await a.save(
        'note',
        noteData(bible, body: 'Bewerkte versie'),
        entityId: note.id,
        expected: [note.revision],
      );
      await b.save(
        'note',
        note.data,
        entityId: note.id,
        expected: [note.revision],
        deleted: true,
      );
      await SyncEngine(cloud).synchronize(a);
      await SyncEngine(cloud).synchronize(b);
      expect(b.conflicts.single.length, 2);
      await b.save(
        'note',
        edit.data,
        entityId: note.id,
        expected: b.heads[note.id]!.map((e) => e.revision).toList(),
      );
      await SyncEngine(cloud).synchronize(b);
      await SyncEngine(cloud).synchronize(a);
      expect(a.conflicts, isEmpty);
      expect(a.ofKind('note').single.text('body'), 'Bewerkte versie');
      expect(a.history.where((e) => e.id == note.id).length, 4);
    },
  );
  test(
    'Compare-and-swap retries merge a writer that wins the upload race',
    () async {
      await SyncEngine(cloud).synchronize(a);
      await a.save('note', noteData(bible, body: 'A'));
      await b.save('note', noteData(bible, body: 'B'));
      cloud.beforeWrite = () async {
        cloud.current = CloudVersion(await b.snapshot(), '${++cloud.revision}');
      };
      await SyncEngine(cloud).synchronize(a);
      final remote = await cloud.current!.snapshot.validate(bible);
      expect(remote.ofKind('note').length, 2);
    },
  );
  test('Failed upload keeps local changes; retry transfers them', () async {
    await a.save('note', noteData(bible));
    final before = Map.of(aFiles.contents);
    cloud.fail = true;
    await expectLater(
      SyncEngine(cloud).synchronize(a),
      throwsA(isA<DropboxFailure>()),
    );
    expect(aFiles.contents, before);
    cloud.fail = false;
    await SyncEngine(cloud).synchronize(a);
    expect(cloud.current!.snapshot.contents, before);
  });
  test(
    'Missing cloud file is recreated; no revision is deleted locally',
    () async {
      await a.save('note', noteData(bible));
      await SyncEngine(cloud).synchronize(a);
      cloud.current = null;
      await SyncEngine(cloud).synchronize(a);
      expect(
        (await cloud.current!.snapshot.validate(bible)).ofKind('note').length,
        1,
      );
    },
  );
  test(
    'Externally edited revision is rejected without changing either side',
    () async {
      final note = await a.save('note', noteData(bible));
      await b.mergeSnapshot(await a.snapshot());
      final path = 'records/${note.filename}';
      bFiles.contents[path] = bFiles.contents[path]!.replaceFirst(
        'Een gedachte',
        'Extern gewijzigd',
      );
      final before = Map.of(aFiles.contents);
      await expectLater(
        a.mergeSnapshot(await b.snapshot()),
        throwsA(isA<VaultConflict>()),
      );
      expect(aFiles.contents, before);
      expect(bFiles.contents[path], contains('Extern gewijzigd'));
    },
  );
  test(
    'Incomplete remote history and malformed record are rejected before writing',
    () async {
      final first = await b.save('note', noteData(bible));
      await b.save(
        'note',
        noteData(bible, body: 'Versie 2'),
        entityId: first.id,
        expected: [first.revision],
      );
      final incoming = {...(await b.snapshot()).contents}
        ..remove('records/${first.filename}');
      final before = Map.of(aFiles.contents);
      await expectLater(
        a.mergeSnapshot(VaultSnapshot(incoming)),
        throwsFormatException,
      );
      incoming['records/${first.filename}'] = 'half bestand';
      await expectLater(
        a.mergeSnapshot(VaultSnapshot(incoming)),
        throwsFormatException,
      );
      expect(aFiles.contents, before);
    },
  );
  test(
    'Interrupted local merge is retryable and parents are always written first',
    () async {
      final first = await b.save('note', noteData(bible));
      await b.save(
        'note',
        noteData(bible, body: 'Versie 2'),
        entityId: first.id,
        expected: [first.revision],
      );
      aFiles.failWrite = true;
      await expectLater(
        a.mergeSnapshot(await b.snapshot()),
        throwsA(isA<Exception>()),
      );
      aFiles.failWrite = false;
      await a.reload();
      await a.mergeSnapshot(await b.snapshot());
      expect(a.ofKind('note').single.text('body'), 'Versie 2');
    },
  );
  test(
    'Concurrent preferences with the same scheme remain resolvable',
    () async {
      final pref = a.ofKind('preferences').single;
      await a.save(
        'preferences',
        {'versification': 'english', 'deuterocanonical': true},
        entityId: a.id,
        expected: [pref.revision],
      );
      await b.save(
        'preferences',
        {'versification': 'english', 'deuterocanonical': false},
        entityId: b.id,
        expected: [pref.revision],
      );
      await a.mergeSnapshot(await b.snapshot());
      expect(a.conflicts.single.length, 2);
      await a.save(
        'preferences',
        pref.data,
        entityId: a.id,
        expected: a.heads[a.id]!.map((e) => e.revision).toList(),
      );
      expect(a.conflicts, isEmpty);
    },
  );
  test(
    'Different versification choices block merging without local changes',
    () async {
      final pref = b.ofKind('preferences').single;
      await b.save(
        'preferences',
        {'versification': 'original', 'deuterocanonical': false},
        entityId: b.id,
        expected: [pref.revision],
      );
      await a.save('note', noteData(bible));
      final before = Map.of(aFiles.contents);
      await expectLater(
        a.mergeSnapshot(await b.snapshot()),
        throwsA(isA<VaultConflict>()),
      );
      expect(aFiles.contents, before);
    },
  );
  test('Snapshot rejects paths outside the record namespace', () {
    expect(
      () => VaultSnapshot.decode(
        jsonEncode({
          'format': 'mosterdzaad-snapshot',
          'version': 1,
          'files': {'mosterdzaad.json': '{}', '../token.json': 'secret'},
        }),
      ),
      throwsFormatException,
    );
  });
  test(
    'PKCE uses the RFC 7636 challenge and validates origin/state before exchange',
    () async {
      final auth = DropboxAuthorization(
        redirect: 'https://example.test/app/auth.html',
        verifier: 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
        state: 'state',
      );
      expect(auth.challenge, 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      });
      await expectLater(
        auth.exchange(
          'https://evil.test/app/auth.html?code=c&state=state',
          client,
        ),
        throwsFormatException,
      );
      expect(called, false);
      expect(auth.url.queryParameters['token_access_type'], 'online');
    },
  );
  test('OAuth exchanges code without a secret and rejects replay', () async {
    final auth = DropboxAuthorization(
      redirect: 'nl.mosterdzaad://dropbox',
      state: 's',
    );
    final client = MockClient((r) async {
      expect(r.bodyFields['code_verifier'], auth.verifier);
      expect(r.bodyFields.containsKey('client_secret'), false);
      return http.Response(
        jsonEncode({'access_token': 'test-token', 'expires_in': 14400}),
        200,
      );
    });
    final session = await auth.exchange(
      'nl.mosterdzaad://dropbox?code=c&state=s',
      client,
    );
    expect(session.valid, true);
    await expectLater(
      auth.exchange('nl.mosterdzaad://dropbox?code=c&state=s', client),
      throwsFormatException,
    );
  });
  test(
    'Dropbox wire format uses strict CAS; errors are never mistaken for a missing file',
    () async {
      final snapshot = await a.snapshot();
      final client = DropboxClient(
        MockClient((request) async {
          if (request.url.path.endsWith('upload')) {
            final args = jsonDecode(request.headers['Dropbox-API-Arg']!) as Map;
            expect(args['mode'], {'.tag': 'update', 'update': 'rev-1'});
            expect(args['strict_conflict'], true);
            expect(args['autorename'], false);
            return http.Response(
              '{"error":{".tag":"path","path":{".tag":"conflict"}}}',
              409,
            );
          }
          return http.Response('unauthorized', 401);
        }),
        'token',
      );
      await expectLater(
        client.write(a.id, snapshot, 'rev-1'),
        throwsA(isA<CloudChanged>()),
      );
      await expectLater(client.read(a.id), throwsA(isA<DropboxFailure>()));
    },
  );
}
