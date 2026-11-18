import 'dart:convert';

class Book {
  Book(Map<String, dynamic> json)
    : code = json['code'] as String,
      name = json['name'] as String,
      testament = json['testament'] as String,
      aliases = List<String>.from(json['aliases'] as List),
      chapters = List<int>.from(json['chapters'] as List);
  final String code, name, testament;
  final List<String> aliases;
  final List<int> chapters;
  int get verseCount => chapters.fold(0, (a, b) => a + b);
}

class Passage {
  const Passage(this.book, this.chapter, this.start, this.end);
  final String book;
  final int chapter, start, end;
  Map<String, dynamic> toJson() => {
    'book': book,
    'chapter': chapter,
    'start': start,
    'end': end,
  };
  factory Passage.fromJson(Map<String, dynamic> j) => Passage(
    j['book'] as String,
    j['chapter'] as int,
    j['start'] as int,
    j['end'] as int,
  );
  String get key => '$book:$chapter:$start:$end';
}

class Bible {
  Bible(String english, String original)
    : schemes = {
        'english': (jsonDecode(english) as List)
            .map((e) => Book(Map<String, dynamic>.from(e as Map)))
            .toList(),
        'original': (jsonDecode(original) as List)
            .map((e) => Book(Map<String, dynamic>.from(e as Map)))
            .toList(),
      };
  final Map<String, List<Book>> schemes;
  List<Book> books(String scheme, {bool extra = true}) =>
      schemes[scheme]!.where((b) => extra || b.testament != 'DC').toList();
  Book book(String code, String scheme) =>
      books(scheme).firstWhere((b) => b.code == code);
  String normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s.]'), '');

  List<Passage> parse(String text, String scheme) {
    final lookup = <String, Book>{};
    for (final book in books(scheme)) {
      for (final alias in [book.code, book.name, ...book.aliases]) {
        lookup[normalize(alias)] = book;
      }
    }
    final result = <String, Passage>{};
    for (var raw in text.split(RegExp(r'[;\n]+'))) {
      raw = raw.trim().replaceAll('–', '-').replaceAll('—', '-');
      if (raw.isEmpty) continue;
      final match = RegExp(
        r'^(.+?)\s+(\d+)(?::(\d+))?(?:\s*-\s*(\d+)(?::(\d+))?)?$',
      ).firstMatch(raw);
      if (match == null) {
        throw FormatException(
          'Onbekende verwijzing: $raw. Gebruik bijvoorbeeld Johannes 3:16–18.',
        );
      }
      final b = lookup[normalize(match[1]!)];
      if (b == null) throw FormatException('Onbekend Bijbelboek: ${match[1]}.');
      final ch = int.parse(match[2]!);
      final vs = match[3] == null ? null : int.parse(match[3]!);
      final last = match[4] == null ? null : int.parse(match[4]!);
      final lastVs = match[5] == null ? null : int.parse(match[5]!);
      final endCh = vs != null && last != null && lastVs == null
          ? ch
          : last ?? ch;
      final startV = vs ?? 1;
      if (vs == null && lastVs != null) {
        throw const FormatException(
          'Vermeld bij een versbereik aan beide kanten een hoofdstuk en vers.',
        );
      }
      if (ch < 1 || ch > endCh || endCh > b.chapters.length) {
        throw FormatException(
          'Ongeldig hoofdstuk in $raw. ${b.name} heeft ${b.chapters.length} hoofdstukken.',
        );
      }
      final endV = vs == null ? b.chapters[endCh - 1] : (lastVs ?? last ?? vs);
      if (startV < 1 ||
          startV > b.chapters[ch - 1] ||
          endV < 1 ||
          endV > b.chapters[endCh - 1] ||
          (ch == endCh && startV > endV)) {
        throw FormatException(
          'Ongeldig versbereik: $raw. Controleer ook je versindeling.',
        );
      }
      for (var c = ch; c <= endCh; c++) {
        final p = Passage(
          b.code,
          c,
          c == ch ? startV : 1,
          c == endCh ? endV : b.chapters[c - 1],
        );
        result[p.key] = p;
      }
    }
    return result.values.toList();
  }

  void validate(Passage p, String scheme) {
    final matches = books(scheme).where((b) => b.code == p.book);
    if (matches.isEmpty) {
      throw const FormatException('Onbekende passage in studieboek.');
    }
    final b = matches.first;
    if (p.chapter < 1 ||
        p.chapter > b.chapters.length ||
        p.start < 1 ||
        p.end < p.start ||
        p.end > b.chapters[p.chapter - 1]) {
      throw const FormatException('Ongeldige passage in studieboek.');
    }
  }

  String label(Passage p, String scheme) =>
      '${book(p.book, scheme).name} ${p.chapter}:${p.start}${p.end == p.start ? '' : '–${p.end}'}';
}

Map<String, Set<int>> coverage(Iterable<List<Passage>> notes) {
  final result = <String, Set<int>>{};
  for (final passages in notes) {
    for (final p in passages) {
      final verses = result.putIfAbsent(
        '${p.book}:${p.chapter}',
        () => <int>{},
      );
      for (var n = p.start; n <= p.end; n++) {
        verses.add(n);
      }
    }
  }
  return result;
}

double passageProgress(List<Passage> passages, Map<String, Set<int>> covered) {
  final target = coverage([passages]);
  var total = 0, done = 0;
  for (final e in target.entries) {
    total += e.value.length;
    done += e.value.intersection(covered[e.key] ?? {}).length;
  }
  return total == 0 ? 0 : done / total;
}
