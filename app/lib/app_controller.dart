import 'dart:async';

import 'package:sodium/sodium_sumo.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import 'platform/platform_services.dart';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'domain/bible.dart';
import 'domain/entry.dart';
import 'storage/vault_files.dart';
import 'storage/vault_repository.dart';
import 'storage/search_index.dart';
import 'storage/vault_snapshot.dart';
import 'sync/dropbox_auth.dart';
import 'sync/crypto_box.dart';
import 'sync/encrypted_cloud.dart';
import 'sync/encrypted_sync.dart';
import 'sync/local_state.dart';
import 'sync/background_sync.dart';
import 'sync/sync_trigger.dart';

String describeError(Object error) => error is FormatException
    ? error.message
    : error
          .toString()
          .replaceFirst('PlatformException(storage, ', '')
          .replaceFirst('Exception: ', '');

class AppController extends ChangeNotifier {
  AppController({
    required this.bible,
    required this.supportDirectory,
    required this.cacheDirectory,
    VaultPicker? picker,
  }) : picker = picker ?? VaultPicker();
  final Bible bible;
  final String supportDirectory, cacheDirectory;
  final VaultPicker picker;
  VaultRepository? repository;
  SearchIndex? index;
  bool busy = false;
  String? error, notice;
  DropboxSession? _dropboxSession;
  String? _refreshToken;
  final _secrets = SecretStore();
  late final _state = LocalStateStore(supportDirectory);
  late final _crypto = Future<SodiumSumo>.sync(SodiumSumoInit.init)
      .then(CryptoBox.new);
  final _http = http.Client();
  SyncJournal? _journal;
  SecureKey? _dataKey;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  late final _syncTrigger = SyncTrigger(
    canRun: () => syncEnabled && dropboxConnected && !busy && !syncing,
    synchronize: syncNow,
  );
  bool syncing = false, syncOffline = false;
  String? syncError;
  DateTime? lastSynced;
  DateTime? get lastBackup => _journal?.lastBackup;
  int get pendingChanges => _journal == null
      ? 0
      : repository?.history
                .where((e) => !_journal!.acknowledged.containsKey(e.revision))
                .length ??
            0;
  bool get dropboxConnected => _dropboxSession != null || _refreshToken != null;
  bool get syncEnabled =>
      _journal != null && _dataKey != null && repository != null;
  String get dropboxRedirect => oauthRedirect;
  Future<EncryptedSync> _engine([http.Client? client]) async => EncryptedSync(
    DropboxObjects(client ?? _http, _token),
    await _crypto,
    _state,
    _secrets,
    bible,
  );

  Future<String> _token(bool force) async {
    if (!force && _dropboxSession?.valid == true) {
      return _dropboxSession!.accessToken;
    }
    _refreshToken ??= await _secrets.read('dropbox-refresh');
    if (_refreshToken == null) {
      throw const DropboxFailure('Koppel Dropbox opnieuw.', unauthorized: true);
    }
    _dropboxSession = await refreshDropbox(_refreshToken!, _http);
    return _dropboxSession!.accessToken;
  }

  Future<void> connectDropbox() async {
    final auth = DropboxAuthorization(redirect: oauthRedirect);
    final callback = await FlutterWebAuth2.authenticate(
      url: auth.url.toString(),
      callbackUrlScheme: oauthLoopback ? oauthRedirect : 'nl.mosterdzaad',
      options: const FlutterWebAuth2Options(
        useWebview: false,
        timeout: 180,
        landingPageHtml: '<!doctype html><html lang="nl"><meta charset="utf-8"><title>Mosterdzaad</title><p>Keer terug naar Mosterdzaad.</p></html>',
      ),
    );
    _dropboxSession = await auth.exchange(callback, _http);
    _refreshToken = _dropboxSession!.refreshToken;
    if (_refreshToken != null) {
      await _secrets.write('dropbox-refresh', _refreshToken!);
    }
    syncError = null;
    _startAutomaticSync();
    requestSync();
    notifyListeners();
  }

