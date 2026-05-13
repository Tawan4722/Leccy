import 'dart:convert';
import 'dart:typed_data';

import '../domain/models.dart';
import 'leccy_store.dart';

class MemoryLeccyStore implements LeccyStore {
  final List<LectureFolder> _folders = [];
  final List<LectureFile> _files = [];
  final List<StudySet> _sets = [];
  final List<StudySetItem> _items = [];

  int _nextFolderId = 1;
  int _nextFileId = 1;
  int _nextSetId = 1;
  int _nextItemId = 1;

  @override
  Future<List<LectureFolder>> folders() async {
    return [..._folders]..sort((a, b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      return order == 0
          ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
          : order;
    });
  }

  @override
  Future<LectureFolder> createFolder({
    required String name,
    required int colorValue,
    required String badge,
    String? coverImagePath,
  }) async {
    final folder = LectureFolder(
      id: _nextFolderId++,
      name: name,
      colorValue: colorValue,
      badge: badge,
      coverImagePath: coverImagePath,
      sortOrder: _folders.length + 1,
    );
    _folders.add(folder);
    return folder;
  }

  @override
  Future<void> updateFolder(LectureFolder folder) async {
    final index = _folders.indexWhere((item) => item.id == folder.id);
    if (index != -1) {
      _folders[index] = folder;
    }
  }

  @override
  Future<List<LectureFile>> filesForFolder(int folderId) async {
    return _files.where((file) => file.folderId == folderId).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  Future<Map<int, int>> fileCountsByFolder() async {
    final counts = <int, int>{};
    for (final file in _files) {
      counts[file.folderId] = (counts[file.folderId] ?? 0) + 1;
    }
    return counts;
  }

  @override
  Future<Map<int, int>> folderProgress() async {
    final totals = <int, int>{};
    final counts = <int, int>{};
    for (final file in _files) {
      totals[file.folderId] =
          (totals[file.folderId] ?? 0) + file.progressPercent;
      counts[file.folderId] = (counts[file.folderId] ?? 0) + 1;
    }
    return {
      for (final entry in totals.entries)
        entry.key: (entry.value / counts[entry.key]!).round(),
    };
  }

  @override
  Future<LectureFile> createFile(int folderId) async {
    final file = LectureFile(
      id: _nextFileId++,
      folderId: folderId,
      title: 'Untitled lecture',
      description: '',
      contentJson: LectureFile.emptyDocumentJson(),
      quickNote: '',
      progressPercent: 0,
      updatedAt: DateTime.now(),
      autoSummaryEnabled: false,
      summarySourceHash: null,
      summaryUpdatedAt: null,
    );
    _files.add(file);
    return file;
  }

  @override
  Future<void> updateFile(LectureFile file) async {
    final index = _files.indexWhere((item) => item.id == file.id);
    if (index != -1) {
      _files[index] = file.copyWith(updatedAt: DateTime.now());
    }
  }

  @override
  Future<List<StudySet>> studySetsForFolder(int folderId) async {
    return _sets.where((set) => set.folderId == folderId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<List<StudySetItem>> studySetItems(int studySetId) async {
    return _items.where((item) => item.studySetId == studySetId).toList()
      ..sort((a, b) => a.itemOrder.compareTo(b.itemOrder));
  }

  @override
  Future<StudySet> createStudySet({
    required int folderId,
    required String name,
    required List<LectureFile> files,
  }) async {
    final set = StudySet(
      id: _nextSetId++,
      folderId: folderId,
      name: name,
      createdAt: DateTime.now(),
    );
    _sets.add(set);
    for (var index = 0; index < files.length; index++) {
      final file = files[index];
      _items.add(
        StudySetItem(
          id: _nextItemId++,
          studySetId: set.id,
          fileId: file.id,
          itemOrder: index,
          markerPercent: file.progressPercent,
        ),
      );
    }
    return set;
  }

  @override
  Future<void> updateStudySetMarker({
    required int itemId,
    required int fileId,
    required int percent,
  }) async {
    final marker = percent.clamp(0, 100);
    final itemIndex = _items.indexWhere((item) => item.id == itemId);
    if (itemIndex != -1) {
      final item = _items[itemIndex];
      _items[itemIndex] = StudySetItem(
        id: item.id,
        studySetId: item.studySetId,
        fileId: item.fileId,
        itemOrder: item.itemOrder,
        markerPercent: marker,
      );
    }
    final fileIndex = _files.indexWhere((file) => file.id == fileId);
    if (fileIndex != -1) {
      _files[fileIndex] = _files[fileIndex].copyWith(progressPercent: marker);
    }
  }

  @override
  Future<String> saveCoverImage({
    required Uint8List bytes,
    required String extension,
  }) async {
    final cleanExtension = extension.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
    final mimeExtension = cleanExtension.isEmpty ? 'png' : cleanExtension;
    return 'data:image/$mimeExtension;base64,${base64Encode(bytes)}';
  }

  @override
  Future<void> close() async {}
}
