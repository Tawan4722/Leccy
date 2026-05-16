import 'dart:convert';

class LectureFolder {
  const LectureFolder({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.badge,
    required this.sortOrder,
    this.coverImagePath,
    this.deletedAt,
  });

  final int id;
  final String name;
  final int colorValue;
  final String badge;
  final String? coverImagePath;
  final int sortOrder;
  final DateTime? deletedAt;

  LectureFolder copyWith({
    int? id,
    String? name,
    int? colorValue,
    String? badge,
    String? coverImagePath,
    bool clearCoverImagePath = false,
    int? sortOrder,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return LectureFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      badge: badge ?? this.badge,
      coverImagePath: clearCoverImagePath
          ? null
          : coverImagePath ?? this.coverImagePath,
      sortOrder: sortOrder ?? this.sortOrder,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    );
  }

  factory LectureFolder.fromMap(Map<String, Object?> map) {
    return LectureFolder(
      id: map['id'] as int,
      name: map['name'] as String,
      colorValue: map['color_value'] as int,
      badge: map['badge'] as String,
      coverImagePath: map['cover_image_path'] as String?,
      sortOrder: map['sort_order'] as int,
      deletedAt: (map['deleted_at'] as int?) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['deleted_at'] as int),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id == 0 ? null : id,
      'name': name,
      'color_value': colorValue,
      'badge': badge,
      'cover_image_path': coverImagePath,
      'sort_order': sortOrder,
      'deleted_at': deletedAt?.millisecondsSinceEpoch,
    };
  }
}

class LectureFile {
  LectureFile({
    required this.id,
    required this.folderId,
    required this.title,
    required this.description,
    required this.contentJson,
    required this.quickNote,
    required this.sheetJson,
    required this.slidesJson,
    required this.flashcardsJson,
    required this.progressPercent,
    required this.updatedAt,
    required this.autoSummaryEnabled,
    this.isImportant = false,
    this.deletedAt,
    this.summarySourceHash,
    this.summaryUpdatedAt,
  });

  final int id;
  final int folderId;
  final String title;
  final String description;
  final String contentJson;
  final String quickNote;
  final String sheetJson;
  final String slidesJson;
  final String flashcardsJson;
  final int progressPercent;
  final DateTime updatedAt;
  final bool autoSummaryEnabled;
  final bool isImportant;
  final DateTime? deletedAt;
  final String? summarySourceHash;
  final DateTime? summaryUpdatedAt;

  static String emptyDocumentJson() {
    return jsonEncode([
      {'insert': '\n'},
    ]);
  }

  static String emptySheetJson() {
    return jsonEncode({
      'columns': ['A', 'B', 'C'],
      'rows': [
        ['', '', ''],
        ['', '', ''],
        ['', '', ''],
      ],
      'chartType': 'bar',
      'labelColumn': 0,
      'valueColumn': 1,
    });
  }

  static String emptySlidesJson() {
    return jsonEncode({'slides': <Map<String, Object?>>[]});
  }

  static String emptyFlashcardsJson() {
    return jsonEncode({'cards': <Map<String, Object?>>[]});
  }

  LectureFile copyWith({
    int? id,
    int? folderId,
    String? title,
    String? description,
    String? contentJson,
    String? quickNote,
    String? sheetJson,
    String? slidesJson,
    String? flashcardsJson,
    int? progressPercent,
    DateTime? updatedAt,
    bool? autoSummaryEnabled,
    bool? isImportant,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    String? summarySourceHash,
    DateTime? summaryUpdatedAt,
    bool clearSummarySourceHash = false,
    bool clearSummaryUpdatedAt = false,
  }) {
    return LectureFile(
      id: id ?? this.id,
      folderId: folderId ?? this.folderId,
      title: title ?? this.title,
      description: description ?? this.description,
      contentJson: contentJson ?? this.contentJson,
      quickNote: quickNote ?? this.quickNote,
      sheetJson: sheetJson ?? this.sheetJson,
      slidesJson: slidesJson ?? this.slidesJson,
      flashcardsJson: flashcardsJson ?? this.flashcardsJson,
      progressPercent: progressPercent ?? this.progressPercent,
      updatedAt: updatedAt ?? this.updatedAt,
      autoSummaryEnabled: autoSummaryEnabled ?? this.autoSummaryEnabled,
      isImportant: isImportant ?? this.isImportant,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
      summarySourceHash: clearSummarySourceHash
          ? null
          : summarySourceHash ?? this.summarySourceHash,
      summaryUpdatedAt: clearSummaryUpdatedAt
          ? null
          : summaryUpdatedAt ?? this.summaryUpdatedAt,
    );
  }

  factory LectureFile.fromMap(Map<String, Object?> map) {
    return LectureFile(
      id: map['id'] as int,
      folderId: map['folder_id'] as int,
      title: map['title'] as String,
      description: map['description'] as String,
      contentJson: map['content_json'] as String,
      quickNote: map['quick_note'] as String,
      sheetJson: map['sheet_json'] as String? ?? emptySheetJson(),
      slidesJson: map['slides_json'] as String? ?? emptySlidesJson(),
      flashcardsJson:
          map['flashcards_json'] as String? ?? emptyFlashcardsJson(),
      progressPercent: map['progress_percent'] as int,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      autoSummaryEnabled: (map['auto_summary_enabled'] as int? ?? 0) == 1,
      isImportant: (map['important_flag'] as int? ?? 0) == 1,
      deletedAt: (map['deleted_at'] as int?) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['deleted_at'] as int),
      summarySourceHash: map['summary_source_hash'] as String?,
      summaryUpdatedAt: (map['summary_updated_at'] as int?) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              map['summary_updated_at'] as int,
            ),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id == 0 ? null : id,
      'folder_id': folderId,
      'title': title,
      'description': description,
      'content_json': contentJson,
      'quick_note': quickNote,
      'sheet_json': sheetJson,
      'slides_json': slidesJson,
      'flashcards_json': flashcardsJson,
      'progress_percent': progressPercent.clamp(0, 100),
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'auto_summary_enabled': autoSummaryEnabled ? 1 : 0,
      'important_flag': isImportant ? 1 : 0,
      'deleted_at': deletedAt?.millisecondsSinceEpoch,
      'summary_source_hash': summarySourceHash,
      'summary_updated_at': summaryUpdatedAt?.millisecondsSinceEpoch,
    };
  }
}

class StudySet {
  const StudySet({
    required this.id,
    required this.folderId,
    required this.name,
    required this.createdAt,
  });

  final int id;
  final int folderId;
  final String name;
  final DateTime createdAt;

  factory StudySet.fromMap(Map<String, Object?> map) {
    return StudySet(
      id: map['id'] as int,
      folderId: map['folder_id'] as int,
      name: map['name'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id == 0 ? null : id,
      'folder_id': folderId,
      'name': name,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }
}

class StudySetItem {
  const StudySetItem({
    required this.id,
    required this.studySetId,
    required this.fileId,
    required this.itemOrder,
    required this.markerPercent,
  });

  final int id;
  final int studySetId;
  final int fileId;
  final int itemOrder;
  final int markerPercent;

  factory StudySetItem.fromMap(Map<String, Object?> map) {
    return StudySetItem(
      id: map['id'] as int,
      studySetId: map['study_set_id'] as int,
      fileId: map['file_id'] as int,
      itemOrder: map['item_order'] as int,
      markerPercent: map['marker_percent'] as int,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id == 0 ? null : id,
      'study_set_id': studySetId,
      'file_id': fileId,
      'item_order': itemOrder,
      'marker_percent': markerPercent.clamp(0, 100),
    };
  }
}
