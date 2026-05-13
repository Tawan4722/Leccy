import 'package:flutter_test/flutter_test.dart';
import 'package:leccy/src/domain/summary_service.dart';

void main() {
  final service = SummaryService();

  test('summarize returns stable short summary for lecture text', () {
    final summary = service.summarize(
      title: 'Linear Algebra',
      noteText:
          'Matrices are rectangular arrays of numbers. Matrix multiplication combines rows and columns. Determinants describe scaling and invertibility. Eigenvalues explain stretch factors in transformations.',
      quickNote: 'Focus on determinants and eigenvalues.',
    );

    expect(summary, isNotEmpty);
    expect(summary.length <= 265, isTrue);
  });

  test('plain text extraction reads quill insert operations', () {
    final text = service.plainTextFromQuillJson(
      '[{"insert":"Hello world\\n"},{"insert":"Second line\\n"}]',
    );
    expect(text, contains('Hello world'));
    expect(text, contains('Second line'));
  });

  test('shouldAutoSummarize skips when hash is unchanged', () {
    final hash = service.sourceHash(
      title: 'Title',
      noteText: 'This is long enough content to pass thresholds for summary.',
      quickNote: 'quick',
    );
    final shouldRun = service.shouldAutoSummarize(
      sourceHash: hash,
      previousHash: hash,
      sourceText: 'This is long enough content to pass thresholds for summary.',
    );
    expect(shouldRun, isFalse);
  });
}
