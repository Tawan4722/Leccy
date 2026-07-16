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

  test('StructuredNote handles malformed/missing subsections safely', () {
    final note = StructuredNote.fromJson({
      'title': 'Physics',
      'sections': [
        {
          'heading': 'Forces',
          'body': ['A force changes motion.'],
          'subsections': 'invalid_string_not_list'
        },
      ],
    });

    expect(note.title, 'Physics');
    expect(note.sections.single.heading, 'Forces');
    expect(note.sections.single.subsections, isEmpty);
  });

  test('GeneratedSlide handles malformed/missing bullets list safely', () {
    final slide = GeneratedSlide.fromJson({
      'title': 'Intro',
      'bullets': 'invalid_string_not_list',
    });

    expect(slide.title, 'Intro');
    expect(slide.bullets, isEmpty);
  });
}