  Future<void> _resumeSync() async {
    _stopAutomaticSync();
    _dataKey?.dispose();
    _dataKey = null;
    _journal = null;
    final repo = repository;
    if (repo == null) return;
    final stored = await _state.read('book-${repo.id}');
    if (stored == null) return; // Purely local users never need a keychain.
    _refreshToken ??= await _secrets.read('dropbox-refresh');
    final binding = await (await _engine()).load(repo.id);
    if (binding == null || repository != repo) {
      binding?.$2.dispose();
      return;
    }
    _journal = binding.$1;
    _dataKey = binding.$2;
    repo.actor = _journal!.actor;
    lastSynced = _journal!.lastSuccess;
    if (dropboxConnected) {
      _startAutomaticSync();
      requestSync();
    }
  }

  Future<void> enableSync(String password) async {
    final repo = repository;
    if (repo == null) return;
    if (!dropboxConnected) await connectDropbox();
    final binding = await (await _engine()).create(repo, password);
    _dataKey?.dispose();
    _journal = binding.$1;
    _dataKey = binding.$2;
    _startAutomaticSync();
    await syncNow(rethrowErrors: true);
  }

  Future<void> disconnectDropbox() async {
    if (syncing) return;
    _stopAutomaticSync();
    await _secrets.delete('dropbox-refresh');
    await cancelBackground();
    if (_journal != null) await _secrets.delete('dek/${_journal!.dataset}');
    _dataKey?.dispose();
    _dataKey = null;
    _journal = null;
    _dropboxSession = null;
    _refreshToken = null;
    syncError = null;
    lastSynced = null;
    notifyListeners();
  }

  void _stopAutomaticSync() {
    _syncTrigger.cancel();
    unawaited(_connectivity?.cancel());
    _connectivity = null;
  }

  void _startAutomaticSync() {
    if (!syncEnabled || !dropboxConnected || _connectivity != null) return;
    // OS/browser events only: this does not probe Dropbox in the background.
    _connectivity = Connectivity().onConnectivityChanged.listen(
      (connections) {
        if (connections.any((c) => c != ConnectivityResult.none) &&
            (syncOffline || pendingChanges > 0)) {
          requestSync();
        }
      },
      // Some systems cannot observe connectivity. Focus/save/manual still work.
      onError: (Object _) {},
    );
  }

  /// Startup, foreground/window focus, and reconnection share one queue.
  void requestSync({Duration delay = const Duration(milliseconds: 400)}) {
    if (syncEnabled && dropboxConnected) _syncTrigger.request(delay: delay);
  }

  Future<void> syncNow({bool rethrowErrors = false}) async {
    final repo = repository, journal = _journal, key = _dataKey;
    if (repo == null || journal == null || key == null) return;
    if (syncing || (!rethrowErrors && busy)) {
      requestSync();
      return;
    }
    // This run also satisfies any earlier focus/startup/save request.
    _syncTrigger.cancel();
    syncing = true;
    syncError = null;
    notifyListeners();
    try {
      await (await _engine()).synchronize(repo, journal, key);
      syncOffline = false;
      lastSynced = journal.lastSuccess;
      if (repository == repo) await rebuildIndex();
    } catch (e) {
      syncOffline =
          e is CloudOffline ||
          e is http.ClientException ||
          e is TimeoutException;
      if (!syncOffline) syncError = describeError(e);
      // Discard any uncommitted in-memory cursor after an interrupted merge.
      try {
        final saved = await _state.read('book-${repo.id}');
        if (saved != null) _journal = SyncJournal.decode(saved);
      } catch (_) {
        syncError = 'De synchronisatiestatus kon niet worden gelezen. Je wijzigingen zijn lokaal bewaard.';
      }
      if (rethrowErrors) rethrow;
    } finally {
      syncing = false;
      notifyListeners();
      _syncTrigger.wake();
    }
  }

  Future<void> backupNow() async {
    await syncNow(rethrowErrors: true);
    await (await _engine()).backup(repository!, _journal!, _dataKey!);
    notifyListeners();
  }

  Future<void> compactBackups() async {
    await (await _engine()).compact(repository!, _journal!, _dataKey!);
    notifyListeners();
  }

  Future<void> changeSyncPassword(String password) async {
    await (await _engine()).changePassword(
      repository!.id,
      _journal!,
      _dataKey!,
      password,
    );
    notifyListeners();
  }

