import 'package:uuid/uuid.dart';

import 'bible.dart';
import 'entry.dart';

String sessionId(Entry plan, int index) =>
    plan.sessions[index]['id'] as String? ??
    const Uuid().v5(Namespace.oid.value, '${plan.id}/session/$index');

String sessionLink(Entry plan, int index) =>
    '${plan.id}/${sessionId(plan, index)}';

/// New notes link to a stable session ID. Older notes count only when they
/// belong to this plan and refer to a passage in this specific session.
bool sessionHasNote(Entry plan, int index, Iterable<Entry> notes) {
  final link = sessionLink(plan, index);
  final passages = (plan.sessions[index]['passages'] as List).map(
    (p) => Passage.fromJson(Map<String, dynamic>.from(p as Map)),
  );
  return notes.any((note) {
    if (!note.links('plans').contains(plan.id)) return false;
    final explicit = note.links('planSessions');
    if (explicit.contains(link)) return true;
    if (explicit.isNotEmpty) return false;
    return passages.any(
      (p) => note.passages.any(
        (n) =>
            n.book == p.book &&
            n.chapter == p.chapter &&
            n.start <= p.end &&
            n.end >= p.start,
      ),
    );
  });
}

int completedSessions(Entry plan, Iterable<Entry> notes) => List.generate(
  plan.sessions.length,
  (i) => sessionHasNote(plan, i, notes),
).where((done) => done).length;
