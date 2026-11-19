import 'dart:js_interop';

import '../storage/vault_files_web.dart';

@JS('mosterdzaadSecrets.read')
external JSPromise<JSAny?> _read(JSString key);
@JS('mosterdzaadSecrets.write')
external JSPromise<JSAny?> _write(JSString key, JSString value);
@JS('mosterdzaadSecrets.remove')
external JSPromise<JSAny?> _remove(JSString key);

/// A non-exportable WebCrypto key in IndexedDB wraps browser secrets.
/// This is origin/profile protection, NOT an OS keychain or XSS protection.
class SecretStore {
  Future<String?> read(String key) async =>
      (await _read(key.toJS).toDart as JSString?)?.toDart;
  Future<void> write(String key, String value) async {
    await _write(key.toJS, value.toJS).toDart;
  }

  Future<void> delete(String key) async {
    await _remove(key.toJS).toDart;
  }
}

class LocalStateStore {
  LocalStateStore(String directory);
  Future<String?> read(String key) async =>
      await (await browserDatabase).setting('sync-v2/$key') as String?;
  Future<void> write(String key, String value) async =>
      (await browserDatabase).setSetting('sync-v2/$key', value);
}
