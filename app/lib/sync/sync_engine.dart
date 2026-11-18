import '../storage/vault_repository.dart';
import 'dropbox_client.dart';

/// Merge append-only histories, then atomically compare-and-swap the cloud file.
/// An interrupted transfer can never expose half a revision graph remotely.
class SyncEngine {
  SyncEngine(this.cloud);
  final CloudStore cloud;
  Future<void> synchronize(VaultRepository repo) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      final remote = await cloud.read(repo.id);
      final merged = remote == null
          ? await repo.snapshot()
          : await repo.mergeSnapshot(remote.snapshot);
      if (remote != null && merged.encode() == remote.snapshot.encode()) return;
      try {
        await cloud.write(repo.id, merged, remote?.revision);
        return;
      } on CloudChanged {
        // A different device uploaded after our download. Fetch, merge and retry.
      }
    }
    throw const DropboxFailure(
      'Het studieboek wordt op een ander apparaat bijgewerkt. Probeer opnieuw.',
    );
  }
}
