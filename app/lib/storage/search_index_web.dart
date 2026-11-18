import '../domain/entry.dart';

/// Browser search is a disposable in-memory index of the IndexedDB records.
class SearchIndex {
  final _text = <String, String>{};
  Future<void> rebuild(List<Entry> entries) async {
    final titles = {for (final e in entries) e.id: e.title};
    _text.clear();
    for (final e in entries) {
      final related = [
        'themes',
        'plans',
        'studies',
      ].expand(e.links).map((id) => titles[id] ?? '').join(' ');
      _text[e.id] =
          '${e.title} ${e.text('body')} ${e.text('description')} ${e.text('references')} $related'
              .toLowerCase();
    }
  }

  Future<Set<String>> search(String query) async => _text.entries
      .where((e) => e.value.contains(query.toLowerCase()))
      .map((e) => e.key)
      .toSet();
  Future<void> close() async => _text.clear();
}
