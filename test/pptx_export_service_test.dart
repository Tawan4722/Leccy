import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leccy/src/domain/gemini_service.dart';
import 'package:leccy/src/domain/pptx_export_service.dart';

void main() {
  test('buildDeck creates a pptx archive with slide files', () {
    final service = PptxExportService();
    final bytes = service.buildDeck(
      title: 'Lecture',
      slides: const [
        GeneratedSlide(title: 'Intro', bullets: ['First idea', 'Second idea']),
      ],
    );

    final archive = ZipDecoder().decodeBytes(bytes);

    expect(archive.findFile('ppt/presentation.xml'), isNotNull);
    expect(archive.findFile('ppt/slides/slide1.xml'), isNotNull);
  });
}
