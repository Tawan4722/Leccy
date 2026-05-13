import 'package:flutter_test/flutter_test.dart';
import 'package:leccy/src/data/memory_leccy_store.dart';
import 'package:leccy/src/ui/app_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('manual summary writes description and metadata', () async {
    final controller = AppController(repository: MemoryLeccyStore());
    await controller.load();
    await controller.createFolder(
      name: 'Chemistry',
      colorValue: 0xFF2457C5,
      badge: 'CH',
    );
    await controller.createFile();
    await controller.generateSummaryForSelectedFile(
      noteText:
          'Atoms consist of protons neutrons and electrons. Bonding explains molecular structure and reactions.',
      manual: true,
    );

    final file = controller.selectedFile!;
    expect(file.description, isNotEmpty);
    expect(file.summarySourceHash, isNotNull);
    expect(file.summaryUpdatedAt, isNotNull);
    expect(file.autoSummaryEnabled, isFalse);
  });

  test('auto summary does nothing when auto toggle is off', () async {
    final controller = AppController(repository: MemoryLeccyStore());
    await controller.load();
    await controller.createFolder(
      name: 'History',
      colorValue: 0xFF2457C5,
      badge: 'HI',
    );
    await controller.createFile();
    final file = controller.selectedFile!;
    await controller.updateFile(
      file.copyWith(description: 'Custom manual description'),
    );

    await controller.maybeAutoSummarizeSelectedFile(
      noteText:
          'World War topics and political shifts over multiple decades with many major events.',
    );

    expect(controller.selectedFile!.description, 'Custom manual description');
    expect(controller.selectedFile!.autoSummaryEnabled, isFalse);
  });

  test('auto summary skips rerun when source hash is unchanged', () async {
    final controller = AppController(repository: MemoryLeccyStore());
    await controller.load();
    await controller.createFolder(
      name: 'Math',
      colorValue: 0xFF2457C5,
      badge: 'MA',
    );
    await controller.createFile();
    await controller.setAutoSummaryEnabledForSelectedFile(true);

    const noteText =
        'Calculus studies limits derivatives and integrals. Practice problems help with understanding.';
    await controller.maybeAutoSummarizeSelectedFile(noteText: noteText);
    final first = controller.selectedFile!;
    final firstUpdatedAt = first.summaryUpdatedAt;

    await controller.maybeAutoSummarizeSelectedFile(noteText: noteText);
    final second = controller.selectedFile!;

    expect(second.summaryUpdatedAt, firstUpdatedAt);
    expect(second.summarySourceHash, first.summarySourceHash);
  });
}
