import 'dart:convert';

import 'package:idb_shim/idb_shim.dart';

import 'vault_types.dart';

/// Records and the book catalogue live in IndexedDB, never in the app cache.
class BrowserDatabase {
  BrowserDatabase(this.database);
  final Database database;
  static Future<BrowserDatabase> open(IdbFactory factory) async =>
      BrowserDatabase(
        await factory.open(
          'mosterdzaad-v1',
          version: 1,
          onUpgradeNeeded: (event) {
            event.database.createObjectStore('files');
            event.database.createObjectStore('books');
            event.database.createObjectStore('settings');
          },
        ),
      );

  Future<Object?> setting(String key) async {
    final tx = database.transaction('settings', idbModeReadOnly);
    final value = await tx.objectStore('settings').getObject(key);
    await tx.completed;
    return value;
  }

  Future<void> setSetting(String key, Object? value) async {
    final tx = database.transaction('settings', idbModeReadWrite);
    final store = tx.objectStore('settings');
    if (value == null) {
      await store.delete(key);
    } else {
      await store.put(value, key);
    }
    await tx.completed;
  }

  Future<List<VaultLocation>> books() async {
    final tx = database.transaction('books', idbModeReadOnly);
    final values = await tx.objectStore('books').getAll();
    await tx.completed;
    return values
        .map((v) => VaultLocation.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList();
  }
}

class BrowserVaultFiles implements VaultFiles {
  BrowserVaultFiles(this.db, this.location);
  final BrowserDatabase db;
  @override
  final VaultLocation location;
  String _key(String name) {
    checkRelative(name);
    return '${location.token}/$name';
  }

  @override
  Future<List<String>> list(String directory) async {
    final prefix = '${_key(directory)}/';
    final tx = db.database.transaction('files', idbModeReadOnly);
    final keys = await tx
        .objectStore('files')
        .getAllKeys(KeyRange.bound(prefix, '$prefix\uffff'));
    await tx.completed;
    return keys.cast<String>().map((k) => k.substring(prefix.length)).toList();
  }

  @override
  Future<String?> read(String name) async {
    final tx = db.database.transaction('files', idbModeReadOnly);
    final value = await tx.objectStore('files').getObject(_key(name));
    await tx.completed;
    return value as String?;
  }

  @override
  Future<void> writeNew(String name, String contents) async {
    final key = _key(name);
    final manifest = name == 'mosterdzaad.json'
        ? jsonDecode(contents) as Map
        : null;
    final tx = db.database.transactionList([
      'files',
      'books',
    ], idbModeReadWrite);
    // Observe completion before a failed add can abort the transaction.
    final completion = tx.completed;
    try {
      await tx.objectStore('files').add(contents, key);
      if (manifest != null) {
        await tx
            .objectStore('books')
            .put(
              VaultLocation(
                'browser',
                location.token,
                manifest['name'] as String,
              ).toJson(),
              location.token,
            );
      }
      await completion;
    } catch (_) {
      await completion.catchError((_) => db.database);
      rethrow;
    }
  }

  @override
  Future<void> makeDirectory(String name) async => checkRelative(name);
}
