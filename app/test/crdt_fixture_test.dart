import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loro_crdt/loro_crdt.dart';

void main() {
  test('Web-produced Loro binary changes merge with native edits', () async {
    await initLoro();
    final fixture = jsonDecode(
      await File('test/fixtures/loro-web.json').readAsString(),
    ) as Map;
    final base = LoroDoc()..import(base64Decode(fixture['snapshot'] as String));
    final native = base.fork()..peerId = '103';
    native
        .getText('body')
        .update('First paragraph.\nSecond paragraph 🌱 native.');
    native.commit(timestamp: 0);
    final bytes = native.exportUpdates(from: base.oplogVersion);
    native.import(base64Decode(fixture['update'] as String));
    expect(
      native.getText('body').toString(),
      'First edited paragraph.\nSecond paragraph 🌱 native.',
    );
    final output = File('build/native-fixture.json');
    await output.parent.create(recursive: true);
    await output.writeAsString(
      jsonEncode({
        'snapshot': fixture['snapshot'],
        'update': base64Encode(bytes),
      }),
    );
    base.dispose();
    native.dispose();
  });
}
