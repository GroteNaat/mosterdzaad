import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosterdzaad/domain/entry.dart';
import 'package:mosterdzaad/storage/vault_repository.dart';
import 'package:mosterdzaad/storage/vault_files.dart';
import 'package:mosterdzaad/storage/search_index.dart';
import 'package:uuid/uuid.dart';
import 'helpers.dart';

void main() {
  final bible = testBible();
  late MemoryFiles files;
  late VaultRepository repo;
  setUp(() async {
    files = MemoryFiles();
    repo = await VaultRepository.create(
      files,
      bible,
      'Mijn studieboek',
      'english',
      false,
    );
  });

  test(
    'Create, edit, reopen, delete and restore preserve complete history',
    () async {
      final first = await repo.save(
        'note',
        noteData(bible, body: 'Origineel\n\nEen tweede regel.'),
      );
      final second = await repo.save(
        'note',
        noteData(bible, body: 'Bijgewerkt'),
        entityId: first.id,
        expected: [first.revision],
      );
      expect(
        files.contents['records/${first.filename}'],
        contains('Origineel'),
      );
      final reopened = VaultRepository(files, bible);
      await reopened.reload();
      expect(reopened.ofKind('note').single.text('body'), 'Bijgewerkt');
      final tombstone = await reopened.save(
        'note',
        second.data,
        entityId: second.id,
        expected: [second.revision],
        deleted: true,
      );
      expect(reopened.ofKind('note'), isEmpty);
      await reopened.save(
        'note',
        first.data,
        entityId: first.id,
        expected: [tombstone.revision],
      );
      expect(reopened.ofKind('note').single.text('body'), first.text('body'));
      expect(reopened.history.where((e) => e.kind == 'note').length, 4);
    },
  );
  test('Existing studybook is never overwritten by creation', () async {
    final before = Map.of(files.contents);
    await expectLater(
      VaultRepository.create(files, bible, 'Nieuw', 'english', false),
      throwsFormatException,
    );
    expect(files.contents, before);
  });
  test('Stale edits fail without replacing another writer', () async {
    final first = await repo.save('note', noteData(bible));
    final other = VaultRepository(files, bible);
    await other.reload();
    await other.save(
      'note',
      noteData(bible, body: 'Ander apparaat'),
      entityId: first.id,
      expected: [first.revision],
    );
    await expectLater(
      repo.save(
        'note',
        noteData(bible, body: 'Mijn concept'),
        entityId: first.id,
        expected: [first.revision],
      ),
      throwsA(isA<VaultConflict>()),
    );
    expect(repo.ofKind('note').single.text('body'), 'Ander apparaat');
  });
  test('Concurrent branches are kept and can be explicitly resolved', () async {
    final first = await repo.save('note', noteData(bible));
    final one = await repo.save(
      'note',
      noteData(bible, body: 'Eerste apparaat'),
      entityId: first.id,
      expected: [first.revision],
    );
    final other = Entry(
      id: first.id,
      revision: const Uuid().v4(),
      parents: [first.revision],
      kind: 'note',
      data: noteData(bible, body: 'Tweede apparaat'),
      updated: DateTime.now(),
    );
    await files.writeNew('records/${other.filename}', other.encode());
    await repo.reload();
    expect(repo.conflicts.single.length, 2);
    expect(repo.ofKind('note'), isEmpty);
    await repo.save(
      'note',
      one.data,
      entityId: first.id,
      expected: [one.revision, other.revision],
    );
    expect(repo.conflicts, isEmpty);
    expect(repo.ofKind('note').single.text('body'), 'Eerste apparaat');
  });
  test(
    'External Markdown edits cannot be lost after a background refresh',
    () async {
      final first = await repo.save('note', noteData(bible));
      final original = repo.ofKind('note').single;
      final path = 'records/${first.filename}';
      files.contents[path] = files.contents[path]!.replaceFirst(
        'Een gedachte',
        'Bewerkt met een teksteditor',
      );
      await repo.reload();
      await expectLater(
        repo.save(
          'note',
          noteData(bible, body: 'Concept dat nog open stond'),
          entityId: first.id,
          expected: [first.revision],
          expectedHashes: {first.revision: original.fileFingerprint!},
        ),
        throwsA(isA<VaultConflict>()),
      );
      expect(
        repo.ofKind('note').single.text('body'),
        'Bewerkt met een teksteditor',
      );
    },
  );
  test(
    'Disk failures preserve old data and do not create a fake saved state',
    () async {
      final note = await repo.save('note', noteData(bible));
      files.failWrite = true;
      await expectLater(
        repo.save(
          'note',
          noteData(bible, body: 'Niet bewaard'),
          entityId: note.id,
          expected: [note.revision],
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(repo.ofKind('note').single.text('body'), 'Een gedachte');
    },
  );
  test(
    'Interrupted records are reported and further edits are blocked',
    () async {
      await repo.save('note', noteData(bible));
      files.contents['records/${const Uuid().v4()}.md'] = '---\n{"incomplete":';
      await repo.reload();
      expect(repo.warnings, hasLength(1));
      expect(repo.ofKind('note'), hasLength(1));
      await expectLater(
        repo.save('note', noteData(bible)),
        throwsA(isA<VaultConflict>()),
      );
    },
  );
  test(
    'Revoked permission and unsupported formats never become empty books',
    () async {
      files.denied = true;
      await expectLater(repo.reload(), throwsA(isA<FileSystemException>()));
      files.denied = false;
      files.contents['mosterdzaad.json'] =
          '{"format":"mosterdzaad-studybook","version":99}';
      await expectLater(repo.reload(), throwsFormatException);
    },
  );
  test('Versification stays fixed even after a note is deleted', () async {
    final note = await repo.save('note', noteData(bible));
    await repo.save(
      'note',
      note.data,
      entityId: note.id,
      expected: [note.revision],
      deleted: true,
    );
    final prefs = repo.ofKind('preferences').single;
    await expectLater(
      repo.save(
        'preferences',
        {'versification': 'original', 'deuterocanonical': false},
        entityId: prefs.id,
        expected: [prefs.revision],
      ),
      throwsFormatException,
    );
  });
  test('Group references and note connections are validated', () async {
    await expectLater(
      repo.save('note', noteData(bible, body: '  ')),
      throwsFormatException,
    );
    await expectLater(
      repo.save('note', noteData(bible, references: '')),
      throwsFormatException,
    );
    final group = await repo.save('group', {'name': 'Bijbelkring'});
    await repo.save('study', {
      'title': 'Samen lezen',
      'date': '2026-11-17',
      'kind': 'group',
      'group': group.id,
    });
    await expectLater(
      repo.save(
        'group',
        group.data,
        entityId: group.id,
        expected: [group.revision],
        deleted: true,
      ),
      throwsFormatException,
    );
  });
  test(
    'Real folder survives repository recreation and blocks overwrite/traversal',
    () async {
      final dir = await Directory.systemTemp.createTemp('mosterdzaad-test-');
      try {
        final fs = LocalVaultFiles(VaultLocation('path', dir.path, 'Test'));
        final disk = await VaultRepository.create(
          fs,
          bible,
          'Op schijf',
          'english',
          false,
        );
        final note = await disk.save('note', noteData(bible));
        final reopened = VaultRepository(fs, bible);
        await reopened.reload();
        expect(reopened.ofKind('note').single.id, note.id);
        await expectLater(
          fs.writeNew('mosterdzaad.json', 'overwrite'),
          throwsA(isA<FileSystemException>()),
        );
        expect(() => fs.path('../escape'), throwsFormatException);
        expect(() => fs.path('C:/escape'), throwsFormatException);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'SQLite index can be rebuilt and searches linked titles literally',
    () async {
      final theme = await repo.save('theme', {
        'name': 'Genade',
        'description': '',
      });
      await repo.save('note', {
        ...noteData(bible, body: '100% vertrouwen'),
        'themes': [theme.id],
      });
      final index = SearchIndex.memory();
      try {
        await index.rebuild(repo.entries);
        expect(
          await index.search('genade'),
          contains(repo.ofKind('note').single.id),
        );
        expect(
          await index.search('%'),
          contains(repo.ofKind('note').single.id),
        );
        expect(await index.search('_'), isEmpty);
        await index.rebuild([]);
        expect(await index.search('vertrouwen'), isEmpty);
      } finally {
        await index.close();
      }
    },
  );
}
