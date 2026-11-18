import 'package:flutter_test/flutter_test.dart';
import 'package:mosterdzaad/domain/bible.dart';
import 'helpers.dart';

void main() {
  final bible = testBible();
  test('Canon, optional books and versification remain intact', () {
    expect(bible.books('english', extra: false).length, 66);
    expect(bible.books('english').length, 78);
    expect(
      bible
          .books('english', extra: false)
          .fold(0, (n, b) => n + b.chapters.length),
      1189,
    );
    expect(() => bible.parse('Joël 4', 'english'), throwsFormatException);
    expect(bible.parse('Joël 4', 'original').single.chapter, 4);
  });
  test(
    'Passages cover whole chapters, numbered books and cross-chapter ranges',
    () {
      expect(
        bible
            .parse('Johannes 3:16–18; 1 Johannes 1:1\nPsalm 23', 'english')
            .map((p) => p.key),
        ['JHN:3:16:18', '1JN:1:1:1', 'PSA:23:1:6'],
      );
      expect(
        bible
            .parse('Genesis 1:30-2:3; Genesis 1:30-31', 'english')
            .map((p) => p.key),
        ['GEN:1:30:31', 'GEN:2:1:3'],
      );
      expect(bible.parse('Genesis 1–2', 'english').map((p) => p.key), [
        'GEN:1:1:31',
        'GEN:2:1:25',
      ]);
    },
  );
  test('Invalid input never partially resolves', () {
    for (final text in [
      'Johannes 0',
      'Johannes 22',
      'Johannes 3:0',
      'Johannes 3:37',
      'Johannes 3:18-16',
      'Genesis 2-1',
      'Genesis 2:3-1:30',
      'Geenboek 1:1',
      'Johannes 3:16,18',
      'Genesis 1-2:3',
      'Johannes 3:1; fout',
    ]) {
      expect(
        () => bible.parse(text, 'english'),
        throwsFormatException,
        reason: text,
      );
    }
  });
  test('Overlapping notes count a verse only once; plans use coverage', () {
    final covered = coverage([
      bible.parse('Johannes 3:16-18', 'english'),
      bible.parse('Johannes 3:18-20', 'english'),
    ]);
    expect(covered['JHN:3'], {16, 17, 18, 19, 20});
    expect(
      passageProgress(bible.parse('Johannes 3:16-20', 'english'), covered),
      1,
    );
    expect(
      passageProgress(bible.parse('Johannes 3:16-21', 'english'), covered),
      closeTo(5 / 6, .00001),
    );
    expect(passageProgress([], covered), 0);
  });
}
