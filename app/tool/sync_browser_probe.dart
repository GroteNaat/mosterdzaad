import 'dart:js_interop';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:loro_crdt/loro_crdt.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:mosterdzaad/domain/bible.dart';
import 'package:mosterdzaad/sync/crypto_box.dart';

import 'sync_checks.dart';

@JS('prototypeResult')
external set result(JSString text);
@JS('webFixture')
external set webFixture(JSString text);
@JS('requireInterop')
external bool get requireInterop;
Future<void> main() async {
  try {
    await initLoro();
    final sodium = await SodiumSumoInit.init();
    final base = LoroDoc()..peerId = '101';
    base.getText('body').update('First paragraph.\nSecond paragraph 🌱.');
    base.commit(timestamp: 0);
    final edit = base.fork()..peerId = '102';
    edit
        .getText('body')
        .update('First edited paragraph.\nSecond paragraph 🌱.');
    edit.commit(timestamp: 0);
    webFixture = jsonEncode({
      'snapshot': base64Encode(base.exportSnapshot()),
      'update': base64Encode(edit.exportUpdates(from: base.oplogVersion)),
    }).toJS;
    if (requireInterop) {
      final fixture = await http.get(Uri.base.resolve('native-fixture.json'));
      if (fixture.statusCode != 200) throw StateError('Native fixture missing');
      final data = jsonDecode(fixture.body) as Map;
      final doc = LoroDoc()
        ..import(base64Decode(data['snapshot'] as String))
        ..import(base64Decode(data['update'] as String));
      doc.import(edit.exportUpdates(from: base.oplogVersion));
      if (doc.getText('body').toString() !=
          'First edited paragraph.\nSecond paragraph 🌱 native.') {
        throw StateError('Native/web interoperability');
      }
      doc.dispose();
    }
    base.dispose();
    edit.dispose();
    final english = await http.get(Uri.base.resolve('books.json'));
    final original = await http.get(Uri.base.resolve('books-original.json'));
    await runSyncChecks(Bible(english.body, original.body), CryptoBox(sodium));
    result = 'PASS: encrypted sync, concurrent text, stale editor, recovery, long-offline compaction, password rotation, tamper/truncation rejection'
        .toJS;
  } catch (e, s) {
    result = 'FAIL: $e\n$s'.toJS;
  }
}
