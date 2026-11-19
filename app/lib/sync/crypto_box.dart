import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import '../domain/entry.dart';
import 'canonical.dart';
import 'password_key.dart';

/// Versioned wire format. Headers are authenticated, including dataset/object
/// identities, algorithms, KDF limits and key generation. Nothing user-written
/// appears in a filename or unauthenticated header.
class CryptoBox {
  CryptoBox(this.sodium);
  final SodiumSumo sodium;
  static const maxObjectBytes = 40 * 1024 * 1024;
  static const chunkSize = 64 * 1024;
  SecureKey newKey() => sodium.crypto.aeadXChaCha20Poly1305IETF.keygen();
  SecureKey importKey(Uint8List bytes) => sodium.secureCopy(bytes);
  Uint8List _bytes(Object? value) =>
      Uint8List.fromList(utf8.encode(canonicalJson(value)));

  Map<String, dynamic> _header(String dataset, String type, String object) {
    if (!uuidPattern.hasMatch(dataset) || !uuidPattern.hasMatch(object)) {
      throw const FormatException('Ongeldige versleutelde identiteit.');
    }
    return {
      'format': 'mosterdzaad-encrypted',
      'version': 2,
      'dataset': dataset,
      'type': type,
      'object': object,
      'algorithm': 'xchacha20poly1305-ietf',
    };
  }

  Map<String, dynamic> _read(
    Uint8List bytes,
    String dataset,
    String type,
    String object,
  ) {
    if (bytes.length > maxObjectBytes) {
      throw const FormatException('Versleuteld bestand te groot.');
    }
    final json = jsonDecode(utf8.decode(bytes)) as Map;
    final header = Map<String, dynamic>.from(json['header'] as Map);
    final expected = _header(dataset, type, object);
    for (final e in expected.entries) {
      if (header[e.key] != e.value) {
        throw const FormatException(
          'Onbekend of verwisseld versleuteld bestand.',
        );
      }
    }
    return Map<String, dynamic>.from(json)..['header'] = header;
  }

  Uint8List seal(
    String dataset,
    String type,
    String object,
    Uint8List plain,
    SecureKey key, {
    Map<String, dynamic> metadata = const {},
  }) {
    final nonce = sodium.randombytes.buf(24);
    final header = {
      ...metadata,
      ..._header(dataset, type, object),
      'nonce': base64Encode(nonce),
    };
    final cipher = sodium.crypto.aeadXChaCha20Poly1305IETF.encrypt(
      message: plain,
      nonce: nonce,
      key: key,
      additionalData: _bytes(header),
    );
    final encoded = _bytes({
      'header': header,
      'ciphertext': base64Encode(cipher),
    });
    if (encoded.length > maxObjectBytes) {
      throw const FormatException('Versleuteld bestand te groot.');
    }
    return encoded;
  }

