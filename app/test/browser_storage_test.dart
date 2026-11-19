import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosterdzaad/domain/bible.dart';
import 'package:mosterdzaad/storage/browser_database.dart';
import 'package:mosterdzaad/storage/vault_repository.dart';
import 'package:mosterdzaad/storage/vault_types.dart';

import 'idb_factory_native.dart'
    if (dart.library.js_interop) 'idb_factory_web.dart';

void main() {
  test('Browser studybook, catalogue and recent location survive database close/reopen', () async {
    await testFactory.deleteDatabase('mosterdzaad-v1');
    final bible = Bible(
      await rootBundle.loadString('assets/data/books.json'),
      await rootBundle.loadString('assets/data/books-original.json'),
    );
    const location = VaultLocation('browser', 'test-book', 'Mijn browserboek');
    var db = await BrowserDatabase.open(testFactory);
    final repo = await VaultRepository.create(
      BrowserVaultFiles(db, location),
      bible,
      'Mijn browserboek',
      'english',
      false,
    );
    await repo.save('theme', {'name': 'Vertrouwen', 'description': ''});
    await db.setSetting('recent', location.toJson());
    final snapshot = (await repo.snapshot()).encode();
    db.database.close();
    db = await BrowserDatabase.open(testFactory);
    final reopened = VaultRepository(BrowserVaultFiles(db, location), bible);
    await reopened.reload();
    expect(reopened.ofKind('theme').single.text('name'), 'Vertrouwen');
    expect((await reopened.snapshot()).encode(), snapshot);
    expect((await db.books()).single.label, 'Mijn browserboek');
    expect(await db.setting('recent'), location.toJson());
    db.database.close();
    await testFactory.deleteDatabase('mosterdzaad-v1');
  });
  test(
    'IndexedDB cannot overwrite a revision and catalogues only published books',
    () async {
      await testFactory.deleteDatabase('mosterdzaad-v1');
      final db = await BrowserDatabase.open(testFactory);
      final files = BrowserVaultFiles(
        db,
        const VaultLocation('browser', 'new-book', 'Nieuw'),
      );
      await files.writeNew('records/record.json', 'original');
      expect(await db.books(), isEmpty);
      await expectLater(
        files.writeNew('records/record.json', 'replacement'),
        throwsA(anything),
      );
      expect(await files.read('records/record.json'), 'original');
      expect(await files.list('records'), ['record.json']);
      db.database.close();
      await testFactory.deleteDatabase('mosterdzaad-v1');
    },
  );
}
