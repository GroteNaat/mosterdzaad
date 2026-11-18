import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'domain/bible.dart';
import 'domain/entry.dart';
import 'storage/vault_files.dart';
import 'storage/vault_repository.dart';
import 'storage/search_index.dart';

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
  final Directory supportDirectory, cacheDirectory;
  final VaultPicker picker;
  VaultRepository? repository;
  SearchIndex? index;
  bool busy = false;
  String? error, notice;
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
    try {
      await recent.save(repo.files.location);
    } catch (_) {
      notice =
          'De map wordt niet onthouden. Je kunt dit studieboek de volgende keer opnieuw openen.';
    }
    try {
      await cacheDirectory.create(recursive: true);
      index = SearchIndex(
        File(p.join(cacheDirectory.path, '${repo.id}.sqlite')),
      );
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
    await recent.clear();
    await index?.close();
    index = null;
    repository = null;
    error = null;
    notice = null;
    notifyListeners();
  }
}
