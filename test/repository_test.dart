import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leccy/src/data/app_database.dart';
import 'package:leccy/src/data/leccy_repository.dart';
import 'package:leccy/src/domain/backup_models.dart';
import 'package:leccy/src/domain/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  late AppDatabase appDatabase;
  late LeccyRepository repository;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return Directory.systemTemp.path;
          }
          return Directory.systemTemp.path;
        });
    appDatabase = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repository = LeccyRepository(appDatabase.database);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
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
    expect(files.single.sheetJson, isNotEmpty);
    expect(files.single.slidesJson, isNotEmpty);
    expect(files.single.flashcardsJson, isNotEmpty);
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

  test(
    'exports and replaces complete backup data including cover images',
    () async {
      final folder = await repository.createFolder(
        name: 'Chemistry',
        colorValue: 0xFF34567A,
        badge: 'CH',
      );
      final coverPath = await repository.saveCoverImage(
        bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
        extension: 'png',
      );
      await repository.updateFolder(folder.copyWith(coverImagePath: coverPath));

      final file = await repository.createFile(folder.id);
      await repository.updateFile(
        file.copyWith(
          title: 'Atoms',
          description: 'Matter basics',
          progressPercent: 55,
        ),
      );
      final files = await repository.filesForFolder(folder.id);
      await repository.createStudySet(
        folderId: folder.id,
        name: 'Chem set',
        files: files,
      );

      final backup = await repository.exportBackup();
      expect(backup.folders, hasLength(1));
      expect(backup.files, hasLength(1));
      expect(backup.studySets, hasLength(1));
      expect(backup.studySetItems, hasLength(1));
      expect(backup.coverImages, hasLength(1));

      await repository.createFolder(
        name: 'Temporary',
        colorValue: 0xFF123456,
        badge: 'TMP',
      );

      await repository.importBackup(backup, mode: BackupImportMode.replace);

      final restoredFolders = await repository.folders();
      expect(restoredFolders, hasLength(1));
      expect(restoredFolders.single.name, 'Chemistry');
      expect(restoredFolders.single.coverImagePath, isNotNull);

      final restoredFiles = await repository.filesForFolder(
        restoredFolders.single.id,
      );
      expect(restoredFiles, hasLength(1));
      expect(restoredFiles.single.title, 'Atoms');
      expect(restoredFiles.single.progressPercent, 55);

      final restoredSets = await repository.studySetsForFolder(
        restoredFolders.single.id,
      );
      expect(restoredSets, hasLength(1));
      final restoredItems = await repository.studySetItems(
        restoredSets.single.id,
      );
      expect(restoredItems, hasLength(1));
    },
  );

  test('merges backup as new data with remapped ids', () async {
    final existing = await repository.createFolder(
      name: 'Existing',
      colorValue: 0xFF101010,
      badge: 'EX',
    );
    await repository.createFile(existing.id);

    final backup = LeccyBackupBundle(
      exportedAt: DateTime(2026, 1, 1),
      folders: const [
        LectureFolder(
          id: 1,
          name: 'Imported',
          colorValue: 0xFFABCDEF,
          badge: 'IM',
          sortOrder: 1,
        ),
      ],
      files: [
        LectureFile(
          id: 1,
          folderId: 1,
          title: 'Imported note',
          description: 'From backup',
          contentJson: LectureFile.emptyDocumentJson(),
          quickNote: '',
          sheetJson: LectureFile.emptySheetJson(),
          slidesJson: LectureFile.emptySlidesJson(),
          flashcardsJson: LectureFile.emptyFlashcardsJson(),
          progressPercent: 70,
          updatedAt: DateTime(2026, 1, 1),
          autoSummaryEnabled: true,
          summarySourceHash: 'hash',
          summaryUpdatedAt: DateTime(2026, 1, 1),
        ),
      ],
      studySets: [
        StudySet(
          id: 1,
          folderId: 1,
          name: 'Imported set',
          createdAt: DateTime(2026, 1, 1),
        ),
      ],
      studySetItems: const [
        StudySetItem(
          id: 1,
          studySetId: 1,
          fileId: 1,
          itemOrder: 0,
          markerPercent: 70,
        ),
      ],
      coverImages: [
        LeccyBackupCoverImage(
          folderId: 1,
          extension: 'png',
          bytesBase64: base64Encode([7, 8, 9]),
        ),
      ],
    );

    await repository.importBackup(backup, mode: BackupImportMode.merge);

    final folders = await repository.folders();
    expect(folders, hasLength(2));
    final importedFolder = folders.firstWhere(
      (folder) => folder.name == 'Imported',
    );
    expect(importedFolder.id, isNot(1));

    final importedFiles = await repository.filesForFolder(importedFolder.id);
    expect(importedFiles, hasLength(1));
    expect(importedFiles.single.title, 'Imported note');
    expect(importedFiles.single.progressPercent, 70);

    final importedSets = await repository.studySetsForFolder(importedFolder.id);
    expect(importedSets, hasLength(1));
    final items = await repository.studySetItems(importedSets.single.id);
    expect(items, hasLength(1));
    expect(items.single.fileId, importedFiles.single.id);
  });
}
