import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'models.dart';

enum BackupImportMode { replace, merge }

class LeccyBackupBundle {
  const LeccyBackupBundle({
    required this.exportedAt,
    required this.folders,
    required this.files,
    required this.studySets,
    required this.studySetItems,
    required this.coverImages,
    this.checksumSha256,
    this.version = currentVersion,
  });

  static const String format = 'leccy-backup';
  static const int currentVersion = 2;

  final int version;
  final DateTime exportedAt;
  final List<LectureFolder> folders;
  final List<LectureFile> files;
  final List<StudySet> studySets;
  final List<StudySetItem> studySetItems;
  final List<LeccyBackupCoverImage> coverImages;
  final String? checksumSha256;

  Map<String, Object?> toJson() {
    final unsigned = _unsignedJson();
    final checksum = _checksumFor(unsigned);
    return {...unsigned, 'checksum_sha256': checksum};
  }

  String toJsonString({bool pretty = false}) {
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert(toJson());
  }

  factory LeccyBackupBundle.fromJson(Map<String, Object?> json) {
    if (json['format']?.toString() != format) {
      throw const FormatException('Invalid backup format.');
    }
    final version = _asInt(json['version']);
    if (version > currentVersion) {
      throw FormatException('Backup version $version is not supported yet.');
    }
    final backup = LeccyBackupBundle(
      version: version,
      exportedAt: DateTime.fromMillisecondsSinceEpoch(
        _asInt(json['exported_at']),
      ),
      folders: _asList(
        json['folders'] ?? const [],
      ).map((item) => _decodeFolder(_asMap(item))).toList(),
      files: _asList(
        json['files'] ?? const [],
      ).map((item) => _decodeFile(_asMap(item))).toList(),
      studySets: _asList(
        json['study_sets'] ?? const [],
      ).map((item) => _decodeStudySet(_asMap(item))).toList(),
      studySetItems: _asList(
        json['study_set_items'] ?? const [],
      ).map((item) => _decodeStudySetItem(_asMap(item))).toList(),
      coverImages: _asList(
        json['cover_images'] ?? const [],
      ).map((item) => LeccyBackupCoverImage.fromJson(_asMap(item))).toList(),
      checksumSha256: json['checksum_sha256']?.toString(),
    );
    backup._validateChecksum();
    return backup;
  }

  static LectureFolder _decodeFolder(Map<String, Object?> map) {
    return LectureFolder(
      id: _asInt(map['id']),
      name: map['name']?.toString() ?? '',
      colorValue: _asInt(map['color_value']),
      badge: map['badge']?.toString() ?? '',
      coverImagePath: map['cover_image_path']?.toString(),
      sortOrder: _asInt(map['sort_order']),
      deletedAt: _toDateTime(map['deleted_at']),
    );
  }

  static LectureFile _decodeFile(Map<String, Object?> map) {
    final summaryUpdated = map['summary_updated_at'];
    return LectureFile(
      id: _asInt(map['id']),
      folderId: _asInt(map['folder_id']),
      title: map['title']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      contentJson:
          map['content_json']?.toString() ?? LectureFile.emptyDocumentJson(),
      quickNote: map['quick_note']?.toString() ?? '',
      sheetJson: map['sheet_json']?.toString() ?? LectureFile.emptySheetJson(),
      slidesJson:
          map['slides_json']?.toString() ?? LectureFile.emptySlidesJson(),
      flashcardsJson:
          map['flashcards_json']?.toString() ??
          LectureFile.emptyFlashcardsJson(),
      progressPercent: _asInt(map['progress_percent']),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(_asInt(map['updated_at'])),
      autoSummaryEnabled: _asIntOrDefault(map['auto_summary_enabled'], 0) == 1,
      isImportant: _asIntOrDefault(map['important_flag'], 0) == 1,
      deletedAt: _toDateTime(map['deleted_at']),
      summarySourceHash: map['summary_source_hash']?.toString(),
      summaryUpdatedAt: summaryUpdated == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(_asInt(summaryUpdated)),
    );
  }

  static StudySet _decodeStudySet(Map<String, Object?> map) {
    return StudySet(
      id: _asInt(map['id']),
      folderId: _asInt(map['folder_id']),
      name: map['name']?.toString() ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(_asInt(map['created_at'])),
    );
  }

  static StudySetItem _decodeStudySetItem(Map<String, Object?> map) {
    return StudySetItem(
      id: _asInt(map['id']),
      studySetId: _asInt(map['study_set_id']),
      fileId: _asInt(map['file_id']),
      itemOrder: _asInt(map['item_order']),
      markerPercent: _asInt(map['marker_percent']),
    );
  }

  Map<String, Object?> _unsignedJson() {
    return {
      'format': format,
      'version': version,
      'exported_at': exportedAt.millisecondsSinceEpoch,
      'folders': folders.map((folder) => folder.toMap()).toList(),
      'files': files.map((file) => file.toMap()).toList(),
      'study_sets': studySets.map((set) => set.toMap()).toList(),
      'study_set_items': studySetItems.map((item) => item.toMap()).toList(),
      'cover_images': coverImages.map((image) => image.toJson()).toList(),
    };
  }

  void _validateChecksum() {
    if (version < 2) {
      return;
    }
    final checksum = checksumSha256?.trim() ?? '';
    if (checksum.isEmpty) {
      throw const FormatException('Backup checksum is missing.');
    }
    final expected = _checksumFor(_unsignedJson());
    if (checksum.toLowerCase() != expected) {
      throw const FormatException('Backup checksum mismatch.');
    }
  }
}

class LeccyBackupCoverImage {
  const LeccyBackupCoverImage({
    required this.folderId,
    required this.extension,
    required this.bytesBase64,
  });

  final int folderId;
  final String extension;
  final String bytesBase64;

  Map<String, Object?> toJson() {
    return {
      'folder_id': folderId,
      'extension': extension,
      'bytes_base64': bytesBase64,
    };
  }

  factory LeccyBackupCoverImage.fromJson(Map<String, Object?> json) {
    return LeccyBackupCoverImage(
      folderId: _asInt(json['folder_id']),
      extension: json['extension']?.toString() ?? 'bin',
      bytesBase64: json['bytes_base64']?.toString() ?? '',
    );
  }
}

List<Object?> _asList(Object? value) {
  if (value is List) {
    return value.cast<Object?>();
  }
  throw const FormatException('Backup JSON has an invalid list field.');
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map) {
    return value.map(
      (key, mapValue) => MapEntry(key.toString(), mapValue as Object?),
    );
  }
  throw const FormatException('Backup JSON has an invalid object field.');
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  throw const FormatException('Backup JSON has an invalid integer field.');
}

int _asIntOrDefault(Object? value, int fallback) {
  if (value == null) {
    return fallback;
  }
  return _asInt(value);
}

DateTime? _toDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(_asInt(value));
}

String _checksumFor(Map<String, Object?> value) {
  return sha256.convert(utf8.encode(jsonEncode(value))).toString();
}
