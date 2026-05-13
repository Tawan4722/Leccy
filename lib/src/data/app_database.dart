import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDatabase {
  AppDatabase._(this.database);

  final Database database;

  static Future<AppDatabase> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    sqfliteFfiInit();
    final dbFactory = factory ?? databaseFactoryFfi;
    final dbPath = path ?? await _defaultDatabasePath();
    final db = await dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
          await _createSchema(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              "ALTER TABLE lecture_files ADD COLUMN auto_summary_enabled INTEGER NOT NULL DEFAULT 0",
            );
            await db.execute(
              "ALTER TABLE lecture_files ADD COLUMN summary_source_hash TEXT",
            );
            await db.execute(
              "ALTER TABLE lecture_files ADD COLUMN summary_updated_at INTEGER",
            );
          }
        },
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );
    return AppDatabase._(db);
  }

  static Future<String> _defaultDatabasePath() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbDir = Directory(p.join(dir.path, 'Leccy'));
    if (!dbDir.existsSync()) {
      dbDir.createSync(recursive: true);
    }
    return p.join(dbDir.path, 'leccy.db');
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        color_value INTEGER NOT NULL,
        badge TEXT NOT NULL,
        cover_image_path TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE lecture_files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        folder_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        content_json TEXT NOT NULL,
        quick_note TEXT NOT NULL DEFAULT '',
        progress_percent INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        auto_summary_enabled INTEGER NOT NULL DEFAULT 0,
        summary_source_hash TEXT,
        summary_updated_at INTEGER,
        FOREIGN KEY(folder_id) REFERENCES folders(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE study_sets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        folder_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY(folder_id) REFERENCES folders(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE study_set_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        study_set_id INTEGER NOT NULL,
        file_id INTEGER NOT NULL,
        item_order INTEGER NOT NULL,
        marker_percent INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(study_set_id) REFERENCES study_sets(id) ON DELETE CASCADE,
        FOREIGN KEY(file_id) REFERENCES lecture_files(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> close() => database.close();
}
