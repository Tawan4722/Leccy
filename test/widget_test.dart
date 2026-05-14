import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:leccy/src/data/memory_leccy_store.dart';
import 'package:leccy/src/domain/models.dart';
import 'package:leccy/src/ui/app_controller.dart';
import 'package:leccy/src/ui/leccy_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('folder library shows created folders and actions', (
    tester,
  ) async {
    final controller = AppController(repository: MemoryLeccyStore())
      ..isLoading = false
      ..folders = const [
        LectureFolder(
          id: 1,
          name: 'Biology',
          colorValue: 0xFF596F62,
          badge: 'BIO',
          sortOrder: 1,
        ),
      ]
      ..fileCounts = {1: 3}
      ..progressByFolder = {1: 40}
      ..selectedFolderId = 1;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(body: FolderLibrary(controller: controller)),
      ),
    );

    expect(find.text('Leccy'), findsOneWidget);
    expect(find.text('Biology'), findsOneWidget);
    expect(find.byTooltip('New folder'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('note editor heading fold toggles without marking draft dirty', (
    tester,
  ) async {
    final controller = AppController(repository: MemoryLeccyStore())
      ..isLoading = false
      ..selectedFileId = 1
      ..files = [
        LectureFile(
          id: 1,
          folderId: 1,
          title: 'Lecture',
          description: '',
          contentJson:
              '[{"insert":"Main"},{"insert":"\\n","attributes":{"header":1}},{"insert":"Child"},{"insert":"\\n","attributes":{"header":2}},{"insert":"Child body\\n"}]',
          quickNote: '',
          progressPercent: 0,
          updatedAt: DateTime(2026),
          autoSummaryEnabled: false,
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          quill.FlutterQuillLocalizations.delegate,
        ],
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 800,
            child: NoteEditor(controller: controller),
          ),
        ),
      ),
    );

    expect(find.byTooltip('Collapse section'), findsWidgets);
    expect(find.text('Saved'), findsOneWidget);

    await tester.tap(find.byTooltip('Collapse section').first);
    await tester.pump();

    expect(find.byTooltip('Expand section'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);

    controller.dispose();
  });
}
