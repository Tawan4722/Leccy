import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:leccy/src/domain/backup_models.dart';
import 'package:leccy/src/domain/models.dart';

void main() {
  test('backup json round-trip validates checksum', () {
    final bundle = LeccyBackupBundle(
      exportedAt: DateTime(2026, 5, 17),
      folders: const [
        LectureFolder(
          id: 1,
          name: 'Physics',
          colorValue: 0xFF123456,
          badge: 'PH',
          sortOrder: 1,
        ),
      ],
      files: [
        LectureFile(
          id: 1,
          folderId: 1,
          title: 'Vectors',
          description: '',
          contentJson: LectureFile.emptyDocumentJson(),
          quickNote: '',
          sheetJson: LectureFile.emptySheetJson(),
          slidesJson: LectureFile.emptySlidesJson(),
          flashcardsJson: LectureFile.emptyFlashcardsJson(),
          progressPercent: 0,
          updatedAt: DateTime(2026, 5, 17),
          autoSummaryEnabled: false,
          summarySourceHash: null,
          summaryUpdatedAt: null,
        ),
      ],
      studySets: const [],
      studySetItems: const [],
      coverImages: const [],
    );

    final parsed = LeccyBackupBundle.fromJson(
      jsonDecode(bundle.toJsonString()) as Map<String, Object?>,
    );

    expect(parsed.version, LeccyBackupBundle.currentVersion);
    expect(parsed.folders.single.name, 'Physics');
  });

  test('checksum mismatch throws format exception for v2 backups', () {
    final bundle = LeccyBackupBundle(
      exportedAt: DateTime(2026, 5, 17),
      folders: const [
        LectureFolder(
          id: 1,
          name: 'Original',
          colorValue: 0xFF123456,
          badge: 'OR',
          sortOrder: 1,
        ),
      ],
      files: const [],
      studySets: const [],
      studySetItems: const [],
      coverImages: const [],
    );
    final json = Map<String, Object?>.from(bundle.toJson());
    final folder = Map<String, Object?>.from(
      (json['folders'] as List<Object?>).single as Map<String, Object?>,
    );
    folder['name'] = 'Tampered';
    json['folders'] = [folder];

    expect(
      () => LeccyBackupBundle.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });
}
