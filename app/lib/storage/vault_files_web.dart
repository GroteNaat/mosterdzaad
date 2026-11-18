import 'package:idb_shim/idb_browser.dart';
import 'package:uuid/uuid.dart';
import 'browser_database.dart';
import 'vault_types.dart';

final browserDatabase = BrowserDatabase.open(idbFactoryWeb);

class VaultPicker {
  Future<List<VaultLocation>> listBooks() async =>
      (await browserDatabase).books();
  Future<VaultLocation?> pick() async =>
      const VaultLocation('browser', '', 'Deze browser');
  VaultFiles files(VaultLocation location) => _DeferredFiles(location);
  Future<VaultLocation> createChild(VaultLocation parent, String name) async =>
      VaultLocation('browser', const Uuid().v4(), name);
}

class _DeferredFiles implements VaultFiles {
  _DeferredFiles(this.location);
  @override
  final VaultLocation location;
  Future<BrowserVaultFiles> get files async =>
      BrowserVaultFiles(await browserDatabase, location);
  @override
  Future<List<String>> list(String directory) async =>
      (await files).list(directory);
  @override
  Future<String?> read(String name) async => (await files).read(name);
  @override
  Future<void> writeNew(String name, String contents) async =>
      (await files).writeNew(name, contents);
  @override
  Future<void> makeDirectory(String name) async =>
      (await files).makeDirectory(name);
}

class RecentVaultStore {
  RecentVaultStore(String directory);
  Future<VaultLocation?> load() async {
    final value = await (await browserDatabase).setting('recent');
    return value == null
        ? null
        : VaultLocation.fromJson(Map<String, dynamic>.from(value as Map));
  }

  Future<void> save(VaultLocation location) async =>
      (await browserDatabase).setSetting('recent', location.toJson());
  Future<void> clear() async =>
      (await browserDatabase).setSetting('recent', null);
}
