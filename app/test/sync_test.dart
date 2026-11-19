import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:mosterdzaad/storage/vault_repository.dart';
import 'package:mosterdzaad/storage/vault_snapshot.dart';
import 'package:mosterdzaad/sync/dropbox_auth.dart';
import 'package:mosterdzaad/sync/crypto_box.dart';
import 'package:mosterdzaad/sync/encrypted_cloud.dart';

import '../tool/sync_checks.dart';
import 'helpers.dart';

void main() {
  final bible = testBible();
  late VaultRepository a, b;
  late MemoryFiles aFiles, bFiles;
  setUp(() async {
    aFiles = MemoryFiles();
    bFiles = MemoryFiles();
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
    'Encrypted multi-device protocol and cryptographic rejection checks',
    () async {
      await runSyncChecks(bible, CryptoBox(await SodiumSumoInit.init()));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test('Incomplete remote history and malformed record are rejected before writing', () async {
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
  });
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
  test('PKCE uses the RFC 7636 challenge and validates origin/state before exchange', () async {
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
    expect(auth.url.queryParameters['token_access_type'], 'offline');
  });
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

  test('Dropbox rejects plaintext, uses CAS, never treats authentication errors as missing', () async {
    final client = DropboxObjects(
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
      (_) async => 'token',
    );
    await expectLater(
      client.upload(
        '/v2/test/key.enc',
        Uint8List.fromList(utf8.encode((await a.snapshot()).encode())),
      ),
      throwsFormatException,
    );
    final crypto = CryptoBox(await SodiumSumoInit.init()),
        key = crypto.newKey();
    try {
      final bytes = crypto.seal(
        a.id,
        'change',
        a.id,
        Uint8List.fromList([1]),
        key,
      );
      await expectLater(
        client.upload('/v2/test/key.enc', bytes, revision: 'rev-1'),
        throwsA(isA<CloudChanged>()),
      );
      await expectLater(
        client.download('/v2/test/key.enc'),
        throwsA(isA<DropboxFailure>()),
      );
    } finally {
      key.dispose();
    }
  });
}
