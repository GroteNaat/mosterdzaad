import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecretStore {
  final _store = const FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  Future<String?> read(String key) => _store.read(key: 'mosterdzaad-v2/$key');
  Future<void> write(String key, String value) =>
      _store.write(key: 'mosterdzaad-v2/$key', value: value);
  Future<void> delete(String key) => _store.delete(key: 'mosterdzaad-v2/$key');
}

class LocalStateStore {
  LocalStateStore(this.directory);
  final String directory;
  final _writes = <String, Future<void>>{};
  File _file(String key) {
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(key)) {
      throw const FormatException('Ongeldige lokale sleutel.');
    }
    return File(p.join(directory, 'sync-v2', '$key.json'));
  }

  Future<String?> read(String key) async {
    final file = _file(key);
    return await file.exists() ? file.readAsString() : null;
  }

  Future<void> write(String key, String value) {
    final result = (_writes[key] ?? Future<void>.value()).then(
      (_) => _write(key, value),
    );
    _writes[key] = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _write(String key, String value) async {
    final file = _file(key);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(value, flush: true);
    await temporary.rename(file.path);
  }
}
