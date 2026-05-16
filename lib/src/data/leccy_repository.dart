import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/backup_models.dart';
import '../domain/models.dart';
import 'leccy_store.dart';

class LeccyRepository implements LeccyStore {
  LeccyRepository(this._db);

  final Database _db;

  @override
  Future<List<LectureFolder>> folders() async {
    final rows = await _db.query(
      'folders',
      where: 'deleted_at IS NULL',
      orderBy: 'sort_order ASC, name COLLATE NOCASE ASC',
    );
    return rows.map(LectureFolder.fromMap).toList();
  }

  @override
  Future<LectureFolder> createFolder({
    required String name,
    required int colorValue,
    required String badge,
    String? coverImagePath,
  }) async {
    final orderResult = await _db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), 0) + 1 AS next_order FROM folders',
    );
    final nextOrder = orderResult.first['next_order'] as int;
    final folder = LectureFolder(
      id: 0,
      name: name,
      colorValue: colorValue,
      badge: badge,
      coverImagePath: coverImagePath,
      sortOrder: nextOrder,
    );
    final id = await _db.insert('folders', folder.toMap());
    return folder.copyWith(id: id);
  }

  @override
  Future<void> updateFolder(LectureFolder folder) async {
    await _db.update(
      'folders',
      folder.toMap(),
      where: 'id = ?',
      whereArgs: [folder.id],
    );
  }

  @override
  Future<List<LectureFile>> filesForFolder(int folderId) async {
    final rows = await _db.query(
      'lecture_files',
      where: 'folder_id = ? AND deleted_at IS NULL',
      whereArgs: [folderId],
      orderBy: 'updated_at DESC, title COLLATE NOCASE ASC',
    );
    return rows.map(LectureFile.fromMap).toList();
  }

  @override
  Future<List<LectureFile>> searchFiles(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return const [];
    }
    final like = '%${normalized.toLowerCase()}%';
    final rows = await _db.query(
      'lecture_files',
      where:
          'deleted_at IS NULL AND (LOWER(title) LIKE ? OR LOWER(description) LIKE ? OR LOWER(quick_note) LIKE ? OR LOWER(content_json) LIKE ?)',
      whereArgs: [like, like, like, like],
      orderBy: 'updated_at DESC, title COLLATE NOCASE ASC',
    );
    return rows.map(LectureFile.fromMap).toList();
  }

  @override
  Future<Map<int, int>> fileCountsByFolder() async {
    final rows = await _db.rawQuery('''
      SELECT folder_id, COUNT(*) AS count
      FROM lecture_files
      WHERE deleted_at IS NULL
      GROUP BY folder_id
    ''');
    return {
      for (final row in rows) row['folder_id'] as int: row['count'] as int,
    };
  }

  @override
  Future<Map<int, int>> folderProgress() async {
    final rows = await _db.rawQuery('''
      SELECT folder_id, ROUND(AVG(progress_percent)) AS progress
      FROM lecture_files
      WHERE deleted_at IS NULL
      GROUP BY folder_id
    ''');
    return {
      for (final row in rows)
        row['folder_id'] as int: (row['progress'] as num).round(),
    };
  }

  @override
  Future<LectureFile> createFile(int folderId) async {
    final now = DateTime.now();
    final file = LectureFile(
      id: 0,
      folderId: folderId,
      title: 'Untitled lecture',
      description: '',
      contentJson: LectureFile.emptyDocumentJson(),
      quickNote: '',
      sheetJson: LectureFile.emptySheetJson(),
      slidesJson: LectureFile.emptySlidesJson(),
      flashcardsJson: LectureFile.emptyFlashcardsJson(),
      progressPercent: 0,
      updatedAt: now,
      autoSummaryEnabled: false,
      summarySourceHash: null,
      summaryUpdatedAt: null,
      deletedAt: null,
    );
    final id = await _db.insert('lecture_files', file.toMap());
    return file.copyWith(id: id);
  }

  @override
  Future<void> updateFile(LectureFile file) async {
    await _db.update(
      'lecture_files',
      file.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [file.id],
    );
  }

  @override
  Future<List<StudySet>> studySetsForFolder(int folderId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT DISTINCT s.*
      FROM study_sets s
      JOIN study_set_items i ON i.study_set_id = s.id
      JOIN lecture_files f ON f.id = i.file_id
      WHERE s.folder_id = ? AND f.deleted_at IS NULL
      ORDER BY s.created_at DESC
      ''',
      [folderId],
    );
    return rows.map(StudySet.fromMap).toList();
  }

  @override
  Future<List<StudySetItem>> studySetItems(int studySetId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT i.*
      FROM study_set_items i
      JOIN lecture_files f ON f.id = i.file_id
      WHERE i.study_set_id = ? AND f.deleted_at IS NULL
      ORDER BY i.item_order ASC
      ''',
      [studySetId],
    );
    return rows.map(StudySetItem.fromMap).toList();
  }

  @override
  Future<StudySet> createStudySet({
    required int folderId,
    required String name,
    required List<LectureFile> files,
  }) async {
    return _db.transaction((txn) async {
      final now = DateTime.now();
      final set = StudySet(
        id: 0,
        folderId: folderId,
        name: name,
        createdAt: now,
      );
      final setId = await txn.insert('study_sets', set.toMap());
      for (var index = 0; index < files.length; index++) {
        final file = files[index];
        final item = StudySetItem(
          id: 0,
          studySetId: setId,
          fileId: file.id,
          itemOrder: index,
          markerPercent: file.progressPercent,
        );
        await txn.insert('study_set_items', item.toMap());
      }
      return StudySet(
        id: setId,
        folderId: folderId,
        name: name,
        createdAt: now,
      );
    });
  }

  @override
  Future<void> updateStudySetMarker({
    required int itemId,
    required int fileId,
    required int percent,
  }) async {
    await _db.transaction((txn) async {
      await txn.update(
        'study_set_items',
        {'marker_percent': percent.clamp(0, 100)},
        where: 'id = ?',
        whereArgs: [itemId],
      );
      await txn.update(
        'lecture_files',
        {
          'progress_percent': percent.clamp(0, 100),
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [fileId],
      );
    });
  }

  @override
  Future<String> saveCoverImage({
    required Uint8List bytes,
    required String extension,
  }) async {
    return saveAttachment(
      bytes: bytes,
      extension: extension,
      mediaType: 'covers',
    );
  }

  @override
  Future<String> saveAttachment({
    required Uint8List bytes,
    required String extension,
    required String mediaType,
  }) async {
    final documents = await getApplicationDocumentsDirectory();
    final safeType = mediaType.replaceAll(RegExp('[^a-zA-Z0-9_-]'), '');
    final attachmentDir = Directory(
      p.join(
        documents.path,
        'Leccy',
        safeType.isEmpty ? 'attachments' : safeType,
      ),
    );
    if (!attachmentDir.existsSync()) {
      attachmentDir.createSync(recursive: true);
    }
    final safeExtension = extension.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
    final file = File(
      p.join(
        attachmentDir.path,
        'leccy_${DateTime.now().microsecondsSinceEpoch}.${safeExtension.isEmpty ? 'bin' : safeExtension}',
      ),
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  Future<List<LectureFolder>> trashedFolders() async {
    final rows = await _db.query(
      'folders',
      where: 'deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC',
    );
    return rows.map(LectureFolder.fromMap).toList();
  }

  @override
  Future<List<LectureFile>> trashedFiles() async {
    final rows = await _db.query(
      'lecture_files',
      where: 'deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC',
    );
    return rows.map(LectureFile.fromMap).toList();
  }

  @override
  Future<void> moveFileToTrash(int fileId) async {
    await _db.update(
      'lecture_files',
      {
        'deleted_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [fileId],
    );
  }

  @override
  Future<void> restoreFileFromTrash(int fileId) async {
    await _db.update(
      'lecture_files',
      {'deleted_at': null, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [fileId],
    );
  }

  @override
  Future<void> permanentlyDeleteFile(int fileId) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'study_set_items',
        where: 'file_id = ?',
        whereArgs: [fileId],
      );
      await txn.delete('lecture_files', where: 'id = ?', whereArgs: [fileId]);
      await txn.execute('''
        DELETE FROM study_sets
        WHERE id NOT IN (
          SELECT DISTINCT study_set_id FROM study_set_items
        )
      ''');
    });
  }

  @override
  Future<void> moveFolderToTrash(int folderId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      await txn.update(
        'folders',
        {'deleted_at': now},
        where: 'id = ?',
        whereArgs: [folderId],
      );
      await txn.update(
        'lecture_files',
        {'deleted_at': now, 'updated_at': now},
        where: 'folder_id = ?',
        whereArgs: [folderId],
      );
    });
  }

  @override
  Future<void> restoreFolderFromTrash(int folderId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      await txn.update(
        'folders',
        {'deleted_at': null},
        where: 'id = ?',
        whereArgs: [folderId],
      );
      await txn.update(
        'lecture_files',
        {'deleted_at': null, 'updated_at': now},
        where: 'folder_id = ?',
        whereArgs: [folderId],
      );
    });
  }

  @override
  Future<void> permanentlyDeleteFolder(int folderId) async {
    await _db.delete('folders', where: 'id = ?', whereArgs: [folderId]);
  }

  @override
  Future<String?> getSetting(String key) async {
    final rows = await _db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['value'] as String;
  }

  @override
  Future<void> setSetting(String key, String value) async {
    await _db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<LeccyBackupBundle> exportBackup() async {
    final folders = (await _db.query(
      'folders',
      orderBy: 'sort_order ASC, id ASC',
    )).map(LectureFolder.fromMap).toList();
    final files = (await _db.query(
      'lecture_files',
      orderBy: 'folder_id ASC, updated_at DESC, id ASC',
    )).map(LectureFile.fromMap).toList();
    final studySets = (await _db.query(
      'study_sets',
      orderBy: 'folder_id ASC, created_at DESC, id ASC',
    )).map(StudySet.fromMap).toList();
    final studySetItems = (await _db.query(
      'study_set_items',
      orderBy: 'study_set_id ASC, item_order ASC, id ASC',
    )).map(StudySetItem.fromMap).toList();

    final coverImages = <LeccyBackupCoverImage>[];
    for (final folder in folders) {
      final coverImage = await _readCoverImage(
        folder.id,
        folder.coverImagePath,
      );
      if (coverImage != null) {
        coverImages.add(coverImage);
      }
    }

    return LeccyBackupBundle(
      exportedAt: DateTime.now(),
      folders: folders,
      files: files,
      studySets: studySets,
      studySetItems: studySetItems,
      coverImages: coverImages,
    );
  }

  @override
  Future<void> importBackup(
    LeccyBackupBundle backup, {
    required BackupImportMode mode,
  }) async {
    final coverPathByFolder = <int, String>{};
    for (final cover in backup.coverImages) {
      final bytes = base64Decode(cover.bytesBase64);
      final path = await saveCoverImage(
        bytes: bytes,
        extension: cover.extension,
      );
      coverPathByFolder[cover.folderId] = path;
    }
    if (mode == BackupImportMode.replace) {
      await _importReplace(backup, coverPathByFolder);
      return;
    }
    await _importMerge(backup, coverPathByFolder);
  }

  Future<void> _importReplace(
    LeccyBackupBundle backup,
    Map<int, String> coverPathByFolder,
  ) async {
    await _db.transaction((txn) async {
      await txn.delete('study_set_items');
      await txn.delete('study_sets');
      await txn.delete('lecture_files');
      await txn.delete('folders');

      final folderIds = <int>{};
      for (final folder in backup.folders) {
        folderIds.add(folder.id);
        await txn.insert(
          'folders',
          folder
              .copyWith(
                coverImagePath: coverPathByFolder[folder.id],
                clearCoverImagePath: !coverPathByFolder.containsKey(folder.id),
              )
              .toMap(),
        );
      }

      final fileIds = <int>{};
      for (final file in backup.files) {
        if (!folderIds.contains(file.folderId)) {
          continue;
        }
        fileIds.add(file.id);
        await txn.insert('lecture_files', file.toMap());
      }

      final setIds = <int>{};
      for (final set in backup.studySets) {
        if (!folderIds.contains(set.folderId)) {
          continue;
        }
        setIds.add(set.id);
        await txn.insert('study_sets', set.toMap());
      }

      for (final item in backup.studySetItems) {
        if (!setIds.contains(item.studySetId) ||
            !fileIds.contains(item.fileId)) {
          continue;
        }
        await txn.insert('study_set_items', item.toMap());
      }
    });
  }

  Future<void> _importMerge(
    LeccyBackupBundle backup,
    Map<int, String> coverPathByFolder,
  ) async {
    final nextFolderId = await _nextId('folders');
    final nextFileId = await _nextId('lecture_files');
    final nextSetId = await _nextId('study_sets');
    final nextItemId = await _nextId('study_set_items');
    final nextSortOrder = await _nextSortOrder();

    var folderId = nextFolderId;
    var fileId = nextFileId;
    var setId = nextSetId;
    var itemId = nextItemId;
    var sortOrder = nextSortOrder;

    final folderMap = <int, int>{};
    final fileMap = <int, int>{};
    final setMap = <int, int>{};

    await _db.transaction((txn) async {
      final sortedFolders = [...backup.folders]
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      for (final folder in sortedFolders) {
        final newId = folderId++;
        folderMap[folder.id] = newId;
        await txn.insert(
          'folders',
          folder
              .copyWith(
                id: newId,
                sortOrder: sortOrder++,
                coverImagePath: coverPathByFolder[folder.id],
                clearCoverImagePath: !coverPathByFolder.containsKey(folder.id),
              )
              .toMap(),
        );
      }

      for (final file in backup.files) {
        final mappedFolderId = folderMap[file.folderId];
        if (mappedFolderId == null) {
          continue;
        }
        final newId = fileId++;
        fileMap[file.id] = newId;
        await txn.insert(
          'lecture_files',
          file.copyWith(id: newId, folderId: mappedFolderId).toMap(),
        );
      }

      for (final set in backup.studySets) {
        final mappedFolderId = folderMap[set.folderId];
        if (mappedFolderId == null) {
          continue;
        }
        final newId = setId++;
        setMap[set.id] = newId;
        await txn.insert('study_sets', {
          'id': newId,
          'folder_id': mappedFolderId,
          'name': set.name,
          'created_at': set.createdAt.millisecondsSinceEpoch,
        });
      }

      for (final item in backup.studySetItems) {
        final mappedSetId = setMap[item.studySetId];
        final mappedFileId = fileMap[item.fileId];
        if (mappedSetId == null || mappedFileId == null) {
          continue;
        }
        await txn.insert('study_set_items', {
          'id': itemId++,
          'study_set_id': mappedSetId,
          'file_id': mappedFileId,
          'item_order': item.itemOrder,
          'marker_percent': item.markerPercent.clamp(0, 100),
        });
      }
    });
  }

  Future<int> _nextId(String tableName) async {
    final result = await _db.rawQuery(
      'SELECT COALESCE(MAX(id), 0) + 1 AS next_id FROM $tableName',
    );
    return (result.first['next_id'] as num).toInt();
  }

  Future<int> _nextSortOrder() async {
    final result = await _db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), 0) + 1 AS next_order FROM folders',
    );
    return (result.first['next_order'] as num).toInt();
  }

  Future<LeccyBackupCoverImage?> _readCoverImage(
    int folderId,
    String? coverPath,
  ) async {
    if (coverPath == null || coverPath.trim().isEmpty) {
      return null;
    }
    if (coverPath.startsWith('data:')) {
      final comma = coverPath.indexOf(',');
      if (comma <= 0) {
        return null;
      }
      final header = coverPath.substring(0, comma).toLowerCase();
      final slash = header.indexOf('/');
      final semicolon = header.indexOf(';');
      final extension = slash != -1 && semicolon > slash
          ? header.substring(slash + 1, semicolon)
          : 'bin';
      return LeccyBackupCoverImage(
        folderId: folderId,
        extension: extension,
        bytesBase64: coverPath.substring(comma + 1),
      );
    }
    final file = File(coverPath);
    if (!file.existsSync()) {
      return null;
    }
    final extension = p.extension(coverPath).replaceFirst('.', '');
    final bytes = await file.readAsBytes();
    return LeccyBackupCoverImage(
      folderId: folderId,
      extension: extension.isEmpty ? 'bin' : extension,
      bytesBase64: base64Encode(bytes),
    );
  }

  @override
  Future<void> close() async {}
}
