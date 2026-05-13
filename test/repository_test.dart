import 'package:flutter_test/flutter_test.dart';
import 'package:leccy/src/data/app_database.dart';
import 'package:leccy/src/data/leccy_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDatabase;
  late LeccyRepository repository;

  setUp(() async {
    appDatabase = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repository = LeccyRepository(appDatabase.database);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('creates folders and files with sortable metadata', () async {
    final folder = await repository.createFolder(
      name: 'Physics',
      colorValue: 0xFF2B8C7E,
      badge: 'PH',
    );
    final file = await repository.createFile(folder.id);

    await repository.updateFile(
      file.copyWith(
        title: 'Kinematics',
        description: 'Vectors and velocity',
        quickNote: 'Reviewed examples',
        progressPercent: 40,
      ),
    );

    final folders = await repository.folders();
    final files = await repository.filesForFolder(folder.id);
    final counts = await repository.fileCountsByFolder();
    final progress = await repository.folderProgress();

    expect(folders.single.name, 'Physics');
    expect(files.single.title, 'Kinematics');
    expect(files.single.description, 'Vectors and velocity');
    expect(files.single.quickNote, 'Reviewed examples');
    expect(counts[folder.id], 1);
    expect(progress[folder.id], 40);
  });

  test('creates saved study sets and updates markers', () async {
    final folder = await repository.createFolder(
      name: 'Math',
      colorValue: 0xFFD28B37,
      badge: 'M',
    );
    final first = await repository.createFile(folder.id);
    final second = await repository.createFile(folder.id);
    await repository.updateFile(first.copyWith(progressPercent: 25));
    await repository.updateFile(second.copyWith(progressPercent: 75));

    final files = await repository.filesForFolder(folder.id);
    final set = await repository.createStudySet(
      folderId: folder.id,
      name: 'Progress set 1',
      files: files,
    );
    var items = await repository.studySetItems(set.id);

    expect(items, hasLength(2));
    expect(items.map((item) => item.markerPercent), containsAll([25, 75]));

    await repository.updateStudySetMarker(
      itemId: items.first.id,
      fileId: items.first.fileId,
      percent: 100,
    );
    items = await repository.studySetItems(set.id);
    final updatedFiles = await repository.filesForFolder(folder.id);

    expect(items.first.markerPercent, 100);
    expect(
      updatedFiles
          .firstWhere((file) => file.id == items.first.fileId)
          .progressPercent,
      100,
    );
  });
}
