import 'dart:async';
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
import 'sync/dropbox_client.dart';
import 'sync/sync_engine.dart';

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
  final _syncBooks = <String>{};
  Timer? _syncDelay, _syncPoll;
  bool syncing = false;
  String? syncError;
  DateTime? lastSynced;
  bool get dropboxConnected => _dropboxSession?.valid ?? false;
  bool get syncEnabled => _syncBooks.contains(repository?.id);
  String get dropboxRedirect => oauthRedirect;
  DropboxClient _cloud(http.Client client) {
    if (!dropboxConnected) {
      throw const DropboxFailure(
        'Meld opnieuw aan bij Dropbox.',
        unauthorized: true,
      );
    }
    return DropboxClient(client, _dropboxSession!.accessToken);
  }

  Future<void> connectDropbox() async {
    if (dropboxAppKey.isEmpty) {
      throw const FormatException('Deze build heeft nog geen Dropbox-app key.');
    }
    final auth = DropboxAuthorization(redirect: oauthRedirect);
    // Launch directly from the tap: iOS blocks popups after unrelated async work.
    final callback = await FlutterWebAuth2.authenticate(
      url: auth.url.toString(),
      callbackUrlScheme: oauthLoopback ? oauthRedirect : 'nl.mosterdzaad',
      options: const FlutterWebAuth2Options(
        useWebview: false,
        timeout: 180,
        landingPageHtml:
            '<!doctype html><html lang="nl"><meta charset="utf-8"><title>Mosterdzaad</title><p>Keer terug naar Mosterdzaad om de aanmelding af te ronden.</p></html>',
      ),
    );
    final client = http.Client();
    try {
      _dropboxSession = await auth.exchange(callback, client);
      syncError = null;
      _syncPoll?.cancel();
      _syncPoll = Timer.periodic(const Duration(minutes: 1), (_) {
        if (syncEnabled) unawaited(syncNow());
      });
      notifyListeners();
    } finally {
      client.close();
    }
  }

  Future<void> enableSync() async {
    final repo = repository;
    if (repo == null) return;
    if (!dropboxConnected) await connectDropbox();
    if (repository != repo) return;
    _syncBooks.add(repo.id);
    await syncNow();
  }

  void disconnectDropbox() {
    if (syncing) return;
    _syncDelay?.cancel();
    _syncPoll?.cancel();
    _dropboxSession = null;
    _syncBooks.clear();
    syncError = null;
    lastSynced = null;
    notifyListeners();
  }

  Future<void> syncNow() async {
    final repo = repository;
    if (syncing || repo == null || !syncEnabled) return;
    syncing = true;
    syncError = null;
    notifyListeners();
    final client = http.Client();
    try {
      await SyncEngine(_cloud(client)).synchronize(repo);
      if (repository == repo) {
        lastSynced = DateTime.now();
        await rebuildIndex();
      }
    } catch (e) {
      if (repository == repo) syncError = describeError(e);
      if (e is DropboxFailure && e.unauthorized) _dropboxSession = null;
    } finally {
      client.close();
      syncing = false;
      notifyListeners();
    }
  }

  Future<List<CloudBook>> cloudBooks() async {
    final client = http.Client();
    try {
      return await _cloud(client).listBooks();
    } finally {
      client.close();
    }
  }

  Future<VaultSnapshot> cloudSnapshot(String id) async {
    final client = http.Client();
    try {
      final version = await _cloud(client).read(id);
      if (version == null) {
        throw const FormatException(
          'Dit Dropbox-studieboek bestaat niet meer.',
        );
      }
      await version.snapshot.validate(bible);
      return version.snapshot;
    } finally {
      client.close();
    }
  }

  Future<void> restoreSnapshot(
    VaultSnapshot snapshot, {
    bool fromDropbox = false,
  }) async {
    await snapshot.validate(bible);
    final parent = await picker.pick();
    if (parent == null) return;
    final location = await picker.createChild(
      parent,
      'Studieboek-${const Uuid().v4().substring(0, 8)}',
    );
    await snapshot.restoreTo(picker.files(location), bible);
    await open(location);
    if (fromDropbox) {
      _syncBooks.add(snapshot.id);
      await syncNow();
    }
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
    }
  }

  Future<void> open(VaultLocation location) async {
    final repo = VaultRepository(picker.files(location), bible);
    await repo.reload();
    await attach(repo);
  }

  Future<void> attach(VaultRepository repo) async {
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
      notice =
          'De map wordt niet onthouden. Je kunt dit studieboek de volgende keer opnieuw openen.';
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
      notice =
          'Je browser kan lokale gegevens opruimen. Maak regelmatig een reservekopie of synchroniseer met Dropbox.';
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
    }
  }

  Future<void> refresh() => run(() async {
    await repository?.reload();
    await rebuildIndex();
    if (syncEnabled) await syncNow();
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
      expected: parents ?? (original == null ? [] : [original.revision]),
      expectedHashes: original?.fileFingerprint == null
          ? null
          : {original!.revision: original.fileFingerprint!},
      deleted: deleted,
    );
    await rebuildIndex();
    if (syncEnabled) {
      _syncDelay?.cancel();
      _syncDelay = Timer(
        const Duration(seconds: 2),
        () => unawaited(syncNow()),
      );
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
    _syncDelay?.cancel();
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
    _syncDelay?.cancel();
    _syncPoll?.cancel();
    unawaited(index?.close());
    super.dispose();
  }
}
