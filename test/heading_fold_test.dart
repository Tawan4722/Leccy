import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:leccy/src/ui/leccy_app.dart';

void main() {
  quill.Document documentFromLines(List<Map<String, Object?>> lines) {
    final ops = <Map<String, Object?>>[];
    for (final line in lines) {
      ops.add({'insert': line['text']});
      final level = line['header'];
      if (level == null) {
        ops.add({'insert': '\n'});
      } else {
        ops.add({
          'insert': '\n',
          'attributes': {'header': level},
        });
      }
    }
    return quill.Document.fromJson(ops);
  }

  test('H1 folds child headings and content until the next H1', () {
    final document = documentFromLines([
      {'text': 'Main', 'header': 1},
      {'text': 'Intro body'},
      {'text': 'Child', 'header': 2},
      {'text': 'Child body'},
      {'text': 'Next', 'header': 1},
    ]);

    final ranges = computeLeccyHeadingFoldRanges(document);

    expect(ranges, hasLength(3));
    expect(ranges[0].headingLevel, 1);
    expect(ranges[0].childLineOffsets, hasLength(3));
    expect(ranges[0].canFold, isTrue);
  });

  test('H2 folds child content until the next H1 or H2', () {
    final document = documentFromLines([
      {'text': 'Main', 'header': 1},
      {'text': 'First child', 'header': 2},
      {'text': 'First child body'},
      {'text': 'Nested child', 'header': 3},
      {'text': 'Nested child body'},
      {'text': 'Second child', 'header': 2},
    ]);

    final ranges = computeLeccyHeadingFoldRanges(document);
    final firstChild = ranges.firstWhere((range) => range.headingLevel == 2);

    expect(firstChild.childLineOffsets, hasLength(3));
    expect(firstChild.canFold, isTrue);
  });

  test('heading with no children has no effective collapse target', () {
    final document = documentFromLines([
      {'text': 'Empty', 'header': 2},
      {'text': 'Next', 'header': 2},
    ]);

    final ranges = computeLeccyHeadingFoldRanges(document);

    expect(ranges.first.childLineOffsets, isEmpty);
    expect(ranges.first.canFold, isFalse);
  });

  test('temporary fold attributes are stripped from persisted content', () {
    const contentJson =
        '[{"insert":"Hidden line"},{"insert":"\\n","attributes":{"leccy-fold-hidden":true,"leccy-fold-heading-level":2,"list":"leccy-fold-leading"}}]';

    final stripped = stripLeccyFoldHiddenFromContentJson(contentJson);

    expect(stripped, isNot(contains(leccyFoldHiddenAttributeKey)));
    expect(stripped, isNot(contains('leccy-fold-heading-level')));
    expect(stripped, isNot(contains('leccy-fold-leading')));
    expect(stripped, contains('"header":2'));
  });
}
