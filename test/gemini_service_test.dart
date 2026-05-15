import 'package:flutter_test/flutter_test.dart';
import 'package:leccy/src/domain/gemini_service.dart';

void main() {
  test('StructuredNote parses header subheader body hierarchy', () {
    final note = StructuredNote.fromJson({
      'title': 'Physics',
      'sections': [
        {
          'heading': 'Forces',
          'body': ['A force changes motion.'],
          'subsections': [
            {'heading': 'Newton laws', 'body': 'First law\nSecond law'},
          ],
        },
      ],
    });

    expect(note.title, 'Physics');
    expect(note.sections.single.heading, 'Forces');
    expect(note.sections.single.subsections.single.heading, 'Newton laws');
    expect(note.sections.single.subsections.single.body, hasLength(2));
  });
}
