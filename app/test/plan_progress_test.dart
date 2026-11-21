import 'package:flutter_test/flutter_test.dart';
import 'package:mosterdzaad/domain/entry.dart';
import 'package:mosterdzaad/domain/plan_progress.dart';
import 'package:mosterdzaad/storage/vault_repository.dart';
import 'package:uuid/uuid.dart';

import 'helpers.dart';

void main() {
  test(
    'Restoring legacy sessions preserves their explicit note links',
    () async {
      final bible = testBible();
      final repo = await VaultRepository.create(
        MemoryFiles(),
        bible,
        'Sessions',
        'english',
        false,
      );
      final plan = await repo.save('plan', {
        'title': 'Legacy plan',
        'description': '',
        'sessions': [
          {
            'title': '',
            'references': '',
            'reflection': '',
            'passages': <Map<String, dynamic>>[],
          },
        ],
      });
      await repo.save('note', {
        ...noteData(bible),
        'plans': [plan.id],
        'planSessions': [sessionLink(plan, 0)],
      });
      final copy = await (await repo.snapshot()).separateCopy(bible);
      final restored = await copy.validate(bible);
      expect(restored.ofKind('plan').single.id, isNot(plan.id));
      expect(
        completedSessions(
          restored.ofKind('plan').single,
          restored.ofKind('note'),
        ),
        1,
      );
    },
  );
  test(
    'Each session needs its own linked note, including duplicate passages',
    () {
      final bible = testBible();
      final plan = Entry(
        id: const Uuid().v4(),
        revision: const Uuid().v4(),
        parents: [],
        kind: 'plan',
        updated: DateTime.utc(2026),
        data: {
          'title': 'Two moments',
          'description': '',
          'sessions': [
            for (var i = 0; i < 2; i++)
              {
                'id': const Uuid().v4(),
                'title': '',
                'references': 'Psalm 23',
                'reflection': '',
                'passages': bible
                    .parse('Psalm 23', 'english')
                    .map((p) => p.toJson())
                    .toList(),
              },
          ],
        },
      );
      Entry note(int session) => Entry(
        id: const Uuid().v4(),
        revision: const Uuid().v4(),
        parents: [],
        kind: 'note',
        updated: DateTime.utc(2026),
        data: {
          ...noteData(bible, references: 'Psalm 23'),
          'plans': [plan.id],
          'planSessions': [sessionLink(plan, session)],
        },
      );
      expect(completedSessions(plan, [note(0)]), 1);
      expect(completedSessions(plan, [note(0), note(1)]), 2);
      final unrelated = Entry(
        id: const Uuid().v4(),
        revision: const Uuid().v4(),
        parents: [],
        kind: 'note',
        updated: DateTime.utc(2026),
        data: noteData(bible, references: 'Psalm 23'),
      );
      expect(completedSessions(plan, [unrelated]), 0);
      final reversed = Entry(
        id: plan.id,
        revision: plan.revision,
        parents: [],
        kind: plan.kind,
        updated: plan.updated,
        data: {...plan.data, 'sessions': plan.sessions.reversed.toList()},
      );
      expect(sessionHasNote(reversed, 1, [note(0)]), isTrue);
      expect(sessionHasNote(reversed, 0, [note(0)]), isFalse);
    },
  );
}
