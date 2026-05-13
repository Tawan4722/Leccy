import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leccy/src/domain/models.dart';
import 'package:leccy/src/ui/app_controller.dart';
import 'package:leccy/src/ui/leccy_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('folder library shows created folders and actions', (
    tester,
  ) async {
    final controller = AppController(repository: null)
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
    expect(find.byIcon(Icons.create_new_folder_outlined), findsOneWidget);

    controller.dispose();
  });
}
