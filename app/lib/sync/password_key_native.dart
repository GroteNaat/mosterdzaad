import 'dart:isolate';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

Future<Uint8List> passwordKey(String password, Uint8List salt) =>
    Isolate.run(() async {
      final sodium = await SodiumSumoInit.init();
      final key = sodium.crypto.pwhash.callStr(
        outLen: 32,
        password: password,
        salt: salt,
        opsLimit: 3,
        memLimit: 64 * 1024 * 1024,
        alg: CryptoPwhashAlgorithm.argon2id13,
      );
      try {
        return key.extractBytes();
      } finally {
        key.dispose();
      }
    });
