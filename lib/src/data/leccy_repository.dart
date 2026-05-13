import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/models.dart';
import 'leccy_store.dart';

class LeccyRepository implements LeccyStore {
  LeccyRepository(this._db);

  final Database _db;

  @override
  Future<List<LectureFolder>> folders() async {
    final rows = await _db.query(
      'folders',
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
      where: 'folder_id = ?',
      whereArgs: [folderId],
      orderBy: 'updated_at DESC, title COLLATE NOCASE ASC',
    );
    return rows.map(LectureFile.fromMap).toList();
  }

  @override
  Future<Map<int, int>> fileCountsByFolder() async {
    final rows = await _db.rawQuery('''
      SELECT folder_id, COUNT(*) AS count
      FROM lecture_files
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
      progressPercent: 0,
      updatedAt: now,
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
    final rows = await _db.query(
      'study_sets',
      where: 'folder_id = ?',
      whereArgs: [folderId],
      orderBy: 'created_at DESC',
    );
    return rows.map(StudySet.fromMap).toList();
  }

  @override
  Future<List<StudySetItem>> studySetItems(int studySetId) async {
    final rows = await _db.query(
      'study_set_items',
      where: 'study_set_id = ?',
      whereArgs: [studySetId],
      orderBy: 'item_order ASC',
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
    final documents = await getApplicationDocumentsDirectory();
    final coverDir = Directory(p.join(documents.path, 'Leccy', 'covers'));
    if (!coverDir.existsSync()) {
      coverDir.createSync(recursive: true);
    }
    final safeExtension = extension.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
    final file = File(
      p.join(
        coverDir.path,
        'cover_${DateTime.now().millisecondsSinceEpoch}.${safeExtension.isEmpty ? 'png' : safeExtension}',
      ),
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  Future<void> close() async {}
}