  Uint8List open(
    String dataset,
    String type,
    String object,
    Uint8List bytes,
    SecureKey key,
  ) {
    try {
      final json = _read(bytes, dataset, type, object);
      final header = json['header'] as Map;
      return sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
        cipherText: base64Decode(json['ciphertext'] as String),
        nonce: base64Decode(header['nonce'] as String),
        key: key,
        additionalData: _bytes(header),
      );
    } catch (_) {
      throw const FormatException(
        'Versleuteld bestand is beschadigd, verwisseld of gebruikt een andere sleutel.',
      );
    }
  }

  Future<Uint8List> wrap(
    String dataset,
    SecureKey dek,
    String password,
    int generation,
  ) async {
    if (password.length < 12) {
      throw const FormatException(
        'Gebruik een wachtwoord van minstens 12 tekens.',
      );
    }
    final salt = sodium.randombytes.buf(16);
    final raw = await passwordKey(password, salt);
    final kek = importKey(raw);
    raw.fillRange(0, raw.length, 0);
    final plain = dek.extractBytes();
    try {
      return seal(
        dataset,
        'key',
        dataset,
        plain,
        kek,
        metadata: {
          'generation': generation,
          'kdf': 'argon2id',
          'kdfVersion': 19,
          'memory': 67108864,
          'iterations': 3,
          'parallelism': 1,
          'salt': base64Encode(salt),
        },
      );
    } finally {
      kek.dispose();
      plain.fillRange(0, plain.length, 0);
    }
  }

  Future<SecureKey> unwrap(
    String dataset,
    Uint8List bytes,
    String password,
  ) async {
    final json = _read(bytes, dataset, 'key', dataset);
    final h = json['header'] as Map;
    // Fixed, versioned parameters also prevent attacker-controlled KDF DoS.
    if (h['kdf'] != 'argon2id' ||
        h['kdfVersion'] != 19 ||
        h['memory'] != 67108864 ||
        h['iterations'] != 3 ||
        h['parallelism'] != 1 ||
        h['generation'] is! int ||
        (h['generation'] as int) < 1) {
      throw const FormatException('Onbekende wachtwoordversleuteling.');
    }
    final salt = base64Decode(h['salt'] as String);
    if (salt.length != 16) {
      throw const FormatException('Ongeldig wachtwoordbestand.');
    }
    final raw = await passwordKey(password, salt);
    final kek = importKey(raw);
    raw.fillRange(0, raw.length, 0);
    try {
      final plain = open(dataset, 'key', dataset, bytes, kek);
      try {
        if (plain.length != 32) {
          throw const FormatException('Ongeldige gegevenssleutel.');
        }
        return importKey(plain);
      } finally {
        plain.fillRange(0, plain.length, 0);
      }
    } catch (_) {
      throw const FormatException(
        'Wachtwoord onjuist of sleutelbestand beschadigd.',
      );
    } finally {
      kek.dispose();
    }
  }

  Future<Uint8List> sealSnapshot(
    String dataset,
    String object,
    Uint8List plain,
    SecureKey key,
  ) async {
    if (plain.isEmpty || plain.length > 20 * 1024 * 1024) {
      throw const FormatException(
        'De volledige back-up inclusief geschiedenis is groter dan 20 MB. Lokale gegevens blijven behouden.',
      );
    }
    final header = {
      ..._header(dataset, 'snapshot', object),
      'stream': true,
      'chunkSize': chunkSize,
    };
    Stream<SecretStreamPlainMessage> messages() async* {
      for (
        var offset = 0, index = 0;
        offset < plain.length;
        offset += chunkSize, index++
      ) {
        final end = (offset + chunkSize).clamp(0, plain.length);
        yield SecretStreamPlainMessage(
          Uint8List.sublistView(plain, offset, end),
          additionalData: _bytes([header, index]),
          tag: end == plain.length
              ? SecretStreamMessageTag.finalPush
              : SecretStreamMessageTag.message,
        );
      }
    }

    final frames = <String>[];
    await for (final frame in sodium.crypto.secretStream.pushEx(
      messageStream: messages(),
      key: key,
    )) {
      frames.add(base64Encode(frame.message));
    }
    final bytes = _bytes({'header': header, 'frames': frames});
    if (bytes.length > maxObjectBytes) {
      throw const FormatException('Reservekopie te groot.');
    }
    return bytes;
  }

  Future<Uint8List> openSnapshot(
    String dataset,
    String object,
    Uint8List bytes,
    SecureKey key,
  ) async {
    try {
      final json = _read(bytes, dataset, 'snapshot', object);
      final header = json['header'] as Map;
      if (header['stream'] != true || header['chunkSize'] != chunkSize) {
        throw const FormatException();
      }
      final frames = (json['frames'] as List).cast<String>();
      if (frames.length < 2 || frames.length > 400) {
        throw const FormatException();
      }
      Stream<SecretStreamCipherMessage> messages() async* {
        for (var i = 0; i < frames.length; i++) {
          final frame = base64Decode(frames[i]);
          if (frame.length > chunkSize + 64) throw const FormatException();
          yield SecretStreamCipherMessage(
            frame,
            additionalData: i == 0 ? null : _bytes([header, i - 1]),
          );
        }
      }

      final result = BytesBuilder(copy: false);
      await for (final message in sodium.crypto.secretStream.pullEx(
        cipherStream: messages(),
        key: key,
      )) {
        result.add(message.message);
        if (result.length > 20 * 1024 * 1024) throw const FormatException();
      }
      return result.takeBytes();
    } catch (_) {
      throw const FormatException(
        'Reservekopie beschadigd of onvolledig. De lokale gegevens zijn behouden.',
      );
    }
  }
}
