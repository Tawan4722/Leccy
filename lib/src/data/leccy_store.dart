import 'dart:typed_data';

import '../domain/backup_models.dart';
import '../domain/models.dart';

abstract interface class LeccyStore {
  Future<List<LectureFolder>> folders();

  Future<LectureFolder> createFolder({
    required String name,
    required int colorValue,
    required String badge,
    String? coverImagePath,
  });

  Future<void> updateFolder(LectureFolder folder);

  Future<List<LectureFile>> filesForFolder(int folderId);

  Future<Map<int, int>> fileCountsByFolder();

  Future<Map<int, int>> folderProgress();

  Future<LectureFile> createFile(int folderId);

  Future<void> updateFile(LectureFile file);

  Future<List<StudySet>> studySetsForFolder(int folderId);

  Future<List<StudySetItem>> studySetItems(int studySetId);

  Future<StudySet> createStudySet({
    required int folderId,
    required String name,
    required List<LectureFile> files,
  });

  Future<void> updateStudySetMarker({
    required int itemId,
    required int fileId,
    required int percent,
  });

  Future<String> saveCoverImage({
    required Uint8List bytes,
    required String extension,
  });

  Future<String> saveAttachment({
    required Uint8List bytes,
    required String extension,
    required String mediaType,
  });

  Future<LeccyBackupBundle> exportBackup();

  Future<void> importBackup(
    LeccyBackupBundle backup, {
    required BackupImportMode mode,
  });

  Future<void> close();
}
