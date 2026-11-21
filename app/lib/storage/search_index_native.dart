import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../domain/entry.dart';

/// Disposable index. All original data lives in the selected studybook folder.
class SearchIndex extends GeneratedDatabase {
  SearchIndex(File file) : super(NativeDatabase.createInBackground(file));
  SearchIndex.memory() : super(NativeDatabase.memory());
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await customStatement(
        'CREATE TABLE search_entries (id TEXT PRIMARY KEY, kind TEXT NOT NULL, text TEXT NOT NULL)',
      );
    },
  );
  Future<void> rebuild(List<Entry> entries) async {
    await customStatement('PRAGMA secure_delete=ON');
    await transaction(() async {
      await customStatement('DELETE FROM search_entries');
      final titles = {for (final e in entries) e.id: e.title};
      for (final e in entries) {
        final related = [
          'themes',
          'plans',
          'studies',
        ].expand(e.links).map((id) => titles[id] ?? '').join(' ');
        await customStatement(
          'INSERT INTO search_entries (id, kind, text) VALUES (?, ?, ?)',
          [
            e.id,
            e.kind,
            '${e.title} ${e.text('body')} ${e.text('description')} ${e.text('references')} $related'
                .toLowerCase(),
          ],
        );
      }
    });
  }

  Future<void> compact() async {
    await customStatement('VACUUM');
    await customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
  }

  Future<Set<String>> search(String query) async {
    final escaped = query
        .toLowerCase()
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    final rows = await customSelect(
      "SELECT id FROM search_entries WHERE text LIKE ? ESCAPE '\\'",
      variables: [Variable<String>('%$escaped%')],
    ).get();
    return rows.map((r) => r.read<String>('id')).toSet();
  }
}
