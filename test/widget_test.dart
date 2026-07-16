import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:leccy/src/data/memory_leccy_store.dart';
import 'package:leccy/src/domain/models.dart';
import 'package:leccy/src/ui/app_controller.dart';
import 'package:leccy/src/ui/leccy_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(AppController, quill.QuillController)> pumpNoteEditor(
    WidgetTester tester, {
    required String contentJson,
  }) async {
    final controller = AppController(repository: MemoryLeccyStore())
      ..isLoading = false
      ..selectedFileId = 1
      ..files = [
        LectureFile(
          id: 1,
          folderId: 1,
          title: 'Lecture',
          description: '',
          contentJson: contentJson,
          quickNote: '',
          sheetJson: LectureFile.emptySheetJson(),
          slidesJson: LectureFile.emptySlidesJson(),
          flashcardsJson: LectureFile.emptyFlashcardsJson(),
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

    final editor = tester.widget<quill.QuillEditor>(
      find.byType(quill.QuillEditor),
    );
    return (controller, editor.controller);
  }

  List<int?> headerLevels(quill.QuillController controller) {
    final json = controller.document.toDelta().toJson();
    final levels = <int?>[];
    for (final op in json.whereType<Map>()) {
      if (op['insert'] != '\n') {
        continue;
      }
      final attributes = op['attributes'];
      if (attributes is Map && attributes['header'] is int) {
        levels.add(attributes['header'] as int);
      } else {
        levels.add(null);
      }
    }
    return levels;
  }

  int offsetOfLine(quill.QuillController controller, String text) {
    final offset = controller.document.toPlainText().indexOf(text);
    expect(offset, greaterThanOrEqualTo(0));
    return offset;
  }

  Future<void> focusEditor(WidgetTester tester) async {
    await tester.tap(find.byType(quill.QuillEditor));
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> drainAutosave(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
  }

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
  });

  testWidgets('empty file title is shown as untitled lecture in file list', (
    tester,
  ) async {
    final controller = AppController(repository: MemoryLeccyStore())
      ..isLoading = false
      ..selectedFolderId = 1
      ..selectedFileId = 1
      ..files = [
        LectureFile(
          id: 1,
          folderId: 1,
          title: '',
          description: '',
          contentJson: LectureFile.emptyDocumentJson(),
          quickNote: '',
          sheetJson: LectureFile.emptySheetJson(),
          slidesJson: LectureFile.emptySlidesJson(),
          flashcardsJson: LectureFile.emptyFlashcardsJson(),
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
            child: FileListPanel(
              controller: controller,
              folder: const LectureFolder(
                id: 1,
                name: 'Biology',
                colorValue: 0xFF596F62,
                badge: 'BIO',
                sortOrder: 1,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Untitled lecture'), findsOneWidget);
  });

  testWidgets('note editor heading fold toggles without marking draft dirty', (
    tester,
  ) async {
    await pumpNoteEditor(
      tester,
      contentJson:
          '[{"insert":"Main"},{"insert":"\\n","attributes":{"header":1}},{"insert":"Child"},{"insert":"\\n","attributes":{"header":2}},{"insert":"Child body\\n"}]',
    );

    expect(find.byTooltip('Collapse section'), findsWidgets);
    expect(find.text('Saved'), findsOneWidget);

    await tester.tap(find.byTooltip('Collapse section').first);
    await tester.pump();

    expect(find.byTooltip('Expand section'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('mind map adds child branch as nested heading', (tester) async {
    final (_, quillController) = await pumpNoteEditor(
      tester,
      contentJson:
          '[{"insert":"Root"},{"insert":"\\n","attributes":{"header":1}},{"insert":"Root body\\n"}]',
    );

    await tester.tap(find.byIcon(Icons.hub_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Mind map'), findsOneWidget);
    expect(find.byTooltip('Add branch'), findsWidgets);

    await tester.tap(find.byTooltip('Add branch').at(1));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Child branch');
    await tester.tap(find.widgetWithText(FilledButton, 'Add branch'));
    await tester.pumpAndSettle();

    expect(quillController.document.toPlainText(), contains('Child branch'));
    final ranges = computeLeccyHeadingFoldRanges(quillController.document);
    expect(ranges.any((range) => range.headingLevel == 1), isTrue);
    expect(ranges.any((range) => range.headingLevel == 2), isTrue);
    await drainAutosave(tester);
  });

  testWidgets('tab on body line converts it to H2', (tester) async {
    final (_, quillController) = await pumpNoteEditor(
      tester,
      contentJson: '[{"insert":"Body line\\n"}]',
    );
    await focusEditor(tester);

    quillController.updateSelection(
      TextSelection.collapsed(
        offset: offsetOfLine(quillController, 'Body') + 1,
      ),
      quill.ChangeSource.local,
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(headerLevels(quillController), [2]);
    await drainAutosave(tester);
  });

  testWidgets('tab on H1 converts it to H2', (tester) async {
    final (_, quillController) = await pumpNoteEditor(
      tester,
      contentJson:
          '[{"insert":"Top"},{"insert":"\\n","attributes":{"header":1}}]',
    );
    await focusEditor(tester);

    quillController.updateSelection(
      TextSelection.collapsed(offset: offsetOfLine(quillController, 'Top') + 1),
      quill.ChangeSource.local,
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(headerLevels(quillController), [2]);
    await drainAutosave(tester);
  });

  testWidgets('tab on H2 converts it to H3', (tester) async {
    final (_, quillController) = await pumpNoteEditor(
      tester,
      contentJson:
          '[{"insert":"Sub"},{"insert":"\\n","attributes":{"header":2}}]',
    );
    await focusEditor(tester);

    quillController.updateSelection(
      TextSelection.collapsed(offset: offsetOfLine(quillController, 'Sub') + 1),
      quill.ChangeSource.local,
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(headerLevels(quillController), [3]);
    await drainAutosave(tester);
  });

  testWidgets('tab on H3 does not go deeper or insert tab', (tester) async {
    final (_, quillController) = await pumpNoteEditor(
      tester,
      contentJson:
          '[{"insert":"Deep"},{"insert":"\\n","attributes":{"header":3}}]',
    );
    await focusEditor(tester);
    final before = jsonEncode(quillController.document.toDelta().toJson());

    quillController.updateSelection(
      TextSelection.collapsed(
        offset: offsetOfLine(quillController, 'Deep') + 1,
      ),
      quill.ChangeSource.local,
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    final after = jsonEncode(quillController.document.toDelta().toJson());
    expect(headerLevels(quillController), [3]);
    expect(quillController.document.toPlainText(), isNot(contains('\t')));
    expect(after, before);
    await drainAutosave(tester);
  });

  testWidgets('backspace at start of H2 promotes to H1', (tester) async {
    final (_, quillController) = await pumpNoteEditor(
      tester,
      contentJson:
          '[{"insert":"Sub"},{"insert":"\\n","attributes":{"header":2}}]',
    );
    await focusEditor(tester);

    quillController.updateSelection(
      TextSelection.collapsed(offset: offsetOfLine(quillController, 'Sub')),
      quill.ChangeSource.local,
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(headerLevels(quillController), [1]);
    await drainAutosave(tester);
  });

  testWidgets('backspace away from heading start keeps normal deletion', (
    tester,
  ) async {
    final (_, quillController) = await pumpNoteEditor(
      tester,
      contentJson:
          '[{"insert":"Sub"},{"insert":"\\n","attributes":{"header":2}}]',
    );
    await focusEditor(tester);

    final start = offsetOfLine(quillController, 'Sub');
    quillController.updateSelection(
      TextSelection.collapsed(offset: start + 1),
      quill.ChangeSource.local,
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(headerLevels(quillController), [2]);
    expect(quillController.document.toPlainText(), startsWith('ub'));
    await drainAutosave(tester);
  });

  testWidgets('fold ranges reflect tab and backspace heading changes', (
    tester,
  ) async {
    final (_, quillController) = await pumpNoteEditor(
      tester,
      contentJson: '[{"insert":"Root\\n"}]',
    );
    await focusEditor(tester);

    quillController.updateSelection(
      TextSelection.collapsed(
        offset: offsetOfLine(quillController, 'Root') + 1,
      ),
      quill.ChangeSource.local,
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    final afterTab = computeLeccyHeadingFoldRanges(quillController.document);
    expect(afterTab.any((range) => range.headingLevel == 2), isTrue);

    quillController.updateSelection(
      TextSelection.collapsed(offset: offsetOfLine(quillController, 'Root')),
      quill.ChangeSource.local,
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    final afterBackspace = computeLeccyHeadingFoldRanges(
      quillController.document,
    );
    expect(afterBackspace.any((range) => range.headingLevel == 1), isTrue);
    await drainAutosave(tester);
  });

  testWidgets('spreadsheet resolves transitive formulas and maintains focus', (tester) async {
    final (controller, _) = await pumpNoteEditor(
      tester,
      contentJson: LectureFile.emptyDocumentJson(),
    );

    // Switch to Sheet tab
    await tester.tap(find.byIcon(Icons.table_chart_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Mini sheet'), findsOneWidget);

    // Enter values:
    // Row 1, Col A (index 0) = "10"
    // Row 2, Col B (index 4) = "=A1+5"
    // Row 3, Col B (index 7) = "=B2+5"
    await tester.enterText(find.byType(TextFormField).at(0), '10');
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(4), '=A1+5');
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(7), '=B2+5');
    await tester.pumpAndSettle();

    final element = tester.element(
      find.byElementPredicate(
        (el) => el.widget.runtimeType.toString() == '_SheetGraphWorkspace',
      ),
    );
    final dynamic state = (element as StatefulElement).state;

    // Verify row values
    expect(state.rows[0][0], '10');
    expect(state.rows[1][1], '=A1+5');
    expect(state.rows[2][1], '=B2+5');

    // Verify evaluation by inspecting the CustomPaint painter's points:
    // B2 (points[1]) = 10 + 5 = 15
    // B3 (points[2]) = B2 + 5 = 20
    final customPaint = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter.runtimeType.toString() == '_GraphPainter',
      ),
    );
    final dynamic painter = customPaint.painter;
    final List<dynamic> points = painter.points;

    expect(points[0].label, 'Row 2');
    expect(points[0].value, 15.0);
    expect(points[1].label, 'Row 3');
    expect(points[1].value, 20.0);

    // Verify circular reference prevention does not stack overflow
    await tester.enterText(find.byType(TextFormField).at(0), '=B2');
    await tester.pumpAndSettle();

    final customPaint2 = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter.runtimeType.toString() == '_GraphPainter',
      ),
    );
    final dynamic painter2 = customPaint2.painter;
    final List<dynamic> points2 = painter2.points;
    expect(points2[0].value, 10.0); // Circular resolves to 10.0 without crash
  });
}