  Future<void> setBackupPolicy(int hours, int operations, int retention) async {
    _journal!
      ..snapshotEveryHours = hours.clamp(1, 168)
      ..snapshotEveryOperations = operations.clamp(1, 10000)
      ..retainSnapshots = retention.clamp(2, 100);
    await (await _engine()).persist(repository!.id, _journal!);
    notifyListeners();
  }

  Future<List<RestorePoint>> restorePoints() async =>
      (await _engine()).restorePoints(_journal!.dataset, _dataKey!);
  Future<void> restorePoint(RestorePoint point) async {
    await restoreSnapshot(await point.snapshot.separateCopy(bible));
    notice = 'Hersteld als afzonderlijk studieboek. Het vorige studieboek en de wijzigingen op je andere apparaten blijven beschikbaar.';
    notifyListeners();
  }

  Future<List<String>> cloudBooks() async => (await _engine()).datasets();
  Future<void> openCloud(
    String dataset,
    String password, {
    required bool mergeLocal,
  }) async {
    final engine = await _engine();
    final (journal, key, cloudSnapshot) = await engine.unlock(
      dataset,
      password,
    );
    try {
      var snapshot = cloudSnapshot;
      final local = repository == null ? null : await repository!.snapshot();
      if (mergeLocal && local != null) {
        snapshot = local.id == snapshot.id
            ? snapshot.union(local)
            : await local.copyInto(snapshot, bible);
      }
      final parent = await picker.pick();
      if (parent == null) return;
      final location = await picker.createChild(
        parent,
        'Studieboek-${const Uuid().v4().substring(0, 8)}',
      );
      await snapshot.restoreTo(picker.files(location), bible);
      final repo = VaultRepository(picker.files(location), bible);
      await repo.reload();
      await attach(repo, resumeSync: false);
      _dataKey?.dispose();
      _dataKey = key.copy();
      _journal = journal;
      repo.actor = journal.actor;
      await engine.rememberKey(dataset, key);
      await engine.persist(repo.id, journal);
      _startAutomaticSync();
      await syncNow(rethrowErrors: true);
    } finally {
      key.dispose();
    }
  }

  Future<void> restoreSnapshot(VaultSnapshot snapshot) async {
    await snapshot.validate(bible);
    final parent = await picker.pick();
    if (parent == null) return;
    final location = await picker.createChild(
      parent,
      'Studieboek-${const Uuid().v4().substring(0, 8)}',
    );
    await snapshot.restoreTo(picker.files(location), bible);
    final repo = VaultRepository(picker.files(location), bible);
    await repo.reload();
    await attach(repo, resumeSync: false);
  }

  Future<void> exportBackup() async {
    final snapshot = await repository!.snapshot();
    await downloadBackup(
      'Mosterdzaad-${snapshot.id}.mosterdzaad.json',
      snapshot.encode(),
    );
  }

  RecentVaultStore get recent => RecentVaultStore(supportDirectory);
  List<Entry> get entries => repository?.entries ?? [];
  List<Entry> ofKind(String kind) =>
      entries.where((e) => e.kind == kind).toList();
  Map<String, Set<int>> get covered =>
      coverage(ofKind('note').map((n) => n.passages));

  Future<void> start() async {
    busy = true;
    notifyListeners();
    try {
      final location = await recent.load();
      if (location != null) await open(location);
    } catch (e) {
      error =
          'Het vorige studieboek kon niet worden geopend. Kies de map opnieuw. ${describeError(e)}';
    } finally {
      busy = false;
      notifyListeners();
      _syncTrigger.wake();
    }
  }

  Future<void> open(VaultLocation location) async {
    final repo = VaultRepository(picker.files(location), bible);
    await repo.reload();
    await attach(repo);
  }

