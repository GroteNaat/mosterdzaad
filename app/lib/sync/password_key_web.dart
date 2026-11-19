import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<Uint8List> passwordKey(String password, Uint8List salt) async {
  final worker = web.Worker('argon_worker.js'.toJS);
  final result = Completer<Uint8List>();
  worker.onmessage = ((web.MessageEvent event) {
    final data = event.data.dartify() as Map;
    if (data['key'] is String) {
      result.complete(base64Decode(data['key'] as String));
    } else {
      result.completeError(
        const FormatException('De wachtwoordsleutel kon niet worden berekend.'),
      );
    }
  }).toJS;
  worker.onerror = ((web.Event event) {
    if (!result.isCompleted) {
      result.completeError(
        const FormatException(
          'De versleutelingsmodule kon niet worden geladen.',
        ),
      );
    }
  }).toJS;
  worker.postMessage(
    {'password': password, 'salt': base64Encode(salt)}.jsify(),
  );
  try {
    return await result.future.timeout(const Duration(minutes: 2));
  } finally {
    worker.terminate();
  }
}