  Future<void> attach(VaultRepository repo, {bool resumeSync = true}) async {
    _stopAutomaticSync();
    _dataKey?.dispose();
    _dataKey = null;
    _journal = null;
    await index?.close();
    index = null;
    repository = repo;
    error = null;
    notice = null;
    lastSynced = null;
    syncError = null;
    try {
      await recent.save(repo.files.location);
    } catch (_) {
      notice = 'De map wordt niet onthouden. Je kunt dit studieboek de volgende keer opnieuw openen.';
    }
    try {
      index = await createSearchIndex(cacheDirectory, repo.id);
      await index!.rebuild(entries);
    } catch (_) {
      await index?.close();
      index = null;
      notice =
          'De zoekindex is niet beschikbaar. Eenvoudig zoeken blijft werken.';
    }
    notifyListeners();
    if (resumeSync) {
      try {
        await _resumeSync();
      } catch (_) {
        syncError = 'De veilige sleutelopslag is niet beschikbaar. Koppel Dropbox opnieuw wanneer deze is ontgrendeld.';
        notifyListeners();
      }
    }
  }

  Future<void> chooseExisting() async => run(() async {
    final location = await picker.pick();
    if (location != null) await open(location);
  });
  Future<void> create(String name, String scheme, bool extra) async {
    final parent = await picker.pick();
    if (parent == null) return;
    final safeName = name
        .trim()
        .replaceAll(RegExp(r'[^\p{L}\p{N} _-]', unicode: true), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    final folderName =
        '${safeName.isEmpty ? 'Studieboek' : safeName}-${const Uuid().v4().substring(0, 8)}';
    final location = await picker.createChild(parent, folderName);
    await attach(
      await VaultRepository.create(
        picker.files(location),
        bible,
        name,
        scheme,
        extra,
      ),
    );
    if (kIsWeb && !await requestPersistence()) {
      notice = 'Je browser kan lokale gegevens opruimen. Maak regelmatig een reservekopie of synchroniseer met Dropbox.';
      notifyListeners();
    }
  }

  Future<void> run(Future<void> Function() operation) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await operation();
    } catch (e) {
      error = describeError(e);
    } finally {
      busy = false;
      notifyListeners();
      _syncTrigger.wake();
    }
  }

  Future<void> refresh() => run(() async {
    await repository?.reload();
    await rebuildIndex();
    if (syncEnabled) await syncNow(rethrowErrors: true);
  });
  Future<void> rebuildIndex() async {
    try {
      await index?.rebuild(entries);
    } catch (_) {
      notice = 'De zoekindex kon niet worden bijgewerkt.';
      await index?.close();
      index = null;
    }
    notifyListeners();
  }

  Future<Entry> save(
    String kind,
    Map<String, dynamic> data, {
    Entry? original,
    String? id,
    List<String>? parents,
    bool deleted = false,
  }) async {
    final result = await repository!.save(
      kind,
      data,
      entityId: original?.id ?? id,
      expected:
          parents ??
          original?.causalHeads ??
          (original == null ? [] : [original.revision]),
      expectedHashes:
          original?.causalHashes ??
          (original?.fileFingerprint == null
              ? null
              : {original!.revision: original.fileFingerprint!}),
      deleted: deleted,
    );
    await rebuildIndex();
    if (syncEnabled) {
      try {
        await (await _engine()).stage(repository!, _journal!, _dataKey!);
        await scheduleBackground(supportDirectory, repository!.id);
      } catch (_) {
        notice = 'Je wijziging is lokaal opgeslagen. Achtergrondsynchronisatie is nog niet beschikbaar; houd de app open om te synchroniseren.';
        notifyListeners();
      }
      requestSync(delay: const Duration(seconds: 2));
    }
    return result;
  }

  Future<Set<String>> search(String value) async {
    if (index != null) return index!.search(value);
    final titles = {for (final e in entries) e.id: e.title};
    return entries
        .where(
          (e) =>
              '${e.title} ${e.text('body')} ${e.text('references')} ${['themes', 'plans', 'studies'].expand(e.links).map((id) => titles[id] ?? '').join(' ')}'
                  .toLowerCase()
                  .contains(value.toLowerCase()),
        )
        .map((e) => e.id)
        .toSet();
  }

  Future<void> closeBook() async {
    if (syncing) {
      throw const FormatException('Wacht tot de synchronisatie is afgerond.');
    }
    _stopAutomaticSync();
    _dataKey?.dispose();
    _dataKey = null;
    _journal = null;
    await recent.clear();
    await index?.close();
    index = null;
    repository = null;
    error = null;
    notice = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopAutomaticSync();
    _syncTrigger.dispose();
    _http.close();
    _dataKey?.dispose();
    unawaited(index?.close());
    super.dispose();
  }
}
